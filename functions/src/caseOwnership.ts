/**
 * Case ownership (master spec §4.5) — who is currently responsible for a signal,
 * and how that responsibility moves.
 *
 * > The original poster becomes the initial case holder. Case ownership can be
 * > transferred if someone else takes responsibility. Ownership history is
 * > visible in the case timeline; the original poster and previous case holders
 * > remain visible. The current case holder can update status.
 *
 * **Why a callable and not rules.** `firestore.rules` can express "the holder may
 * change the status" — `isCaseHolderUpdate()` does — but it cannot express the
 * *transfer*, for four reasons that compound:
 *
 *  1. A transfer is two documents (the signal and its timeline event) that must
 *     land together. Rules validate writes one at a time; a client that wrote
 *     only the signal would move ownership with no history saying so, which is
 *     precisely what master spec §4.5 requires be visible.
 *  2. The timeline entry has to be **unforgeable**. `ownership_transfer` is
 *     deliberately absent from `isSignalEventCreate()`, so the only writer is
 *     the Admin SDK — here. See `SignalEventType.serverOnly` on the Dart side.
 *  3. Approving a request must check that the request is real and pending, and
 *     mark it approved, in the same breath as the transfer.
 *  4. The staleness escape hatch needs a **server clock** compared against a
 *     field a client must not be able to choose. `isValidHolderStamp()` pins
 *     `holderActiveAt` to `request.time` for exactly this reason.
 *
 * **The deadlock this is shaped around.** Ownership that only the holder can
 * give away is ownership that a holder who stops answering keeps forever, and
 * the case with it. So there are three ways out and they escalate: ask the
 * holder (`requestTakeover`, which they approve or decline), take it when the
 * holder has released it, or take it when the holder has been silent for
 * {@link STALE_HOLDER_DAYS}. Nothing here needs a moderator, which matters —
 * moderators are scarce and a stray dog is not.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { buildEventData, buildOwnershipEventData } from "./events";
import {
  caseHolderOf,
  db,
  requireId,
  requireNote,
  signalRefOf,
  SignalCollection,
} from "./signalRefs";

/**
 * How long a case holder may be silent before anyone may take the case from
 * them.
 *
 * Fourteen days. A rescue moves in hours or days, so two weeks of no status
 * change, no urgency change and no transfer is a case that has been abandoned
 * rather than one being worked quietly. It is also comfortably inside the
 * ~6-month archive window (master spec §4.10), so a case cannot age out while
 * still stuck behind a silent holder.
 *
 * **This is the enforcement**, and a claim it disagrees with comes back as
 * `failed-precondition`. `CaseOwnershipService.staleHolderAfter` mirrors the
 * number so the client knows which of two buttons to draw — without it the
 * escape hatch is unreachable, because a case held by someone who stopped
 * answering looks exactly like one held by someone active. That copy decides
 * nothing and grants nothing; drift there mis-draws a button, and
 * `test/takeover_cooldown_guard_test.dart` parses this line to catch it.
 */
export const STALE_HOLDER_DAYS = 14;

/** Every action name. Stable strings — they land in the audit-shaped result. */
const ACTIONS = [
  "claim",
  "release",
  "approveRequest",
  "declineRequest",
] as const;
type OwnershipAction = (typeof ACTIONS)[number];

/** Status codes a client may set alongside a claim. Mirrors `SignalStatus`. */
const MIN_STATUS = 0;
const MAX_STATUS = 2;

/**
 * Confirms the caller is signed in with a real account, and returns their uid.
 *
 * **Anonymous callers are rejected here**, and this is the one write path in the
 * app where that is true from day one. Signal and comment creation still accept
 * them (M-1, HelpAPaw/Flutter#67) only because already-released builds do it and
 * blocking them server-side would break those builds. Nothing has ever taken
 * ownership of a case, so there is no such client to protect, and taking
 * responsibility for an animal is the last thing that should be attributable to
 * an account nobody can reach.
 */
export function requireRealAccount(auth: { uid: string; token: Record<string, unknown> } | undefined): string {
  if (!auth?.uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to take responsibility for a case."
    );
  }
  const firebase = auth.token?.firebase as { sign_in_provider?: string } | undefined;
  if (firebase?.sign_in_provider === "anonymous") {
    throw new HttpsError(
      "permission-denied",
      "Taking responsibility for a case needs a real account."
    );
  }
  return auth.uid;
}

/** When the holder last did anything, falling back to when the signal was made. */
export function holderActiveAtOf(
  data: Record<string, unknown> | undefined
): FirebaseFirestore.Timestamp | null {
  const active = data?.holderActiveAt;
  if (active instanceof admin.firestore.Timestamp) return active;
  const created = data?.createdAt;
  if (created instanceof admin.firestore.Timestamp) return created;
  return null;
}

/**
 * Whether the current holder has been silent long enough to be displaced.
 *
 * A signal with no usable timestamp at all reads as **not** stale. That is the
 * safe direction: the failure of a missing field should be "you have to ask the
 * holder", never "anyone may take this".
 */
export function isHolderStale(data: Record<string, unknown> | undefined): boolean {
  const active = holderActiveAtOf(data);
  if (active == null) return false;
  const ageMs = Date.now() - active.toMillis();
  return ageMs > STALE_HOLDER_DAYS * 24 * 60 * 60 * 1000;
}

/** What an action reports back, and what the ownership notification reads. */
interface OwnershipResult {
  collection: SignalCollection;
  signalId: string;
  previousHolderId: string | null;
  newHolderId: string | null;
}

/**
 * Every action's return value. Three of the four fields are the same each time;
 * only who ends up holding the case differs, so that is the only argument.
 */
function ownershipResult(
  ctx: ActionContext,
  newHolderId: string | null
): OwnershipResult {
  return {
    collection: ctx.collection,
    signalId: ctx.signalId,
    previousHolderId: ctx.currentHolder?.id ?? null,
    newHolderId,
  };
}

/**
 * The one case-ownership entry point.
 *
 * Sequence, in order: authenticate → validate → load → **inside a transaction**
 * re-read the signal, authorize against the *current* holder, and write the
 * signal, the timeline event and the subscription together.
 *
 * The authorization is re-derived from the transactional read rather than
 * trusted from the client, because the client's view of who holds a case can be
 * seconds stale — and "seconds stale" is exactly the window in which two
 * volunteers both tap Take responsibility.
 */
export const caseOwnership = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireRealAccount(
    request.auth as { uid: string; token: Record<string, unknown> } | undefined
  );

  const data = (request.data ?? {}) as Record<string, unknown>;
  const action = data.action as OwnershipAction;
  if (!ACTIONS.includes(action)) {
    throw new HttpsError("invalid-argument", "Unknown case-ownership action.");
  }
  const note = requireNote(
    data.note,
    "Every ownership change needs a note saying what you intend to do."
  );

  const { collection, signalId, ref } = signalRefOf(data);
  const actor = db().collection("users").doc(uid);

  // A TRANSACTION, not a batch.
  //
  // Every action here decides what to do by reading who currently holds the
  // case, and a batch takes no read lock — so two volunteers tapping Take
  // responsibility within the same second would both read `caseHolder: null`,
  // both pass the guard, and both commit: two `ownership_transfer` rows on the
  // timeline, last-write-wins on the field, and the loser told they now hold a
  // case they do not. `approveRequest` has the same shape, where a double-tap
  // would transfer twice.
  //
  // The read has to happen INSIDE the transaction for the lock to mean
  // anything, which is why the signal is re-read here rather than reusing
  // `loadSignal`'s snapshot — that one exists only to reject a missing signal
  // before any work starts.
  const result = await db().runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "That signal no longer exists.");
    }
    const signal = snapshot.data() as Record<string, unknown> | undefined;

    return runAction({
      action,
      uid,
      note,
      data,
      signal,
      currentHolder: caseHolderOf(signal),
      collection,
      signalId,
      ref,
      actor,
      // Inside the transaction so a retry re-stamps rather than reusing the
      // timestamp of the attempt that lost.
      now: admin.firestore.Timestamp.now(),
      tx,
    });
  });

  return { ok: true, ...result };
});

interface ActionContext {
  action: OwnershipAction;
  uid: string;
  note: string;
  data: Record<string, unknown>;
  signal: Record<string, unknown> | undefined;
  currentHolder: FirebaseFirestore.DocumentReference | null;
  collection: SignalCollection;
  signalId: string;
  ref: FirebaseFirestore.DocumentReference;
  actor: FirebaseFirestore.DocumentReference;
  now: FirebaseFirestore.Timestamp;
  /**
   * The enclosing transaction. Every read an action makes must go through it or
   * the lock does not cover the value the decision was made on.
   */
  tx: FirebaseFirestore.Transaction;
}

async function runAction(ctx: ActionContext): Promise<OwnershipResult> {
  switch (ctx.action) {
    case "claim":
      return claim(ctx);
    case "release":
      return release(ctx);
    case "approveRequest":
      return approveRequest(ctx);
    case "declineRequest":
      return declineRequest(ctx);
  }
}

/**
 * Registers the signal-document half of a transfer, plus its timeline event.
 *
 * Shared by every action that moves ownership so the three things that must
 * travel together — the field, the stamp and the event — cannot come apart. The
 * `lastUpdatedBy` stamp matters beyond bookkeeping: `handleSignalUpdated` reads
 * it to decide whom *not* to notify, so an ownership write that left it stale
 * would silently mute whoever made the previous change.
 */
function writeTransfer(
  ctx: ActionContext,
  newHolder: FirebaseFirestore.DocumentReference | null,
  extraSignalFields: Record<string, unknown> = {}
): void {
  ctx.tx.update(ctx.ref, {
    caseHolder: newHolder,
    holderActiveAt: ctx.now,
    lastUpdatedBy: ctx.actor,
    ...extraSignalFields,
  });
  ctx.tx.set(
    ctx.ref.collection("events").doc(),
    buildOwnershipEventData({
      oldHolder: ctx.currentHolder,
      newHolder,
      note: ctx.note,
      actor: ctx.actor,
      createdAt: ctx.now,
    })
  );
}

/** Subscribes a uid to the signal, so they hear about what happens next. */
function subscribe(ctx: ActionContext, uid: string): void {
  ctx.tx.set(
    db().collection("users").doc(uid),
    {
      signalSubscriptions: admin.firestore.FieldValue.arrayUnion(ctx.signalId),
    },
    { merge: true }
  );
}

/**
 * Take responsibility for a case (master spec §4.5).
 *
 * Allowed when the case is unheld, when the holder has gone stale, or when the
 * caller already holds it (a no-op transfer that still refreshes the stamp — the
 * "I am still on this" case, which is what keeps an active holder from being
 * displaced by {@link isHolderStale}).
 *
 * **The optional `status` is what makes claim-to-act one action instead of two.**
 * A volunteer who opens a case and moves it to "In progress" is doing one thing
 * as far as they are concerned, and the note they write explains both halves. If
 * these were two round trips, the second could fail and leave someone owning a
 * case they only meant to update — so the field change, the status change and
 * *both* timeline events go in one batch.
 */
function claim(ctx: ActionContext): OwnershipResult {
  const { currentHolder, uid } = ctx;

  if (currentHolder != null && currentHolder.id !== uid && !isHolderStale(ctx.signal)) {
    // `failed-precondition` rather than `permission-denied`: the caller is not
    // forbidden, the case is simply already taken, and the app turns this into
    // an offer to request a takeover instead.
    throw new HttpsError(
      "failed-precondition",
      "Someone else is responsible for this case. Ask them to hand it over."
    );
  }

  const extras: Record<string, unknown> = {};
  const status = optionalStatus(ctx.data.status);
  const previousStatus = typeof ctx.signal?.status === "number" ? ctx.signal.status : MIN_STATUS;

  if (status != null && status !== previousStatus) {
    extras.status = status;
    ctx.tx.set(
      ctx.ref.collection("events").doc(),
      buildEventData("status_change", {
        oldValue: previousStatus,
        newValue: status,
        note: ctx.note,
        actor: ctx.actor,
        createdAt: ctx.now,
      })
    );
  }

  writeTransfer(ctx, ctx.actor, extras);
  subscribe(ctx, uid);

  // A claim answers any request the CALLER had outstanding — they got what they
  // asked for, by another route. Left pending it would sit in the holder's list
  // forever, asking them to hand over a case they already hold.
  //
  // Other people's pending requests are deliberately left alone. When a case is
  // claimed from a stale holder, or after a release, those requests were
  // addressed to somebody who is no longer responsible — but the thing they
  // actually say is "I am willing to take this on", which is still true and is
  // exactly what the new holder wants to know if they cannot continue. Clearing
  // them would throw away a live offer to make the list tidier.
  ctx.tx.delete(ctx.ref.collection("takeoverRequests").doc(uid));

  return ownershipResult(ctx, uid);
}

/**
 * Step down (master spec §4.8, "I cannot go anymore").
 *
 * Writes an **explicit null** rather than deleting the field. Deleting it would
 * make the signal indistinguishable from one written before case ownership
 * existed, which every reader derives back to *the reporter* — handing the case
 * straight to the one person who may have just stepped away from it.
 */
function release(ctx: ActionContext): OwnershipResult {
  requireCurrentHolder(ctx, "Only the current case holder can release a case.");
  writeTransfer(ctx, null);
  return ownershipResult(ctx, null);
}

/**
 * Answers a pending takeover request, and returns whose it was.
 *
 * Shared by approve and decline because the *reading* half is identical and is
 * the concurrency guard: the `tx.get` is what stops a double-tapped approve
 * transferring twice. Two copies would be two places to forget the `tx.` and
 * drop the lock, and two copies of a message a user actually sees.
 *
 * The callers' divergent halves — moving the case vs. persisting the reason —
 * stay where they are, because they are genuinely different work.
 */
async function answerRequest(
  ctx: ActionContext,
  status: "approved" | "declined",
  extra: Record<string, unknown> = {}
): Promise<string> {
  const requesterId = requireId(ctx.data.requesterId, "requester id");
  const requestRef = ctx.ref.collection("takeoverRequests").doc(requesterId);

  const snapshot = await ctx.tx.get(requestRef);
  if (!snapshot.exists || snapshot.data()?.status !== "pending") {
    throw new HttpsError(
      "not-found",
      "That request has already been answered or withdrawn."
    );
  }

  ctx.tx.update(requestRef, {
    status,
    resolvedBy: ctx.actor,
    resolvedAt: ctx.now,
    ...extra,
  });

  return requesterId;
}

/** Hand the case to someone who asked for it. */
async function approveRequest(ctx: ActionContext): Promise<OwnershipResult> {
  requireCurrentHolder(ctx, "Only the current case holder can hand a case over.");
  const requesterId = await answerRequest(ctx, "approved");

  writeTransfer(ctx, db().collection("users").doc(requesterId));
  subscribe(ctx, requesterId);

  return ownershipResult(ctx, requesterId);
}

/**
 * Turn a request down.
 *
 * Writes **no timeline event**, because nothing happened to the case — ownership
 * did not move, the status did not change. The requester is told directly (the
 * inbox entry `handleTakeoverResolved` writes); the public history of the case
 * is not the place to record that someone was turned away.
 */
async function declineRequest(ctx: ActionContext): Promise<OwnershipResult> {
  requireCurrentHolder(ctx, "Only the current case holder can decline a request.");
  // `resolvedNote` is persisted here and nowhere else. Every other action's note
  // lands on the timeline event it writes; a decline writes no event by design,
  // so without this the holder is made to type a reason that is thrown away and
  // the requester is told "no" with nothing attached. They can read it.
  await answerRequest(ctx, "declined", { resolvedNote: ctx.note });

  // Ownership did not move, so the "new" holder is the current one.
  return ownershipResult(ctx, ctx.currentHolder?.id ?? null);
}

/**
 * Asserts the caller currently holds the case.
 *
 * Note this is the *derived* holder, so on a signal written before case
 * ownership the reporter passes — which is correct, and is why the derivation
 * lives in `caseHolderOf` rather than being inlined per call site.
 */
function requireCurrentHolder(ctx: ActionContext, message: string): void {
  if (ctx.currentHolder?.id !== ctx.uid) {
    throw new HttpsError("permission-denied", message);
  }
}

/** A status code sent alongside a claim, or null when none was. */
export function optionalStatus(raw: unknown): number | null {
  if (raw === undefined || raw === null) return null;
  if (
    typeof raw !== "number" ||
    !Number.isInteger(raw) ||
    raw < MIN_STATUS ||
    raw > MAX_STATUS
  ) {
    throw new HttpsError(
      "invalid-argument",
      `Status must be an integer ${MIN_STATUS}–${MAX_STATUS}.`
    );
  }
  return raw;
}

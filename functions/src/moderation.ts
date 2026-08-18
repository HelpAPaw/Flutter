/**
 * Moderator actions (master spec 3.6.1, 18.3) — the privileged half of the
 * moderation feature.
 *
 * **Why these are functions and not rules.** Every action here has to leave an
 * audit entry (spec 18.7), and an audit log a client can write is a log a
 * client can forge. Routing through the Admin SDK also keeps `firestore.rules`
 * from having to spell out a second, moderator-shaped write path for every
 * field a moderator can touch — the rules stay a statement about *owners*, and
 * `moderationActions` stays server-only.
 *
 * **Why the role is a document, not a custom claim.** `setCustomUserClaims`
 * bakes the role into the ID token, so a revoked moderator keeps their powers
 * until that token expires — up to an hour. Reading `moderators/{uid}` here
 * costs one document read per action (these are rare by nature) and makes both
 * grant and revoke take effect on the very next call. It is also the same
 * check `firestore.rules` makes, rather than a second copy that can drift.
 *
 * **One endpoint, not eight.** Every action shares the authorization check, the
 * note validation, the audit write and the report resolution, and all four are
 * things that must never be skipped. A single dispatching callable makes
 * skipping one a compile error rather than a code-review question, and gives
 * the Dart client one URL to know about (which matters more than usual — see
 * the plain-HTTPS transport quirk in docs/SPECIFICATION.md §7.14).
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import {
  buildEventData,
  MAX_EVENT_NOTE_LENGTH,
  SIGNAL_EVENT_FIELDS,
} from "./events";

/**
 * Lazy handle on Firestore.
 *
 * NOT a module-level `admin.firestore()`: this module is imported by
 * `index.ts`, so its top level runs *before* `admin.initializeApp()` on line 32
 * of that file. Grabbing the instance at call time is the difference between
 * working and throwing at deploy.
 */
const db = () => admin.firestore();

/** The two signal collections a moderator can act on. */
const SIGNAL_COLLECTIONS = ["signals", "signals_test"] as const;
type SignalCollection = (typeof SIGNAL_COLLECTIONS)[number];

/** Where a hidden signal's document goes. Denied to every client by rules. */
const QUARANTINE_COLLECTION = "moderationQuarantine";

/** Warning labels a moderator can pin to a signal (spec 18.3, "warning label"). */
const MODERATION_LABELS = ["unverified", "duplicate", "disputed"] as const;
type ModerationLabel = (typeof MODERATION_LABELS)[number];

/**
 * Every action name, which is also what lands in `moderationActions.action`.
 * Stable strings — the audit log is append-only and never migrated.
 */
const ACTIONS = [
  "hideSignal",
  "restoreSignal",
  "setCommentsLocked",
  "setUrgency",
  "deleteComment",
  "setLabel",
  "resolveReport",
  "addNote",
] as const;
type ModerationAction = (typeof ACTIONS)[number];

/** Terminal states a report can be moved to. */
const OUTCOMES = ["actioned", "dismissed"] as const;
type ReportOutcome = (typeof OUTCOMES)[number];

/** Urgency codes, mirroring `isValidUrgency()` in the rules and Dart's enum. */
const MIN_URGENCY = 0;
const MAX_URGENCY = 2;

/**
 * Confirms the caller holds the moderator role, and returns their uid.
 *
 * Reads `moderators/{uid}` rather than `request.auth.token` — see the module
 * doc comment. Callers get `permission-denied` with no detail about whether the
 * roster exists or who is on it.
 */
async function requireModerator(uid: string | undefined): Promise<string> {
  if (!uid) {
    throw new HttpsError(
      "unauthenticated",
      "You must be signed in to moderate."
    );
  }
  const moderator = await db().collection("moderators").doc(uid).get();
  if (!moderator.exists) {
    throw new HttpsError(
      "permission-denied",
      "This action requires the moderator role."
    );
  }
  return uid;
}

/** A required, bounded free-text justification. Every action carries one. */
function requireNote(raw: unknown): string {
  const note = typeof raw === "string" ? raw.trim() : "";
  if (note.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Every moderation action needs a note explaining it."
    );
  }
  if (note.length > MAX_EVENT_NOTE_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Note must be ${MAX_EVENT_NOTE_LENGTH} characters or fewer.`
    );
  }
  return note;
}

function requireSignalCollection(raw: unknown): SignalCollection {
  if (!SIGNAL_COLLECTIONS.includes(raw as SignalCollection)) {
    throw new HttpsError("invalid-argument", "Unknown signal collection.");
  }
  return raw as SignalCollection;
}

export function requireId(raw: unknown, what: string): string {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 200) {
    throw new HttpsError("invalid-argument", `Missing or invalid ${what}.`);
  }
  // `doc()` takes a RELATIVE PATH, not just an id: "abc/comments/xyz" resolves
  // to a real nested document, which would let a caller address something these
  // actions never meant to reach — and would make quarantineId() build a nested
  // path that restoreSignal could never find again. Rejecting the separator is
  // this validator's whole job.
  if (raw.includes("/") || raw === "." || raw === "..") {
    throw new HttpsError("invalid-argument", `Missing or invalid ${what}.`);
  }
  return raw;
}

/** Quarantine document id. Namespaced so both collections can share it. */
function quarantineId(collection: SignalCollection, signalId: string): string {
  return `${collection}__${signalId}`;
}

/**
 * Validates a signal-targeting action's arguments and loads the signal.
 *
 * Four branches used to repeat this preamble — validate collection, validate
 * id, `get()`, throw `not-found` — each with its own copy of the message and
 * its own chance to forget the existence check. One helper means a new signal
 * action cannot skip it.
 */
async function loadSignal(data: Record<string, unknown>): Promise<{
  collection: SignalCollection;
  signalId: string;
  ref: FirebaseFirestore.DocumentReference;
  snapshot: FirebaseFirestore.DocumentSnapshot;
}> {
  const collection = requireSignalCollection(data.collection);
  const signalId = requireId(data.signalId, "signal id");
  const ref = db().collection(collection).doc(signalId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "That signal no longer exists.");
  }
  return { collection, signalId, ref, snapshot };
}

/** The `moderation` map on a loaded signal, or an empty one. */
function moderationOf(
  snapshot: FirebaseFirestore.DocumentSnapshot
): Record<string, unknown> {
  return (snapshot.data()?.moderation ?? {}) as Record<string, unknown>;
}

/**
 * What every action returns to the client and records in the audit log.
 *
 * `before`/`after` are deliberately small summaries, not whole documents: the
 * audit log is read by moderators and must not become a second, permanently
 * readable copy of content that was hidden precisely because it should not be
 * read.
 */
interface ActionResult {
  targetType: "signal" | "comment" | "user" | "report";
  targetId: string;
  collection?: SignalCollection;
  before?: Record<string, unknown>;
  after?: Record<string, unknown>;
}

/**
 * The one moderator entry point.
 *
 * Sequence, in order and without exception: authenticate → authorize → validate
 * → act → audit → resolve the originating report. The audit write and the
 * report resolution happen here, once, for every action.
 */
export const moderateAction = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = await requireModerator(request.auth?.uid);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const action = data.action as ModerationAction;
    if (!ACTIONS.includes(action)) {
      throw new HttpsError("invalid-argument", "Unknown moderation action.");
    }
    const note = requireNote(data.note);

    // Optional: the report this action answers. Validated here so a bad id
    // fails before anything is mutated.
    const reportId =
      data.reportId === undefined || data.reportId === null
        ? null
        : requireId(data.reportId, "report id");

    // ONE batch for the action, its audit entry and the report resolution.
    //
    // Each action does its reads with `await` and then registers its writes
    // here rather than committing for itself. That is what makes the audit
    // entry unskippable in practice and not just by convention: when these were
    // two commits, a failure of the second left the action already applied with
    // no `moderationActions` row and the report still open — and for
    // `hideSignal` the moderator's retry then failed with "That signal no
    // longer exists", leaving a signal hidden with no audit trail at all. A
    // batch is atomic, so either all of it lands or none of it does.
    const batch = db().batch();

    const result = await runAction(action, uid, note, data, batch);

    batch.set(db().collection("moderationActions").doc(), {
      action,
      moderatorId: uid,
      targetType: result.targetType,
      targetId: result.targetId,
      ...(result.collection ? { collection: result.collection } : {}),
      ...(reportId ? { reportId } : {}),
      ...(result.before ? { before: result.before } : {}),
      ...(result.after ? { after: result.after } : {}),
      note,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // `resolveReport` sets the status itself (that IS the action), and
    // `addNote` deliberately changes nothing — a moderator jotting a thought
    // before deciding must not have the report silently closed and dropped out
    // of their queue.
    if (reportId && action !== "resolveReport" && action !== "addNote") {
      batch.update(db().collection("reports").doc(reportId), {
        status: "actioned",
        resolvedBy: uid,
        resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    console.log(
      `Moderation: ${action} by ${uid} on ${result.targetType} ${result.targetId}`
    );

    return { ok: true, ...result };
  }
);

/** Dispatch. Each branch validates its own arguments and performs its write. */
async function runAction(
  action: ModerationAction,
  uid: string,
  note: string,
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  switch (action) {
    case "hideSignal":
      return hideSignal(uid, note, data, batch);
    case "restoreSignal":
      return restoreSignal(uid, note, data, batch);
    case "setCommentsLocked":
      return setCommentsLocked(data, batch);
    case "setUrgency":
      return setUrgency(uid, note, data, batch);
    case "deleteComment":
      return deleteComment(data, batch);
    case "setLabel":
      return setLabel(uid, data, batch);
    case "resolveReport":
      return resolveReport(uid, data, batch);
    // Writes nothing of its own — the audit entry IS the note.
    case "addNote":
      return addNote(data);
  }
}

/**
 * Hide a signal by moving its document to quarantine (spec 18.3, "Hide post").
 *
 * **Only the document moves.** Firestore keeps subcollections when a document
 * is deleted, so `comments` and `events` stay exactly where they are and a
 * restore is lossless — no recursive copy, no risk of losing history to a
 * partial batch.
 *
 * This is also why hiding is a *move* rather than a `hidden: true` field: the
 * map's geohash range query would need an equality filter on that field, which
 * no already-stored signal would match without a full backfill, and `signals`
 * is world-readable so the flag would hide the signal from the app and from
 * nobody else. A document that is not in `signals` is not readable at all.
 *
 * Safe from triggers: no `onDocumentDeleted` handler is registered.
 */
async function hideSignal(
  uid: string,
  note: string,
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  const { collection, signalId, ref, snapshot } = await loadSignal(data);

  batch.set(db().collection(QUARANTINE_COLLECTION).doc(quarantineId(collection, signalId)), {
    data: snapshot.data(),
    collection,
    signalId,
    hiddenBy: uid,
    hiddenAt: admin.firestore.FieldValue.serverTimestamp(),
    note,
  });
  batch.delete(ref);

  return {
    // No before/after: `action: "hideSignal"` already says it, and a summary
    // that restates the action name reads like observed prior state.
    targetType: "signal",
    targetId: signalId,
    collection,
  };
}

/**
 * Put a quarantined signal back (spec 18.3 — hiding is "temporarily", and an
 * escalation to an admin is what makes it permanent).
 *
 * The restored document carries `moderation.restoredAt`, which is not
 * decoration: writing to `signals/{id}` is a *create*, so `onSignalCreated`
 * fires and would push a months-old signal to everyone in range a second time.
 * `handleSignalCreated` early-returns on that marker. Removing the marker
 * without removing the guard silently re-notifies an entire city.
 */
async function restoreSignal(
  uid: string,
  note: string,
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  const collection = requireSignalCollection(data.collection);
  const signalId = requireId(data.signalId, "signal id");

  const quarantineRef = db()
    .collection(QUARANTINE_COLLECTION)
    .doc(quarantineId(collection, signalId));
  const signalRef = db().collection(collection).doc(signalId);

  const [snapshot, live] = await Promise.all([
    quarantineRef.get(),
    signalRef.get(),
  ]);
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "That signal is not in quarantine.");
  }
  // The write below is a blind full-document overwrite of the snapshot taken at
  // hide time. If something already occupies the id — a re-created signal, a
  // concurrent restore — that state would be silently discarded.
  if (live.exists) {
    throw new HttpsError(
      "already-exists",
      "A signal already exists at that id."
    );
  }

  const stored = (snapshot.data()?.data ?? {}) as Record<string, unknown>;
  const priorModeration = (stored.moderation ?? {}) as Record<string, unknown>;

  batch.set(signalRef, {
    ...stored,
    moderation: {
      ...priorModeration,
      restoredAt: admin.firestore.FieldValue.serverTimestamp(),
      restoredBy: uid,
      restoreNote: note,
    },
  });
  batch.delete(quarantineRef);

  return {
    targetType: "signal",
    targetId: signalId,
    collection,
  };
}

/** Lock or unlock a signal's comments (spec 18.3). Enforced in the rules too. */
async function setCommentsLocked(
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  if (typeof data.locked !== "boolean") {
    throw new HttpsError("invalid-argument", "`locked` must be a boolean.");
  }
  const { collection, signalId, ref, snapshot } = await loadSignal(data);
  const before = moderationOf(snapshot).commentsLocked === true;

  batch.update(ref, { "moderation.commentsLocked": data.locked });

  return {
    targetType: "signal",
    targetId: signalId,
    collection,
    before: { commentsLocked: before },
    after: { commentsLocked: data.locked },
  };
}

/**
 * Correct a misused urgency label (spec 5.3, "Downgrade urgency level").
 *
 * This is the power the rules comment on `isStatusOnlyUpdate()` has been
 * describing all along: urgency is deliberately excluded from the non-reporter
 * allow-list because spec 5.2 restricts it to "the case holder, a moderator or
 * an admin", and until now the reporter was the whole of that set.
 *
 * Writes an `events` row alongside the field, exactly as the client does, so
 * the correction appears in the public timeline rather than silently altering
 * the signal — a moderator overruling someone is precisely the change that
 * should be visible. **This is the first server-written event**, which is why
 * ./events exists.
 */
async function setUrgency(
  uid: string,
  note: string,
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  const urgency = data.urgency;
  if (
    typeof urgency !== "number" ||
    !Number.isInteger(urgency) ||
    urgency < MIN_URGENCY ||
    urgency > MAX_URGENCY
  ) {
    throw new HttpsError(
      "invalid-argument",
      `Urgency must be an integer ${MIN_URGENCY}–${MAX_URGENCY}.`
    );
  }

  const { collection, signalId, ref, snapshot } = await loadSignal(data);
  const previous = snapshot.data()?.urgency;
  const oldValue = typeof previous === "number" ? previous : MIN_URGENCY;

  const actor = db().collection("users").doc(uid);
  // Field name from the shared table rather than a literal, so the event and
  // the field it describes can never disagree — that table is the guarded copy
  // of the mapping (test/signal_event_vocabulary_guard_test.dart), and until
  // now nothing in production actually read it.
  batch.update(ref, {
    [SIGNAL_EVENT_FIELDS.urgency_change]: urgency,
    lastUpdatedBy: actor,
  });
  batch.set(
    ref.collection("events").doc(),
    buildEventData("urgency_change", {
      oldValue,
      newValue: urgency,
      note,
      actor,
      createdAt: admin.firestore.Timestamp.now(),
    })
  );

  return {
    targetType: "signal",
    targetId: signalId,
    collection,
    before: { urgency: oldValue },
    after: { urgency },
  };
}

/** Remove a single comment (spec 18.3, "Hide post" applied at comment level). */
async function deleteComment(
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  const collection = requireSignalCollection(data.collection);
  const signalId = requireId(data.signalId, "signal id");
  const commentId = requireId(data.commentId, "comment id");

  const ref = db()
    .collection(collection)
    .doc(signalId)
    .collection("comments")
    .doc(commentId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "That comment no longer exists.");
  }

  batch.delete(ref);

  return {
    targetType: "comment",
    targetId: commentId,
    collection,
    // The author, so a pattern across one person's comments stays visible in
    // the audit log after the comments themselves are gone. Not the text.
    before: { author: snapshot.data()?.author?.id ?? null, signalId },
  };
}

/** Pin or clear a warning label on a signal (spec 18.3, "Add warning label"). */
async function setLabel(
  uid: string,
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  const label = data.label ?? null;
  if (label !== null && !MODERATION_LABELS.includes(label as ModerationLabel)) {
    throw new HttpsError("invalid-argument", "Unknown moderation label.");
  }

  const { collection, signalId, ref, snapshot } = await loadSignal(data);
  const before = moderationOf(snapshot).label ?? null;

  batch.update(ref, {
    "moderation.label": label,
    "moderation.labelSetBy": label === null ? null : uid,
    "moderation.labelSetAt":
      label === null ? null : admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    targetType: "signal",
    targetId: signalId,
    collection,
    before: { label: before },
    after: { label },
  };
}

/** Close a report without acting on the content (spec 18: dismiss, or record). */
async function resolveReport(
  uid: string,
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  const reportId = requireId(data.reportId, "report id");
  const outcome = data.outcome as ReportOutcome;
  if (!OUTCOMES.includes(outcome)) {
    throw new HttpsError("invalid-argument", "Unknown report outcome.");
  }

  const ref = db().collection("reports").doc(reportId);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "That report no longer exists.");
  }

  batch.update(ref, {
    status: outcome,
    resolvedBy: uid,
    resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    targetType: "report",
    targetId: reportId,
    before: { status: snapshot.data()?.status ?? null },
    after: { status: outcome },
  };
}

/**
 * Record an internal note with no content change (spec 18.3, "Add internal
 * notes"). The note itself is the audit entry — nothing else is written.
 */
async function addNote(data: Record<string, unknown>): Promise<ActionResult> {
  const targetType = data.targetType;
  if (
    targetType !== "signal" &&
    targetType !== "comment" &&
    targetType !== "user"
  ) {
    throw new HttpsError("invalid-argument", "Unknown note target.");
  }
  return {
    targetType,
    targetId: requireId(data.targetId, "target id"),
    ...(data.collection === undefined
      ? {}
      : { collection: requireSignalCollection(data.collection) }),
  };
}

/**
 * Removing a signal — the reporter's own "delete", made recoverable.
 *
 * **Why this exists.** Deleting a signal used to be a client-side cascade:
 * best-effort Storage deletes, a hand-maintained list of subcollections to
 * empty, and a document delete. Three things were wrong with that.
 *
 *  1. It could not be finished. Firestore keeps subcollection documents when
 *     the parent document is deleted, so an app killed mid-cascade orphaned
 *     them permanently — and `isParentSignalReporter()` in the rules *errors*
 *     on the missing parent, so no client could ever go back and clean up.
 *  2. It forced the rules open. `comments`, `events` and `takeoverRequests` all
 *     granted the reporter a delete for no reason other than to let that
 *     cascade run. On `events` that made the case timeline tamper-evident at
 *     best (HelpAPaw/Flutter#68); on `comments` it was worse than an audit
 *     problem, because there is no author-delete rule at all — the effect was
 *     that a comment's author could not delete their own comment but the
 *     signal's reporter could delete anyone's, unaudited.
 *  3. It was unrecoverable, which is why people used it as "this case is
 *     done" instead of marking the case Resolved, and why contribution
 *     statistics under-counted (master spec §3.5.1: stats must survive a case
 *     being deleted or archived).
 *
 * **Removal is a move, not a flag**, for exactly the reasons `hideSignal`
 * already documents in ./moderation: `signals` is world-readable, so a
 * `hidden: true` field would hide a signal from this app and from nobody else;
 * rules cannot enforce a query filter a patched client simply drops; and an
 * equality filter never matches a document that lacks the field, so it would
 * need a full backfill plus new composite indexes on the map's geohash query.
 * A document that is not in `signals` is not in `signals`.
 *
 * **A separate collection from `moderationQuarantine`**, though the shape is
 * deliberately identical. Three differences justify it: these expire and
 * quarantine does not, the reporter restores these and only a moderator
 * restores quarantine, and `listQuarantined` is a 50-item moderator worklist
 * that ordinary user removals would swamp.
 *
 * **Anonymous callers are allowed**, unlike `caseOwnership`, which rejects
 * them. Released builds create signals from anonymous sessions, so an
 * anonymous account is the reporter of real signals; refusing them here would
 * take away the ability to remove their own report.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  db,
  loadSignal,
  requireSignalCollection,
  signalRefOf,
  SignalCollection,
} from "./signalRefs";

/** Where a removed signal's document goes. Readable only by its reporter. */
export const REMOVED_COLLECTION = "removedSignals";

/**
 * How long a removed signal is recoverable before it is purged for good.
 *
 * This window is the entire reason removal can be both recoverable and lawful:
 * a bounded, disclosed retention period followed by a real purge. **It must be
 * stated in the privacy policy**, and the purge below must actually run — a
 * retention window with no purge job is just indefinite retention wearing a
 * different name.
 */
export const REMOVED_RETENTION_DAYS = 30;

/** How many expired removals one scheduled run purges. Bounded for the timeout. */
const PURGE_BATCH_SIZE = 200;

/** Every action name. Stable strings; they appear in logs. */
const ACTIONS = ["remove", "restore", "deletePermanently"] as const;
type RemovalAction = (typeof ACTIONS)[number];

/**
 * Removal document id. Namespaced by collection so production and test-mode
 * signals cannot collide, matching `moderationQuarantine`'s scheme.
 */
export function removedId(
  collection: SignalCollection,
  signalId: string
): string {
  return `${collection}__${signalId}`;
}

/**
 * Confirms the caller is the signal's reporter.
 *
 * Deliberately stricter than moderation's `requireNotOwnContent`, which lets an
 * absent or malformed owner through: there, refusing to moderate ownerless
 * content would leave the legacy documents most likely to need moderating
 * unmoderatable. Here the question is ownership itself, so an unreadable owner
 * has to mean "not yours" — otherwise a signal with a corrupt `reporter` field
 * would be removable by anybody who found it.
 */
function requireReporter(owner: unknown, uid: string): void {
  const ownerId = (owner as FirebaseFirestore.DocumentReference | undefined)
    ?.id;
  if (ownerId === undefined || ownerId !== uid) {
    throw new HttpsError(
      "permission-denied",
      "Only the person who reported a signal can remove it."
    );
  }
}

/**
 * Refuses to remove a signal that is currently under review.
 *
 * The one real abuse of a recoverable removal is not the removal — it is post
 * something harmful, then take it down before a moderator reaches the queue,
 * which today destroys the evidence outright. Blocking removal while a report
 * is open closes that without changing what removal means for the other
 * 99% of cases. The moderator's `hideSignal` still works: quarantine is a
 * different collection with a different key, so the two never race for the
 * document.
 */
async function requireNotUnderReview(signalId: string): Promise<void> {
  const open = await db()
    .collection("reports")
    .where("targetType", "==", "signal")
    .where("targetId", "==", signalId)
    .where("status", "==", "open")
    .limit(1)
    .get();
  if (!open.empty) {
    throw new HttpsError(
      "failed-precondition",
      "This signal is being reviewed and cannot be removed right now."
    );
  }
}

/** Loads a removal document, or throws `not-found`. */
async function loadRemoved(data: Record<string, unknown>): Promise<{
  collection: SignalCollection;
  signalId: string;
  removedRef: FirebaseFirestore.DocumentReference;
  signalRef: FirebaseFirestore.DocumentReference;
  stored: Record<string, unknown>;
}> {
  const { collection, signalId, ref: signalRef } = signalRefOf(data);
  const removedRef = db()
    .collection(REMOVED_COLLECTION)
    .doc(removedId(collection, signalId));
  const snapshot = await removedRef.get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "That signal is not in your removed list.");
  }
  return {
    collection,
    signalId,
    removedRef,
    signalRef,
    stored: (snapshot.data()?.data ?? {}) as Record<string, unknown>,
  };
}

/**
 * The one signal-removal entry point.
 *
 * Sequence: authenticate → validate → authorize against the stored `reporter`
 * → act. One dispatching callable rather than three, matching `moderateAction`
 * and `caseOwnership`: the authorization step is the one that must never be
 * skipped, and a shared preamble makes skipping it a compile error rather than
 * a review question.
 */
export const signalRemoval = onCall(
  { enforceAppCheck: true },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to remove a signal."
      );
    }

    const data = (request.data ?? {}) as Record<string, unknown>;
    const action = data.action as RemovalAction;
    if (!ACTIONS.includes(action)) {
      throw new HttpsError("invalid-argument", "Unknown removal action.");
    }

    switch (action) {
      case "remove":
        return remove(uid, data);
      case "restore":
        return restore(uid, data);
      case "deletePermanently":
        return deletePermanently(uid, data);
    }
  }
);

/**
 * Move the signal document out of `signals` and into `removedSignals`.
 *
 * **Only the document moves.** Its `comments`, `events` and `takeoverRequests`
 * subcollections stay at `signals/{id}/…`, and its photos stay at
 * `signals/{id}/photos/…` in Storage. That is what makes a restore lossless —
 * no recursive copy, no partial-batch risk — and it is the same trick
 * `hideSignal` uses. The consequence to remember is that everything which
 * cleans up after a removal has to reach for `signals/{id}`, **not** for
 * anything under `removedSignals`.
 *
 * The stored copy keeps the contact phone. `deleteAccount` therefore purges a
 * user's removals outright rather than anonymizing them the way it anonymizes
 * their live signals — see the note there.
 */
async function remove(uid: string, data: Record<string, unknown>) {
  const { collection, signalId, ref, snapshot } = await loadSignal(data);
  requireReporter(snapshot.data()?.reporter, uid);
  await requireNotUnderReview(signalId);

  const batch = db().batch();
  batch.set(
    db().collection(REMOVED_COLLECTION).doc(removedId(collection, signalId)),
    {
      data: snapshot.data(),
      collection,
      signalId,
      removedBy: uid,
      removedAt: admin.firestore.FieldValue.serverTimestamp(),
    }
  );
  batch.delete(ref);
  await batch.commit();

  console.log(`Removal: ${uid} removed ${collection}/${signalId}`);
  return { ok: true, collection, signalId };
}

/**
 * Put a removed signal back.
 *
 * **The `moderation.restoredAt` marker is not decoration.** Writing to
 * `signals/{id}` is a *create*, so `onSignalCreated` fires and would push a
 * weeks-old signal to everyone within 50 km all over again, as if it had just
 * been reported. `handleSignalCreated` early-returns on that marker via
 * `isRestoredSignal`. Deliberately the SAME field `moderateAction`'s
 * `restoreSignal` writes, so there is one guard to keep working rather than
 * two — a restore is a restore whoever asked for it.
 */
async function restore(uid: string, data: Record<string, unknown>) {
  const { collection, signalId, removedRef, signalRef, stored } =
    await loadRemoved(data);
  requireReporter(stored.reporter, uid);

  // The write below is a blind full-document overwrite of the snapshot taken at
  // removal time. If something already occupies the id — a moderator restoring
  // it from quarantine, a concurrent restore — that state would be discarded.
  const live = await signalRef.get();
  if (live.exists) {
    throw new HttpsError(
      "already-exists",
      "A signal already exists at that id."
    );
  }

  const priorModeration = (stored.moderation ?? {}) as Record<string, unknown>;

  const batch = db().batch();
  batch.set(signalRef, {
    ...stored,
    moderation: {
      ...priorModeration,
      restoredAt: admin.firestore.FieldValue.serverTimestamp(),
      restoredBy: uid,
    },
  });
  batch.delete(removedRef);
  await batch.commit();

  console.log(`Removal: ${uid} restored ${collection}/${signalId}`);
  return { ok: true, collection, signalId };
}

/**
 * Erase a removed signal now, without waiting out the retention window.
 *
 * This is the true-erasure path, and having it is part of what makes a
 * recoverable removal defensible in the first place: a user who means "delete
 * this, actually" has a way to say so. `deleteAccount` is the other one.
 */
async function deletePermanently(uid: string, data: Record<string, unknown>) {
  const { collection, signalId, removedRef, stored } = await loadRemoved(data);
  requireReporter(stored.reporter, uid);

  await purgeRemoval(collection, signalId, removedRef);

  console.log(`Removal: ${uid} purged ${collection}/${signalId}`);
  return { ok: true, collection, signalId };
}

/**
 * Destroy everything a removed signal left behind, then the removal record.
 *
 * Order matters. The removal document is deleted **last**, so a run that dies
 * half way leaves the record in place and the next purge — scheduled or
 * manual — finds it again and finishes the job. Deleting it first would strand
 * the subcollections and photos with nothing left pointing at them, which is
 * precisely the orphaning this whole change exists to stop.
 *
 * `recursiveDelete` walks `signals/{id}` and every subcollection under it. It
 * works on a reference whose document does not exist, which is exactly this
 * case — the document is in `removedSignals`, the descendants are not. Using it
 * rather than an explicit list is also what retires the standing hazard in
 * §7.5 that adding a subcollection to a signal meant remembering to add it to
 * the client's delete cascade.
 *
 * It is a `BulkWriter` operation and so cannot join a `WriteBatch`; the three
 * steps here are therefore not atomic with each other. That is the reason the
 * ordering above is load-bearing rather than merely tidy.
 */
async function purgeRemoval(
  collection: SignalCollection,
  signalId: string,
  removedRef: FirebaseFirestore.DocumentReference
): Promise<void> {
  await db().recursiveDelete(db().collection(collection).doc(signalId));

  // Photos live at `signals/{id}/photos/**` for BOTH collections — the Storage
  // path has never carried the test-mode split (see storage.rules).
  try {
    await admin
      .storage()
      .bucket()
      // Trailing slash on purpose: this is a *prefix* match feeding a bulk
      // delete, and without it `signals/X/photos` would also match a sibling
      // path like `signals/X/photosomethingelse/`. Nothing writes such a path
      // today, which is exactly why it would go unnoticed if something did.
      .deleteFiles({ prefix: `signals/${signalId}/photos/` });
  } catch (error) {
    // Best-effort, and logged rather than swallowed: once the signal document
    // is gone nothing can authorize a photo delete through the rules
    // (storage.rules resolves the reporter with a cross-service get on the
    // signal), so this is the only thing that will ever clean them up.
    console.error(`Failed to delete photos for ${signalId}:`, error);
  }

  await removedRef.delete();
}

/**
 * Purge removals past the retention window (see {@link REMOVED_RETENTION_DAYS}).
 *
 * Weekly, following `cleanupAnonymousUsers`. `retryCount: 0` for the same
 * reason it has one: a partial run is safe to leave to next week, because
 * `purgeRemoval` deletes the removal record last and so is naturally resumable.
 */
export const purgeRemovedSignals = onSchedule(
  {
    schedule: "0 4 * * 0",
    timeZone: "Etc/UTC",
    timeoutSeconds: 540,
    memory: "256MiB",
    retryCount: 0,
  },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - REMOVED_RETENTION_DAYS * 24 * 60 * 60 * 1000
    );

    const expired = await db()
      .collection(REMOVED_COLLECTION)
      .where("removedAt", "<", cutoff)
      .limit(PURGE_BATCH_SIZE)
      .get();

    if (expired.empty) {
      console.log("Purge: nothing past the retention window.");
      return;
    }

    let purged = 0;
    for (const doc of expired.docs) {
      const raw = doc.data();
      const collection = raw.collection as SignalCollection;
      const signalId = raw.signalId as string;
      // A malformed record would otherwise recursiveDelete the wrong path, or
      // the whole collection. Skip it loudly instead.
      if (typeof signalId !== "string" || signalId.length === 0) {
        console.error(`Purge: skipping malformed removal ${doc.id}`);
        continue;
      }
      try {
        await purgeRemoval(
          requireSignalCollection(collection),
          signalId,
          doc.ref
        );
        purged += 1;
      } catch (error) {
        console.error(`Purge: failed for ${doc.id}:`, error);
      }
    }

    console.log(`Purge: ${purged}/${expired.size} removals erased.`);
  }
);

/**
 * Erase every removal belonging to a user, for `deleteAccount`.
 *
 * **Purged, not anonymized.** `deleteAccount` anonymizes a departing user's
 * live signals because those are community content that other people are still
 * working on. A *removed* signal is content its author already took down, so
 * there is no case for keeping it past the account — and purging it means there
 * is no fourth place for a phone number to survive account deletion, which is
 * the bug that had to be fixed once already when hiding introduced the third
 * (`moderationQuarantine`).
 */
export async function purgeRemovalsFor(
  userRef: FirebaseFirestore.DocumentReference
): Promise<void> {
  const owned = await db()
    .collection(REMOVED_COLLECTION)
    .where("data.reporter", "==", userRef)
    .get();

  for (const doc of owned.docs) {
    const raw = doc.data();
    const signalId = raw.signalId as string;
    if (typeof signalId !== "string" || signalId.length === 0) {
      console.error(`Account deletion: skipping malformed removal ${doc.id}`);
      continue;
    }
    try {
      await purgeRemoval(
        requireSignalCollection(raw.collection),
        signalId,
        doc.ref
      );
    } catch (error) {
      console.error(`Account deletion: purge failed for ${doc.id}:`, error);
    }
  }
}

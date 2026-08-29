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

import { buildEventData, SIGNAL_EVENT_FIELDS } from "./events";
import {
  db,
  loadSignal as loadSignalDocument,
  requireId,
  requireNote as requireNoteShared,
  requireSignalCollection,
  SignalCollection,
  withheldSignalId,
} from "./signalRefs";
import { URGENCY_GREEN, URGENCY_RED } from "./urgency";
import { REMOVED_COLLECTION } from "./removeSignal";

// Signal addressing (`db`, the collection list, `requireId`, the note bound, and
// `loadSignal` — imported here as `loadSignalDocument`) lives in ./signalRefs so
// `signalOwnership` uses the same definitions. The local `loadSignal` below wraps
// it to add the self-moderation guard, which is a moderation concern and must
// NOT move into the shared helper: acting on your own signal is signalOwnership's
// normal path. `requireId` is re-exported because this module's own test suite
// imports it by that path, and because it is a moderation-era decision that
// happens to be shared rather than a signalRefs-era one.
export { requireId };

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

// Urgency bounds come from ./urgency rather than being restated here: that
// module is the one `test/urgency_derivation_guard_test.dart` parses, so a
// fourth urgency level would be added there — and silently missed by a local
// copy, after which this callable would reject a level the app can produce.
const MIN_URGENCY = URGENCY_GREEN;
const MAX_URGENCY = URGENCY_RED;

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
  return requireNoteShared(
    raw,
    "Every moderation action needs a note explaining it."
  );
}



/**
 * Refuses an action whose target belongs to the moderator performing it.
 *
 * Moderator powers are for the community's content, not one's own. Without this
 * a moderator could quietly clear a `disputed` label off their own signal, lock
 * comments on the thread criticising it, or downgrade someone's Red Alert about
 * them — each one perfectly audited, and each one exactly the unchecked power
 * master spec §3.6.1 says the role must not carry ("Moderators are the first
 * line of community safeguarding, but they should not have unchecked power").
 *
 * Enforced here rather than in the client alone, because the client is only an
 * affordance: the shield icon is hidden on your own signal, so an ordinary
 * moderator never meets this error, and anyone who does was bypassing the UI.
 *
 * [owner] is the `reporter` / `author` field as stored — a `DocumentReference`
 * into `users`. An absent or malformed owner does **not** trip the guard: it
 * cannot equal a uid, and refusing to moderate ownerless content would leave
 * exactly the legacy documents most likely to need moderating unmoderatable.
 *
 * `failed-precondition` rather than `permission-denied`: the caller *is* a
 * moderator and the role is intact. It is this specific target that is out of
 * bounds, and the two get different messages in the app.
 */
export function requireNotOwnContent(owner: unknown, uid: string): void {
  const ownerId = (owner as FirebaseFirestore.DocumentReference | undefined)
    ?.id;
  if (ownerId !== undefined && ownerId === uid) {
    throw new HttpsError(
      "failed-precondition",
      "You cannot moderate your own content."
    );
  }
}

/**
 * Loads a signal for a MODERATOR action, refusing their own content.
 *
 * Wraps the shared addressing helper (`signalRefs.loadSignal`) rather than
 * duplicating it, and adds the one thing that is a *moderation* concern rather
 * than an addressing one.
 *
 * **Deliberately not pushed down into the shared helper**: `signalOwnership` uses
 * it too, and there acting on your own signal is the entire normal path — taking
 * responsibility for a signal you reported is the default, not an abuse.
 *
 * The self-check is here rather than in each of the four callers, for the same
 * reason the audit entry and the batch live in `moderateAction`: a check every
 * branch has to remember is a check some future branch will forget.
 */
async function loadSignal(
  uid: string,
  data: Record<string, unknown>
): Promise<{
  collection: SignalCollection;
  signalId: string;
  ref: FirebaseFirestore.DocumentReference;
  snapshot: FirebaseFirestore.DocumentSnapshot;
}> {
  const loaded = await loadSignalDocument(data);
  requireNotOwnContent(loaded.snapshot.data()?.reporter, uid);
  return loaded;
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
        // From the table, not a literal — this line was already bypassing
        // OUTCOMES inside the file that defines it.
        status: OUTCOMES[0],
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
      return setCommentsLocked(uid, data, batch);
    case "setUrgency":
      return setUrgency(uid, note, data, batch);
    case "deleteComment":
      return deleteComment(uid, data, batch);
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
  const { collection, signalId, ref, snapshot } = await loadSignal(uid, data);

  batch.set(db().collection(QUARANTINE_COLLECTION).doc(withheldSignalId(collection, signalId)), {
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
    .doc(withheldSignalId(collection, signalId));
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
  // Now that hiding your own signal is refused, the only way your own signal is
  // in quarantine is that ANOTHER moderator hid it — and quietly putting it
  // back is precisely the conflict of interest this guard exists to prevent.
  // Escalating to an admin is the route, once that tier exists (spec §3.6.2).
  requireNotOwnContent(stored.reporter, uid);
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
  uid: string,
  data: Record<string, unknown>,
  batch: FirebaseFirestore.WriteBatch
): Promise<ActionResult> {
  if (typeof data.locked !== "boolean") {
    throw new HttpsError("invalid-argument", "`locked` must be a boolean.");
  }
  const { collection, signalId, ref, snapshot } = await loadSignal(uid, data);
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

  const { collection, signalId, ref, snapshot } = await loadSignal(uid, data);
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
  uid: string,
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
  // TWO owners to clear, because a comment has two.
  //
  // The author, so a moderator cannot delete a comment they wrote themselves —
  // that is the reporter's cascade, not a moderation action.
  requireNotOwnContent(snapshot.data()?.author, uid);
  // And the signal's reporter, because deleting the comment criticising your
  // own signal is the same conflict of interest as locking the thread it sits in.
  // Read directly rather than through `loadSignal`, whose `not-found` would
  // break the one legitimate case where the parent is absent: a signal hidden
  // earlier keeps its comments, since subcollections survive the document. An
  // absent parent leaves the guard untripped, which is the right answer — the
  // content is already withheld from everyone.
  const parent = await db().collection(collection).doc(signalId).get();
  requireNotOwnContent(parent.data()?.reporter, uid);

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

  const { collection, signalId, ref, snapshot } = await loadSignal(uid, data);
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

// ---------------------------------------------------------------------------
// Reading quarantine (master spec 18.3 — hiding is "temporarily")
// ---------------------------------------------------------------------------

/** Most recently hidden signals returned in one page. Matches the queue's cap. */
const QUARANTINE_PAGE_SIZE = 50;

/**
 * What the client is told about a hidden signal.
 *
 * A **summary, deliberately not the document.** `moderationQuarantine` holds the
 * whole signal — description, photo URLs, contact phone — and the entire reason
 * that collection has no client rule match is that its contents are withheld
 * from readers. A moderator's actual need is "what did I hide, and put that one
 * back", which title and reason answer. Shipping `data` would undo the hide for
 * anyone with the moderator role and a crafted client.
 */
export interface QuarantineSummary {
  quarantineId: string;
  signalId: string;
  collection: string;
  title: string;
  hiddenBy: string;
  note: string;
  /** Epoch millis — a Firestore Timestamp does not survive the JSON envelope. */
  hiddenAtMillis: number | null;
  /**
   * Which withheld-signal collection this came from.
   *
   * `moderationQuarantine` is a moderator hiding something; `removedSignals` is
   * the reporter taking their own signal down (#68). The two are separate
   * collections with separate lifecycles, and a moderator reading a list of
   * them needs to know which they are looking at — "hidden by a colleague" and
   * "the author withdrew it" call for very different next steps.
   */
  source: SignalWithholdingSource;
}

/** The two places a signal document goes when it leaves `signals`. */
export const WITHHOLDING_SOURCES = ["quarantine", "removed"] as const;
export type SignalWithholdingSource = (typeof WITHHOLDING_SOURCES)[number];

/**
 * Per-source field names.
 *
 * The two documents are the same shape with different words on it — `hiddenBy`
 * / `hiddenAt` / `note` against `removedBy` / `removedAt` / (no note, because a
 * user removing their own signal is not asked to justify it to anybody). One
 * table beats two near-identical projection functions that drift.
 */
const SOURCE_FIELDS: Record<
  SignalWithholdingSource,
  { collection: string; actor: string; at: string }
> = {
  quarantine: {
    collection: QUARANTINE_COLLECTION,
    actor: "hiddenBy",
    at: "hiddenAt",
  },
  removed: { collection: REMOVED_COLLECTION, actor: "removedBy", at: "removedAt" },
};

/**
 * Projects a quarantine document to its summary.
 *
 * Exported for its own test: this is where a serialization bug would hide, and
 * the `hiddenAt` conversion in particular has no compile-time protection —
 * returning the Timestamp itself yields `{_seconds, _nanoseconds}` on some
 * transports and `{}` on others, both of which render as a blank date rather
 * than failing.
 */
export function quarantineSummary(
  id: string,
  raw: Record<string, unknown> | undefined,
  source: SignalWithholdingSource = "quarantine"
): QuarantineSummary {
  const fields = SOURCE_FIELDS[source];
  const data = (raw?.data ?? {}) as Record<string, unknown>;
  const at = raw?.[fields.at] as FirebaseFirestore.Timestamp | undefined;
  const actor = raw?.[fields.actor];
  return {
    quarantineId: id,
    signalId: typeof raw?.signalId === "string" ? raw.signalId : "",
    collection: typeof raw?.collection === "string" ? raw.collection : "",
    title: typeof data.title === "string" ? data.title : "",
    hiddenBy: typeof actor === "string" ? actor : "",
    note: typeof raw?.note === "string" ? raw.note : "",
    hiddenAtMillis: typeof at?.toMillis === "function" ? at.toMillis() : null,
    source,
  };
}

/**
 * Lists the signals currently in quarantine, for the moderator who wants to
 * put one back.
 *
 * **A callable rather than a client read**, which is the whole design decision
 * here. Letting a moderator read `moderationQuarantine` through the rules would
 * have been less code and would have given live updates, but it would also ship
 * the withheld content to the client and would mean the one moderator power
 * that works by direct read — every other one goes through `moderateAction`
 * precisely so it is authorized server-side. Keeping the collection denied to
 * every client preserves the hide guarantee in its strongest form: a hidden
 * signal is not readable by anyone, moderators included.
 *
 * Separate from `moderateAction` on purpose: that endpoint's contract is that
 * every call carries a mandatory note and leaves an audit entry, and neither
 * belongs on a read.
 *
 * Scoped by collection so a moderator in test mode sees the test-mode
 * quarantine, matching how the report queue splits.
 *
 * **`source` also covers `removedSignals`** (#68) — signals their own reporter
 * took down. A moderator investigating an account needs to see what it
 * withdrew, and the projection is what makes that safe to offer: a removal
 * document holds the whole signal including the contact phone, and only title,
 * actor and timestamp ever leave the server. The same reasoning that keeps
 * `data` out of a quarantine summary keeps it out of this one.
 */
export const listQuarantined = onCall(
  { enforceAppCheck: true },
  async (request) => {
    await requireModerator(request.auth?.uid);

    const data = (request.data ?? {}) as Record<string, unknown>;
    const collection = requireSignalCollection(data.collection);

    // Absent means quarantine, so every already-released client keeps asking
    // the question it has always asked and gets the answer it has always got.
    const source = (data.source ?? "quarantine") as SignalWithholdingSource;
    if (!WITHHOLDING_SOURCES.includes(source)) {
      throw new HttpsError("invalid-argument", "Unknown withholding source.");
    }
    const fields = SOURCE_FIELDS[source];

    const snapshot = await db()
      .collection(fields.collection)
      .where("collection", "==", collection)
      .orderBy(fields.at, "desc")
      .limit(QUARANTINE_PAGE_SIZE)
      .get();

    return {
      items: snapshot.docs.map((doc) =>
        quarantineSummary(doc.id, doc.data(), source)
      ),
    };
  }
);

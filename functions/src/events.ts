/**
 * Signal-timeline event vocabulary, shared by the Cloud Functions and guarded
 * against the Dart copy.
 *
 * Its own module for the same reason as ./urgency and ./tags: the drift guard
 * (`test/signal_event_vocabulary_guard_test.dart`) parses this file, and
 * requiring `../lib/index` would boot the whole functions runtime to read a
 * list of strings.
 *
 * **This file exists because the server now writes events.** `docs/
 * SPECIFICATION.md` §12 invariant 5a said there was deliberately no TypeScript
 * copy of the vocabulary "and one should be added, with a parity test, the
 * first time the server writes an event". The `setUrgency` action of
 * `moderateAction` (./moderation) is that first time.
 *
 * The other copies are `SignalEventType` (`lib/src/models/signal_event.dart`)
 * and the closed `type ==` list inside `isSignalEventCreate()` in
 * `firestore.rules`. All three must agree. The two failure modes are
 * asymmetric, and the dangerous one is silent:
 *
 *  - a type the app writes but the rules reject is denied **loudly**;
 *  - a type that is stored but that the Dart decoder does not know is dropped
 *    on read, so the row simply **never appears in anyone's history** — no
 *    error, no log, just a moderator action that looks like it never happened.
 */

/**
 * Every event type code, matching Dart's `SignalEventType.code` and the `type
 * ==` clauses in `isSignalEventCreate()`.
 *
 * Codes are **stable, opaque identifiers**. Never rename or reuse one: they are
 * stored on event documents that are never backfilled.
 */
export const SIGNAL_EVENT_TYPES = ["status_change", "urgency_change"] as const;

export type SignalEventType = (typeof SIGNAL_EVENT_TYPES)[number];

/**
 * Field on the signal document that each event type describes, mirroring Dart's
 * `SignalEventType.signalField`.
 */
export const SIGNAL_EVENT_FIELDS: Record<SignalEventType, string> = {
  status_change: "status",
  urgency_change: "urgency",
};

/**
 * The `old*` / `new*` key names each event type carries, mirroring Dart's
 * `oldKey` / `newKey`. `isValidLevel()` in the rules reads exactly these.
 */
export const SIGNAL_EVENT_KEYS: Record<
  SignalEventType,
  { oldKey: string; newKey: string }
> = {
  status_change: { oldKey: "oldStatus", newKey: "newStatus" },
  urgency_change: { oldKey: "oldUrgency", newKey: "newUrgency" },
};

/**
 * Maximum length of an event's update note.
 *
 * Mirrors `SignalEventType.maxNoteLength` (Dart), the
 * `LengthLimitingTextInputFormatter` on the note dialog, and
 * `isValidEventNote()` in the rules — see the field-length invariant in
 * `docs/SPECIFICATION.md` §12.
 */
export const MAX_EVENT_NOTE_LENGTH = 500;

/**
 * Whether a signal document is one `moderateAction`'s `restoreSignal` just put
 * back, rather than a newly reported one.
 *
 * Lives here, extracted and exported, so it can be tested: writing a
 * quarantined signal back to `signals/{id}` is a *create*, so `onSignalCreated`
 * fires and would push a months-old signal to everyone within 50 km all over
 * again. That is the highest-consequence invariant in the moderation feature
 * and the one thing in it that fails at the scale of a whole city.
 *
 * Keyed on the marker rather than a `createdAt` age heuristic: a restore
 * preserves the original `createdAt`, so age cannot tell a restore from a
 * backdated import, and guessing wrong is a mass notification.
 *
 * Note the marker is permanent, so a once-restored signal is exempt from
 * fan-out forever. Consequence-free today — only `restoreSignal` writes it, and
 * a signal is only ever created once.
 */
export function isRestoredSignal(data: Record<string, unknown> | undefined) {
  const moderation = data?.moderation as Record<string, unknown> | undefined;
  return moderation?.restoredAt != null;
}

/**
 * Builds an event document, the server-side counterpart of Dart's
 * `SignalEventType.eventData`.
 *
 * One encoder, so the `old*`/`new*` key names are never spelled out at a call
 * site — the mistake this replaced on the Dart side, where the same mapping
 * lived as string literals in two widgets and a decoder switch.
 *
 * `actor` is a DocumentReference to `users/{uid}`, not a uid string: the field
 * is named `actor` rather than `author` precisely so the profile page's
 * `collectionGroup('comments')` count can never pick events up.
 */
export function buildEventData(
  type: SignalEventType,
  params: {
    oldValue: number;
    newValue: number;
    note: string;
    actor: FirebaseFirestore.DocumentReference;
    createdAt: FirebaseFirestore.Timestamp | Date;
  }
): Record<string, unknown> {
  const { oldKey, newKey } = SIGNAL_EVENT_KEYS[type];
  return {
    type,
    [oldKey]: params.oldValue,
    [newKey]: params.newValue,
    note: params.note,
    actor: params.actor,
    createdAt: params.createdAt,
  };
}

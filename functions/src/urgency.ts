/**
 * Signal urgency, shared by the Cloud Functions and the backfill script.
 *
 * Its own module rather than living in index.ts because `scripts/
 * backfill_urgency.js` needs it: requiring `../lib/index` would boot the whole
 * functions runtime (triggers, Admin SDK init) just to read a ternary.
 *
 * The remaining copy of this logic is the Dart one
 * (`lib/src/models/signal_urgency.dart`). That duplication is inherent — no
 * shared runtime, and the repo already accepts it for SIGNAL_TYPES /
 * SIGNAL_STATUSES — so it is guarded by `test/urgency_derivation_guard_test.dart`,
 * which parses THIS file and fails the build if the two drift.
 */

/** Stable Firestore urgency codes. Mirrors Dart's `SignalUrgency.code`. */
export const URGENCY_GREEN = 0;
export const URGENCY_AMBER = 1;
export const URGENCY_RED = 2;

/** Status code meaning "Resolved". Mirrors Dart's `SignalStatus.resolved`. */
export const STATUS_RESOLVED = 2;

/**
 * Urgency names keyed by the stable code (NOT array position), exactly as
 * SIGNAL_STATUSES in index.ts. Push text is English-only.
 */
export const SIGNAL_URGENCIES: Record<number, string> = {
  [URGENCY_GREEN]: "Green",
  [URGENCY_AMBER]: "Amber",
  [URGENCY_RED]: "Red",
};

/**
 * Urgency for a document written by an app build that predates the urgency
 * system, derived from its status.
 *
 * A resolved signal is under control; anything else needs help but is not
 * assumed critical. **Nothing is ever inferred as Red** — that is a human
 * judgement (master spec 5.2), and a migration that manufactured Red Alerts
 * would devalue every real one.
 */
export function urgencyForStatus(status: unknown): number {
  return status === STATUS_RESOLVED ? URGENCY_GREEN : URGENCY_AMBER;
}

/**
 * Urgency of a signal document — the stored value when there is one, the
 * status-derived fallback otherwise.
 *
 * Keeping this identical to the backfill script's mapping is what makes the
 * backfill notification-safe: `handleSignalUpdated` derives the same value
 * before and after the write, so nothing looks like an escalation. If they
 * diverge, a backfill pushes a notification for every signal in the database.
 */
export function urgencyOf(data: { urgency?: unknown; status?: unknown }): number {
  if (typeof data.urgency === "number") return data.urgency;
  return urgencyForStatus(data.status);
}

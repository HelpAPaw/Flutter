/**
 * Deciding what a change to a signal *says*, separately from delivering it.
 *
 * Its own module for the same reason as ./urgency, ./tags and
 * ./recipientSelection: these are pure functions whose output is user-visible
 * English, and importing `../lib/index` to test them would boot the whole
 * functions runtime — secrets, triggers and all.
 *
 * They exist as functions rather than as branches of a ternary because
 * `handleSignalUpdated` has to pick ONE announcement when a single write moves
 * several things at once, and because the winner sometimes needs to say what
 * the loser would have said. A ternary could express the first; only separate
 * producers with a shared shape express the second without re-implementing a
 * sentence.
 */

import { SIGNAL_URGENCIES, URGENCY_RED } from "./urgency";

/**
 * Every kind of thing the app can put in someone's inbox, and the same
 * vocabulary as the FCM `data.type`.
 *
 * Lives here rather than on `InboxEntry` in index.ts so that this module does
 * not have to import from there — a type-only cycle compiles, but it would make
 * the pure half depend on the runtime half, which is the thing keeping this
 * testable.
 *
 * Mirrored by the `type` switch in `my_notifications_page.dart`. A type the
 * server writes and the client cannot render **fails silently** — the row shows
 * the stored English fallback and nothing reports it.
 */
export type NotificationType =
  | "new_signal"
  | "status_change"
  | "urgency_change"
  | "new_comment"
  // Signal ownership, master spec 4.5. `ownership_change` goes to a signal's
  // subscribers; the two `takeover_*` types go to one person each.
  | "ownership_change"
  | "takeover_request"
  | "takeover_approved"
  | "takeover_declined";

/**
 * Status labels for push text, keyed by CODE (not array position).
 *
 * Source of truth is the app's SignalStatus enum
 * (lib/src/models/signal_status.dart), where `code` is an opaque, stable id and
 * declaration order is a separate display-ordering concern. Push text is
 * English-only (the functions have no i18n). Unknown codes fall back to
 * "Updated" at the lookup site.
 */
export const SIGNAL_STATUSES: Record<number, string> = {
  0: "Needs help",
  1: "In progress",
  2: "Resolved",
};

/**
 * One change to a signal that could be announced to its subscribers.
 *
 * The other half of the {@link InboxEntry} contract: an entry says what is
 * *stored*, this says what a particular kind of change *is*. Declared here
 * rather than inline because there are three producers of it and they have to
 * agree on the shape.
 *
 * `docId` is load-bearing. `st_{signalId}` alone would make a later transition
 * overwrite the earlier entry instead of adding one. Known and accepted for
 * urgency, which can oscillate: green→amber→green→amber re-uses an id,
 * overwriting the entry (correct — it *is* a fresh escalation and should
 * resurface as unread) while `unread` is incremented again, so the counter
 * over-counts. That counter is advisory by design and the app repairs it with a
 * count() aggregation on resume; see the `userCounters` note in
 * docs/SPECIFICATION.md, which says not to add a trigger to fix it.
 */
export interface AnnouncedChange {
  docId: string;
  type: NotificationType;
  title: string;
  body: string;
  /**
   * The change stated as a fragment, for when another change outranks this one
   * but still wants to say it happened — see the ownership/status merge in
   * `handleSignalUpdated`. Without it the winner has to re-implement the
   * loser's phrasing, which is how one sentence ends up written twice.
   */
  summary: string;
  inboxField: {
    urgency?: number;
    statusCode?: number;
    newOwnerId?: string | null;
    newOwnerName?: string;
  };
  dataField: Record<string, string>;
}

export function statusChangeOf(
  signalId: string,
  signalTitle: string,
  newStatus: number
): AnnouncedChange {
  const summary = SIGNAL_STATUSES[newStatus] || "Updated";
  return {
    docId: `st_${signalId}_${newStatus}`,
    type: "status_change",
    title: "Signal status updated",
    body: `${signalTitle}: ${summary}`,
    summary,
    inboxField: { statusCode: newStatus },
    dataField: { statusCode: String(newStatus) },
  };
}

export function urgencyChangeOf(
  signalId: string,
  signalTitle: string,
  newUrgency: number
): AnnouncedChange {
  // No `|| "Updated"` fallback: the rules bound urgency to 0-2 and the caller
  // already required a stored number, so every key is present.
  const summary = SIGNAL_URGENCIES[newUrgency];
  return {
    docId: `urg_${signalId}_${newUrgency}`,
    type: "urgency_change",
    title:
      newUrgency === URGENCY_RED
        ? "🔴 Escalated to RED ALERT"
        : "Signal urgency raised",
    body: `${signalTitle}: ${summary}`,
    summary,
    inboxField: { urgency: newUrgency },
    dataField: { urgency: String(newUrgency) },
  };
}

/**
 * Signal ownership moved (master spec §4.5) — taken on, handed over or released.
 *
 * Keyed by the new owner so a signal that changes hands twice produces two rows,
 * and a retry of either produces one. A release keys on `none`, which is the
 * only value it can have.
 */
export function ownershipChangeOf(
  signalId: string,
  signalTitle: string,
  newOwner: FirebaseFirestore.DocumentReference | null,
  newOwnerName: string | undefined
): AnnouncedChange {
  const summary = newOwner
    ? `${newOwnerName ?? "A volunteer"} is now responsible`
    : "nobody is responsible for this signal now";
  return {
    docId: `own_${signalId}_${newOwner?.id ?? "none"}`,
    type: "ownership_change",
    title: newOwner ? "Someone took responsibility" : "This signal needs someone",
    body: `${signalTitle}: ${summary}`,
    summary,
    inboxField: {
      newOwnerId: newOwner?.id ?? null,
      ...(newOwnerName ? { newOwnerName } : {}),
    },
    dataField: {
      ...(newOwner ? { newOwnerId: newOwner.id } : {}),
    },
  };
}


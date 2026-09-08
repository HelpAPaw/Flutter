/**
 * @-mentions on a comment (SPECIFICATION 7.5).
 *
 * ## What a mention is, and what it deliberately is not
 *
 * A mention **re-words a notification the recipient was already being sent**.
 * It never adds a recipient: the split below intersects the mentioned uids with
 * the signal's subscribers, so somebody who is not subscribed is not reachable
 * by mentioning them, no matter what a client writes into the array.
 *
 * That is what makes the whole feature safe without a privilege check. The app
 * only offers people who have already interacted with the signal, but the array
 * is client-written and `firestore.rules` can only bound its *length* (rules
 * cannot iterate a list). A forged entry therefore buys nothing at all — at most
 * it changes the wording of a push that was already on its way to a subscriber —
 * so there is no reason to spend a read per mention proving participation.
 *
 * Pure and dependency-free, like `announcements.ts` and `events.ts`: `index.ts`
 * has no test of its own, so anything with branches to get wrong lives out here
 * where jest can reach it without booting the runtime.
 */

/** Matches `maxMentionsPerComment` in lib/src/models/comment_mention.dart. */
export const MAX_MENTIONS = 10;

/**
 * The uids named by a comment's `mentions` array.
 *
 * Every kind of malformed input answers with fewer uids rather than a throw:
 * this runs inside a Firestore trigger, and a bad array must cost its own
 * wording, never the notification the comment was going to produce anyway.
 * Duplicates collapse — mentioning the same person twice in one comment is one
 * mention — and the cap is applied here as well as in the rules, because the
 * rules that were deployed when a document was written are not necessarily the
 * ones deployed now.
 */
export function mentionedUids(commentData: unknown): string[] {
  const raw = (commentData as { mentions?: unknown } | undefined)?.mentions;
  if (!Array.isArray(raw)) return [];

  const uids: string[] = [];
  for (const entry of raw) {
    if (typeof entry !== "object" || entry === null) continue;
    const uid = (entry as { uid?: unknown }).uid;
    if (typeof uid !== "string" || uid.length === 0) continue;
    if (uids.includes(uid)) continue;
    uids.push(uid);
    if (uids.length === MAX_MENTIONS) break;
  }
  return uids;
}

/**
 * Splits a comment's recipients into the people it named and everyone else.
 *
 * `recipients` is the subscriber list the fan-out has already built, so the
 * intersection is the whole authorization story (see the module comment). Order
 * within each half is preserved, which keeps the log lines and the batched
 * writes deterministic.
 */
export function splitCommentRecipients(
  recipients: string[],
  mentioned: string[]
): { mentioned: string[]; others: string[] } {
  const named = new Set(mentioned);
  const inMentions: string[] = [];
  const others: string[] = [];
  for (const uid of recipients) {
    if (named.has(uid)) {
      inMentions.push(uid);
    } else {
      others.push(uid);
    }
  }
  return { mentioned: inMentions, others };
}

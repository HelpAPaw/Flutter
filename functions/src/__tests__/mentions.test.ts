/**
 * @-mentions on a comment.
 *
 * The property worth pinning here is the one the whole design rests on:
 * **the split can only re-label, never widen.** Every uid that comes out of
 * `splitCommentRecipients` came in as a subscriber, so no array a client writes
 * can put a notification in front of somebody who was not already getting one.
 * If that ever stops being true, `firestore.rules` has nothing to fall back on —
 * it can bound this array's length and nothing else.
 *
 * The decoder's failures are all quiet in the other direction: a dropped entry
 * costs one person the word "mentioned" and nothing else, which is why every
 * malformed shape below answers with fewer uids rather than a throw.
 */

import { MAX_MENTIONS, mentionedUids, splitCommentRecipients } from "../mentions";

const mention = (uid: string) => ({ uid, start: 0, end: 5 });

describe("mentionedUids", () => {
  it("reads the uids out of a well-formed array", () => {
    expect([
      ...mentionedUids({ text: "hi", mentions: [mention("a"), mention("b")] }),
    ]).toEqual(["a", "b"]);
  });

  it("answers empty for a comment with no mentions at all", () => {
    expect(mentionedUids({ text: "hi" }).size).toBe(0);
    expect(mentionedUids(undefined).size).toBe(0);
  });

  it("drops anything that is not a usable entry instead of throwing", () => {
    expect([
      ...mentionedUids({
        mentions: [
          mention("a"),
          null,
          "b",
          42,
          { start: 0, end: 1 },
          { uid: "" },
          { uid: 7 },
          mention("c"),
        ],
      }),
    ]).toEqual(["a", "c"]);
  });

  it("treats a non-list mentions field as no mentions", () => {
    expect(mentionedUids({ mentions: "a" }).size).toBe(0);
    expect(mentionedUids({ mentions: { uid: "a" } }).size).toBe(0);
  });

  it("collapses duplicates — naming someone twice is one mention", () => {
    expect([...mentionedUids({ mentions: [mention("a"), mention("a")] })]).toEqual([
      "a",
    ]);
  });

  // The rules cap the array too, but the ruleset deployed when a document was
  // written is not necessarily the one deployed now.
  it("caps the list independently of the rules", () => {
    const many = Array.from({ length: MAX_MENTIONS + 5 }, (_, i) => mention(`u${i}`));
    expect(mentionedUids({ mentions: many }).size).toBe(MAX_MENTIONS);
  });
});

describe("splitCommentRecipients", () => {
  it("separates the named subscribers from the rest, preserving order", () => {
    expect(
      splitCommentRecipients(["a", "b", "c", "d"], new Set(["c", "a"]))
    ).toEqual({
      mentioned: ["a", "c"],
      others: ["b", "d"],
    });
  });

  // THE property. A mention is a re-wording, never a new recipient.
  it("cannot reach anybody who is not already a recipient", () => {
    const split = splitCommentRecipients(["a"], new Set(["stranger", "a"]));
    expect(split.mentioned).toEqual(["a"]);
    expect(split.others).toEqual([]);
    expect([...split.mentioned, ...split.others]).toEqual(["a"]);
  });

  it("leaves everyone in `others` when nobody was mentioned", () => {
    expect(splitCommentRecipients(["a", "b"], new Set())).toEqual({
      mentioned: [],
      others: ["a", "b"],
    });
  });
});

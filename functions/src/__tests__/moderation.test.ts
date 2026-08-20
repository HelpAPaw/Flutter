/**
 * `requireId`, the argument validator every signal-targeting moderator action
 * runs its ids through.
 *
 * Tested against the real function rather than a restatement of its rule: an
 * earlier version of this file recomputed the predicate locally, which meant
 * the assertions could not fail no matter how `moderation.ts` regressed.
 *
 * The property that matters is not length-bounding but the path separator.
 * Firestore's `doc()` takes a RELATIVE PATH, so `"abc/comments/xyz"` resolves
 * to a real nested document — `deleteComment` would address something it was
 * never meant to reach, and `quarantineId()` would build a nested path that
 * `restoreSignal` could never find again.
 */

import { quarantineSummary, requireId } from "../moderation";

/** Whether `requireId` accepts a value, as a boolean rather than a throw. */
function accepts(raw: unknown): boolean {
  try {
    requireId(raw, "test id");
    return true;
  } catch {
    return false;
  }
}

describe("requireId", () => {
  it("rejects path separators and traversal", () => {
    expect(accepts("abc/comments/xyz")).toBe(false);
    expect(accepts("/")).toBe(false);
    expect(accepts("a/b")).toBe(false);
    expect(accepts(".")).toBe(false);
    expect(accepts("..")).toBe(false);
  });

  it("accepts ordinary Firestore ids", () => {
    expect(accepts("U9nLxygLCSRo642MwuVz")).toBe(true);
    expect(accepts("signals_test__b6VZKW7Ujlx9Xow1gFx2")).toBe(true);
    // A report id, which embeds the reporter uid and the target type.
    expect(accepts("ejoG9fXU3aVhBLd3q1MfAjeE9ZH3_signal_U9nLxygLCSRo642MwuVz"))
      .toBe(true);
  });

  it("rejects empty, over-long and non-string ids", () => {
    expect(accepts("")).toBe(false);
    expect(accepts("a".repeat(201))).toBe(false);
    expect(accepts("a".repeat(200))).toBe(true);
    expect(accepts(undefined)).toBe(false);
    expect(accepts(null)).toBe(false);
    expect(accepts(42)).toBe(false);
  });

  it("throws an invalid-argument HttpsError naming the field", () => {
    expect(() => requireId("a/b", "signal id")).toThrow(/signal id/);
  });
});

describe("quarantineSummary", () => {
  // This projection is what keeps the withheld content server-side: the
  // quarantine document holds the ENTIRE hidden signal, and only these fields
  // may reach a client. A field added here by accident un-hides content for
  // anyone holding the moderator role.
  const doc = {
    data: {
      title: "Injured cat near bus stop",
      description: "Long description that must not travel",
      contactPhone: "+359888123456",
      photoUrls: ["https://example.test/photo.jpg"],
    },
    collection: "signals_test",
    signalId: "U9nLxygLCSRo642MwuVz",
    hiddenBy: "moderator-uid",
    note: "Duplicate of an existing report",
    hiddenAt: { toMillis: () => 1755000000000 },
  } as unknown as Record<string, unknown>;

  it("returns only the summary fields", () => {
    const summary = quarantineSummary("signals_test__U9nLx", doc);
    expect(Object.keys(summary).sort()).toEqual([
      "collection",
      "hiddenAtMillis",
      "hiddenBy",
      "note",
      "quarantineId",
      "signalId",
      "title",
    ]);
  });

  it("never leaks the hidden content", () => {
    const summary = quarantineSummary("signals_test__U9nLx", doc) as unknown as
      Record<string, unknown>;
    expect(summary.description).toBeUndefined();
    expect(summary.contactPhone).toBeUndefined();
    expect(summary.photoUrls).toBeUndefined();
    expect(summary.data).toBeUndefined();
    expect(JSON.stringify(summary)).not.toContain("+359888123456");
    expect(JSON.stringify(summary)).not.toContain("must not travel");
  });

  it("carries what a moderator needs to decide", () => {
    const summary = quarantineSummary("signals_test__U9nLx", doc);
    expect(summary.quarantineId).toBe("signals_test__U9nLx");
    expect(summary.signalId).toBe("U9nLxygLCSRo642MwuVz");
    expect(summary.collection).toBe("signals_test");
    expect(summary.title).toBe("Injured cat near bus stop");
    expect(summary.hiddenBy).toBe("moderator-uid");
    expect(summary.note).toBe("Duplicate of an existing report");
  });

  it("converts hiddenAt to millis, not a Timestamp", () => {
    // A Timestamp does not survive the callable's JSON envelope: it arrives as
    // {_seconds,_nanoseconds} or {} depending on transport, and both render as
    // a blank date rather than failing.
    const summary = quarantineSummary("id", doc);
    expect(summary.hiddenAtMillis).toBe(1755000000000);
    expect(typeof summary.hiddenAtMillis).toBe("number");
  });

  it("survives a malformed or partial document", () => {
    // Quarantine documents are server-written, so this is defence rather than
    // an expected case — but a blank row is far better than a crashed screen
    // that hides every OTHER restorable signal too.
    const summary = quarantineSummary("id", {});
    expect(summary.title).toBe("");
    expect(summary.signalId).toBe("");
    expect(summary.hiddenAtMillis).toBeNull();
    expect(quarantineSummary("id", undefined).quarantineId).toBe("id");
  });
});

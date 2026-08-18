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

import { requireId } from "../moderation";

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

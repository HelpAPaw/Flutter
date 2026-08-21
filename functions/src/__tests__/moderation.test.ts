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

import * as fs from "fs";
import * as path from "path";

import {
  quarantineSummary,
  requireId,
  requireNotOwnContent,
} from "../moderation";

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

describe("requireNotOwnContent", () => {
  /** A stored `reporter`/`author` field, which is a DocumentReference. */
  const userRef = (id: string) => ({ id, path: `users/${id}` });

  /** Whether the guard lets an action through, as a boolean rather than a throw. */
  function allows(owner: unknown, uid: string): boolean {
    try {
      requireNotOwnContent(owner, uid);
      return true;
    } catch {
      return false;
    }
  }

  it("refuses content owned by the acting moderator", () => {
    expect(allows(userRef("mod-uid"), "mod-uid")).toBe(false);
  });

  it("allows somebody else's content", () => {
    expect(allows(userRef("someone-else"), "mod-uid")).toBe(true);
  });

  it("throws failed-precondition, not permission-denied", () => {
    // The distinction is load-bearing: the app maps the two codes to different
    // messages, and `permission-denied` there means "your role was revoked".
    // Reporting a revoked role to a moderator who still has one would send them
    // to the wrong person for help.
    let code: string | undefined;
    try {
      requireNotOwnContent(userRef("mod-uid"), "mod-uid");
    } catch (e) {
      code = (e as { code?: string }).code;
    }
    expect(code).toBe("failed-precondition");
  });

  it("does not trip on ownerless or malformed content", () => {
    // Refusing here would make exactly the legacy documents most likely to need
    // moderating the ones nobody can moderate.
    expect(allows(undefined, "mod-uid")).toBe(true);
    expect(allows(null, "mod-uid")).toBe(true);
    expect(allows({}, "mod-uid")).toBe(true);
    expect(allows("mod-uid", "mod-uid")).toBe(true);
  });
});

/**
 * Every action that touches existing content must run the self-moderation
 * guard, and there is no type that can enforce that — a new action added later
 * would compile perfectly while skipping it.
 *
 * Asserted against the source, in the same spirit as the vocabulary guards: the
 * failure this catches is silent and permanent (a moderator quietly acting on
 * their own content, fully audited and looking legitimate), so it is worth a
 * test that reads the file.
 */
describe("self-moderation guard coverage", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "moderation.ts"),
    "utf8"
  );

  /** The body of a top-level `async function <name>(` declaration. */
  function bodyOf(name: string): string {
    const start = source.indexOf(`async function ${name}(`);
    expect(start).toBeGreaterThan(-1);
    const next = source.indexOf("\nasync function ", start + 1);
    return source.slice(start, next === -1 ? source.length : next);
  }

  it("guards the four signal actions via loadSignal", () => {
    // These four never load a signal for themselves, so guarding `loadSignal`
    // guards all of them at once.
    expect(bodyOf("loadSignal")).toContain("requireNotOwnContent");
    for (const action of [
      "hideSignal",
      "setCommentsLocked",
      "setUrgency",
      "setLabel",
    ]) {
      expect(bodyOf(action)).toContain("loadSignal(uid, data)");
    }
  });

  it("guards the two actions that bypass loadSignal", () => {
    // `deleteComment` reads the comment directly and `restoreSignal` reads the
    // quarantine copy, so neither inherits loadSignal's check.
    expect(bodyOf("restoreSignal")).toContain("requireNotOwnContent");
    // Twice for a comment, which has two owners: its author, and the reporter
    // of the signal it sits under. Deleting the comment criticising your own
    // case is the same conflict of interest as locking the thread.
    expect(bodyOf("deleteComment").match(/requireNotOwnContent/g)).toHaveLength(
      2
    );
  });

  it("leaves addNote unguarded, deliberately", () => {
    // An internal note on your own content changes nothing and is exactly the
    // context the audit log wants. If this ever starts failing, the exemption
    // was removed on purpose or addNote grew a write it should not have.
    expect(bodyOf("addNote")).not.toContain("requireNotOwnContent");
  });
});

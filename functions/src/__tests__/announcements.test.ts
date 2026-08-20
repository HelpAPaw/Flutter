/**
 * What a change to a signal *says*.
 *
 * These were branches of a chained ternary inside `handleSignalUpdated` and so
 * could only be exercised by standing up a whole trigger event. As functions
 * they are testable directly, which matters most for the one rule that is
 * invisible in the code that consumes them: **one write must produce one
 * announcement**, even when it moved several things.
 *
 * The failure modes are all quiet. Too many announcements is a user muting a
 * signal that mattered; the wrong `docId` is either a lost row (overwritten) or
 * a duplicate; a missing `statusCode` is an inbox row that renders its stored
 * English fallback instead of the localized sentence.
 */

import {
  AnnouncedChange,
  ownershipChangeOf,
  SIGNAL_STATUSES,
  statusChangeOf,
  urgencyChangeOf,
} from "../announcements";
import { URGENCY_AMBER, URGENCY_RED } from "../urgency";

const SIGNAL = "signal-1";
const TITLE = "Injured dog near the park";
const holder = { id: "holder-uid" } as never;

/** The merge `handleSignalUpdated` performs when ownership outranks status. */
function merge(winner: AnnouncedChange, loser: AnnouncedChange): AnnouncedChange {
  return {
    ...winner,
    body: `${winner.body} — ${loser.summary}`,
    inboxField: { ...winner.inboxField, ...loser.inboxField },
    dataField: { ...winner.dataField, ...loser.dataField },
  };
}

describe("statusChangeOf", () => {
  it("keys the doc id by the status, so two transitions are two rows", () => {
    expect(statusChangeOf(SIGNAL, TITLE, 1).docId).toBe(`st_${SIGNAL}_1`);
    expect(statusChangeOf(SIGNAL, TITLE, 2).docId).toBe(`st_${SIGNAL}_2`);
  });

  it("falls back to a generic word for a code this build does not know", () => {
    // A newer client can set a status this deployment has no label for. The row
    // still has to say something.
    expect(statusChangeOf(SIGNAL, TITLE, 99).summary).toBe("Updated");
  });

  it("carries the code, not just the sentence", () => {
    // The client re-renders the row from `statusCode` in its own language; the
    // English body is the fallback for a build that cannot.
    expect(statusChangeOf(SIGNAL, TITLE, 2).inboxField).toEqual({ statusCode: 2 });
    expect(statusChangeOf(SIGNAL, TITLE, 2).dataField).toEqual({ statusCode: "2" });
  });
});

describe("urgencyChangeOf", () => {
  it("says Red Alert in the title, not just in the body", () => {
    expect(urgencyChangeOf(SIGNAL, TITLE, URGENCY_RED).title).toMatch(/RED ALERT/);
    expect(urgencyChangeOf(SIGNAL, TITLE, URGENCY_AMBER).title).not.toMatch(
      /RED ALERT/
    );
  });

  it("keys the doc id by the level", () => {
    expect(urgencyChangeOf(SIGNAL, TITLE, URGENCY_RED).docId).toBe(
      `urg_${SIGNAL}_${URGENCY_RED}`
    );
  });
});

describe("ownershipChangeOf", () => {
  it("names the new holder when one is known", () => {
    const change = ownershipChangeOf(SIGNAL, TITLE, holder, "Ana");
    expect(change.body).toContain("Ana");
    expect(change.inboxField).toEqual({
      newHolderId: "holder-uid",
      newHolderName: "Ana",
    });
  });

  // A profile read can fail or the account can have no name; the push still has
  // to be a sentence.
  it("falls back to a generic actor when the name is unknown", () => {
    const change = ownershipChangeOf(SIGNAL, TITLE, holder, undefined);
    expect(change.body).toContain("A volunteer");
    expect(change.inboxField.newHolderName).toBeUndefined();
  });

  // A release is the same server type with a null holder — an answer, not a
  // missing value, which is what lets the client render the two differently.
  it("describes a release as nobody holding the case", () => {
    const change = ownershipChangeOf(SIGNAL, TITLE, null, undefined);
    expect(change.title).toBe("This case needs someone");
    expect(change.inboxField.newHolderId).toBeNull();
    expect(change.docId).toBe(`own_${SIGNAL}_none`);
  });

  it("keys the doc id by the new holder, so two handovers are two rows", () => {
    const a = ownershipChangeOf(SIGNAL, TITLE, { id: "u1" } as never, undefined);
    const b = ownershipChangeOf(SIGNAL, TITLE, { id: "u2" } as never, undefined);
    expect(a.docId).not.toBe(b.docId);
  });
});

// `caseOwnership`'s `claim` writes `caseHolder` and `status` in one batch, so
// this arrives as ONE trigger invocation with two diffs. It is one action to the
// person who did it, and letting both announce is how a single tap becomes two
// pushes.
describe("a claim that also moved the status", () => {
  const ownership = ownershipChangeOf(SIGNAL, TITLE, holder, "Ana");
  const status = statusChangeOf(SIGNAL, TITLE, 1);
  const merged = merge(ownership, status);

  it("announces once, as the ownership change", () => {
    expect(merged.type).toBe("ownership_change");
    expect(merged.docId).toBe(ownership.docId);
  });

  it("still says what the status became", () => {
    expect(merged.body).toContain("Ana");
    expect(merged.body).toContain(SIGNAL_STATUSES[1]);
  });

  it("carries both codes, so the client can render either half", () => {
    expect(merged.inboxField).toEqual({
      newHolderId: "holder-uid",
      newHolderName: "Ana",
      statusCode: 1,
    });
    expect(merged.dataField).toEqual({
      newHolderId: "holder-uid",
      statusCode: "1",
    });
  });

  // The status sentence has exactly one author. Before the merge existed, the
  // ownership branch re-implemented it inline and the two could drift.
  it("takes the status wording from the status producer itself", () => {
    expect(merged.body.endsWith(status.summary)).toBe(true);
  });
});

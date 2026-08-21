import * as fs from "fs";
import * as path from "path";

import { REMOVED_RETENTION_DAYS, removedId } from "../removeSignal";

describe("removedId", () => {
  it("namespaces by collection so the two modes cannot collide", () => {
    // Test mode and production can hold the same signal id — `signals_test` is
    // a separate collection, not a separate id space. A removal document keyed
    // on the id alone would let a test-mode removal restore over a production
    // signal, or be purged by the other one's expiry.
    expect(removedId("signals", "abc")).toBe("signals__abc");
    expect(removedId("signals_test", "abc")).toBe("signals_test__abc");
    expect(removedId("signals", "abc")).not.toBe(
      removedId("signals_test", "abc")
    );
  });
});

describe("retention", () => {
  it("is a bounded window, not indefinite retention", () => {
    // The whole legal argument for a recoverable removal is that it is
    // disclosed, bounded and actually purged. A zero or absent window would
    // mean the bin never empties, which is retention wearing another name.
    expect(REMOVED_RETENTION_DAYS).toBeGreaterThan(0);
    expect(Number.isInteger(REMOVED_RETENTION_DAYS)).toBe(true);
  });
});

describe("removal guard coverage", () => {
  const source = fs.readFileSync(
    path.join(__dirname, "..", "removeSignal.ts"),
    "utf8"
  );

  /** The body of a top-level `async function <name>(` declaration. */
  function bodyOf(name: string): string {
    const start = source.indexOf(`async function ${name}(`);
    expect(start).toBeGreaterThan(-1);
    const next = source.indexOf("\nasync function ", start + 1);
    return source.slice(start, next === -1 ? source.length : next);
  }

  it("authorizes every action against the stored reporter", () => {
    // Read from the source rather than exercised, for the same reason the
    // self-moderation guard is: a fourth action that forgot this would compile
    // perfectly and let anyone erase anyone's signal. There is no shared
    // choke-point to guard instead — `remove` loads the live signal and the
    // other two load the removal copy — so each branch has to call it, and
    // this is what makes forgetting fail loudly.
    for (const action of ["remove", "restore", "deletePermanently"]) {
      expect(bodyOf(action)).toContain("requireReporter");
    }
  });

  it("refuses to remove a signal that is under review", () => {
    // The one abuse a recoverable removal invites: post something harmful,
    // then withdraw it before a moderator reaches the queue. Only `remove`
    // needs this — restoring and purging something already withdrawn cannot
    // destroy evidence that removal did not already put out of reach.
    expect(bodyOf("remove")).toContain("requireNotUnderReview");
  });

  it("deletes the removal record last, so a failed purge is resumable", () => {
    // `recursiveDelete` is a BulkWriter operation and cannot join a
    // WriteBatch, so the three steps of a purge are not atomic with each
    // other. The ordering is therefore load-bearing: the record is what the
    // next run finds the descendants by, and deleting it first would strand
    // the subcollections and photos with nothing pointing at them — exactly
    // the orphaning this change exists to stop.
    const body = bodyOf("purgeRemoval");
    expect(body.indexOf("recursiveDelete")).toBeLessThan(
      body.indexOf("removedRef.delete()")
    );
    expect(body.indexOf("deleteFiles")).toBeLessThan(
      body.indexOf("removedRef.delete()")
    );
  });

  it("never lets a malformed record aim recursiveDelete at a collection root", () => {
    // `db().collection(c).doc("")` throws, but an undefined id silently
    // produces an auto-id — and a wrong path handed to recursiveDelete is the
    // one bug in this file that destroys data nobody asked to delete. Both
    // sweeps validate before they call it.
    for (const sweep of ["purgeRemovedSignals", "purgeRemovalsFor"]) {
      const start = source.indexOf(sweep);
      expect(start).toBeGreaterThan(-1);
      const body = source.slice(start);
      expect(body).toContain('typeof signalId !== "string"');
    }
  });
});

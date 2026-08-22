/**
 * Case ownership (master spec §4.5) — the decisions that are wrong to get wrong.
 *
 * The callable itself needs Firestore, so what is tested here is the set of pure
 * predicates it delegates its judgement to. Each one has a failure mode that no
 * type checker and no rules test can catch:
 *
 *  - {@link caseHolderOf} collapsing "absent" into "released" would hand every
 *    legacy signal to nobody, or hand every released case straight back to the
 *    person who stepped away from it;
 *  - {@link isHolderStale} defaulting the wrong way would let anyone take any
 *    case whose timestamps are unusual;
 *  - {@link requireRealAccount} is the only thing standing between an
 *    unreachable anonymous account and responsibility for a live animal;
 *  - {@link requireCurrentHolder} is what keeps answering an offer the holder's
 *    decision once the app shows that offer to the reporter as well;
 *  - the ownership encoder writing a wrong key is accepted by the Admin SDK,
 *    stored, and then silently dropped by the Dart decoder.
 */

import { Timestamp } from "firebase-admin/firestore";

import {
  ActionContext,
  holderActiveAtOf,
  isHolderStale,
  optionalStatus,
  requireCurrentHolder,
  requireRealAccount,
  STALE_HOLDER_DAYS,
} from "../caseOwnership";
import { buildOwnershipEventData, SIGNAL_EVENT_KEYS } from "../events";
import { caseHolderOf } from "../signalRefs";

const reporter = { id: "reporter-uid" } as never;
const holder = { id: "holder-uid" } as never;

const daysAgo = (days: number) =>
  Timestamp.fromMillis(Date.now() - days * 24 * 60 * 60 * 1000);

describe("caseHolderOf", () => {
  // The derivation that must never be dropped: builds released before case
  // ownership keep creating signals with no `caseHolder`, and nothing is
  // backfilled, so there is no version of this app that may assume the field.
  it("derives an absent caseHolder to the reporter", () => {
    expect(caseHolderOf({ reporter })).toBe(reporter);
  });

  // And the distinction that must survive alongside it. A release stores an
  // explicit null; reading that as "absent" would give the case back to the
  // reporter, who is precisely the person who may have just released it.
  it("treats an explicit null as released, NOT as the reporter", () => {
    expect(caseHolderOf({ reporter, caseHolder: null })).toBeNull();
  });

  it("returns the holder when one is set", () => {
    expect(caseHolderOf({ reporter, caseHolder: holder })).toBe(holder);
  });

  it("survives a signal document with no reporter at all", () => {
    expect(caseHolderOf({})).toBeNull();
    expect(caseHolderOf(undefined)).toBeNull();
  });
});

describe("holderActiveAtOf", () => {
  it("prefers holderActiveAt", () => {
    const active = daysAgo(1);
    expect(holderActiveAtOf({ holderActiveAt: active, createdAt: daysAgo(90) })).toBe(
      active
    );
  });

  // Every signal that predates the field, which is all of them on the day this
  // ships. Falling back to `createdAt` is what makes an old, never-touched
  // signal claimable rather than permanently frozen behind its reporter.
  it("falls back to createdAt when the holder has never acted", () => {
    const created = daysAgo(30);
    expect(holderActiveAtOf({ createdAt: created })).toBe(created);
  });

  it("returns null when neither field is a timestamp", () => {
    expect(holderActiveAtOf({ createdAt: "not a timestamp" })).toBeNull();
    expect(holderActiveAtOf(undefined)).toBeNull();
  });
});

describe("isHolderStale", () => {
  it("is false for a holder who acted recently", () => {
    expect(isHolderStale({ holderActiveAt: daysAgo(1) })).toBe(false);
  });

  it(`is true past ${STALE_HOLDER_DAYS} days of silence`, () => {
    expect(isHolderStale({ holderActiveAt: daysAgo(STALE_HOLDER_DAYS + 1) })).toBe(
      true
    );
  });

  it("does not fire exactly on the boundary", () => {
    expect(isHolderStale({ holderActiveAt: daysAgo(STALE_HOLDER_DAYS - 1) })).toBe(
      false
    );
  });

  // The safe direction. A missing or unreadable timestamp must mean "ask the
  // holder", never "anyone may take this" — the latter turns a data defect into
  // a way to seize an actively-worked case.
  it("defaults to NOT stale when there is no usable timestamp", () => {
    expect(isHolderStale({})).toBe(false);
    expect(isHolderStale(undefined)).toBe(false);
  });
});

describe("requireRealAccount", () => {
  it("accepts a real signed-in account", () => {
    expect(
      requireRealAccount({ uid: "u1", token: { firebase: { sign_in_provider: "password" } } })
    ).toBe("u1");
  });

  it("rejects a caller with no session", () => {
    expect(() => requireRealAccount(undefined)).toThrow(/signed in/);
  });

  // Unlike signal creation, which still tolerates anonymous callers for the sake
  // of already-released builds (M-1, HelpAPaw/Flutter#67), nothing has ever
  // claimed a case — so this surface is strict from its first day.
  it("rejects an anonymous caller", () => {
    expect(() =>
      requireRealAccount({ uid: "u1", token: { firebase: { sign_in_provider: "anonymous" } } })
    ).toThrow(/real account/);
  });
});

describe("optionalStatus", () => {
  it("passes through a valid code and null when absent", () => {
    expect(optionalStatus(1)).toBe(1);
    expect(optionalStatus(undefined)).toBeNull();
    expect(optionalStatus(null)).toBeNull();
  });

  it("rejects anything that is not a 0–2 integer", () => {
    for (const bad of [-1, 3, 42, 1.5, "1", true]) {
      expect(() => optionalStatus(bad)).toThrow(/Status must be/);
    }
  });
});

describe("buildOwnershipEventData", () => {
  const actor = { id: "holder-uid" } as never;
  const createdAt = new Date("2026-08-19T12:00:00Z");

  it("writes the keys the Dart decoder reads", () => {
    const event = buildOwnershipEventData({
      oldHolder: reporter,
      newHolder: holder,
      note: "I can get there this afternoon.",
      actor,
      createdAt,
    });

    expect(event).toEqual({
      type: "ownership_transfer",
      oldHolder: reporter,
      newHolder: holder,
      note: "I can get there this afternoon.",
      actor,
      createdAt,
    });
  });

  // Both nulls are real answers, not missing values: a decoder cannot tell
  // "released" from "malformed" if the key is simply absent, so neither may be
  // dropped from the document.
  it("keeps an explicit null newHolder on a release", () => {
    const event = buildOwnershipEventData({
      oldHolder: holder,
      newHolder: null,
      note: "I cannot go anymore.",
      actor,
      createdAt,
    });

    expect(event).toHaveProperty("newHolder", null);
    expect(Object.keys(event)).toContain("newHolder");
  });

  it("keeps an explicit null oldHolder when a released case is claimed", () => {
    const event = buildOwnershipEventData({
      oldHolder: null,
      newHolder: holder,
      note: "Taking this on.",
      actor,
      createdAt,
    });

    expect(event).toHaveProperty("oldHolder", null);
  });

  it("takes its key names from the shared table, not from literals", () => {
    const { oldKey, newKey } = SIGNAL_EVENT_KEYS.ownership_transfer;
    expect(oldKey).toBe("oldHolder");
    expect(newKey).toBe("newHolder");
  });
});

describe("requireCurrentHolder", () => {
  // Only the two fields the check reads. Building a whole ActionContext would
  // need a transaction and a live document, which is the thing this file exists
  // to stay clear of.
  const ctx = (uid: string, currentHolder: { id: string } | null) =>
    ({ uid, currentHolder } as unknown as ActionContext);

  const message = "Only the current case holder can decline a request.";

  it("lets the current holder through", () => {
    expect(() => requireCurrentHolder(ctx("holder-uid", holder), message))
      .not.toThrow();
  });

  // The derived holder, so a signal written before case ownership passes for
  // its reporter — `caseHolderOf` has already resolved the absent field by the
  // time the context is built, which is why this check reads one value and not
  // two.
  it("lets a legacy signal's reporter through, since they are the derived holder", () => {
    expect(() => requireCurrentHolder(ctx("reporter-uid", reporter), message))
      .not.toThrow();
  });

  // The one this is really for. The app now shows the pending offers to the
  // reporter as well as the holder, read-only — so the next person to touch
  // that block will be tempted to wire up Hand over / Decline for them too.
  // Answering an offer moves responsibility for an animal, and the person
  // currently carrying it is the one who decides; a holder who has gone quiet
  // is what staleness is for.
  it("refuses the reporter once they have handed the case on", () => {
    expect(() => requireCurrentHolder(ctx("reporter-uid", holder), message))
      .toThrow(message);
  });

  it("refuses a stranger", () => {
    expect(() => requireCurrentHolder(ctx("someone-else", holder), message))
      .toThrow(message);
  });

  // A released case is held by nobody, so nobody may answer an offer on it —
  // the way to take it is `claim`, which is open to anyone.
  it("refuses everyone on a released case", () => {
    expect(() => requireCurrentHolder(ctx("reporter-uid", null), message))
      .toThrow(message);
  });
});

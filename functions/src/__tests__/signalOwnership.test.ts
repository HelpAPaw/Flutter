/**
 * Signal ownership (master spec §4.5) — the decisions that are wrong to get wrong.
 *
 * The callable itself needs Firestore, so what is tested here is the set of pure
 * predicates it delegates its judgement to. Each one has a failure mode that no
 * type checker and no rules test can catch:
 *
 *  - {@link signalOwnerOf} collapsing "absent" into "released" would hand every
 *    legacy signal to nobody, or hand every released signal straight back to the
 *    person who stepped away from it;
 *  - {@link isOwnerStale} defaulting the wrong way would let anyone take any
 *    signal whose timestamps are unusual;
 *  - {@link requireRealAccount} is the only thing standing between an
 *    unreachable anonymous account and responsibility for a live animal;
 *  - {@link requireCurrentOwner} is what keeps answering an offer the owner's
 *    decision once the app shows that offer to the reporter as well;
 *  - the ownership encoder writing a wrong key is accepted by the Admin SDK,
 *    stored, and then silently dropped by the Dart decoder.
 */

import { Timestamp } from "firebase-admin/firestore";

import {
  ActionContext,
  ownerActiveAtOf,
  isOwnerStale,
  optionalStatus,
  requireCurrentOwner,
  requireRealAccount,
  STALE_OWNER_DAYS,
} from "../signalOwnership";
import { buildOwnershipEventData, SIGNAL_EVENT_KEYS } from "../events";
import { signalOwnerOf } from "../signalRefs";

const reporter = { id: "reporter-uid" } as never;
const owner = { id: "owner-uid" } as never;

const daysAgo = (days: number) =>
  Timestamp.fromMillis(Date.now() - days * 24 * 60 * 60 * 1000);

describe("signalOwnerOf", () => {
  // The derivation that must never be dropped: builds released before signal
  // ownership keep creating signals with no `signalOwner`, and nothing is
  // backfilled, so there is no version of this app that may assume the field.
  it("derives an absent signalOwner to the reporter", () => {
    expect(signalOwnerOf({ reporter })).toBe(reporter);
  });

  // And the distinction that must survive alongside it. A release stores an
  // explicit null; reading that as "absent" would give the signal back to the
  // reporter, who is precisely the person who may have just released it.
  it("treats an explicit null as released, NOT as the reporter", () => {
    expect(signalOwnerOf({ reporter, signalOwner: null })).toBeNull();
  });

  it("returns the owner when one is set", () => {
    expect(signalOwnerOf({ reporter, signalOwner: owner })).toBe(owner);
  });

  it("survives a signal document with no reporter at all", () => {
    expect(signalOwnerOf({})).toBeNull();
    expect(signalOwnerOf(undefined)).toBeNull();
  });
});

describe("ownerActiveAtOf", () => {
  it("prefers ownerActiveAt", () => {
    const active = daysAgo(1);
    expect(ownerActiveAtOf({ ownerActiveAt: active, createdAt: daysAgo(90) })).toBe(
      active
    );
  });

  // Every signal that predates the field, which is all of them on the day this
  // ships. Falling back to `createdAt` is what makes an old, never-touched
  // signal claimable rather than permanently frozen behind its reporter.
  it("falls back to createdAt when the owner has never acted", () => {
    const created = daysAgo(30);
    expect(ownerActiveAtOf({ createdAt: created })).toBe(created);
  });

  it("returns null when neither field is a timestamp", () => {
    expect(ownerActiveAtOf({ createdAt: "not a timestamp" })).toBeNull();
    expect(ownerActiveAtOf(undefined)).toBeNull();
  });
});

describe("isOwnerStale", () => {
  it("is false for an owner who acted recently", () => {
    expect(isOwnerStale({ ownerActiveAt: daysAgo(1) })).toBe(false);
  });

  it(`is true past ${STALE_OWNER_DAYS} days of silence`, () => {
    expect(isOwnerStale({ ownerActiveAt: daysAgo(STALE_OWNER_DAYS + 1) })).toBe(
      true
    );
  });

  it("does not fire exactly on the boundary", () => {
    expect(isOwnerStale({ ownerActiveAt: daysAgo(STALE_OWNER_DAYS - 1) })).toBe(
      false
    );
  });

  // The safe direction. A missing or unreadable timestamp must mean "ask the
  // owner", never "anyone may take this" — the latter turns a data defect into
  // a way to seize an actively-worked signal.
  it("defaults to NOT stale when there is no usable timestamp", () => {
    expect(isOwnerStale({})).toBe(false);
    expect(isOwnerStale(undefined)).toBe(false);
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
  // claimed a signal — so this surface is strict from its first day.
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
  const actor = { id: "owner-uid" } as never;
  const createdAt = new Date("2026-08-19T12:00:00Z");

  it("writes the keys the Dart decoder reads", () => {
    const event = buildOwnershipEventData({
      oldOwner: reporter,
      newOwner: owner,
      note: "I can get there this afternoon.",
      actor,
      createdAt,
    });

    expect(event).toEqual({
      type: "ownership_transfer",
      oldOwner: reporter,
      newOwner: owner,
      note: "I can get there this afternoon.",
      actor,
      createdAt,
    });
  });

  // Both nulls are real answers, not missing values: a decoder cannot tell
  // "released" from "malformed" if the key is simply absent, so neither may be
  // dropped from the document.
  it("keeps an explicit null newOwner on a release", () => {
    const event = buildOwnershipEventData({
      oldOwner: owner,
      newOwner: null,
      note: "I cannot go anymore.",
      actor,
      createdAt,
    });

    expect(event).toHaveProperty("newOwner", null);
    expect(Object.keys(event)).toContain("newOwner");
  });

  it("keeps an explicit null oldOwner when a released signal is claimed", () => {
    const event = buildOwnershipEventData({
      oldOwner: null,
      newOwner: owner,
      note: "Taking this on.",
      actor,
      createdAt,
    });

    expect(event).toHaveProperty("oldOwner", null);
  });

  it("takes its key names from the shared table, not from literals", () => {
    const { oldKey, newKey } = SIGNAL_EVENT_KEYS.ownership_transfer;
    expect(oldKey).toBe("oldOwner");
    expect(newKey).toBe("newOwner");
  });
});

describe("requireCurrentOwner", () => {
  // Only the two fields the check reads. Building a whole ActionContext would
  // need a transaction and a live document, which is the thing this file exists
  // to stay clear of.
  const ctx = (uid: string, currentOwner: { id: string } | null) =>
    ({ uid, currentOwner } as unknown as ActionContext);

  const message = "Only the current signal owner can decline a request.";

  it("lets the current owner through", () => {
    expect(() => requireCurrentOwner(ctx("owner-uid", owner), message))
      .not.toThrow();
  });

  // The derived owner, so a signal written before signal ownership passes for
  // its reporter — `signalOwnerOf` has already resolved the absent field by the
  // time the context is built, which is why this check reads one value and not
  // two.
  it("lets a legacy signal's reporter through, since they are the derived owner", () => {
    expect(() => requireCurrentOwner(ctx("reporter-uid", reporter), message))
      .not.toThrow();
  });

  // The one this is really for. The app now shows the pending offers to the
  // reporter as well as the owner, read-only — so the next person to touch
  // that block will be tempted to wire up Hand over / Decline for them too.
  // Answering an offer moves responsibility for an animal, and the person
  // currently carrying it is the one who decides; an owner who has gone quiet
  // is what staleness is for.
  it("refuses the reporter once they have handed the signal on", () => {
    expect(() => requireCurrentOwner(ctx("reporter-uid", owner), message))
      .toThrow(message);
  });

  it("refuses a stranger", () => {
    expect(() => requireCurrentOwner(ctx("someone-else", owner), message))
      .toThrow(message);
  });

  // A released signal is held by nobody, so nobody may answer an offer on it —
  // the way to take it is `claim`, which is open to anyone.
  it("refuses everyone on a released signal", () => {
    expect(() => requireCurrentOwner(ctx("reporter-uid", null), message))
      .toThrow(message);
  });
});

import {
  RecipientCandidate,
  selectRecipients,
} from "../recipientSelection";
import {
  effectiveHelperTags,
  helpNeededTagsOf,
  matchesHelpTags,
  wantsAnimalType,
} from "../tags";

/**
 * Shorthand candidate. Distance defaults are spread out so ordering assertions
 * cannot pass by accident on ties.
 */
function candidate(
  uid: string,
  matchesTags: boolean,
  withinOwnRadius: boolean,
  distanceKm: number
): RecipientCandidate {
  return { uid, matchesTags, withinOwnRadius, distanceKm };
}

describe("selectRecipients", () => {
  it("notifies every tag match in radius, even far past the floor", () => {
    const candidates = Array.from({ length: 120 }, (_, i) =>
      candidate(`u${i}`, true, true, i)
    );

    const result = selectRecipients(candidates, { minRecipients: 50 });

    // The floor is a floor, never a ceiling.
    expect(result.uids).toHaveLength(120);
    expect(result.backfilled).toBe(0);
    expect(result.tierCounts.a).toBe(120);
  });

  it("backfills to the floor when too few match", () => {
    const candidates = [
      candidate("match", true, true, 1),
      ...Array.from({ length: 10 }, (_, i) =>
        candidate(`near${i}`, false, true, 5 + i)
      ),
    ];

    const result = selectRecipients(candidates, { minRecipients: 4 });

    expect(result.uids).toEqual(["match", "near0", "near1", "near2"]);
    expect(result.backfilled).toBe(3);
  });

  it("prefers a distant tag match over a close non-match", () => {
    const candidates = [
      // Non-matching neighbour, right next door.
      candidate("neighbour", false, true, 0.5),
      // Matching helper, well outside the radius they configured.
      candidate("helper", true, false, 60),
    ];

    const result = selectRecipients(candidates, { minRecipients: 1 });

    expect(result.uids).toEqual(["helper"]);
  });

  it("walks the tiers in A, C, B, D order", () => {
    const candidates = [
      candidate("d", false, false, 1),
      candidate("b", false, true, 2),
      candidate("c", true, false, 3),
      candidate("a", true, true, 4),
    ];

    const result = selectRecipients(candidates, { minRecipients: 4 });

    expect(result.uids).toEqual(["a", "c", "b", "d"]);
    expect(result.tierCounts).toEqual({ a: 1, c: 1, b: 1, d: 1 });
  });

  it("orders nearest first inside each tier", () => {
    const candidates = [
      candidate("far", true, true, 30),
      candidate("near", true, true, 1),
      candidate("mid", true, true, 10),
    ];

    const result = selectRecipients(candidates, { minRecipients: 3 });

    expect(result.uids).toEqual(["near", "mid", "far"]);
  });

  it("takes everyone when the floor cannot be reached", () => {
    const candidates = [
      candidate("a", true, true, 1),
      candidate("b", false, false, 2),
    ];

    const result = selectRecipients(candidates, { minRecipients: 50 });

    expect(result.uids).toHaveLength(2);
  });

  it("returns nothing when there are no candidates", () => {
    const result = selectRecipients([], { minRecipients: 50 });

    expect(result.uids).toEqual([]);
    expect(result.backfilled).toBe(0);
  });

  it("sorts candidates with no usable position last", () => {
    const candidates = [
      candidate("unknown", false, false, Infinity),
      candidate("known", false, false, 100),
    ];

    const result = selectRecipients(candidates, { minRecipients: 2 });

    expect(result.uids).toEqual(["known", "unknown"]);
  });
});

describe("helpNeededTagsOf", () => {
  it("falls back to rescue for a signal written before the field existed", () => {
    // The property the staged rollout depends on: legacy signals still reach
    // people rather than matching nobody.
    expect(helpNeededTagsOf({})).toEqual(["rescue"]);
    expect(helpNeededTagsOf({ helpNeededTags: [] })).toEqual(["rescue"]);
  });

  it("keeps codes it does not recognise", () => {
    // An unknown code came from a newer client, and users on that build will
    // have it too — dropping it here would silently stop matching them.
    expect(helpNeededTagsOf({ helpNeededTags: ["foster", "brandNew"] })).toEqual(
      ["foster", "brandNew"]
    );
  });

  it("ignores non-string entries", () => {
    expect(helpNeededTagsOf({ helpNeededTags: ["foster", 3, null] })).toEqual([
      "foster",
    ]);
  });
});

describe("effectiveHelperTags", () => {
  it("treats absent and empty identically, unlike the filter fields", () => {
    expect(effectiveHelperTags({})).toEqual(["rescue"]);
    expect(effectiveHelperTags({ helperTags: [] })).toEqual(["rescue"]);
  });

  it("returns the user's own tags when they have chosen", () => {
    expect(effectiveHelperTags({ helperTags: ["foster"] })).toEqual(["foster"]);
  });
});

describe("matchesHelpTags", () => {
  it("matches on any overlap", () => {
    expect(matchesHelpTags(["foster", "vetCare"], ["transport", "vetCare"])).toBe(
      true
    );
  });

  it("does not match disjoint sets", () => {
    expect(matchesHelpTags(["foster"], ["transport"])).toBe(false);
  });

  it("matches a legacy signal against a defaulted user", () => {
    // Both sides resolve to rescue, which is what makes deploying the server
    // ahead of the client a no-op for who gets notified.
    expect(
      matchesHelpTags(helpNeededTagsOf({}), effectiveHelperTags({}))
    ).toBe(true);
  });
});

describe("wantsAnimalType", () => {
  it("matches a signal with no species against everyone", () => {
    expect(wantsAnimalType({ animalTypes: ["cat"] }, undefined)).toBe(true);
  });

  it("matches every species when the user has never chosen", () => {
    expect(wantsAnimalType({}, "dog")).toBe(true);
  });

  it("respects an explicit empty selection as none", () => {
    expect(wantsAnimalType({ animalTypes: [] }, "dog")).toBe(false);
  });

  it("filters on the user's chosen species", () => {
    expect(wantsAnimalType({ animalTypes: ["cat"] }, "dog")).toBe(false);
    expect(wantsAnimalType({ animalTypes: ["cat"] }, "cat")).toBe(true);
  });
});

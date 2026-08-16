import {
  RecipientCandidate,
  selectRecipients,
} from "../recipientSelection";
import {
  displayTagsOf,
  effectiveHelperTags,
  helpNeededTagsOf,
  helpTagHeadline,
  primarySignalTag,
  signalHeadline,
  HELP_TAGS,
  HELP_TAGS_WITHOUT_NEEDED_SUFFIX,
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

  // Someone who turned live tracking off and set no region of interest, but
  // whose stale userLocations doc still exists. Distance was the only way the
  // old code could ever reach them, so it never did — the floor must not either,
  // or it pushes on the strength of a position they stopped sharing.
  it("never backfills a candidate with no usable position", () => {
    const candidates = [
      candidate("unplaceable", true, false, Infinity),
      candidate("known", false, false, 100),
    ];

    const result = selectRecipients(candidates, { minRecipients: 50 });

    expect(result.uids).toEqual(["known"]);
    expect(result.uids).not.toContain("unplaceable");
  });

  it("keeps the unplaceable out of the tier counts too", () => {
    const result = selectRecipients(
      [candidate("unplaceable", true, true, Infinity)],
      { minRecipients: 50 }
    );

    expect(result.uids).toEqual([]);
    expect(result.tierCounts).toEqual({ a: 0, c: 0, b: 0, d: 0 });
  });
});

// The rollout's central claim: deploying the server before the app changes
// nobody's notifications. Everyone is untagged, so everyone matches, so tier A
// is exactly the set the old radius-only code notified.
describe("MIN_RECIPIENTS = 0 reproduces the pre-tag behaviour exactly", () => {
  const untagged = (uid: string, withinOwnRadius: boolean, km: number) =>
    candidate(uid, true, withinOwnRadius, km);

  it("notifies everyone in radius and nobody else", () => {
    const world = [
      untagged("in1", true, 1),
      untagged("in2", true, 2),
      untagged("out", false, 40),
    ];

    expect(selectRecipients(world, { minRecipients: 0 }).uids).toEqual([
      "in1",
      "in2",
    ]);
  });

  it("notifies nobody when nobody is in radius", () => {
    // The case that separates 0 from 1. A floor of 1 reaches one person outside
    // the radius they configured, where the old code reached none — small, but
    // not the "identical behaviour" a pre-app deploy is supposed to have.
    const nobodyNear = [untagged("far1", false, 40), untagged("far2", false, 60)];

    expect(selectRecipients(nobodyNear, { minRecipients: 0 }).uids).toEqual([]);
    expect(selectRecipients(nobodyNear, { minRecipients: 1 }).uids).toEqual([
      "far1",
    ]);
  });

  it("still never truncates tier A, whatever the floor", () => {
    const many = Array.from({ length: 8 }, (_, i) =>
      untagged(`in${i}`, true, i)
    );

    expect(selectRecipients(many, { minRecipients: 0 }).uids).toHaveLength(8);
    expect(selectRecipients(many, { minRecipients: 1 }).uids).toHaveLength(8);
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

describe("helpTagHeadline", () => {
  it("asks for what is needed", () => {
    expect(helpTagHeadline("rescue")).toBe("Rescue needed");
    expect(helpTagHeadline("bloodDonation")).toBe("Blood donation needed");
    expect(helpTagHeadline("babyCare")).toBe("Newborn care needed");
  });

  it("does not say 'needed' for the two non-needs", () => {
    // A lost dog is not "Lost / found needed". These describe a situation, not
    // a request for a service, which is the whole reason the exemption list
    // exists.
    expect(helpTagHeadline("lostFound")).toBe("Lost / found");
    expect(helpTagHeadline("dangerWarning")).toBe("Local danger");
  });

  it("covers every tag with a real name", () => {
    // A missing HELP_TAG_NAMES entry falls back to the raw code, so the push
    // would read "babyCare needed". Nothing throws — this is the only place it
    // would ever be noticed.
    for (const code of HELP_TAGS) {
      expect(helpTagHeadline(code)).not.toContain(code);
    }
  });

  it("falls back to the raw code for a tag from a newer client", () => {
    // Unknown codes are deliberately kept rather than dropped (see
    // helpNeededTagsOf), so the headline has to render *something*. The raw
    // code is honest; a wrong label is not.
    expect(helpTagHeadline("teleportation")).toBe("teleportation needed");
  });

  it("exempts only codes that exist", () => {
    for (const code of HELP_TAGS_WITHOUT_NEEDED_SUFFIX) {
      expect(HELP_TAGS).toContain(code);
    }
  });
});

describe("signalHeadline — the phased-release path", () => {
  // The shipped build (6.0.2+129) writes `signalType` and no tags, and keeps
  // doing so until users update. Without the legacy table every one of its
  // signals would headline as "Rescue needed", because helpNeededTagsOf
  // substitutes the fallback for anything untagged — the server discarding a
  // category the client still sends and still means.
  it("keeps the real category for a signal from the shipped build", () => {
    expect(signalHeadline({ signalType: 2 })).toBe("Blood donation needed");
    expect(signalHeadline({ signalType: 1 })).toBe("Lost / found");
    expect(signalHeadline({ signalType: 4 })).toBe("Neutering needed");
    expect(signalHeadline({ signalType: 3 })).toBe("Foster needed");
  });

  it("prefers tags whenever the signal has them", () => {
    // A new-build signal must never be routed through the retired table, even
    // if something upstream also wrote a type.
    expect(signalHeadline({ helpNeededTags: ["foster"], signalType: 0 }))
      .toBe("Foster needed");
    expect(signalHeadline({ helpNeededTags: ["lostFound"] }))
      .toBe("Lost / found");
  });

  it("falls back for a signal carrying neither, or a nonsense type", () => {
    expect(signalHeadline({})).toBe("Rescue needed");
    expect(signalHeadline({ helpNeededTags: [] })).toBe("Rescue needed");
    expect(signalHeadline({ signalType: 99 })).toBe("Rescue needed");
    expect(signalHeadline({ signalType: "two" })).toBe("Rescue needed");
  });

  it("covers every retired type code", () => {
    // 0-6 were the whole vocabulary; a gap would silently become "Rescue".
    for (let type = 0; type <= 6; type++) {
      expect(signalHeadline({ signalType: type })).toBeTruthy();
    }
  });
});

describe("displayTagsOf — the inbox row must not contradict the push", () => {
  // The bug this covers: the inbox entry was written with the MATCHED tags,
  // which collapse an untagged legacy signal to `rescue`, while the push body
  // beside it was built from signalHeadline and said "Blood donation needed".
  // Same event, same document, two different categories.
  it("agrees with the push headline for a legacy signal", () => {
    expect(displayTagsOf({ signalType: 2 })).toEqual(["bloodDonation"]);
    expect(helpTagHeadline(displayTagsOf({ signalType: 2 })[0]))
      .toBe(signalHeadline({ signalType: 2 }));
  });

  it("is the identity for a tagged signal, extra tags and order intact", () => {
    expect(displayTagsOf({ helpNeededTags: ["foster", "transport"] }))
      .toEqual(["foster", "transport"]);
    // A stray legacy type must not displace the tags the reporter chose.
    expect(displayTagsOf({ helpNeededTags: ["adoption"], signalType: 2 }))
      .toEqual(["adoption"]);
  });

  it("falls back exactly where the matched list does", () => {
    expect(displayTagsOf({})).toEqual(["rescue"]);
    expect(displayTagsOf({ helpNeededTags: [] })).toEqual(["rescue"]);
    expect(displayTagsOf({ signalType: 99 })).toEqual(["rescue"]);
  });

  it("never widens the reach a signal was matched with", () => {
    // This value is also written to the inbox doc, which firestore.rules caps
    // at 3 entries — and it must never claim MORE tags than were matched on.
    for (const data of [
      {},
      { signalType: 2 },
      { helpNeededTags: ["foster", "transport", "vetCare"] },
    ]) {
      expect(displayTagsOf(data).length).toBe(helpNeededTagsOf(data).length);
    }
  });
});

describe("primarySignalTag", () => {
  // The share page badge and the push headline both derive from this, so a
  // legacy signal must not be badged "Rescue" on the one page people see
  // before they have the app.
  it("maps a retired type onto the tag that replaced it", () => {
    expect(primarySignalTag({ signalType: 1 })).toBe("lostFound");
    expect(primarySignalTag({ signalType: 2 })).toBe("bloodDonation");
    expect(primarySignalTag({ signalType: 3 })).toBe("foster");
    expect(primarySignalTag({ signalType: 4 })).toBe("neutering");
  });

  it("prefers tags, and falls back when there is nothing to read", () => {
    expect(primarySignalTag({ helpNeededTags: ["adoption"], signalType: 0 }))
      .toBe("adoption");
    expect(primarySignalTag({})).toBe("rescue");
    expect(primarySignalTag({ signalType: 42 })).toBe("rescue");
  });

  it("only ever yields a code the vocabulary knows", () => {
    // An unknown code here would render as a raw string on the share page and
    // in the push, since neither has a label for it.
    for (let type = 0; type <= 6; type++) {
      expect(HELP_TAGS).toContain(primarySignalTag({ signalType: type }));
    }
  });
});

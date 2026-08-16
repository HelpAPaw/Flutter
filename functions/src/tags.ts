/**
 * Help tags and animal types — the vocabulary shared by signals and users.
 *
 * Its own module for the same reason as ./urgency: keeping the vocabulary and
 * its resolution rules in one small file lets the drift guard
 * (`test/help_tag_vocabulary_guard_test.dart`) parse it without booting the
 * functions runtime.
 *
 * The other copy is the Dart one (`lib/src/models/help_tag.dart` and
 * `lib/src/models/animal_type.dart`). That duplication is inherent — two
 * runtimes, no codegen — so it is guarded by a test that fails the build if the
 * two lists diverge. The failure this prevents is silent: a code that exists on
 * one side only means a user who selected it is never matched by the fan-out,
 * and nothing logs an error.
 */

/**
 * Every help-tag code, in the app's display order.
 *
 * Codes are **stable, opaque identifiers**. Never rename or reuse one: they are
 * stored on both signal documents and user profiles, so a rename orphans every
 * document already written.
 */
export const HELP_TAGS = [
  "rescue",
  "vetCare",
  "bloodDonation",
  "foster",
  "adoption",
  "transport",
  "food",
  "trapping",
  "neutering",
  "babyCare",
  "fundraising",
  "lostFound",
  "dangerWarning",
] as const;

/**
 * Human-readable English names, keyed by code.
 *
 * The functions have no i18n, so push text is English-only — the client
 * re-localizes from the structured fields in the inbox entry. Mirrors the
 * `helpTag*` ARB keys.
 */
export const HELP_TAG_NAMES: Record<string, string> = {
  rescue: "Rescue",
  vetCare: "Vet care",
  bloodDonation: "Blood donation",
  foster: "Foster",
  adoption: "Adoption",
  transport: "Transport",
  food: "Food & supplies",
  trapping: "Trapping",
  neutering: "Neutering",
  babyCare: "Newborn care",
  fundraising: "Fundraising",
  lostFound: "Lost / found",
  dangerWarning: "Local danger",
};

/**
 * Codes that do **not** take the `" needed"` suffix in notification headlines.
 *
 * A lost dog is not "Lost / found needed", and a poison-bait warning is not
 * "Local danger needed". These two describe a situation rather than a request
 * for a service.
 *
 * Mirrored by `HelpTag.codesWithoutNeededSuffix` in
 * `lib/src/models/help_tag.dart`, which resolves a whole separate localized
 * string per tag rather than suffixing (Bulgarian does not build this phrase by
 * suffixing). The two lists are compared by
 * `test/help_tag_vocabulary_guard_test.dart`, because a divergence is silent —
 * it surfaces only as one runtime saying "Lost / found needed" and the other
 * not.
 */
export const HELP_TAGS_WITHOUT_NEEDED_SUFFIX = [
  "lostFound",
  "dangerWarning",
] as const;

/**
 * Retired signal types, kept only to headline signals from an app build that
 * still writes them.
 *
 * **This is a live path, not a migration.** Builds released before the tag
 * vocabulary keep creating signals with a `signalType` and no tags for as long
 * as they stay installed, and a phased release means that is months, not days.
 * Without this a Blood-donation report from an old build would push as "Rescue
 * needed", because `helpNeededTagsOf` substitutes the fallback for anything
 * untagged — the server would be discarding a category the client still sends
 * and still means.
 *
 * Index = the stored int. Delete this once the installed base has moved on;
 * nothing else depends on it.
 * Tracking: HelpAPaw/Flutter#70.
 */
const RETIRED_SIGNAL_TYPE_TAGS = [
  "rescue", // 0 Emergency — urgency carries the "emergency" part
  "lostFound", // 1 Lost or Found
  "bloodDonation", // 2
  "foster", // 3 Homeless
  "neutering", // 4 Unneutered animals
  "rescue", // 5 Wild animals — animalType carries the "wild" part
  "rescue", // 6 Other
];

/**
 * The tag code that names a signal's category.
 *
 * Prefers `helpNeededTags[0]`, falling back to the retired `signalType` so a
 * signal from a build that predates the vocabulary keeps its real category
 * everywhere it is shown — the push, and the public share page badge.
 */
export function primarySignalTag(data: {
  helpNeededTags?: unknown;
  signalType?: unknown;
}): string {
  const raw = data.helpNeededTags;
  const tagged = Array.isArray(raw) &&
    raw.some((t) => typeof t === "string" && t.length > 0);
  if (tagged) return helpNeededTagsOf(data)[0];

  const type = data.signalType;
  if (typeof type === "number" &&
      type >= 0 &&
      type < RETIRED_SIGNAL_TYPE_TAGS.length) {
    return RETIRED_SIGNAL_TYPE_TAGS[type];
  }
  return HELP_TAG_FALLBACK;
}

/**
 * Push headline for a signal, honouring a legacy `signalType` when there are no
 * tags to read.
 *
 * Prefers tags whenever the document has them, so a new-build signal is never
 * routed through the retired table.
 */
export function signalHeadline(data: {
  helpNeededTags?: unknown;
  signalType?: unknown;
}): string {
  return helpTagHeadline(primarySignalTag(data));
}

/**
 * Headline form of a tag for push text — "Rescue needed", "Lost / found".
 *
 * Unknown codes (written by a newer client) fall back to the raw code rather
 * than to a wrong label; see `helpNeededTagsOf` for why unknown codes are kept.
 */
export function helpTagHeadline(code: string): string {
  const name = HELP_TAG_NAMES[code] ?? code;
  return (HELP_TAGS_WITHOUT_NEEDED_SUFFIX as readonly string[]).includes(code) ?
    name :
    `${name} needed`;
}

/**
 * The tag a signal or user falls back to when it has none.
 *
 * This is what makes the server deployable ahead of the client. Legacy signals
 * resolve to rescue and so do un-onboarded users, so everything matches
 * everything and the recipient set is unchanged until real tags start arriving.
 */
export const HELP_TAG_FALLBACK = "rescue";

/** Maximum tags one signal may declare. Mirrors Dart's `HelpTag.maxPerSignal`. */
export const MAX_HELP_TAGS_PER_SIGNAL = 3;

/** Every animal-type code. Mirrors Dart's `AnimalType`. */
export const ANIMAL_TYPES = ["cat", "dog", "other"] as const;

/**
 * The help tags a signal is asking for.
 *
 * Signals written before this feature have no `helpNeededTags`, and they must
 * still reach people — so they resolve to [HELP_TAG_FALLBACK] rather than to an
 * empty list, which would match nobody. Unknown codes are kept rather than
 * dropped: a code this build does not recognise came from a *newer* client, and
 * a user on that build will have it too.
 */
export function helpNeededTagsOf(data: { helpNeededTags?: unknown }): string[] {
  const raw = data.helpNeededTags;
  if (!Array.isArray(raw)) return [HELP_TAG_FALLBACK];
  const tags = raw.filter((t): t is string => typeof t === "string");
  return tags.length > 0 ? tags : [HELP_TAG_FALLBACK];
}

/**
 * The help tags a user matches on — never empty.
 *
 * **Absent and empty deliberately mean the same thing here**, which is the
 * opposite of how `animalTypes` behaves in the same preferences map. That one
 * is a filter where empty is a real choice to receive nothing; helper tags are
 * a matching input, and `enabled` is how a user turns notifications off.
 * Mirrors Dart's
 * `NotificationPreferences.effectiveHelperTags` — change both together.
 */
export function effectiveHelperTags(prefs: {
  helperTags?: string[];
}): string[] {
  const tags = prefs.helperTags;
  if (!tags || tags.length === 0) return [HELP_TAG_FALLBACK];
  return tags;
}

/**
 * Whether a user can offer any of the help a signal is asking for.
 *
 * A plain set intersection. Signals and users draw from one vocabulary
 * precisely so that no translation step exists to drift.
 */
export function matchesHelpTags(
  signalTags: string[],
  userTags: string[]
): boolean {
  return signalTags.some((tag) => userTags.includes(tag));
}

/**
 * Whether a signal about `animalType` passes a user's species filter.
 *
 * A null/absent `animalType` is a signal written before the field existed and
 * matches everyone — filtering those out would silently hide every legacy
 * signal from anyone who has chosen species. On the preferences side this is a
 * filter, so absent means all and empty means none. Since `signalTypes` was
 * retired it is the only filter-semantics field left in the preferences map.
 */
export function wantsAnimalType(
  prefs: { animalTypes?: string[] },
  animalType: string | undefined
): boolean {
  if (!animalType) return true;
  if (!prefs.animalTypes) return true;
  return prefs.animalTypes.includes(animalType);
}

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
  "foster",
  "transport",
  "vetCare",
  "food",
  "trapping",
  "fundraising",
  "adoption",
  "babyCare",
] as const;

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
 * opposite of how `signalTypes` and `animalTypes` behave in the same
 * preferences map. Those two are filters where empty is a real choice to
 * receive nothing; helper tags are a matching input, and `enabled` is how a
 * user turns notifications off. Mirrors Dart's
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
 * filter, so absent means all and empty means none, exactly like `signalTypes`.
 */
export function wantsAnimalType(
  prefs: { animalTypes?: string[] },
  animalType: string | undefined
): boolean {
  if (!animalType) return true;
  if (!prefs.animalTypes) return true;
  return prefs.animalTypes.includes(animalType);
}

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// [current] with [code] added if absent, removed if present — as a **new list**.
///
/// Non-mutating on purpose. These selections come from Firestore reads
/// (`.cast<String>()` views), from `const []` field initializers, and from
/// immutable state objects; calling `List.remove` on any of those throws
/// `UnsupportedError` at runtime rather than failing to compile. Every toggle
/// callback goes through here so no call site has to remember that.
///
/// Lives beside the vocabulary rather than with the chip widgets because it is
/// a pure list operation — `NewSignalFormState` uses it, and the state layer
/// must not have to import a widget file to reach it. Shared with
/// [AnimalType] selections, which is why it takes bare codes.
///
/// Adding past [max] is a no-op, matching the disabled chips in the selector.
List<String> toggledCode(List<String> current, String code, {int? max}) {
  if (current.contains(code)) {
    return current.where((c) => c != code).toList();
  }
  if (max != null && current.length >= max) return List.of(current);
  return [...current, code];
}

/// A kind of help — declared by a signal ("this is what is needed") and by a
/// user ("this is what I can do").
///
/// **One vocabulary, both sides.** A signal's `helpNeededTags` and a user's
/// `notificationPreferences.helperTags` draw from this same list, so matching is
/// a plain set intersection rather than a curated mapping table. That is the
/// whole reason the vocabulary is coarse: two lists that need translating
/// between them drift, and the drift is silent — a helper simply stops being
/// notified, with no error anywhere.
///
/// **This is also the signal's category.** There used to be a separate
/// `signalType` (0–6: Emergency, Lost or Found, Blood donation, Homeless,
/// Unneutered animals, Wild animals, Other), but four of its seven values were
/// restatements of fields that now exist in their own right — Emergency is
/// `urgency == red`, Blood donation and Unneutered animals are tags, Wild
/// animals is `animalType == other`. The deciding case was an injured animal:
/// master spec §5 uses it as *the* worked example of Red urgency and gives it no
/// category at all, because an injured animal simply *is* red + `[rescue,
/// vetCare]`. Master spec §4.2 makes the main category the top-priority need, so
/// `helpNeededTags[0]` is that category and no second axis is needed.
///
/// Species is deliberately **not** encoded here. "Can help with cats" crossed
/// with every need is the cross-product the spec's 27-tag list spells out by
/// hand; the app keeps the two axes independent and matches [AnimalType]
/// separately. See `lib/src/models/animal_type.dart`.
///
/// Two of the codes — [lostFound] and [dangerWarning] — are honestly a strain on
/// "both sides": they describe an *interest* rather than an ability. That is
/// modelled as [isNeed], which drives both their "tell me about…" wording and
/// their plain [neededLabel]. **If a third such code ever appears, that is the
/// signal this model really does want a second axis after all.**
///
/// [code] is the value persisted in Firestore. It is a **stable, opaque
/// identifier** — never rename or reuse one once it has shipped, because both
/// stored signals and stored user profiles reference it. Declaration order is
/// the display order.
enum HelpTag {
  rescue(code: 'rescue', icon: Icons.support),
  vetCare(code: 'vetCare', icon: Icons.medical_services),
  bloodDonation(code: 'bloodDonation', icon: Icons.bloodtype),
  foster(code: 'foster', icon: Icons.house),
  adoption(code: 'adoption', icon: Icons.favorite),
  transport(code: 'transport', icon: Icons.directions_car),
  food(code: 'food', icon: Icons.restaurant),
  trapping(code: 'trapping', icon: Icons.grid_on),
  neutering(code: 'neutering', icon: Icons.healing),
  babyCare(code: 'babyCare', icon: Icons.child_care),
  fundraising(code: 'fundraising', icon: Icons.volunteer_activism),
  lostFound(code: 'lostFound', icon: Icons.search, isNeed: false),
  dangerWarning(code: 'dangerWarning', icon: Icons.warning_amber, isNeed: false);

  const HelpTag({
    required this.code,
    required this.icon,
    this.isNeed = true,
  });

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final String code;

  /// Icon shown on the selector chips and on signal details.
  final IconData icon;

  /// Whether this tag names something a case *asks for*.
  ///
  /// True for eleven of the thirteen. [lostFound] and [dangerWarning] describe a
  /// situation instead — a lost dog is not "lost / found needed" — so
  /// [neededLabel] leaves them as their plain [label], and their
  /// [helperDescription] is worded "tell me about…" rather than "I can…".
  ///
  /// **This flag is the behaviour, not a note about it.** It drives
  /// [neededLabel] and derives [codesWithoutNeededSuffix], which is what the
  /// cross-runtime guard compares against `HELP_TAGS_WITHOUT_NEEDED_SUFFIX`. An
  /// earlier version kept the exemption as a hand-written list beside an
  /// exhaustive switch that ignored it, so the guard passed while the two
  /// runtimes disagreed.
  final bool isNeed;

  /// The tag every user and signal falls back to.
  ///
  /// A signal written by an app version that predates this feature has no tags,
  /// and a user who has not passed the onboarding gate has none either. Both
  /// resolve to rescue: it is the broadest need, and defaulting to it makes the
  /// server deployable ahead of the client without changing who gets notified —
  /// everything matches everything until real tags start arriving.
  static const HelpTag fallback = HelpTag.rescue;

  /// Maximum tags a single signal may declare.
  ///
  /// The spec models secondary needs as three priority slots ("most urgent need
  /// now, next need, later need"), and the cap doubles as a reach limit: without
  /// it, tagging a signal with all nine guarantees it matches everyone.
  static const int maxPerSignal = 3;

  /// Every code, for validation and for building selector UIs.
  static final List<String> allCodes =
      List.unmodifiable(values.map((t) => t.code));

  /// Codes whose [neededLabel] is **not** the "X needed" phrasing.
  ///
  /// Derived from [isNeed] rather than hand-written, so it cannot disagree with
  /// the labels it describes. Mirrored by `HELP_TAGS_WITHOUT_NEEDED_SUFFIX` in
  /// `functions/src/tags.ts`, which builds English push text by suffixing
  /// `" needed"` to everything else, and compared against it by
  /// `test/help_tag_vocabulary_guard_test.dart`. A divergence is silent — it
  /// shows up only as one runtime emitting "Lost / found needed" and the other
  /// not.
  static final List<String> codesWithoutNeededSuffix = List.unmodifiable(
    values.where((t) => !t.isNeed).map((t) => t.code),
  );

  /// The headline tag for [codes] — the case's category.
  ///
  /// Element 0 is the category (master spec §4.2), so this takes it verbatim
  /// rather than scanning for the first code it recognises. **Matching the
  /// server matters more than rendering something prettier**: `helpTagHeadline`
  /// in `functions/src/tags.ts` uses `[0]` too, so a signal from a newer client
  /// tagged `['newCode', 'foster']` must not headline as "newCode needed" in the
  /// push and "Foster needed" in the inbox row for the same document.
  ///
  /// Falls back to [fallback] for an empty list or an unrecognised code — the
  /// app has no label for the latter, and the server's raw-code rendering is not
  /// available to it.
  static HelpTag primaryOf(Iterable<String> codes) {
    final first = codes.isEmpty ? null : codes.first;
    return (first == null ? null : fromCode(first)) ?? fallback;
  }

  /// Retired `signalType` values, by the int that was stored.
  ///
  /// The Dart mirror of `RETIRED_SIGNAL_TYPE_TAGS` in `functions/src/tags.ts`,
  /// and guarded against it by `test/help_tag_vocabulary_guard_test.dart`.
  ///
  /// **A live path, not a migration.** Builds released before the vocabulary
  /// keep creating signals with a `signalType` and no tags for as long as they
  /// stay installed. Without this the app renders every one of them as
  /// [fallback] while the server — which has always had this table — headlines
  /// the push with the real category, so the same document reads "Blood
  /// donation needed" on the lock screen and "Rescue" everywhere in the app.
  ///
  /// Delete alongside the server copy once the installed base has moved on.
  /// Tracking: HelpAPaw/Flutter#70.
  static const List<String> retiredSignalTypeCodes = [
    'rescue', // 0 Emergency — urgency carries the "emergency" part
    'lostFound', // 1 Lost or Found
    'bloodDonation', // 2
    'foster', // 3 Homeless
    'neutering', // 4 Unneutered animals
    'rescue', // 5 Wild animals — animalType carries the "wild" part
    'rescue', // 6 Other
  ];

  /// The category of a signal that has [codes], or failing that a legacy
  /// [signalType].
  ///
  /// The Dart mirror of `primarySignalTag`. Tags win whenever the document has
  /// any, so a signal from a current build is never routed through the retired
  /// table; [signalType] is consulted only for the untagged legacy documents it
  /// was written by. Out-of-range and unknown values fall back, exactly as the
  /// server does — an old client cannot be trusted to have written a code this
  /// build knows.
  static HelpTag primaryOfSignal(Iterable<String> codes, int? signalType) {
    if (codes.isNotEmpty) return primaryOf(codes);
    if (signalType == null ||
        signalType < 0 ||
        signalType >= retiredSignalTypeCodes.length) {
      return fallback;
    }
    return fromCode(retiredSignalTypeCodes[signalType]) ?? fallback;
  }

  /// The codes to SHOW for a signal — which is not what the fan-out matched on.
  ///
  /// The Dart mirror of `displayTagsOf` in `functions/src/tags.ts`, and it
  /// exists for the same reason: [effectiveCodes] collapses an untagged signal
  /// to [fallback], so a legacy `signalType: 2` document *matches* as rescue.
  /// That is the right list to match with and the wrong one to store on the
  /// notification it produces — the body is built from [primaryOfSignal], which
  /// honours the retired type, so persisting the matched list makes the inbox
  /// row contradict the notification that announced it.
  ///
  /// Only the primary is substituted: for a tagged signal this is the identity,
  /// and any extra tags survive in the order the reporter gave them.
  static List<String> displayCodes(List<String> codes, int? signalType) =>
      codes.isNotEmpty ? codes : [primaryOfSignal(codes, signalType).code];

  /// [codes] as the matching layer sees them — never empty.
  ///
  /// The Dart mirror of `helpNeededTagsOf` in `functions/src/tags.ts`: a signal
  /// written before tags existed asks for [fallback], so it still reaches the
  /// people who default to it. Every Dart caller that needs "what is this signal
  /// asking for" goes through here rather than open-coding the substitution,
  /// which is how the map, the catch-up and the fan-out stay in agreement about
  /// what an untagged signal is.
  static List<String> effectiveCodes(List<String> codes) =>
      codes.isEmpty ? [fallback.code] : codes;

  /// Resolve a persisted [code], or null if it is unknown.
  ///
  /// Nullable rather than falling back: an unrecognised code means the document
  /// was written by a *newer* client than this one, and silently rendering it as
  /// rescue would misreport what a signal actually needs. Callers drop unknown
  /// codes from display and keep the ones they understand.
  static HelpTag? fromCode(String code) {
    for (final tag in values) {
      if (tag.code == code) return tag;
    }
    return null;
  }

  /// The known tags in [codes], preserving order and dropping unknown ones.
  static List<HelpTag> fromCodes(Iterable<String> codes) =>
      codes.map(fromCode).whereType<HelpTag>().toList();

  /// Localized display label. Exhaustive switch so adding a tag is a compile
  /// error until its label is provided here.
  String label(AppLocalizations l10n) {
    switch (this) {
      case HelpTag.rescue:
        return l10n.helpTagRescue;
      case HelpTag.vetCare:
        return l10n.helpTagVetCare;
      case HelpTag.bloodDonation:
        return l10n.helpTagBloodDonation;
      case HelpTag.foster:
        return l10n.helpTagFoster;
      case HelpTag.adoption:
        return l10n.helpTagAdoption;
      case HelpTag.transport:
        return l10n.helpTagTransport;
      case HelpTag.food:
        return l10n.helpTagFood;
      case HelpTag.trapping:
        return l10n.helpTagTrapping;
      case HelpTag.neutering:
        return l10n.helpTagNeutering;
      case HelpTag.babyCare:
        return l10n.helpTagBabyCare;
      case HelpTag.fundraising:
        return l10n.helpTagFundraising;
      case HelpTag.lostFound:
        return l10n.helpTagLostFound;
      case HelpTag.dangerWarning:
        return l10n.helpTagDangerWarning;
    }
  }

  /// Headline form for a notification — "Rescue needed", not "Rescue".
  ///
  /// A **separate localized string, deliberately not `label` + " needed"**. The
  /// suffix works in English, which is all the server emits, but the notification
  /// inbox is localized on the client and Bulgarian does not build this by
  /// suffixing: "Rescue needed" is "Търси се спасяване", not "Спасяване needed".
  ///
  /// Tags with [isNeed] false return their plain [label] — a lost dog is not
  /// "lost / found needed". That branch is taken before the switch, so those two
  /// need no ARB key of their own and cannot drift from their plain label.
  String neededLabel(AppLocalizations l10n) {
    if (!isNeed) return label(l10n);

    switch (this) {
      case HelpTag.rescue:
        return l10n.helpTagRescueNeeded;
      case HelpTag.vetCare:
        return l10n.helpTagVetCareNeeded;
      case HelpTag.bloodDonation:
        return l10n.helpTagBloodDonationNeeded;
      case HelpTag.foster:
        return l10n.helpTagFosterNeeded;
      case HelpTag.adoption:
        return l10n.helpTagAdoptionNeeded;
      case HelpTag.transport:
        return l10n.helpTagTransportNeeded;
      case HelpTag.food:
        return l10n.helpTagFoodNeeded;
      case HelpTag.trapping:
        return l10n.helpTagTrappingNeeded;
      case HelpTag.neutering:
        return l10n.helpTagNeuteringNeeded;
      case HelpTag.babyCare:
        return l10n.helpTagBabyCareNeeded;
      case HelpTag.fundraising:
        return l10n.helpTagFundraisingNeeded;
      // Handled by the `!isNeed` branch above, but still listed so that adding
      // a tag stays a compile error here.
      case HelpTag.lostFound:
      case HelpTag.dangerWarning:
        return label(l10n);
    }
  }

  /// What a user is signing up for by choosing this tag.
  ///
  /// Shown under each option in the onboarding gate. People pick tags once and
  /// then live with the notifications for months, so the guidance travels with
  /// the choice rather than living in a help page nobody opens — the same
  /// reasoning as [SignalUrgency.description].
  String helperDescription(AppLocalizations l10n) {
    switch (this) {
      case HelpTag.rescue:
        return l10n.helpTagRescueHelper;
      case HelpTag.vetCare:
        return l10n.helpTagVetCareHelper;
      case HelpTag.bloodDonation:
        return l10n.helpTagBloodDonationHelper;
      case HelpTag.foster:
        return l10n.helpTagFosterHelper;
      case HelpTag.adoption:
        return l10n.helpTagAdoptionHelper;
      case HelpTag.transport:
        return l10n.helpTagTransportHelper;
      case HelpTag.food:
        return l10n.helpTagFoodHelper;
      case HelpTag.trapping:
        return l10n.helpTagTrappingHelper;
      case HelpTag.neutering:
        return l10n.helpTagNeuteringHelper;
      case HelpTag.babyCare:
        return l10n.helpTagBabyCareHelper;
      case HelpTag.fundraising:
        return l10n.helpTagFundraisingHelper;
      case HelpTag.lostFound:
        return l10n.helpTagLostFoundHelper;
      case HelpTag.dangerWarning:
        return l10n.helpTagDangerWarningHelper;
    }
  }
}

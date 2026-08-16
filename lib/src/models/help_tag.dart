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
/// Species is deliberately **not** encoded here. "Can help with cats" crossed
/// with nine needs is the cross-product the spec's 27-tag list spells out by
/// hand; the app keeps the two axes independent and matches [AnimalType]
/// separately. See `lib/src/models/animal_type.dart`.
///
/// [code] is the value persisted in Firestore. It is a **stable, opaque
/// identifier** — never rename or reuse one once it has shipped, because both
/// stored signals and stored user profiles reference it. Declaration order is
/// the display order.
enum HelpTag {
  rescue(code: 'rescue', icon: Icons.support),
  foster(code: 'foster', icon: Icons.house),
  transport(code: 'transport', icon: Icons.directions_car),
  vetCare(code: 'vetCare', icon: Icons.medical_services),
  food(code: 'food', icon: Icons.restaurant),
  trapping(code: 'trapping', icon: Icons.grid_on),
  fundraising(code: 'fundraising', icon: Icons.volunteer_activism),
  adoption(code: 'adoption', icon: Icons.favorite),
  babyCare(code: 'babyCare', icon: Icons.child_care);

  const HelpTag({required this.code, required this.icon});

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final String code;

  /// Icon shown on the selector chips and on signal details.
  final IconData icon;

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
      case HelpTag.foster:
        return l10n.helpTagFoster;
      case HelpTag.transport:
        return l10n.helpTagTransport;
      case HelpTag.vetCare:
        return l10n.helpTagVetCare;
      case HelpTag.food:
        return l10n.helpTagFood;
      case HelpTag.trapping:
        return l10n.helpTagTrapping;
      case HelpTag.fundraising:
        return l10n.helpTagFundraising;
      case HelpTag.adoption:
        return l10n.helpTagAdoption;
      case HelpTag.babyCare:
        return l10n.helpTagBabyCare;
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
      case HelpTag.foster:
        return l10n.helpTagFosterHelper;
      case HelpTag.transport:
        return l10n.helpTagTransportHelper;
      case HelpTag.vetCare:
        return l10n.helpTagVetCareHelper;
      case HelpTag.food:
        return l10n.helpTagFoodHelper;
      case HelpTag.trapping:
        return l10n.helpTagTrappingHelper;
      case HelpTag.fundraising:
        return l10n.helpTagFundraisingHelper;
      case HelpTag.adoption:
        return l10n.helpTagAdoptionHelper;
      case HelpTag.babyCare:
        return l10n.helpTagBabyCareHelper;
    }
  }
}

import 'animal_type.dart';
import 'help_tag.dart';

/// A user's `users/{uid}.notificationPreferences` map, typed.
///
/// The Dart twin of `UserNotificationPrefs` in `functions/src/index.ts`. The
/// server already had a type for this shape while the client read it as four
/// untyped string keys in three different places, each with its own defaults —
/// so a renamed field would have been a silent no-notifications bug on the
/// client and a compile error on the server.
///
/// Read through `UserRepository.getNotificationPreferences`, which owns the
/// fetch, the timeout and the error policy. Every field has a default, so a
/// user who has never opened the settings screen still gets sensible values.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = false,
    this.locationTrackingEnabled = false,
    this.locationRadiusKm = defaultRadiusKm,
    this.animalTypes,
    this.helperTags,
    this.regionOfInterest,
  });

  /// Radius used when the user has never chosen one.
  ///
  /// Matches the settings screen's initial slider position and the fan-out's
  /// own default, so all three agree on what "nearby" means.
  static const double defaultRadiusKm = 10.0;

  /// Master switch. Everything else is inert while this is false.
  final bool enabled;

  /// Whether the user agreed to have their location tracked and stored.
  final bool locationTrackingEnabled;

  /// How far away a signal can be and still be worth notifying about.
  final double locationRadiusKm;

  /// Animal species the user wants, or null if they have never chosen.
  ///
  /// A **filter**, and the null-vs-empty distinction is load-bearing: null is
  /// "no preference expressed" and reads as *all species*, empty is a
  /// deliberate choice and reads as *no species*. Collapsing the two (here or
  /// in the fan-out) is what once made "Deselect all" behave as "select all".
  /// Codes are [AnimalType.code].
  final List<String>? animalTypes;

  /// Kinds of help the user says they can offer — [HelpTag.code] values.
  ///
  /// **This field uses the opposite null/empty rule from [animalTypes], and
  /// that is deliberate.** That one is a filter, where "empty" is a
  /// meaningful choice to receive nothing. Helper tags are a
  /// *matching input*, not an opt-out mechanism — [enabled] is how a user turns
  /// notifications off. So absent and empty both mean "hasn't chosen", and both
  /// resolve to [HelpTag.fallback] through [effectiveHelperTags]. Reading this
  /// list directly, rather than through that getter, is the bug to avoid: a
  /// user mid-migration would match nothing and silently stop being notified.
  final List<String>? helperTags;

  /// Optional fixed area of interest, independent of the user's own position.
  /// Left as a raw map: only the fan-out interprets it, and it does so in
  /// TypeScript.
  final Map<String, dynamic>? regionOfInterest;

  /// Whether a signal about [animalType] passes the user's species filter.
  ///
  /// A null [animalType] is a signal written before the field existed. It
  /// matches everyone: filtering those out would silently hide every legacy
  /// signal from anyone who has picked species.
  bool wantsAnimalType(String? animalType) {
    if (animalType == null) return true;
    return animalTypes?.contains(animalType) ?? true;
  }

  /// Whether the user has actually picked their helper tags.
  ///
  /// Distinct from [effectiveHelperTags], which never returns empty and so can
  /// never answer this. The onboarding gate and the notification onboarding
  /// both branch on it, and they must agree — two hand-rolled copies of
  /// `tags != null && tags.isNotEmpty` is how the sheet ended up stacked on top
  /// of the gate.
  bool get hasChosenHelperTags => helperTags?.isNotEmpty ?? false;

  /// The tags this user actually matches on — never empty.
  ///
  /// See [helperTags] for why absent and empty collapse to the same answer.
  List<String> get effectiveHelperTags {
    final tags = helperTags;
    if (tags == null || tags.isEmpty) return [HelpTag.fallback.code];
    return tags;
  }

  /// Whether the user can offer any of the help a signal is asking for.
  ///
  /// A plain set intersection — signals and users draw from one vocabulary
  /// precisely so no translation step can drift. An empty [signalTags] means a
  /// signal that predates the field, which is treated as asking for
  /// [HelpTag.fallback] so it still reaches the people who default to it.
  bool matchesSignalTags(List<String> signalTags) {
    final needed =
        signalTags.isEmpty ? [HelpTag.fallback.code] : signalTags;
    final mine = effectiveHelperTags;
    return needed.any(mine.contains);
  }

  factory NotificationPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NotificationPreferences();

    return NotificationPreferences(
      enabled: map['enabled'] == true,
      locationTrackingEnabled: map['locationTrackingEnabled'] == true,
      // `num` rather than `double`: Firestore returns a whole number as an int,
      // so a radius saved as 10 would fail a straight `as double?` cast.
      locationRadiusKm:
          (map['locationRadiusKm'] as num?)?.toDouble() ?? defaultRadiusKm,
      // Left null when the key is absent — see [animalTypes]. Do not add a
      // `?? const []` here; that is the bug this distinction exists to fix.
      //
      // `signalTypes` is deliberately not read — retired with SPECIFICATION
      // §4.4. It survives on old user documents and is never rewritten, because
      // that would opt people back into something they chose against.
      animalTypes: (map['animalTypes'] as List<dynamic>?)?.cast<String>(),
      helperTags: (map['helperTags'] as List<dynamic>?)?.cast<String>(),
      regionOfInterest: map['regionOfInterest'] as Map<String, dynamic>?,
    );
  }
}

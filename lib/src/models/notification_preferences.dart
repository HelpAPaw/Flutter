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
    this.signalTypes,
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

  /// Signal types the user wants, or null if they have never chosen.
  ///
  /// **Null and empty mean opposite things, and the distinction is
  /// load-bearing.** Null is "no preference expressed" and must be read as
  /// *all types*: the onboarding sheet builds `notificationPreferences` with
  /// merged partial writes and never sets this field, so every user who
  /// onboarded without opening the notification settings screen has no stored
  /// list. Empty is a deliberate "Deselect all" and must be read as *no types*
  /// — it can only be produced by that button.
  ///
  /// These were previously collapsed (both here and in the fan-out's
  /// `length > 0` check), which made "Deselect all" behave as "select all".
  final List<int>? signalTypes;

  /// Optional fixed area of interest, independent of the user's own position.
  /// Left as a raw map: only the fan-out interprets it, and it does so in
  /// TypeScript.
  final Map<String, dynamic>? regionOfInterest;

  /// Whether [signalType] passes the user's type filter.
  bool wantsSignalType(int signalType) =>
      signalTypes?.contains(signalType) ?? true;

  factory NotificationPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NotificationPreferences();

    return NotificationPreferences(
      enabled: map['enabled'] == true,
      locationTrackingEnabled: map['locationTrackingEnabled'] == true,
      // `num` rather than `double`: Firestore returns a whole number as an int,
      // so a radius saved as 10 would fail a straight `as double?` cast.
      locationRadiusKm:
          (map['locationRadiusKm'] as num?)?.toDouble() ?? defaultRadiusKm,
      // Left null when the key is absent — see [signalTypes]. Do not add a
      // `?? const []` here; that is the bug this distinction exists to fix.
      signalTypes: (map['signalTypes'] as List<dynamic>?)?.cast<int>(),
      regionOfInterest: map['regionOfInterest'] as Map<String, dynamic>?,
    );
  }
}

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Single source of truth for a signal's urgency (label, color, map pin, code).
///
/// Urgency is **separate from [SignalStatus]**: status says how far along the
/// response is ("nobody has picked this up" / "someone is on it" / "done"),
/// urgency says how bad it is if nobody acts. A resolved signal and a signal nobody
/// has touched can both be Green; a signal someone is already working on can
/// still be Red.
///
/// The map pin color encodes **urgency only** — status is shown as a text chip
/// on the details screen and in My Signals. Sharing the traffic light between
/// the two is what this type exists to stop: a screen of red pins has to mean
/// "these animals may die", not "nobody has clicked In progress yet".
///
/// [code] is the value persisted in Firestore (`Signal.urgency`). It is a
/// **stable, opaque identifier — not an ordering**. Never change or reuse a
/// code once it has shipped. Declaration order is the display order (least to
/// most urgent, matching how the levels are presented to the user).
enum SignalUrgency {
  green(
    code: 0,
    color: Colors.green,
    pinAsset: 'assets/icons/pin_green.png',
  ),
  amber(
    code: 1,
    color: Colors.orange,
    pinAsset: 'assets/icons/pin_orange.png',
  ),
  red(
    code: 2,
    color: Colors.red,
    pinAsset: 'assets/icons/pin_red.png',
  );

  const SignalUrgency({
    required this.code,
    required this.color,
    required this.pinAsset,
  });

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final int code;

  /// Color for urgency badges, text and accents.
  final Color color;

  /// Map-pin / list icon asset for this urgency.
  final String pinAsset;

  /// Resolve a persisted [code] to an urgency.
  ///
  /// Unknown/legacy values fall back to [amber] — deliberately not [green],
  /// which would hide a signal that might be real, and not [red], which would
  /// cry wolf and erode the whole signal.
  static SignalUrgency fromCode(int code) =>
      values.firstWhere((u) => u.code == code, orElse: () => amber);

  /// Urgency for a signal document that predates this field.
  ///
  /// Mirrors the backfill script's mapping so a document the script missed
  /// still renders the same way it will once it is written: a resolved signal is
  /// under control, anything else needs help but is not assumed critical.
  /// Nothing is ever derived as [red] — that is a human judgement.
  static SignalUrgency fromLegacyStatus(int statusCode) =>
      statusCode == 2 ? green : amber;

  /// Whether marking a signal at this level requires explicit confirmation.
  ///
  /// Red Alert is only meaningful while it stays rare, so promoting a signal to
  /// it is gated behind [RedAlertConfirmationDialog].
  bool get requiresConfirmation => this == SignalUrgency.red;

  /// Localized display label. Exhaustive switch so adding an urgency is a
  /// compile error until its label is provided here.
  String label(AppLocalizations l10n) {
    switch (this) {
      case SignalUrgency.green:
        return l10n.urgencyGreen;
      case SignalUrgency.amber:
        return l10n.urgencyAmber;
      case SignalUrgency.red:
        return l10n.urgencyRed;
    }
  }

  /// One-line explanation of when this level applies.
  ///
  /// Shown under each option in the picker. The system collapses if people
  /// guess what the levels mean, so the guidance travels with the choice
  /// rather than living in a help page nobody opens.
  String description(AppLocalizations l10n) {
    switch (this) {
      case SignalUrgency.green:
        return l10n.urgencyGreenDescription;
      case SignalUrgency.amber:
        return l10n.urgencyAmberDescription;
      case SignalUrgency.red:
        return l10n.urgencyRedDescription;
    }
  }
}

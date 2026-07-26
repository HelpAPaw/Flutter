import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Single source of truth for a signal's status (label, color, map pin, code).
///
/// [code] is the value persisted in Firestore (`Signal.status`). It is a
/// **stable, opaque identifier — not an ordering**. Never change or reuse a
/// code once it has shipped.
///
/// Declaration order is the display / progression order. To add a status,
/// append an enum value with the next free [code] and place it in the desired
/// position; existing stored codes stay valid, so no data migration is needed.
/// For example, inserting "On hold" between [inProgress] and [resolved]:
///
/// ```dart
/// needsHelp(code: 0, ...),
/// inProgress(code: 1, ...),
/// onHold(code: 3, ...),   // next free code, slotted into the right position
/// resolved(code: 2, ...), // keeps code 2 in the DB
/// ```
enum SignalStatus {
  needsHelp(
    code: 0,
    color: Colors.red,
    pinAsset: 'assets/icons/pin_red.png',
  ),
  inProgress(
    code: 1,
    color: Colors.orange,
    pinAsset: 'assets/icons/pin_orange.png',
  ),
  resolved(
    code: 2,
    color: Colors.green,
    pinAsset: 'assets/icons/pin_green.png',
  );

  const SignalStatus({
    required this.code,
    required this.color,
    required this.pinAsset,
  });

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final int code;

  /// Color for status badges, text and accents.
  final Color color;

  /// Map-pin / list icon asset for this status.
  final String pinAsset;

  /// Resolve a persisted [code] to a status, defaulting to [needsHelp] for any
  /// unknown/legacy value (the safe "still needs attention" default).
  static SignalStatus fromCode(int code) =>
      values.firstWhere((s) => s.code == code, orElse: () => needsHelp);

  /// Whether this status means the animal still needs attention.
  bool get isOpen => this != SignalStatus.resolved;

  /// Codes for every status that still needs attention.
  ///
  /// Derived from [values] rather than written out, so appending a status
  /// automatically includes it. Used as a Firestore `whereIn` filter, which
  /// caps out at 30 values — not a concern at this cardinality.
  static List<int> get openCodes =>
      values.where((s) => s.isOpen).map((s) => s.code).toList();

  /// Localized display label. Exhaustive switch so adding a status is a
  /// compile error until its label is provided here.
  String label(AppLocalizations l10n) {
    switch (this) {
      case SignalStatus.needsHelp:
        return l10n.statusNeedsHelp;
      case SignalStatus.inProgress:
        return l10n.statusInProgress;
      case SignalStatus.resolved:
        return l10n.statusResolved;
    }
  }
}

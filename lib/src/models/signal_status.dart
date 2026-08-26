import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Single source of truth for a signal's status (label, glyph, code).
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
  needsHelp(code: 0, icon: Icons.error_outline),
  inProgress(code: 1, icon: Icons.autorenew),
  resolved(code: 2, icon: Icons.check_circle_outline);

  const SignalStatus({
    required this.code,
    required this.icon,
  });

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final int code;

  /// Glyph for status badges, chips and list accents.
  ///
  /// **Status has no colour, by design.** It used to be red/amber/green — the
  /// same three colours as [SignalUrgency], carrying the opposite meaning. A
  /// row showed two unlabelled traffic-light chips stacked on each other, and
  /// green+red, red+green, green+green and red+red were all reachable on one
  /// list. Whichever one you read first taught you the wrong thing about the
  /// other.
  ///
  /// So the app has exactly one colour axis now: colour means urgency, always
  /// — on the map, in a chip, in the history. Status is a neutral glyph
  /// instead, which also survives being read by someone who cannot separate
  /// red from green, and by anyone reading Bulgarian, where the two labels are
  /// near-homographs ("нужна е помощ скоро" vs "нужна е помощ").
  final IconData icon;

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
  ///
  /// A lazily-initialized constant rather than a getter: it is passed straight
  /// into a query on the background check's hot path, and the result can never
  /// vary. Unmodifiable so a caller can't corrupt the shared instance.
  static final List<int> openCodes = List.unmodifiable(
    values.where((s) => s.isOpen).map((s) => s.code),
  );

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

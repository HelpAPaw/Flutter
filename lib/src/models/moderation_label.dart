import '../../l10n/app_localizations.dart';

/// A warning label a moderator can pin to a signal (master spec §18.3, "Add
/// warning label").
///
/// [code] is the value persisted in `signals/{id}.moderation.label`. It is a
/// **stable, opaque identifier** — never rename or reuse one once it has
/// shipped, because stored signals reference it. Declaration order is the
/// display order.
///
/// **The other copy is `MODERATION_LABELS` in `functions/src/moderation.ts`**,
/// which is where the value is validated before it is written — the label is
/// only ever set through the `moderateAction` callable, never by a client. The
/// two are guarded by `test/moderation_label_vocabulary_guard_test.dart`, which
/// parses the TypeScript rather than restating it, exactly as the help-tag and
/// signal-event vocabularies are (see docs/SPECIFICATION.md §12).
///
/// The failure modes are the usual asymmetric pair: a code only the server
/// knows is stored and then renders as **nothing** (the banner switch falls
/// through), while a code only Dart knows is rejected by the callable with a
/// loud `invalid-argument`. The silent one is why this is guarded.
enum ModerationLabel {
  unverified(code: 'unverified'),
  duplicate(code: 'duplicate'),
  disputed(code: 'disputed');

  const ModerationLabel({required this.code});

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final String code;

  /// Resolve a persisted [code], returning null for anything unrecognised.
  ///
  /// Null rather than a default: an unknown label means this build is older
  /// than the moderator's, and showing a raw code to a user reading a signal
  /// would be worse than showing no banner at all.
  static ModerationLabel? fromCode(String? code) {
    if (code == null) return null;
    for (final label in values) {
      if (label.code == code) return label;
    }
    return null;
  }

  /// Localized banner text. Exhaustive switch so adding a label is a compile
  /// error until its string is provided here.
  String label(AppLocalizations l10n) {
    switch (this) {
      case ModerationLabel.unverified:
        return l10n.moderationLabelUnverified;
      case ModerationLabel.duplicate:
        return l10n.moderationLabelDuplicate;
      case ModerationLabel.disputed:
        return l10n.moderationLabelDisputed;
    }
  }
}

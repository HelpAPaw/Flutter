import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// What a user is reporting a signal, comment or person *for* — master spec
/// §18.1 ("What Users Can Report").
///
/// [code] is the value persisted in Firestore (`reports/{id}.reason`). It is a
/// **stable, opaque identifier** — never rename or reuse one once it has
/// shipped, because stored reports and the moderator's audit trail reference
/// it. Declaration order is the display order in the report sheet.
///
/// **Deliberately not validated against an allow-list in `firestore.rules`.**
/// Same reasoning as `isValidHelpNeededTags()`: a newer app build may know a
/// code this deployed ruleset has never heard of, and rejecting it would break
/// the new build rather than the old one. An unrecognised code still reaches a
/// moderator, who can read the free-text details.
///
/// Two of the spec's fourteen reasons are missing on purpose —
/// `fundraisingConcern` and `adoptionFosterConcern` — because this app has
/// neither fundraisers nor adoption listings yet. A reason nobody can act on is
/// worse than no reason: it teaches reporters the list is decorative. Add them
/// with their features.
enum ReportReason {
  fraud(code: 'fraud', icon: Icons.money_off),
  abuse(code: 'abuse', icon: Icons.pets),
  harassment(code: 'harassment', icon: Icons.person_off),
  falseInformation(code: 'falseInformation', icon: Icons.fact_check),
  dangerousAdvice(code: 'dangerousAdvice', icon: Icons.dangerous),
  animalEndangerment(code: 'animalEndangerment', icon: Icons.warning),
  graphicContent(code: 'graphicContent', icon: Icons.visibility_off),
  spam(code: 'spam', icon: Icons.block),
  doxxing(code: 'doxxing', icon: Icons.privacy_tip),
  defamationRisk(code: 'defamationRisk', icon: Icons.gavel),
  duplicateCase(code: 'duplicateCase', icon: Icons.copy_all),
  other(code: 'other', icon: Icons.more_horiz);

  const ReportReason({
    required this.code,
    required this.icon,
  });

  /// Stable identifier persisted in Firestore. Never change or reuse.
  final String code;

  /// Icon shown beside the reason in the report sheet.
  final IconData icon;

  /// Resolve a persisted [code], returning null for anything unrecognised.
  ///
  /// Null rather than a default, because the moderator queue renders the raw
  /// code when this fails. Silently folding an unknown reason into [other]
  /// would hide exactly the case worth seeing: a report written by a build
  /// newer than the one reading it.
  static ReportReason? fromCode(String code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }

  /// Localized display label. Exhaustive switch so adding a reason is a compile
  /// error until its label is provided here.
  String label(AppLocalizations l10n) {
    switch (this) {
      case ReportReason.fraud:
        return l10n.reportReasonFraud;
      case ReportReason.abuse:
        return l10n.reportReasonAbuse;
      case ReportReason.harassment:
        return l10n.reportReasonHarassment;
      case ReportReason.falseInformation:
        return l10n.reportReasonFalseInformation;
      case ReportReason.dangerousAdvice:
        return l10n.reportReasonDangerousAdvice;
      case ReportReason.animalEndangerment:
        return l10n.reportReasonAnimalEndangerment;
      case ReportReason.graphicContent:
        return l10n.reportReasonGraphicContent;
      case ReportReason.spam:
        return l10n.reportReasonSpam;
      case ReportReason.doxxing:
        return l10n.reportReasonDoxxing;
      case ReportReason.defamationRisk:
        return l10n.reportReasonDefamationRisk;
      case ReportReason.duplicateCase:
        return l10n.reportReasonDuplicateCase;
      case ReportReason.other:
        return l10n.reportReasonOther;
    }
  }
}

/// What a report points at.
///
/// [code] is persisted as `reports/{id}.targetType` and is part of the report's
/// **document id** (`{uid}_{targetType}_{targetId}`), which is what enforces
/// one report per user per target. Never rename a code: it would let the same
/// user re-report a target they had already reported.
enum ReportTargetType {
  signal('signal'),
  comment('comment'),
  user('user');

  const ReportTargetType(this.code);

  /// Stable identifier persisted in Firestore and embedded in the report id.
  final String code;

  static ReportTargetType? fromCode(String code) {
    for (final type in values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

/// The thing being reported, resolved to everything the report document needs.
///
/// A value type rather than loose parameters so the details screen cannot
/// build a comment report that forgets its `signalId` — without it a moderator
/// has a comment id and no way to find the comment.
@immutable
class ReportTarget {
  const ReportTarget._({
    required this.type,
    required this.targetId,
    required this.collection,
    this.signalId,
    this.reportedUserId,
  });

  /// A whole signal, in [collection] (`signals` or `signals_test`).
  factory ReportTarget.signal({
    required String signalId,
    required String collection,
    String? reportedUserId,
  }) =>
      ReportTarget._(
        type: ReportTargetType.signal,
        targetId: signalId,
        collection: collection,
        signalId: signalId,
        reportedUserId: reportedUserId,
      );

  /// One comment. [signalId] is required — a comment id alone is unresolvable.
  factory ReportTarget.comment({
    required String commentId,
    required String signalId,
    required String collection,
    String? reportedUserId,
  }) =>
      ReportTarget._(
        type: ReportTargetType.comment,
        targetId: commentId,
        collection: collection,
        signalId: signalId,
        reportedUserId: reportedUserId,
      );

  /// A person, reported from wherever their name appears.
  factory ReportTarget.user({
    required String userId,
    required String collection,
  }) =>
      ReportTarget._(
        type: ReportTargetType.user,
        targetId: userId,
        collection: collection,
        reportedUserId: userId,
      );

  final ReportTargetType type;

  /// Id of the reported thing itself — signal, comment or user.
  final String targetId;

  /// Which signal collection this report belongs to (`signals` /
  /// `signals_test`). Carried even on a user report so the moderator queue can
  /// stay split by test mode, exactly like the notification inbox.
  final String collection;

  /// Parent signal, for a comment report. Null for a user report.
  final String? signalId;

  /// The person answerable for the reported content, when it is known.
  final String? reportedUserId;

  /// Deterministic report id — **this is the rate limit.**
  ///
  /// One report per user per target, enforced by rules that allow `create` and
  /// deny `update`: a second attempt hits an existing document and is denied.
  /// That is why no `reportThrottle` collection exists (contrast
  /// `feedbackThrottle`, which throttles an *email*, not a write).
  String documentId(String reporterUid) =>
      '${reporterUid}_${type.code}_$targetId';
}

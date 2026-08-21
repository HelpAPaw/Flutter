import 'package:flutter/foundation.dart';

import 'report_reason.dart';

/// What a moderator is about to act on.
///
/// The counterpart to [ReportTarget], and deliberately **not** that class: a
/// report is filed by a user who always knows what they are reporting, so
/// [ReportTarget] can require a non-null `collection` and `type`. A moderation
/// target may instead be reconstructed from a stored report document whose
/// fields this build cannot decode — see [ModerationTarget.fromReport] — and
/// the safe answer there is "unknown", not a default.
///
/// This type is what let the action sheet stop being report-shaped. Before it,
/// the sheet read `targetType` / `collection` / `signalId` straight out of a raw
/// report map, which made a filed report a hard prerequisite for every moderator
/// power: a moderator could only act on content somebody else had reported, never
/// on something they came across while browsing (master spec §18.3 assumes the
/// opposite — "hide or escalate problematic posts" is a frontline power).
@immutable
class ModerationTarget {
  const ModerationTarget._({
    required this.type,
    required this.targetId,
    required this.collection,
    this.signalId,
  });

  /// A whole signal, in [collection] (`signals` or `signals_test`).
  factory ModerationTarget.signal({
    required String signalId,
    required String collection,
  }) =>
      ModerationTarget._(
        type: ReportTargetType.signal,
        targetId: signalId,
        collection: collection,
        signalId: signalId,
      );

  /// One comment. [signalId] is required — a comment id alone is unresolvable.
  factory ModerationTarget.comment({
    required String commentId,
    required String signalId,
    required String collection,
  }) =>
      ModerationTarget._(
        type: ReportTargetType.comment,
        targetId: commentId,
        collection: collection,
        signalId: signalId,
      );

  /// Rebuilds the target a stored report points at.
  ///
  /// Every field is allowed to come back null, and that is the point. This
  /// decoding used to live in the action sheet's getters, and its two safety
  /// properties move here unchanged:
  ///
  /// - [collection] is **never defaulted to `'signals'`**. Defaulting would act
  ///   on PRODUCTION content for a report whose collection could not be read.
  ///   The rules make the field mandatory so this is near-unreachable, but the
  ///   safe failure is to offer no signal-targeting action at all.
  /// - [type] is decoded through [ReportTargetType.fromCode] rather than
  ///   compared as a raw string, so the vocabulary is not spelled out a second
  ///   time in Dart. A report filed by a build newer than this one decodes to
  ///   null and narrows the menu instead of mis-targeting.
  factory ModerationTarget.fromReport(Map<String, dynamic> report) =>
      ModerationTarget._(
        type: ReportTargetType.fromCode(report['targetType'] as String? ?? ''),
        targetId: report['targetId'] as String? ?? '',
        collection: report['collection'] as String?,
        signalId: report['signalId'] as String?,
      );

  /// Null when the report names a target kind this build cannot decode.
  final ReportTargetType? type;

  /// Id of the thing itself — signal or comment.
  final String targetId;

  /// Which signal collection to act in. Null only on the [fromReport] path.
  final String? collection;

  /// Parent signal. Same value as [targetId] for a signal target.
  final String? signalId;

  /// Whether a signal-targeting action may be offered at all.
  ///
  /// One definition rather than the three-part `signalId != null &&
  /// signalId.isNotEmpty && collection != null` condition the sheet was
  /// repeating inline.
  bool get canActOnSignal =>
      collection != null && signalId != null && signalId!.isNotEmpty;
}

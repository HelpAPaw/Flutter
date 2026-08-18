import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/report_reason.dart';
import 'app_preferences_service.dart';
import 'callable_client.dart';

/// Reporting (master spec 18.1) and moderator powers (18.3).
///
/// Two halves with very different trust levels, deliberately in one place so
/// the split is visible: **filing a report** is a direct Firestore write any
/// signed-in user may make, while **every moderator action** goes through the
/// `moderateAction` callable, because each one has to leave an audit entry that
/// the acting moderator cannot forge.
class ModerationService {
  ModerationService._();
  static final ModerationService instance = ModerationService._();

  static const String _moderatorsCollection = 'moderators';
  static const String _reportsCollection = 'reports';

  /// Longest free-text detail on a report. Mirrors the 1000-char bound in
  /// `firestore.rules` — see the field-length invariant in
  /// docs/SPECIFICATION.md §12.
  static const int maxDetailsLength = 1000;

  /// Longest moderator note. Mirrors `MAX_EVENT_NOTE_LENGTH` in
  /// `functions/src/events.ts` and `isValidEventNote()` in the rules, because a
  /// `setUrgency` note is written straight into a timeline event.
  static const int maxNoteLength = 500;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Whether the signed-in user holds the moderator role, live.
  ///
  /// Rebuilds on auth changes and then listens to `moderators/{uid}`, which the
  /// rules let a user `get` only for themselves. A revocation therefore removes
  /// the moderation UI immediately — the property a custom auth claim could not
  /// give us, since a claim survives in the ID token until it expires
  /// (device-verified in both directions, 2026-08-17).
  ///
  /// This is a **UI affordance only**. The real boundary is the same check
  /// inside the `moderateAction` callable and in `firestore.rules`, so a stale
  /// `true` costs nothing worse than a button that returns `permission-denied`.
  ///
  /// Deliberately the only role API, and deliberately uncached: an earlier
  /// one-shot `isModerator()` with a uid-keyed cache existed alongside it, and
  /// nothing ever called it. Callers memoize this stream in their own State —
  /// see `_moderatorStream` in `HomeRouteDrawer` — which is where the caching
  /// belongs, because only the caller knows its rebuild pattern.
  ///
  /// Errors are swallowed to `false`: offline, the right answer to "should I
  /// draw the moderation entry point" is no.
  Stream<bool> watchIsModerator() {
    return FirebaseAuth.instance.userChanges().asyncExpand((user) {
      if (user == null) return Stream<bool>.value(false);
      return _db
          .collection(_moderatorsCollection)
          .doc(user.uid)
          .snapshots()
          .map((doc) => doc.exists)
          .handleError((Object e) {
            debugPrint('Moderator role stream failed: $e');
          });
    });
  }

  /// Files a report (spec 18.1).
  ///
  /// Written at a **deterministic id** — `{uid}_{targetType}_{targetId}` — and
  /// that is the whole rate limit: the rules allow `create` and deny `update`,
  /// so a second report of the same target by the same person is rejected by
  /// the server. [alreadyReported] is returned so the UI can say so plainly
  /// rather than presenting a permission error.
  ///
  /// Not a callable, unlike every moderator action: a report is an ordinary
  /// user write with no privilege attached, and routing it through a function
  /// would cost an invocation per report to gain nothing.
  Future<ReportOutcome> report({
    required ReportTarget target,
    required ReportReason reason,
    String details = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return ReportOutcome.notSignedIn;

    final trimmed = details.trim();
    if (trimmed.length > maxDetailsLength) {
      return ReportOutcome.failed;
    }

    final data = <String, dynamic>{
      'targetType': target.type.code,
      'targetId': target.targetId,
      'collection': target.collection,
      'reason': reason.code,
      'details': trimmed,
      'reporterId': uid,
      'status': 'open',
      'testMode': AppPreferencesService().isTestMode(),
      'createdAt': FieldValue.serverTimestamp(),
      if (target.signalId != null) 'signalId': target.signalId,
      if (target.reportedUserId != null)
        'reportedUserId': target.reportedUserId,
    };

    try {
      // `create`-only semantics: this throws rather than overwriting when the
      // document already exists, which is how the one-per-target limit surfaces.
      //
      // Time-boxed because a Firestore write only completes on server ack, and
      // offline persistence is on by default — so offline this future never
      // settles at all. The dialog has already disabled its Submit button by
      // then, leaving it dead with no snackbar and no way out. Reporting a
      // failure is the honest answer: the write may still flush later, but the
      // one thing we must not do is leave the user staring at a frozen dialog.
      await _db
          .collection(_reportsCollection)
          .doc(target.documentId(uid))
          .set(data)
          .timeout(const Duration(seconds: 15));
      return ReportOutcome.submitted;
    } on FirebaseException catch (e) {
      // `permission-denied` on a payload this method built itself means the
      // document already exists: the rules allow `create` and deny `update`, so
      // a duplicate is the only ordinary way a well-formed report is refused.
      // (The other denial causes — bad shape, unpinned reporterId, wrong id —
      // are all things this method controls, and a signed-out caller returned
      // above.)
      //
      // The reporter cannot simply read the report back to check: spec 18.7
      // keeps internal moderation records invisible to users, so `reports` is
      // moderator-read-only. This inference is the honest limit of what the
      // client can know, and it errs toward the friendlier message.
      if (e.code == 'permission-denied') {
        return ReportOutcome.alreadyReported;
      }
      debugPrint('Report failed: ${e.code} ${e.message}');
      return ReportOutcome.failed;
    } catch (e) {
      debugPrint('Report failed: $e');
      return ReportOutcome.failed;
    }
  }

  // -------------------------------------------------------------------------
  // Moderator actions. All of these require the role and all are audit-logged
  // server-side; see functions/src/moderation.ts.
  // -------------------------------------------------------------------------

  /// Hides a signal by moving its document to quarantine (spec 18.3).
  Future<void> hideSignal({
    required String collection,
    required String signalId,
    required String note,
    String? reportId,
  }) =>
      _act('hideSignal', {
        'collection': collection,
        'signalId': signalId,
        'note': note,
      }, reportId: reportId);

  /// Puts a quarantined signal back.
  Future<void> restoreSignal({
    required String collection,
    required String signalId,
    required String note,
  }) =>
      _act('restoreSignal', {
        'collection': collection,
        'signalId': signalId,
        'note': note,
      });

  /// Locks or unlocks a signal's comments (spec 18.3).
  Future<void> setCommentsLocked({
    required String collection,
    required String signalId,
    required bool locked,
    required String note,
    String? reportId,
  }) =>
      _act('setCommentsLocked', {
        'collection': collection,
        'signalId': signalId,
        'locked': locked,
        'note': note,
      }, reportId: reportId);

  /// Corrects a misused urgency label (spec 5.3). Writes a timeline event.
  Future<void> setUrgency({
    required String collection,
    required String signalId,
    required int urgency,
    required String note,
    String? reportId,
  }) =>
      _act('setUrgency', {
        'collection': collection,
        'signalId': signalId,
        'urgency': urgency,
        'note': note,
      }, reportId: reportId);

  /// Removes a single comment.
  Future<void> deleteComment({
    required String collection,
    required String signalId,
    required String commentId,
    required String note,
    String? reportId,
  }) =>
      _act('deleteComment', {
        'collection': collection,
        'signalId': signalId,
        'commentId': commentId,
        'note': note,
      }, reportId: reportId);

  /// Pins or clears a warning label (spec 18.3). Pass null to clear.
  Future<void> setLabel({
    required String collection,
    required String signalId,
    required String? label,
    required String note,
    String? reportId,
  }) =>
      _act('setLabel', {
        'collection': collection,
        'signalId': signalId,
        'label': label,
        'note': note,
      }, reportId: reportId);

  /// Closes a report without touching the content.
  Future<void> resolveReport({
    required String reportId,
    required bool actioned,
    required String note,
  }) =>
      _act('resolveReport', {
        'reportId': reportId,
        'outcome': actioned ? 'actioned' : 'dismissed',
        'note': note,
      });

  /// Records an internal note with no content change (spec 18.3).
  Future<void> addNote({
    required ReportTargetType targetType,
    required String targetId,
    required String note,
    String? collection,
    String? reportId,
  }) =>
      _act('addNote', {
        'targetType': targetType.code,
        'targetId': targetId,
        'note': note,
        if (collection != null) 'collection': collection,
      }, reportId: reportId);

  /// One callable for every action — see the module comment in
  /// `functions/src/moderation.ts` for why it is one endpoint and not eight.
  ///
  /// [reportId] is threaded here rather than by each wrapper so the
  /// omit-when-null idiom lives in one place instead of six.
  Future<void> _act(
    String action,
    Map<String, dynamic> params, {
    String? reportId,
  }) async {
    await CallableClient.call('moderateAction', {
      'action': action,
      ...params,
      if (reportId != null) 'reportId': reportId,
    });
  }
}

/// What happened when a user tried to file a report.
enum ReportOutcome {
  submitted,

  /// Refused because this user already reported this target — the intended
  /// effect of the deterministic document id, not an error.
  alreadyReported,

  notSignedIn,
  failed,
}

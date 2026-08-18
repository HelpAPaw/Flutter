import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/report_reason.dart';

/// Covers the two things about a report that are load-bearing rather than
/// cosmetic: the **stability of the codes** (they are stored in Firestore and
/// embedded in document ids) and the **document id format**, which is the
/// entire rate limit — `firestore.rules` allows `create` and denies `update`,
/// so one report per user per target is enforced by the id colliding and by
/// nothing else.
void main() {
  group('ReportReason codes', () {
    test('are unique', () {
      final codes = ReportReason.values.map((r) => r.code).toList();
      expect(codes.toSet().length, codes.length,
          reason: 'Two reasons share a code; stored reports become ambiguous.');
    });

    test('round-trip through fromCode', () {
      for (final reason in ReportReason.values) {
        expect(ReportReason.fromCode(reason.code), reason);
      }
    });

    test('return null for an unknown code rather than defaulting', () {
      // Deliberate: the queue renders the raw code so a report written by a
      // newer build stays legible. Folding it into `other` would hide exactly
      // the case worth noticing.
      expect(ReportReason.fromCode('someFutureReason'), isNull);
      expect(ReportReason.fromCode(''), isNull);
    });

  });

  group('ReportTarget', () {
    const collection = 'signals';

    test('target type codes contain no separator that would corrupt an id', () {
      // The id is `{uid}_{targetType}_{targetId}`, and firestore.rules
      // reconstructs it exactly. A targetType containing "_" makes that id
      // ambiguous.
      for (final type in ReportTargetType.values) {
        expect(type.code.contains('_'), isFalse);
      }
    });

    test('a signal report points at itself', () {
      final target = ReportTarget.signal(
        signalId: 'sig-1',
        collection: collection,
        reportedUserId: 'reporter-uid',
      );
      expect(target.type, ReportTargetType.signal);
      expect(target.targetId, 'sig-1');
      expect(target.signalId, 'sig-1');
      expect(target.reportedUserId, 'reporter-uid');
    });

    test('a comment report keeps its parent signal', () {
      // Without signalId a moderator has a comment id and no way to find the
      // comment — the reason ReportTarget is a value type at all.
      final target = ReportTarget.comment(
        commentId: 'c-1',
        signalId: 'sig-1',
        collection: collection,
      );
      expect(target.targetId, 'c-1');
      expect(target.signalId, 'sig-1');
    });

    test('a user report carries no signal', () {
      final target = ReportTarget.user(userId: 'u-1', collection: collection);
      expect(target.targetId, 'u-1');
      expect(target.reportedUserId, 'u-1');
      expect(target.signalId, isNull);
    });

    test('documentId matches what firestore.rules reconstructs', () {
      // The rules assert:
      //   reportId == request.auth.uid + '_' + targetType + '_' + targetId
      // If this format changes on one side only, every report is denied.
      final target = ReportTarget.signal(
        signalId: 'sig-1',
        collection: collection,
      );
      expect(target.documentId('user-1'), 'user-1_signal_sig-1');

      final comment = ReportTarget.comment(
        commentId: 'c-1',
        signalId: 'sig-1',
        collection: collection,
      );
      expect(comment.documentId('user-1'), 'user-1_comment_c-1');
    });

    test('the same user reporting the same target produces the same id', () {
      // This is the rate limit. Two calls must collide.
      final first = ReportTarget.signal(signalId: 'sig-1', collection: collection);
      final second =
          ReportTarget.signal(signalId: 'sig-1', collection: collection);
      expect(first.documentId('u'), second.documentId('u'));
    });

    test('different users and different targets do not collide', () {
      final target = ReportTarget.signal(signalId: 'sig-1', collection: collection);
      final other = ReportTarget.signal(signalId: 'sig-2', collection: collection);
      expect(target.documentId('u1'), isNot(target.documentId('u2')));
      expect(target.documentId('u1'), isNot(other.documentId('u1')));
    });

    test('a signal and a comment with the same id do not collide', () {
      final signal = ReportTarget.signal(signalId: 'x', collection: collection);
      final comment = ReportTarget.comment(
        commentId: 'x',
        signalId: 'sig-1',
        collection: collection,
      );
      expect(signal.documentId('u'), isNot(comment.documentId('u')));
    });
  });
}

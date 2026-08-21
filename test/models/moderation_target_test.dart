import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/moderation_target.dart';
import 'package:help_a_paw/src/models/report_reason.dart';

/// [ModerationTarget] is what decoupled the moderator action sheet from the
/// report queue, so its decoding carries two safety properties that used to
/// live in the sheet's private getters. Both are the kind that fail silently
/// and expensively, so both are pinned here.
void main() {
  group('ModerationTarget.signal', () {
    test('targets the signal itself', () {
      final target = ModerationTarget.signal(
        signalId: 'abc',
        collection: 'signals_test',
      );
      expect(target.type, ReportTargetType.signal);
      expect(target.targetId, 'abc');
      expect(target.signalId, 'abc');
      expect(target.collection, 'signals_test');
      expect(target.canActOnSignal, isTrue);
    });
  });

  group('ModerationTarget.comment', () {
    test('keeps the parent signal, which a comment id alone cannot resolve',
        () {
      final target = ModerationTarget.comment(
        commentId: 'c1',
        signalId: 'abc',
        collection: 'signals',
      );
      expect(target.type, ReportTargetType.comment);
      expect(target.targetId, 'c1');
      expect(target.signalId, 'abc');
      expect(target.canActOnSignal, isTrue);
    });
  });

  group('ModerationTarget.fromReport', () {
    test('decodes an ordinary signal report', () {
      final target = ModerationTarget.fromReport({
        'targetType': 'signal',
        'targetId': 'abc',
        'collection': 'signals',
        'signalId': 'abc',
      });
      expect(target.type, ReportTargetType.signal);
      expect(target.collection, 'signals');
      expect(target.canActOnSignal, isTrue);
    });

    test('NEVER defaults a missing collection to production', () {
      // The single most expensive possible default in this file: a report whose
      // collection could not be read would otherwise be actioned against the
      // live `signals` collection. The safe failure is to offer no
      // signal-targeting action at all.
      final target = ModerationTarget.fromReport({
        'targetType': 'signal',
        'targetId': 'abc',
        'signalId': 'abc',
      });
      expect(target.collection, isNull);
      expect(target.collection, isNot('signals'));
      expect(target.canActOnSignal, isFalse);
    });

    test('decodes an unknown target type to null rather than guessing', () {
      // A report filed by a newer build. Narrowing the menu is correct;
      // mis-targeting it would not be.
      final target = ModerationTarget.fromReport({
        'targetType': 'somethingNew',
        'targetId': 'abc',
        'collection': 'signals',
      });
      expect(target.type, isNull);
    });

    test('survives a report with nothing usable in it', () {
      final target = ModerationTarget.fromReport({});
      expect(target.type, isNull);
      expect(target.targetId, '');
      expect(target.collection, isNull);
      expect(target.canActOnSignal, isFalse);
    });

    test('an empty signalId does not count as actionable', () {
      // `doc('')` throws, so this has to be caught before a row is offered.
      final target = ModerationTarget.fromReport({
        'targetType': 'signal',
        'targetId': '',
        'collection': 'signals',
        'signalId': '',
      });
      expect(target.canActOnSignal, isFalse);
    });
  });
}

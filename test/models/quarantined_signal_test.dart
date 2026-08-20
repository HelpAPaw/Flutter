import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/quarantined_signal.dart';

/// The client half of the `listQuarantined` contract.
///
/// The server's half is pinned by `functions/src/__tests__/moderation.test.ts`
/// (`quarantineSummary`). This side matters for one reason in particular: the
/// timestamp crosses as **epoch millis**, because a Firestore Timestamp does
/// not survive the callable's JSON envelope. If either side changed that
/// unilaterally the row would render a blank date rather than failing.
void main() {
  Map<String, dynamic> summary({Map<String, dynamic> overrides = const {}}) => {
        'quarantineId': 'signals_test__U9nLx',
        'signalId': 'U9nLxygLCSRo642MwuVz',
        'collection': 'signals_test',
        'title': 'Injured cat near bus stop',
        'hiddenBy': 'moderator-uid',
        'note': 'Duplicate of an existing report',
        'hiddenAtMillis': 1755000000000,
        ...overrides,
      };

  test('decodes what the moderator needs to decide', () {
    final signal = QuarantinedSignal.fromJson(summary());
    expect(signal.quarantineId, 'signals_test__U9nLx');
    expect(signal.signalId, 'U9nLxygLCSRo642MwuVz');
    expect(signal.collection, 'signals_test');
    expect(signal.title, 'Injured cat near bus stop');
    expect(signal.hiddenBy, 'moderator-uid');
    expect(signal.note, 'Duplicate of an existing report');
    expect(signal.hiddenAt, DateTime.fromMillisecondsSinceEpoch(1755000000000));
  });

  test('accepts millis as any num, which JSON may hand over as a double', () {
    final signal =
        QuarantinedSignal.fromJson(summary(overrides: {'hiddenAtMillis': 1755000000000.0}));
    expect(signal.hiddenAt, DateTime.fromMillisecondsSinceEpoch(1755000000000));
  });

  test('a missing or malformed timestamp leaves hiddenAt null, not an epoch', () {
    // Rendering 1 Jan 1970 would look like data rather than absence.
    expect(
      QuarantinedSignal.fromJson(summary(overrides: {'hiddenAtMillis': null})).hiddenAt,
      isNull,
    );
    expect(
      QuarantinedSignal.fromJson(summary(overrides: {'hiddenAtMillis': 'nope'})).hiddenAt,
      isNull,
    );
  });

  test('survives a partial row rather than taking out the whole list', () {
    // One malformed row must not hide every OTHER restorable signal — the list
    // is the only route back for all of them.
    final signal = QuarantinedSignal.fromJson(const {});
    expect(signal.quarantineId, '');
    expect(signal.title, '');
    expect(signal.signalId, '');
    expect(signal.hiddenAt, isNull);
  });

  test('restoring targets the collection the signal came from', () {
    // Not the moderator's current test mode: a prod-mode moderator acting on a
    // test-mode entry must still restore it into signals_test.
    final signal =
        QuarantinedSignal.fromJson(summary(overrides: {'collection': 'signals'}));
    expect(signal.collection, 'signals');
  });
}

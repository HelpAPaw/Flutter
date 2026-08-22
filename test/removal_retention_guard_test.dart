import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/removed_signal.dart';

/// Guards the removal retention window, which lives in two languages.
///
/// `REMOVED_RETENTION_DAYS` in `functions/src/removeSignal.ts` is the
/// **enforcement** — the scheduled purge reads it and erases everything older.
/// [RemovedSignal.retentionDays] exists only so the Removed tab can tell the
/// user the date their signal disappears for good. They must describe the same
/// window, and both ways of drifting are bad in the quiet way:
///
/// * Dart shorter than the server → the app promises a deadline that has
///   already passed while the signal is still restorable, so people purge
///   things by hand that they did not have to.
/// * Dart longer than the server → the app promises time the user does not
///   have, and their signal is gone before the date it showed them. That is the
///   worse direction: a bin that empties early is a delete with extra steps.
///
/// Same pairing and same treatment as the takeover cooldown and the event-note
/// length — parse the real definition rather than restate it, so this cannot
/// drift into agreeing with a stale copy.
void main() {
  final server = File('functions/src/removeSignal.ts');

  test('removeSignal.ts is where the guard expects it', () {
    expect(server.existsSync(), isTrue);
  });

  test('both sides describe the same retention window', () {
    final source = server.readAsStringSync();
    final match = RegExp(r'REMOVED_RETENTION_DAYS\s*=\s*(\d+)')
        .firstMatch(source);

    expect(match, isNotNull,
        reason: 'REMOVED_RETENTION_DAYS is gone from removeSignal.ts — if the '
            'recovery window was removed on purpose, this test goes with it, '
            'and so does everything the app tells users about restoring');

    expect(
      int.parse(match!.group(1)!),
      RemovedSignal.retentionDays,
      reason: 'RemovedSignal.retentionDays has drifted from '
          'REMOVED_RETENTION_DAYS in functions/src/removeSignal.ts',
    );
  });

  test('the window is bounded and non-zero', () {
    // A zero window would make removal an immediate delete with a misleading
    // dialog in front of it; an unbounded one would make it indefinite
    // retention, which is the thing the purge job exists to prevent.
    expect(RemovedSignal.retentionDays, greaterThan(0));
    expect(RemovedSignal.retentionDays, lessThanOrEqualTo(365));
  });
}

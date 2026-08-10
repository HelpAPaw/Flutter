import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';

/// Guards the Dart↔TypeScript copy of the legacy-urgency derivation.
///
/// Signals written before the urgency system have no `urgency` field, so both
/// runtimes derive one from `status`. The Dart copy lives in
/// [SignalUrgency.fromLegacyStatus]; the server copy is
/// `functions/src/urgency.ts`, shared from there with the backfill script.
///
/// The duplication is inherent — two runtimes, no codegen, and the repo already
/// accepts the same split for `SIGNAL_TYPES` / `SIGNAL_STATUSES`. What is *not*
/// acceptable is leaving it guarded by a comment, because the failure is both
/// silent and expensive:
///
/// `handleSignalUpdated` decides "did urgency escalate?" by comparing the
/// derived before-value against the stored after-value. The backfill writes
/// exactly the derived value, so today before == after and it sends nothing.
/// If the two derivations drift, every one of those writes starts looking like
/// an escalation — and a single backfill run pushes a notification to every
/// subscriber of every signal in the database.
///
/// This parses the TypeScript rather than duplicating its numbers, so the test
/// cannot itself drift into agreeing with a stale copy.
void main() {
  final source = File('functions/src/urgency.ts');

  test('the shared urgency module exists where the script requires it', () {
    expect(
      source.existsSync(),
      isTrue,
      reason: 'functions/scripts/backfill_urgency.js requires ../lib/urgency, '
          'built from functions/src/urgency.ts. Moving it silently reverts the '
          'server and the backfill to two independent copies of the mapping.',
    );
  });

  test('TypeScript urgency/status codes match the Dart enums', () {
    final text = source.readAsStringSync();

    int constant(String name) {
      final match =
          RegExp('const\\s+$name\\s*=\\s*(-?\\d+)\\s*;').firstMatch(text);
      expect(
        match,
        isNotNull,
        reason: 'Could not find `const $name = <int>;` in ${source.path}. '
            'If it was renamed, update this guard too.',
      );
      return int.parse(match!.group(1)!);
    }

    expect(constant('URGENCY_GREEN'), SignalUrgency.green.code);
    expect(constant('URGENCY_AMBER'), SignalUrgency.amber.code);
    expect(constant('URGENCY_RED'), SignalUrgency.red.code);
    expect(constant('STATUS_RESOLVED'), SignalStatus.resolved.code);
  });

  test('TypeScript derives the same urgency from status as Dart', () {
    final text = source.readAsStringSync();

    // Matches the body of `urgencyForStatus`:
    //   status === STATUS_RESOLVED ? URGENCY_GREEN : URGENCY_AMBER
    final ternary = RegExp(
      r'status\s*===\s*(\w+)\s*\?\s*(\w+)\s*:\s*(\w+)',
    ).firstMatch(text);

    expect(
      ternary,
      isNotNull,
      reason: 'Could not find the status->urgency ternary in ${source.path}. '
          'If the derivation was rewritten into another shape, this guard has '
          'to be rewritten with it — do not just delete it. See the doc '
          'comment on this test for what drift costs.',
    );

    // The names, resolved through the constants asserted above, must describe
    // "resolved is green, everything else is amber" — and never Red, which is
    // a human judgement no migration may manufacture.
    expect(ternary!.group(1), 'STATUS_RESOLVED');
    expect(ternary.group(2), 'URGENCY_GREEN');
    expect(ternary.group(3), 'URGENCY_AMBER');

    // And that is exactly what Dart does.
    expect(
      SignalUrgency.fromLegacyStatus(SignalStatus.resolved.code),
      SignalUrgency.green,
    );
    for (final status in SignalStatus.values.where((s) => s.isOpen)) {
      expect(SignalUrgency.fromLegacyStatus(status.code), SignalUrgency.amber);
    }
  });
}

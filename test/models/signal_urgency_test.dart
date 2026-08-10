import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';

void main() {
  group('SignalUrgency.fromCode', () {
    test('resolves every shipped code', () {
      for (final urgency in SignalUrgency.values) {
        expect(SignalUrgency.fromCode(urgency.code), urgency);
      }
    });

    test('an unknown code falls back to amber, not green or red', () {
      // Green would hide a case that might be real; red would cry wolf and
      // erode the level that has to stay rare to mean anything.
      expect(SignalUrgency.fromCode(99), SignalUrgency.amber);
      expect(SignalUrgency.fromCode(-1), SignalUrgency.amber);
    });

    test('codes are distinct', () {
      final codes = SignalUrgency.values.map((u) => u.code).toSet();
      expect(codes.length, SignalUrgency.values.length);
    });
  });

  group('SignalUrgency.fromLegacyStatus', () {
    test('a resolved signal reads as green', () {
      expect(
        SignalUrgency.fromLegacyStatus(SignalStatus.resolved.code),
        SignalUrgency.green,
      );
    });

    test('every open status reads as amber', () {
      for (final status in SignalStatus.values.where((s) => s.isOpen)) {
        expect(
          SignalUrgency.fromLegacyStatus(status.code),
          SignalUrgency.amber,
        );
      }
    });

    test('nothing is ever inferred as red', () {
      // Red is a human judgement (spec 5.2) — no migration may manufacture one.
      for (var status = -1; status < 10; status++) {
        expect(
          SignalUrgency.fromLegacyStatus(status),
          isNot(SignalUrgency.red),
          reason: 'status $status was inferred as a Red Alert',
        );
      }
    });
  });

  test('only red requires confirmation', () {
    for (final urgency in SignalUrgency.values) {
      expect(
        urgency.requiresConfirmation,
        urgency == SignalUrgency.red,
        reason: '${urgency.name} confirmation gate is wrong',
      );
    }
  });

  group('Signal.urgencyFrom', () {
    test('a stored urgency is used as-is', () {
      expect(
        Signal.urgencyFrom({'urgency': SignalUrgency.red.code}),
        SignalUrgency.red.code,
      );
    });

    test('a document written before the urgency system derives one', () {
      // Documents the backfill missed must still render rather than blowing up
      // on a null when the map builds its markers.
      expect(
        Signal.urgencyFrom({'status': SignalStatus.needsHelp.code}),
        SignalUrgency.amber.code,
      );
      expect(
        Signal.urgencyFrom({'status': SignalStatus.resolved.code}),
        SignalUrgency.green.code,
      );
    });

    test('a document with neither field still resolves', () {
      expect(Signal.urgencyFrom({}), SignalUrgency.amber.code);
    });

    test('an explicit urgency wins over the status-derived fallback', () {
      // A reporter can mark a resolved case Red (e.g. it has relapsed), and
      // the stored value must survive the legacy fallback.
      expect(
        Signal.urgencyFrom({
          'status': SignalStatus.resolved.code,
          'urgency': SignalUrgency.red.code,
        }),
        SignalUrgency.red.code,
      );
    });
  });
}

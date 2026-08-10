import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/state/map_state.dart';

void main() {
  // MapFilterState's "everything selected" sets have to be `const` (they are
  // default arguments all the way up to MapScreenState), so they cannot be
  // derived from the enums at their definition. These tests are the guard
  // referenced in that class's doc comment.
  //
  // Without them, appending a status/urgency/type would leave the new value
  // missing from the default selection — so signals carrying it would be
  // filtered off the map from the moment they were created, with no error
  // anywhere and nothing failing in CI.
  group('MapFilterState default sets stay in step with their source enums', () {
    test('allStatuses covers every SignalStatus code', () {
      expect(
        MapFilterState.allStatuses,
        SignalStatus.values.map((s) => s.code).toSet(),
      );
    });

    test('allUrgencies covers every SignalUrgency code', () {
      expect(
        MapFilterState.allUrgencies,
        SignalUrgency.values.map((u) => u.code).toSet(),
      );
    });

    test('allSignalTypes covers every signal type index', () {
      expect(
        MapFilterState.allSignalTypes,
        List.generate(Signal.signalTypes.length, (i) => i).toSet(),
      );
    });

    test('a default filter state hides nothing', () {
      const state = MapFilterState();
      expect(state.hasActiveFilters, false);

      for (final status in SignalStatus.values) {
        for (final urgency in SignalUrgency.values) {
          for (var type = 0; type < Signal.signalTypes.length; type++) {
            expect(
              state.signalPassesFilter(type, status.code, urgency.code),
              true,
              reason: 'type $type / status ${status.code} / '
                  'urgency ${urgency.code} was filtered out by default',
            );
          }
        }
      }
    });
  });

  group('MapFilterState.signalPassesFilter', () {
    test('urgency filters independently of status', () {
      // The whole point of the urgency system: a case someone is already
      // working on (In progress) can still be critical (Red).
      final state = const MapFilterState()
          .toggleUrgency(SignalUrgency.red.code); // hide Red

      expect(
        state.signalPassesFilter(
          0,
          SignalStatus.inProgress.code,
          SignalUrgency.red.code,
        ),
        false,
      );
      expect(
        state.signalPassesFilter(
          0,
          SignalStatus.inProgress.code,
          SignalUrgency.amber.code,
        ),
        true,
      );
    });

    test('hasActiveFilters notices an urgency-only filter', () {
      final state =
          const MapFilterState().toggleUrgency(SignalUrgency.green.code);
      expect(state.hasActiveFilters, true);
    });
  });
}

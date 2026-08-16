import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/animal_type.dart';
import 'package:help_a_paw/src/models/help_tag.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/state/map_state.dart';

void main() {
  // MapFilterState's "everything selected" sets have to be `const` (they are
  // default arguments all the way up to MapScreenState), so they cannot be
  // derived from the enums at their definition. These tests are the guard
  // referenced in that class's doc comment.
  //
  // Without them, appending a tag/species/status/urgency would leave the new
  // value missing from the default selection — so signals carrying it would be
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

    test('allHelpTags covers every HelpTag code', () {
      expect(
        MapFilterState.allHelpTags,
        HelpTag.values.map((t) => t.code).toSet(),
      );
    });

    test('allAnimalTypes covers every AnimalType code', () {
      expect(
        MapFilterState.allAnimalTypes,
        AnimalType.values.map((t) => t.code).toSet(),
      );
    });

    test('a default filter state hides nothing', () {
      const state = MapFilterState();
      expect(state.hasActiveFilters, false);

      for (final status in SignalStatus.values) {
        for (final urgency in SignalUrgency.values) {
          for (final tag in HelpTag.values) {
            for (final species in AnimalType.values) {
              expect(
                state.signalPassesFilter(
                  [tag.code],
                  species.code,
                  status.code,
                  urgency.code,
                ),
                true,
                reason: 'tag ${tag.code} / species ${species.code} / '
                    'status ${status.code} / urgency ${urgency.code} was '
                    'filtered out by default',
              );
            }
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
          [HelpTag.rescue.code],
          AnimalType.dog.code,
          SignalStatus.inProgress.code,
          SignalUrgency.red.code,
        ),
        false,
      );
      expect(
        state.signalPassesFilter(
          [HelpTag.rescue.code],
          AnimalType.dog.code,
          SignalStatus.inProgress.code,
          SignalUrgency.amber.code,
        ),
        true,
      );
    });

    test('a signal passes if ANY of its needs is selected', () {
      // A case can declare up to three needs. Someone filtering for fostering
      // still wants the case that needs rescue *and* fostering — requiring all
      // of them to match would hide exactly the multi-need cases that most need
      // help.
      final state = const MapFilterState()
          .toggleHelpTag(HelpTag.rescue.code) // hide rescue
          .toggleHelpTag(HelpTag.vetCare.code); // hide vet care

      expect(
        state.signalPassesFilter(
          [HelpTag.rescue.code, HelpTag.foster.code],
          null,
          SignalStatus.needsHelp.code,
          SignalUrgency.amber.code,
        ),
        true,
      );
      expect(
        state.signalPassesFilter(
          [HelpTag.rescue.code, HelpTag.vetCare.code],
          null,
          SignalStatus.needsHelp.code,
          SignalUrgency.amber.code,
        ),
        false,
      );
    });

    test('an untagged legacy signal is treated as the fallback tag', () {
      // Matches what the fan-out substitutes, so the map and the notifications
      // agree about what an untagged signal is asking for.
      final hidingFallback =
          const MapFilterState().toggleHelpTag(HelpTag.fallback.code);

      expect(
        const MapFilterState().signalPassesFilter(
          const [],
          null,
          SignalStatus.needsHelp.code,
          SignalUrgency.amber.code,
        ),
        true,
      );
      expect(
        hidingFallback.signalPassesFilter(
          const [],
          null,
          SignalStatus.needsHelp.code,
          SignalUrgency.amber.code,
        ),
        false,
      );
    });

    test('a signal with no species survives every species filter', () {
      // Legacy signals carry no animalType. Filtering them out would make them
      // silently disappear for anyone who has picked a species.
      final state = const MapFilterState()
          .toggleAnimalType(AnimalType.cat.code)
          .toggleAnimalType(AnimalType.other.code);

      expect(
        state.signalPassesFilter(
          [HelpTag.rescue.code],
          null,
          SignalStatus.needsHelp.code,
          SignalUrgency.amber.code,
        ),
        true,
      );
      expect(
        state.signalPassesFilter(
          [HelpTag.rescue.code],
          AnimalType.cat.code,
          SignalStatus.needsHelp.code,
          SignalUrgency.amber.code,
        ),
        false,
      );
    });

    test('hasActiveFilters notices an urgency-only filter', () {
      final state =
          const MapFilterState().toggleUrgency(SignalUrgency.green.code);
      expect(state.hasActiveFilters, true);
    });

    test('hasActiveFilters notices a species-only filter', () {
      final state =
          const MapFilterState().toggleAnimalType(AnimalType.dog.code);
      expect(state.hasActiveFilters, true);
    });
  });
}

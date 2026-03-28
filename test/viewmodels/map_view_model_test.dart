import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/repositories/repository_provider.dart';
import 'package:help_a_paw/src/state/map_state.dart';
import 'package:help_a_paw/src/viewmodels/map_view_model.dart';

import '../mocks/mock_signal_repository.dart';
import '../mocks/mock_storage_repository.dart';
import '../mocks/mock_user_repository.dart';

void main() {
  late ProviderContainer container;
  late MapViewModel viewModel;
  late MockSignalRepository mockSignalRepo;
  late MockStorageRepository mockStorageRepo;
  late MockUserRepository mockUserRepo;

  setUp(() {
    mockSignalRepo = MockSignalRepository();
    mockStorageRepo = MockStorageRepository();
    mockUserRepo = MockUserRepository();

    // Inject mock repositories
    RepositoryProvider.resetInstance();
    RepositoryProvider.instance.setSignalRepository(mockSignalRepo);
    RepositoryProvider.instance.setStorageRepository(mockStorageRepo);
    RepositoryProvider.instance.setUserRepository(mockUserRepo);

    container = ProviderContainer();
    viewModel = container.read(mapViewModelProvider.notifier);
  });

  tearDown(() {
    container.dispose();
    mockSignalRepo.dispose();
    mockUserRepo.dispose();
    RepositoryProvider.resetInstance();
  });

  group('Initial state', () {
    test('has default Sofia coordinates', () {
      expect(viewModel.state.centerLatitude, 42.6977);
      expect(viewModel.state.centerLongitude, 23.3219);
    });

    test('is not adding new signal', () {
      expect(viewModel.state.isAddingNewSignal, false);
    });

    test('has no location permission initially', () {
      expect(viewModel.state.hasLocationPermission, false);
    });

    test('has all filters selected by default', () {
      expect(viewModel.state.filterState.selectedSignalTypes.length, 7);
      expect(viewModel.state.filterState.selectedStatuses.length, 3);
      expect(viewModel.state.filterState.hasActiveFilters, false);
    });

    test('vet clinics are hidden initially', () {
      expect(viewModel.state.vetClinicState.showVetClinics, false);
      expect(viewModel.state.vetClinicState.clinics, isEmpty);
    });
  });

  group('Map center', () {
    test('updateMapCenter updates coordinates', () {
      viewModel.updateMapCenter(40.0, 25.0);

      expect(viewModel.state.centerLatitude, 40.0);
      expect(viewModel.state.centerLongitude, 25.0);
    });
  });

  group('Filter management', () {
    test('toggleSignalType removes a type', () {
      viewModel.toggleSignalType(0);

      expect(viewModel.state.filterState.selectedSignalTypes.contains(0), false);
      expect(viewModel.state.filterState.selectedSignalTypes.length, 6);
      expect(viewModel.state.filterState.hasActiveFilters, true);
    });

    test('toggleSignalType adds a type back', () {
      viewModel.toggleSignalType(0); // remove
      viewModel.toggleSignalType(0); // add back

      expect(viewModel.state.filterState.selectedSignalTypes.contains(0), true);
      expect(viewModel.state.filterState.selectedSignalTypes.length, 7);
    });

    test('toggleStatus removes a status', () {
      viewModel.toggleStatus(1);

      expect(viewModel.state.filterState.selectedStatuses.contains(1), false);
      expect(viewModel.state.filterState.selectedStatuses.length, 2);
      expect(viewModel.state.filterState.hasActiveFilters, true);
    });

    test('toggleStatus adds a status back', () {
      viewModel.toggleStatus(1); // remove
      viewModel.toggleStatus(1); // add back

      expect(viewModel.state.filterState.selectedStatuses.contains(1), true);
      expect(viewModel.state.filterState.selectedStatuses.length, 3);
    });

    test('clearAllFilters clears all', () {
      viewModel.clearAllFilters();

      expect(viewModel.state.filterState.selectedSignalTypes, isEmpty);
      expect(viewModel.state.filterState.selectedStatuses, isEmpty);
      expect(viewModel.state.filterState.hasActiveFilters, true);
    });

    test('selectAllFilters restores all', () {
      viewModel.clearAllFilters();
      viewModel.selectAllFilters();

      expect(viewModel.state.filterState.selectedSignalTypes.length, 7);
      expect(viewModel.state.filterState.selectedStatuses.length, 3);
      expect(viewModel.state.filterState.hasActiveFilters, false);
    });

    test('signalPassesFilter checks both type and status', () {
      // All filters selected - everything passes
      expect(viewModel.signalPassesFilter(0, 0), true);
      expect(viewModel.signalPassesFilter(3, 2), true);

      // Remove type 0
      viewModel.toggleSignalType(0);
      expect(viewModel.signalPassesFilter(0, 0), false);
      expect(viewModel.signalPassesFilter(1, 0), true);

      // Remove status 2
      viewModel.toggleStatus(2);
      expect(viewModel.signalPassesFilter(1, 2), false);
      expect(viewModel.signalPassesFilter(1, 1), true);
    });
  });

  group('New signal form', () {
    test('toggleAddingNewSignal switches state', () {
      viewModel.toggleAddingNewSignal();

      expect(viewModel.state.isAddingNewSignal, true);

      viewModel.toggleAddingNewSignal();

      expect(viewModel.state.isAddingNewSignal, false);
    });

    test('cancelAddingNewSignal resets form', () {
      viewModel.toggleAddingNewSignal();
      viewModel.updateFormTitle('Test');
      viewModel.updateFormDescription('Description');

      viewModel.cancelAddingNewSignal();

      expect(viewModel.state.isAddingNewSignal, false);
      expect(viewModel.state.formState.title, '');
      expect(viewModel.state.formState.description, '');
    });

    test('updateFormTitle updates title', () {
      viewModel.updateFormTitle('New title');

      expect(viewModel.state.formState.title, 'New title');
    });

    test('updateFormDescription updates description', () {
      viewModel.updateFormDescription('New description');

      expect(viewModel.state.formState.description, 'New description');
    });

    test('updateFormPhoneNumber updates phone', () {
      viewModel.updateFormPhoneNumber('0888123456');

      expect(viewModel.state.formState.phoneNumber, '0888123456');
    });

    test('setFormSignalType updates type', () {
      viewModel.setFormSignalType(3);

      expect(viewModel.state.formState.signalType, 3);
    });

    test('clearFormImage clears image', () {
      viewModel.clearFormImage();

      expect(viewModel.state.formState.selectedImage, isNull);
    });

    test('submitSignal fails with empty title', () async {
      viewModel.updateFormDescription('Description');

      final (success, errorMessage) = await viewModel.submitSignal(
        latitude: 42.0,
        longitude: 23.0,
      );

      expect(success, false);
      expect(errorMessage, 'title_empty');
    });

    test('submitSignal fails with empty description', () async {
      viewModel.updateFormTitle('Title');

      final (success, errorMessage) = await viewModel.submitSignal(
        latitude: 42.0,
        longitude: 23.0,
      );

      expect(success, false);
      expect(errorMessage, 'description_empty');
    });

    test('submitSignal succeeds with valid form', () async {
      viewModel.updateFormTitle('Help needed');
      viewModel.updateFormDescription('Dog stuck in fence');
      viewModel.updateFormPhoneNumber('0888123456');

      final (success, errorMessage) = await viewModel.submitSignal(
        latitude: 42.0,
        longitude: 23.0,
      );

      expect(success, true);
      expect(errorMessage, isNull);

      // Verify signal was created
      expect(mockSignalRepo.createdSignals.length, 1);
      expect(mockSignalRepo.createdSignals[0]['title'], 'Help needed');
      expect(mockSignalRepo.createdSignals[0]['description'], 'Dog stuck in fence');

      // Verify creator was subscribed
      expect(mockSignalRepo.subscriptions.length, 1);

      // Verify form was reset
      expect(viewModel.state.isAddingNewSignal, false);
      expect(viewModel.state.formState.title, '');
      expect(viewModel.state.newlyCreatedSignalId, isNotNull);
    });

    test('submitSignal handles creation failure', () async {
      mockSignalRepo.shouldCreateSucceed = false;
      mockSignalRepo.createErrorMessage = 'permission-denied';

      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');

      final (success, errorMessage) = await viewModel.submitSignal(
        latitude: 42.0,
        longitude: 23.0,
      );

      expect(success, false);
      expect(errorMessage, 'permission-denied');
      expect(viewModel.state.formState.isSubmitting, false);
    });

    test('submitSignal fails when not authenticated', () async {
      mockUserRepo.setUnauthenticated();

      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');

      final (success, errorMessage) = await viewModel.submitSignal(
        latitude: 42.0,
        longitude: 23.0,
      );

      expect(success, false);
      expect(errorMessage, 'not_authenticated');
    });

    test('submitSignal stores newly created signal ID', () async {
      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');

      await viewModel.submitSignal(latitude: 42.0, longitude: 23.0);
      expect(viewModel.state.newlyCreatedSignalId, isNotNull);
    });
  });

  group('Vet clinic management', () {
    test('toggleVetClinics switches visibility', () {
      viewModel.toggleVetClinics();
      expect(viewModel.state.vetClinicState.showVetClinics, true);

      viewModel.toggleVetClinics();
      expect(viewModel.state.vetClinicState.showVetClinics, false);
    });

    test('toggleVetClinics off clears clinic data', () {
      viewModel.toggleVetClinics(); // on
      viewModel.toggleVetClinics(); // off

      expect(viewModel.state.vetClinicState.clinics, isEmpty);
      expect(viewModel.state.vetClinicState.clinicMarkers, isEmpty);
      expect(viewModel.state.vetClinicState.lastSearchCenter, isNull);
    });

    test('hideSearchThisAreaButton hides button', () {
      viewModel.hideSearchThisAreaButton();

      expect(viewModel.state.vetClinicState.showSearchThisAreaButton, false);
    });
  });

  group('MapFilterState immutability', () {
    test('copyWith creates new instance', () {
      const state1 = MapFilterState();
      final state2 = state1.copyWith(selectedStatuses: {0, 1});

      expect(state1.selectedStatuses.length, 3);
      expect(state2.selectedStatuses.length, 2);
    });

    test('equality works correctly', () {
      const state1 = MapFilterState();
      const state2 = MapFilterState();
      final state3 = state1.copyWith(selectedStatuses: {0});

      expect(state1 == state2, true);
      expect(state1 == state3, false);
    });
  });

  group('NewSignalFormState immutability', () {
    test('isValid requires title and description', () {
      const emptyForm = NewSignalFormState();
      expect(emptyForm.isValid, false);

      const titleOnly = NewSignalFormState(title: 'Title');
      expect(titleOnly.isValid, false);

      const descOnly = NewSignalFormState(description: 'Desc');
      expect(descOnly.isValid, false);

      const valid = NewSignalFormState(title: 'Title', description: 'Desc');
      expect(valid.isValid, true);
    });

    test('reset clears all fields', () {
      const form = NewSignalFormState(
        title: 'Title',
        description: 'Desc',
        phoneNumber: '123',
        signalType: 2,
        isSubmitting: true,
      );

      final reset = form.reset();

      expect(reset.title, '');
      expect(reset.description, '');
      expect(reset.phoneNumber, '');
      expect(reset.signalType, 0);
      expect(reset.isSubmitting, false);
    });
  });

  group('MapScreenState immutability', () {
    test('default state uses Sofia coordinates', () {
      const state = MapScreenState();

      expect(state.centerLatitude, MapScreenState.defaultLatitude);
      expect(state.centerLongitude, MapScreenState.defaultLongitude);
    });

    test('newlyCreatedSignalId is overwritten on next creation', () {
      const state = MapScreenState(newlyCreatedSignalId: 'old_id');
      final updated = state.copyWith(newlyCreatedSignalId: 'new_id');

      expect(updated.newlyCreatedSignalId, 'new_id');
    });
  });
}

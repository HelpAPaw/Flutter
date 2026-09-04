import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:firebase_crashlytics_platform_interface/firebase_crashlytics_platform_interface.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:help_a_paw/src/models/animal_type.dart';
import 'package:help_a_paw/src/models/help_tag.dart';
import 'package:help_a_paw/src/models/new_signal_step.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/repositories/repository_provider.dart';
import 'package:help_a_paw/src/state/map_state.dart';
import 'package:help_a_paw/src/viewmodels/map_view_model.dart';

import '../mocks/mock_signal_repository.dart';
import '../mocks/mock_storage_repository.dart';
import '../mocks/mock_user_repository.dart';

const _pluginConstants = <String, Map<String, Object>>{
  'plugins.flutter.io/firebase_crashlytics': {
    'isCrashlyticsCollectionEnabled': true,
  },
};

class _MockFirebaseApp implements TestFirebaseCoreHostApi {
  @override
  Future<CoreInitializeResponse> initializeApp(
    String appName,
    CoreFirebaseOptions options,
  ) async {
    return CoreInitializeResponse(
      name: appName,
      options: CoreFirebaseOptions(
        apiKey: '123', projectId: '123', appId: '123', messagingSenderId: '123',
      ),
      pluginConstants: _pluginConstants,
    );
  }

  @override
  Future<List<CoreInitializeResponse>> initializeCore() async {
    return [
      CoreInitializeResponse(
        name: defaultFirebaseAppName,
        options: CoreFirebaseOptions(
          apiKey: '123', projectId: '123', appId: '123', messagingSenderId: '123',
        ),
        pluginConstants: _pluginConstants,
      ),
    ];
  }

  @override
  Future<CoreFirebaseOptions> optionsFromResource() async {
    return CoreFirebaseOptions(
      apiKey: '123', projectId: '123', appId: '123', messagingSenderId: '123',
    );
  }
}

/// A [GeolocatorPlatform] that answers from fixed values, so the tests can
/// separate "permission granted" from "location services switched on" — the
/// two conditions the map used to conflate.
class _FakeGeolocator extends GeolocatorPlatform with MockPlatformInterfaceMixin {
  _FakeGeolocator({
    required this.permission,
    this.serviceEnabled = true,
    this.position,
  });

  final LocationPermission permission;
  final bool serviceEnabled;
  final Position? position;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) async {
    final fix = position;
    if (fix == null) {
      throw const LocationServiceDisabledException();
    }
    return fix;
  }
}

Position _positionAt(double latitude, double longitude) => Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.utc(2026),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestFirebaseCoreHostApi.setUp(_MockFirebaseApp());
    await Firebase.initializeApp();

    // Stub the Crashlytics method channel so .log() calls are no-ops in tests
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannelFirebaseCrashlytics.channel,
      (methodCall) async => null,
    );
  });
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
      expect(
        viewModel.state.filterState.selectedHelpTags.length,
        HelpTag.values.length,
      );
      expect(
        viewModel.state.filterState.selectedAnimalTypes.length,
        AnimalType.values.length,
      );
      expect(viewModel.state.filterState.selectedStatuses.length, 3);
      expect(viewModel.state.filterState.hasActiveFilters, false);
    });

    test('vet clinics are hidden initially', () {
      expect(viewModel.state.vetClinicState.showVetClinics, false);
      expect(viewModel.state.vetClinicState.clinics, isEmpty);
    });
  });

  // The map's "locate me" button is the Maps SDK's own, and it is only drawn
  // when the my-location layer is on — which is gated on hasLocationPermission.
  // So a flag that reads false for someone who has actually granted location is
  // a missing button, not just a missing blue dot.
  group('Location permission', () {
    // Each test installs its own fake; this puts the real implementation back.
    // A fake left installed would leak into every group that runs after this
    // one and surface as an UnimplementedError from an unrelated test.
    late GeolocatorPlatform realGeolocator;
    setUp(() => realGeolocator = GeolocatorPlatform.instance);
    tearDown(() => GeolocatorPlatform.instance = realGeolocator);

    test('getUserLocation grants the layer with location services off', () async {
      GeolocatorPlatform.instance = _FakeGeolocator(
        permission: LocationPermission.whileInUse,
        serviceEnabled: false,
      );

      await viewModel.getUserLocation();

      expect(viewModel.state.hasLocationPermission, true);
      // No fix to be had, so the centre stays on the fallback.
      expect(viewModel.state.centerLatitude, MapScreenState.defaultLatitude);
    });

    test('getUserLocation centres on the fix when everything is available',
        () async {
      GeolocatorPlatform.instance = _FakeGeolocator(
        permission: LocationPermission.always,
        position: _positionAt(40.0, 25.0),
      );

      await viewModel.getUserLocation();

      expect(viewModel.state.hasLocationPermission, true);
      expect(viewModel.state.centerLatitude, 40.0);
      expect(viewModel.state.centerLongitude, 25.0);
    });

    test('getUserLocation withholds the layer when permission is denied',
        () async {
      // A fix is there for the taking; the denial is what must stop it.
      GeolocatorPlatform.instance = _FakeGeolocator(
        permission: LocationPermission.deniedForever,
        position: _positionAt(40.0, 25.0),
      );

      await viewModel.getUserLocation();

      expect(viewModel.state.hasLocationPermission, false);
      expect(viewModel.state.centerLatitude, MapScreenState.defaultLatitude);
    });

    test('checkLocationPermission picks up a grant made outside the app',
        () async {
      GeolocatorPlatform.instance = _FakeGeolocator(
        permission: LocationPermission.denied,
      );
      await viewModel.checkLocationPermission();
      expect(viewModel.state.hasLocationPermission, false);

      // What returning from system Settings looks like.
      GeolocatorPlatform.instance = _FakeGeolocator(
        permission: LocationPermission.whileInUse,
      );
      await viewModel.checkLocationPermission();

      expect(viewModel.state.hasLocationPermission, true);
    });

    test('unableToDetermine is not a grant', () async {
      GeolocatorPlatform.instance = _FakeGeolocator(
        permission: LocationPermission.unableToDetermine,
      );

      await viewModel.checkLocationPermission();

      expect(viewModel.state.hasLocationPermission, false);
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
    test('toggleHelpTag removes a tag', () {
      viewModel.toggleHelpTag(HelpTag.rescue.code);

      expect(
        viewModel.state.filterState.selectedHelpTags
            .contains(HelpTag.rescue.code),
        false,
      );
      expect(
        viewModel.state.filterState.selectedHelpTags.length,
        HelpTag.values.length - 1,
      );
      expect(viewModel.state.filterState.hasActiveFilters, true);
    });

    test('toggleHelpTag adds a tag back', () {
      viewModel.toggleHelpTag(HelpTag.rescue.code); // remove
      viewModel.toggleHelpTag(HelpTag.rescue.code); // add back

      expect(
        viewModel.state.filterState.selectedHelpTags
            .contains(HelpTag.rescue.code),
        true,
      );
      expect(
        viewModel.state.filterState.selectedHelpTags.length,
        HelpTag.values.length,
      );
    });

    test('toggleAnimalType filters species', () {
      viewModel.toggleAnimalType(AnimalType.cat.code);

      expect(
        viewModel.state.filterState.selectedAnimalTypes
            .contains(AnimalType.cat.code),
        false,
      );
      expect(viewModel.state.filterState.hasActiveFilters, true);
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

    test('toggleUrgency removes and restores an urgency', () {
      viewModel.toggleUrgency(2); // remove Red
      expect(viewModel.state.filterState.selectedUrgencies.contains(2), false);
      expect(viewModel.state.filterState.hasActiveFilters, true);

      viewModel.toggleUrgency(2); // add back
      expect(viewModel.state.filterState.selectedUrgencies.contains(2), true);
      expect(viewModel.state.filterState.hasActiveFilters, false);
    });

    test('clearAllFilters clears all', () {
      viewModel.clearAllFilters();

      expect(viewModel.state.filterState.selectedHelpTags, isEmpty);
      expect(viewModel.state.filterState.selectedAnimalTypes, isEmpty);
      expect(viewModel.state.filterState.selectedStatuses, isEmpty);
      expect(viewModel.state.filterState.selectedUrgencies, isEmpty);
      expect(viewModel.state.filterState.hasActiveFilters, true);
    });

    test('selectAllFilters restores all', () {
      viewModel.clearAllFilters();
      viewModel.selectAllFilters();

      expect(
        viewModel.state.filterState.selectedHelpTags.length,
        HelpTag.values.length,
      );
      expect(
        viewModel.state.filterState.selectedAnimalTypes.length,
        AnimalType.values.length,
      );
      expect(viewModel.state.filterState.selectedStatuses.length, 3);
      expect(viewModel.state.filterState.selectedUrgencies.length, 3);
      expect(viewModel.state.filterState.hasActiveFilters, false);
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

    test('clearFormImage clears image', () {
      viewModel.clearFormImage();

      expect(viewModel.state.formState.selectedImage, isNull);
    });

    test('submitSignal fails with empty title', () async {
      viewModel.updateFormDescription('Description');

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'title_empty');
    });

    test('submitSignal fails with empty description', () async {
      viewModel.updateFormTitle('Title');

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'description_empty');
    });

    test('submitSignal fails when no urgency was chosen', () async {
      // Urgency is a required field on every signal. Defaulting it would let
      // people publish a level they never picked, which is how an urgency
      // system stops meaning anything.
      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'urgency_unset');
      expect(mockSignalRepo.createdSignals, isEmpty);
    });

    test('submitSignal fails when no help tag was chosen', () async {
      // Mandatory for the same reason as urgency: an untagged signal falls back
      // to `rescue` server-side and reaches everyone, which is precisely the
      // undirected broadcast the tags exist to replace.
      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.setFormAnimalType(AnimalType.cat.code);

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'help_tags_empty');
      expect(mockSignalRepo.createdSignals, isEmpty);
    });

    test('submitSignal fails when no animal type was chosen', () async {
      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.foster.code);

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'animal_type_unset');
      expect(mockSignalRepo.createdSignals, isEmpty);
    });

    test('submitSignal passes the tags and species through', () async {
      viewModel.updateFormTitle('Kittens');
      viewModel.updateFormDescription('Found a litter');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.babyCare.code);
      viewModel.toggleFormHelpTag(HelpTag.foster.code);
      viewModel.setFormAnimalType(AnimalType.cat.code);

      viewModel.confirmLocation(42.0, 23.0);

      final (success, _) = await viewModel.submitSignal();

      expect(success, true);
      // Order is the priority the reporter gave and must survive the write.
      expect(
        mockSignalRepo.createdSignals.single['helpNeededTags'],
        [HelpTag.babyCare.code, HelpTag.foster.code],
      );
      expect(
        mockSignalRepo.createdSignals.single['animalType'],
        AnimalType.cat.code,
      );
    });

    test('a help tag toggles off when tapped again', () async {
      viewModel.toggleFormHelpTag(HelpTag.foster.code);
      viewModel.toggleFormHelpTag(HelpTag.foster.code);

      expect(viewModel.state.formState.helpTags, isEmpty);
    });

    test('help tags stop at the per-signal cap', () async {
      for (final tag in HelpTag.values) {
        viewModel.toggleFormHelpTag(tag.code);
      }

      expect(
        viewModel.state.formState.helpTags,
        hasLength(HelpTag.maxPerSignal),
      );
    });

    test('submitSignal passes the chosen urgency through', () async {
      viewModel.updateFormTitle('Injured dog');
      viewModel.updateFormDescription('Hit by a car');
      viewModel.setFormUrgency(SignalUrgency.red.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);

      viewModel.confirmLocation(42.0, 23.0);

      final (success, _) = await viewModel.submitSignal();

      expect(success, true);
      expect(
        mockSignalRepo.createdSignals.single['urgency'],
        SignalUrgency.red.code,
      );
    });

    test('submitSignal succeeds with valid form', () async {
      viewModel.updateFormTitle('Help needed');
      viewModel.updateFormDescription('Dog stuck in fence');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);
      viewModel.updateFormPhoneNumber('0888123456');

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(errorMessage, isNull, reason: 'submitSignal error: $errorMessage');
      expect(success, true);

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

    test('submitSignal attaches the photo when the upload succeeds', () async {
      viewModel.updateFormTitle('Help needed');
      viewModel.updateFormDescription('Dog stuck in fence');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);
      viewModel.setFormImage(XFile('/tmp/mock-photo.jpg'));

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, true);
      expect(errorMessage, isNull);
      expect(mockStorageRepo.uploadedImages.length, 1);
      expect(
        mockSignalRepo.addedPhotoUrls[viewModel.state.newlyCreatedSignalId],
        hasLength(1),
      );
    });

    test('submitSignal warns when the photo upload is rejected', () async {
      // Regression guard. `uploadSignalImage` reports failure by *returning* an
      // UploadResult rather than throwing, so this case never reached the
      // catch block: a rejected upload fell through to full success and the
      // photo was dropped with no warning at all. That is how a Storage rule
      // which denied every test-mode upload stayed invisible for months.
      mockStorageRepo.shouldUploadSucceed = false;

      viewModel.updateFormTitle('Help needed');
      viewModel.updateFormDescription('Dog stuck in fence');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);
      viewModel.setFormImage(XFile('/tmp/mock-photo.jpg'));

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      // Partial success: the signal exists, so this is not a failure — but the
      // caller must be told, and no photo URL may be attached.
      expect(success, true);
      expect(errorMessage, 'photo_upload_failed');
      expect(mockSignalRepo.createdSignals.length, 1);
      expect(mockSignalRepo.addedPhotoUrls, isEmpty);

      // The form still resets, exactly as on the success path.
      expect(viewModel.state.isAddingNewSignal, false);
      expect(viewModel.state.formState.title, '');
      expect(viewModel.state.newlyCreatedSignalId, isNotNull);
    });

    test('submitSignal handles creation failure', () async {
      mockSignalRepo.shouldCreateSucceed = false;
      mockSignalRepo.createErrorMessage = 'permission-denied';

      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'permission-denied');
      expect(viewModel.state.formState.isSubmitting, false);
    });

    test('submitSignal fails when not authenticated', () async {
      mockUserRepo.setUnauthenticated();

      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);

      viewModel.confirmLocation(42.0, 23.0);

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'not_authenticated');
    });

    test('submitSignal stores newly created signal ID', () async {
      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);

      viewModel.confirmLocation(42.0, 23.0);

      await viewModel.submitSignal();
      expect(viewModel.state.newlyCreatedSignalId, isNotNull);
    });
  });

  group('Wizard step navigation', () {
    /// Fills everything except the pin, so a test can isolate the location.
    void fillEverythingButLocation() {
      viewModel.updateFormTitle('Title');
      viewModel.updateFormDescription('Description');
      viewModel.setFormUrgency(SignalUrgency.amber.code);
      viewModel.toggleFormHelpTag(HelpTag.rescue.code);
      viewModel.setFormAnimalType(AnimalType.dog.code);
    }

    test('a new form starts on the location question', () {
      expect(viewModel.state.formState.step, NewSignalStep.location);
      expect(viewModel.state.formState.isLocationUnset, true);
    });

    test('submitSignal refuses a form with no pin', () async {
      fillEverythingButLocation();

      final (success, errorMessage) = await viewModel.submitSignal();

      expect(success, false);
      expect(errorMessage, 'location_unset');
    });

    test('confirmLocation stores the pin and opens the first question', () {
      viewModel.confirmLocation(42.5, 23.5);

      expect(viewModel.state.formState.latitude, 42.5);
      expect(viewModel.state.formState.longitude, 23.5);
      expect(viewModel.state.formState.step, NewSignalStep.photo);
    });

    test('confirmLocation from the review step returns there, not to the '
        'start', () {
      // Revising the pin is reached from review, so re-confirming must not
      // march the reporter back through every question they already answered.
      viewModel.confirmLocation(42.0, 23.0);
      viewModel.goToStep(NewSignalStep.review);

      viewModel.confirmLocation(43.0, 24.0);

      expect(viewModel.state.formState.step, NewSignalStep.review);
      expect(viewModel.state.formState.latitude, 43.0);
    });

    test('nextStep refuses to move past an unanswered question', () {
      viewModel.confirmLocation(42.0, 23.0);
      viewModel.goToStep(NewSignalStep.animal);

      viewModel.nextStep();
      expect(viewModel.state.formState.step, NewSignalStep.animal);

      viewModel.setFormAnimalType(AnimalType.cat.code);
      viewModel.nextStep();
      expect(viewModel.state.formState.step, NewSignalStep.urgency);
    });

    test('the photo step is complete without an answer', () {
      // The one optional question — it must not strand the reporter behind a
      // disabled Next button.
      final formState = viewModel.state.formState;
      expect(formState.isStepComplete(NewSignalStep.photo), true);
    });

    test('previousStep reports when there is nowhere left to go', () {
      viewModel.confirmLocation(42.0, 23.0);
      expect(viewModel.state.formState.step, NewSignalStep.photo);

      expect(viewModel.previousStep(), true);
      expect(viewModel.state.formState.step, NewSignalStep.location);

      expect(viewModel.previousStep(), false);
      expect(viewModel.state.formState.step, NewSignalStep.location);
    });

    test('every field isValid requires is caught by exactly one step', () {
      // The wizard disables Next on isStepComplete but submits on isValid. If
      // the two ever disagree, the reporter reaches the review screen and is
      // refused with no way to see which answer is missing.
      viewModel.confirmLocation(42.0, 23.0);
      fillEverythingButLocation();
      expect(viewModel.state.formState.isValid, true);

      for (final step in NewSignalStep.values) {
        expect(viewModel.state.formState.isStepComplete(step), true,
            reason: '$step should be complete on a fully valid form');
      }
    });

    test('cancelAddingNewSignal clears the pin and the step', () {
      viewModel.toggleAddingNewSignal();
      viewModel.confirmLocation(42.0, 23.0);
      viewModel.goToStep(NewSignalStep.urgency);

      viewModel.cancelAddingNewSignal();

      expect(viewModel.state.formState.isLocationUnset, true);
      expect(viewModel.state.formState.step, NewSignalStep.location);
    });

    test('isDirty stays false until the reporter actually answers something', () {
      // Guards the discard warning: a wizard the reporter merely opened and
      // backed out of must not prompt them to confirm losing nothing.
      expect(viewModel.state.formState.isDirty, false);

      viewModel.goToStep(NewSignalStep.animal);
      expect(viewModel.state.formState.isDirty, false,
          reason: 'navigating is not answering');

      viewModel.updateFormTitle('Title');
      expect(viewModel.state.formState.isDirty, true);
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
    test('isValid requires title, description and urgency', () {
      const emptyForm = NewSignalFormState();
      expect(emptyForm.isValid, false);

      const titleOnly = NewSignalFormState(title: 'Title');
      expect(titleOnly.isValid, false);

      const descOnly = NewSignalFormState(description: 'Desc');
      expect(descOnly.isValid, false);

      // Urgency is a required field on every signal (spec 4.4), so title +
      // description alone is not publishable.
      const noUrgency = NewSignalFormState(title: 'Title', description: 'Desc');
      expect(noUrgency.isValid, false);
      expect(noUrgency.isUrgencyUnset, true);

      // Help tags and species are required too (spec 4.4), for the same reason:
      // an untagged signal falls back to reaching everyone.
      final noTags = NewSignalFormState(
        title: 'Title',
        description: 'Desc',
        urgency: SignalUrgency.amber.code,
        animalType: AnimalType.dog.code,
      );
      expect(noTags.isValid, false);
      expect(noTags.isHelpTagsEmpty, true);

      final noAnimal = NewSignalFormState(
        title: 'Title',
        description: 'Desc',
        urgency: SignalUrgency.amber.code,
        helpTags: [HelpTag.rescue.code],
      );
      expect(noAnimal.isValid, false);
      expect(noAnimal.isAnimalTypeUnset, true);

      // The pin is a required answer like any other now, not a value read off
      // the map camera at the moment of submit.
      final noLocation = NewSignalFormState(
        title: 'Title',
        description: 'Desc',
        urgency: SignalUrgency.amber.code,
        helpTags: [HelpTag.rescue.code],
        animalType: AnimalType.dog.code,
      );
      expect(noLocation.isValid, false);
      expect(noLocation.isLocationUnset, true);

      final valid = NewSignalFormState(
        title: 'Title',
        description: 'Desc',
        urgency: SignalUrgency.amber.code,
        helpTags: [HelpTag.rescue.code],
        animalType: AnimalType.dog.code,
        latitude: 42.0,
        longitude: 23.0,
      );
      expect(valid.isValid, true);
    });

    test('reset clears all fields', () {
      const form = NewSignalFormState(
        title: 'Title',
        description: 'Desc',
        phoneNumber: '123',
        urgency: 2,
        isSubmitting: true,
      );

      final reset = form.reset();

      expect(reset.title, '');
      expect(reset.description, '');
      expect(reset.phoneNumber, '');
      // Back to "unchosen", not to a level the next reporter never picked.
      expect(reset.urgency, isNull);
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

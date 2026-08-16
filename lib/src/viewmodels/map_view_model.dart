import 'dart:async';
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../models/new_signal_step.dart';
import '../models/vet_clinic.dart';
import '../repositories/repository_provider.dart';
import '../repositories/signal_repository.dart';
import '../services/app_preferences_service.dart';
import '../services/vet_clinic_service.dart';
import '../state/map_state.dart';

/// Provider for test mode state. Toggling this invalidates the signals stream.
final testModeProvider = NotifierProvider<TestModeNotifier, bool>(
  TestModeNotifier.new,
);

class TestModeNotifier extends Notifier<bool> {
  @override
  bool build() => AppPreferencesService().isTestMode();

  void toggle(bool value) => state = value;
}

/// Provider for the map view model
final mapViewModelProvider =
    NotifierProvider<MapViewModel, MapScreenState>(MapViewModel.new);

/// Provider for the signals stream based on current map center and time range
final signalsStreamProvider = StreamProvider<List<SignalWithId>>((ref) {
  // Watch test mode so toggling it re-subscribes to the correct collection
  ref.watch(testModeProvider);

  final centerLat = ref.watch(
    mapViewModelProvider.select((s) => s.centerLatitude),
  );
  final centerLng = ref.watch(
    mapViewModelProvider.select((s) => s.centerLongitude),
  );
  final timeRange = ref.watch(
    mapViewModelProvider.select((s) => s.filterState.selectedTimeRange),
  );
  final signalRepo = RepositoryProvider.instance.signalRepository;

  return signalRepo.getSignalsInRadius(
    centerLatitude: centerLat,
    centerLongitude: centerLng,
    radiusInKm: 100.0,
    createdAfter: timeRange.cutoffDate,
  );
});

/// ViewModel for the map screen using Riverpod Notifier
class MapViewModel extends Notifier<MapScreenState> {
  final _vetClinicService = VetClinicService.instance;
  Timer? _searchButtonDebounce;

  @override
  MapScreenState build() => const MapScreenState();

  // ============================================================
  // Location Management
  // ============================================================

  /// Update the map center location.
  /// Only triggers a state change (and thus a signals re-query) when the new
  /// center is more than [_kReQueryThresholdKm] from the current one, to
  /// avoid excessive Firestore reads on small pans.
  /// Pass [force] = true to bypass the threshold (e.g. initial location set).
  static const _kReQueryThresholdKm = 30.0;

  void updateMapCenter(double latitude, double longitude,
      {bool force = false}) {
    if (!force) {
      final distanceMeters = Geolocator.distanceBetween(
        state.centerLatitude,
        state.centerLongitude,
        latitude,
        longitude,
      );
      if (distanceMeters / 1000 < _kReQueryThresholdKm) return;
    }
    state = state.copyWith(
      centerLatitude: latitude,
      centerLongitude: longitude,
    );
  }

  /// Check and update location permission status
  Future<void> checkLocationPermission() async {
    final permission = await Geolocator.checkPermission();
    final hasPermission = permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;

    state = state.copyWith(hasLocationPermission: hasPermission);
  }

  /// Get user location and update map center
  Future<void> getUserLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      state = state.copyWith(hasLocationPermission: false);
      return;
    }

    state = state.copyWith(hasLocationPermission: true);

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      updateMapCenter(position.latitude, position.longitude, force: true);
    } catch (e) {
      // Silently fail - keep default location
    }
  }

  // ============================================================
  // Filter Management
  // ============================================================

  /// Toggle a help-tag filter
  void toggleHelpTag(String code) {
    state = state.copyWith(
      filterState: state.filterState.toggleHelpTag(code),
    );
  }

  /// Toggle a species filter
  void toggleAnimalType(String code) {
    state = state.copyWith(
      filterState: state.filterState.toggleAnimalType(code),
    );
  }

  /// Toggle a status filter
  void toggleStatus(int status) {
    state = state.copyWith(
      filterState: state.filterState.toggleStatus(status),
    );
  }

  /// Toggle an urgency filter
  void toggleUrgency(int urgency) {
    state = state.copyWith(
      filterState: state.filterState.toggleUrgency(urgency),
    );
  }

  /// Set the time range filter
  void setTimeRange(TimeRange timeRange) {
    state = state.copyWith(
      filterState: state.filterState.copyWith(selectedTimeRange: timeRange),
    );
  }

  /// Select all filters
  void selectAllFilters() {
    state = state.copyWith(
      filterState: state.filterState.selectAll(),
    );
  }

  /// Clear all filters
  void clearAllFilters() {
    state = state.copyWith(
      filterState: state.filterState.clearAll(),
    );
  }

  // ============================================================
  // New Signal Form Management
  // ============================================================

  /// Toggle add new signal mode
  void toggleAddingNewSignal() {
    final isAdding = !state.isAddingNewSignal;
    state = state.copyWith(
      isAddingNewSignal: isAdding,
      formState: isAdding ? state.formState : const NewSignalFormState(),
    );
  }

  /// Cancel adding new signal
  void cancelAddingNewSignal() {
    state = state.copyWith(
      isAddingNewSignal: false,
      formState: const NewSignalFormState(),
    );
  }

  /// Update form title
  void updateFormTitle(String title) {
    state = state.copyWith(
      formState: state.formState.copyWith(title: title),
    );
  }

  /// Update form description
  void updateFormDescription(String description) {
    state = state.copyWith(
      formState: state.formState.copyWith(description: description),
    );
  }

  /// Update form phone number
  void updateFormPhoneNumber(String phoneNumber) {
    state = state.copyWith(
      formState: state.formState.copyWith(phoneNumber: phoneNumber),
    );
  }

  /// Set form urgency
  void setFormUrgency(int urgency) {
    state = state.copyWith(
      formState: state.formState.copyWith(urgency: urgency),
    );
  }

  /// Add or remove a help-needed tag on the form.
  void toggleFormHelpTag(String code) {
    state = state.copyWith(
      formState: state.formState
          .copyWith(helpTags: state.formState.toggledHelpTag(code)),
    );
  }

  /// Set which animal the form's signal is about.
  void setFormAnimalType(String code) {
    state = state.copyWith(
      formState: state.formState.copyWith(animalType: code),
    );
  }

  /// Accept the pin the reporter placed on the map and open the first wizard
  /// question.
  ///
  /// Jumping straight to [NewSignalStep.photo] rather than calling [nextStep]
  /// keeps this correct when the reporter came *back* to the map from the
  /// review step to revise the pin — in that case [step] is already
  /// [NewSignalStep.review] and advancing by one would land them somewhere they
  /// have been through. [goToStep] is what the review screen uses to arrange
  /// that return, so this only ever needs to handle the forward case.
  void confirmLocation(double latitude, double longitude) {
    final formState = state.formState;
    state = state.copyWith(
      formState: formState.copyWith(
        latitude: latitude,
        longitude: longitude,
        step: formState.step == NewSignalStep.location
            ? NewSignalStep.photo
            : formState.step,
      ),
    );
  }

  /// Jump to a specific question — the review screen's "Change" links.
  void goToStep(NewSignalStep step) {
    state = state.copyWith(formState: state.formState.copyWith(step: step));
  }

  /// Advance, but never past an unanswered question.
  ///
  /// The guard matters because auto-advance fires from a timer: a reporter who
  /// taps a chip and immediately taps Back would otherwise be dragged forward
  /// again by the callback that is already in flight.
  void nextStep() {
    final formState = state.formState;
    if (!formState.isStepComplete(formState.step)) return;
    final next = formState.step.next;
    if (next == null) return;
    state = state.copyWith(formState: formState.copyWith(step: next));
  }

  /// Go back one question. Returns false at the first step, where the caller
  /// has to decide whether to leave the wizard entirely.
  bool previousStep() {
    final previous = state.formState.step.previous;
    if (previous == null) return false;
    state = state.copyWith(formState: state.formState.copyWith(step: previous));
    return true;
  }

  /// Set selected image
  void setFormImage(XFile? image) {
    state = state.copyWith(
      formState: state.formState.copyWith(
        selectedImage: image,
        clearImage: image == null,
      ),
    );
  }

  /// Clear selected image
  void clearFormImage() {
    state = state.copyWith(
      formState: state.formState.copyWith(clearImage: true),
    );
  }

  /// Submit a new signal
  ///
  /// The coordinates come from [NewSignalFormState.latitude]/[longitude], set
  /// by [confirmLocation]. They used to be arguments read off the map camera at
  /// this moment, which is why nothing upstream could show the reporter where
  /// their pin was going.
  ///
  /// Returns a tuple of (success, errorMessage)
  Future<(bool success, String? errorMessage)> submitSignal() async {
    if (!state.formState.isValid) {
      if (state.formState.isLocationUnset) {
        return (false, 'location_unset');
      }
      if (state.formState.isTitleEmpty) {
        return (false, 'title_empty');
      }
      if (state.formState.isDescriptionEmpty) {
        return (false, 'description_empty');
      }
      if (state.formState.isUrgencyUnset) {
        return (false, 'urgency_unset');
      }
      if (state.formState.isHelpTagsEmpty) {
        return (false, 'help_tags_empty');
      }
      if (state.formState.isAnimalTypeUnset) {
        return (false, 'animal_type_unset');
      }
      return (false, 'invalid_form');
    }

    // Non-null: `isValid` gates submission on the location above.
    final latitude = state.formState.latitude!;
    final longitude = state.formState.longitude!;

    // Captured up front, like the location, because it is read *after* two
    // awaits. `cancelAddingNewSignal` resets `formState` to a blank one, so a
    // reporter who taps × → Discard mid-submit would otherwise leave this
    // reading null by the time the upload block is reached: the photo would be
    // skipped and the submit would still report full success. Every other field
    // is read before the first await, which is why only this one could drift.
    final selectedImage = state.formState.selectedImage;

    FirebaseCrashlytics.instance.log('Signal: Submitting - tags: ${state.formState.helpTags}, animal: ${state.formState.animalType}, urgency: ${state.formState.urgency}, location: $latitude/$longitude');

    state = state.copyWith(
      formState: state.formState.copyWith(isSubmitting: true),
    );

    try {
      final userRepo = RepositoryProvider.instance.userRepository;
      final userId = userRepo.currentUserId;

      if (userId == null || !userRepo.canModifyData) {
        state = state.copyWith(
          formState: state.formState.copyWith(isSubmitting: false),
        );
        return (false, 'not_authenticated');
      }

      final signalRepo = RepositoryProvider.instance.signalRepository;
      final result = await signalRepo.createSignal(
        title: state.formState.title.trim(),
        description: state.formState.description.trim(),
        phoneNumber: state.formState.phoneNumber.trim(),
        latitude: latitude,
        longitude: longitude,
        reporterUserId: userId,
        // Non-null / non-empty: `isValid` gates submission on all three above.
        urgency: state.formState.urgency!,
        helpNeededTags: state.formState.helpTags,
        animalType: state.formState.animalType!,
      );

      if (!result.success) {
        state = state.copyWith(
          formState: state.formState.copyWith(isSubmitting: false),
        );
        return (false, result.errorMessage);
      }

      // Subscribe creator to their signal
      await signalRepo.subscribeCreatorToSignal(
        signalId: result.signalId,
        userId: userId,
      );

      // Upload image if selected
      if (selectedImage != null) {
        try {
          final storageRepo = RepositoryProvider.instance.storageRepository;
          final uploadResult = await storageRepo.uploadSignalImage(
            signalId: result.signalId,
            imageFile: File(selectedImage.path),
          );

          if (uploadResult.success && uploadResult.downloadUrl != null) {
            await signalRepo.addPhotoUrl(result.signalId, uploadResult.downloadUrl!);
          } else {
            // `uploadSignalImage` reports failure by *returning* an
            // UploadResult, not by throwing, so this can't be left to the catch
            // below. Without it a rejected upload fell through to full success
            // and the photo was dropped with no warning at all — which is how a
            // Storage rule that denied every test-mode upload went unnoticed.
            return _photoUploadFailed(result.signalId);
          }
        } catch (e) {
          // Photo upload failed but signal was created
          // Return partial success
          return _photoUploadFailed(result.signalId);
        }
      }

      FirebaseCrashlytics.instance.log('Signal: Created successfully - id: ${result.signalId}');
      state = state.copyWith(
        isAddingNewSignal: false,
        newlyCreatedSignalId: result.signalId,
        formState: const NewSignalFormState(),
      );
      return (true, null);
    } catch (e) {
      state = state.copyWith(
        formState: state.formState.copyWith(isSubmitting: false),
      );
      return (false, e.toString());
    }
  }

  /// The signal was created but its photo did not attach. Clears the form the
  /// same way the success path does, so the only difference the caller sees is
  /// the warning it gets to show.
  (bool, String?) _photoUploadFailed(String signalId) {
    FirebaseCrashlytics.instance
        .log('Signal: Created without photo (upload failed) - id: $signalId');
    state = state.copyWith(
      isAddingNewSignal: false,
      newlyCreatedSignalId: signalId,
      formState: const NewSignalFormState(),
    );
    return (true, 'photo_upload_failed');
  }

  // ============================================================
  // Vet Clinic Management
  // ============================================================

  /// Toggle vet clinics visibility
  void toggleVetClinics() {
    final show = !state.vetClinicState.showVetClinics;
    FirebaseCrashlytics.instance.log('Map: Vet clinics toggled - show: $show');
    state = state.copyWith(
      vetClinicState: state.vetClinicState.copyWith(
        showVetClinics: show,
        // Clear data when hiding
        clinics: show ? state.vetClinicState.clinics : [],
        clinicMarkers: show ? state.vetClinicState.clinicMarkers : {},
        showSearchThisAreaButton: false,
        clearLastSearch: !show,
      ),
    );
  }

  /// Load vet clinics for the current map area
  Future<void> loadVetClinics({
    required LatLng center,
    required double zoomLevel,
    required BitmapDescriptor? hospitalPin,
    required void Function(String clinicId) onClinicTap,
  }) async {
    state = state.copyWith(
      vetClinicState: state.vetClinicState.copyWith(isLoading: true),
    );

    try {
      final radiusKm = _calculateSearchRadius(zoomLevel);
      final radiusMeters = radiusKm * 1000;

      final clinics = await _vetClinicService.searchNearby(center, radiusMeters);

      final markers = _buildClinicMarkers(
        clinics: clinics,
        hospitalPin: hospitalPin,
        onClinicTap: onClinicTap,
      );

      state = state.copyWith(
        vetClinicState: state.vetClinicState.copyWith(
          clinics: clinics,
          clinicMarkers: markers,
          lastSearchCenter: center,
          lastSearchZoom: zoomLevel,
          showSearchThisAreaButton: false,
          isLoading: false,
        ),
      );
    } catch (e) {
      state = state.copyWith(
        vetClinicState: state.vetClinicState.copyWith(isLoading: false),
      );
      rethrow;
    }
  }

  /// Check if "Search this area" button should be shown
  Future<void> checkVetClinicSearchButton({
    required LatLng currentCenter,
    required double currentZoom,
  }) async {
    if (!state.vetClinicState.showVetClinics ||
        state.vetClinicState.lastSearchCenter == null) {
      return;
    }

    _searchButtonDebounce?.cancel();
    _searchButtonDebounce = Timer(const Duration(milliseconds: 1000), () {
      final lastCenter = state.vetClinicState.lastSearchCenter!;
      final distance = Geolocator.distanceBetween(
            lastCenter.latitude,
            lastCenter.longitude,
            currentCenter.latitude,
            currentCenter.longitude,
          ) /
          1000; // Convert to km

      final zoomDiff = state.vetClinicState.lastSearchZoom != null
          ? (currentZoom - state.vetClinicState.lastSearchZoom!).abs()
          : 0.0;

      if (distance > 2.0 || zoomDiff > 2.0) {
        state = state.copyWith(
          vetClinicState: state.vetClinicState.copyWith(
            showSearchThisAreaButton: true,
          ),
        );
      }
    });
  }

  /// Hide the search this area button
  void hideSearchThisAreaButton() {
    state = state.copyWith(
      vetClinicState: state.vetClinicState.copyWith(
        showSearchThisAreaButton: false,
      ),
    );
  }

  // Private helper methods

  double _calculateSearchRadius(double zoomLevel) {
    final radiusKm = 20000 / (1 << zoomLevel.round());
    return radiusKm.clamp(1.0, 100.0);
  }

  Set<Marker> _buildClinicMarkers({
    required List<VetClinic> clinics,
    required BitmapDescriptor? hospitalPin,
    required void Function(String clinicId) onClinicTap,
  }) {
    return clinics.map((clinic) {
      return Marker(
        markerId: MarkerId('clinic_${clinic.id}'),
        position: LatLng(clinic.latitude, clinic.longitude),
        icon: hospitalPin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: clinic.name,
          snippet: clinic.address,
          onTap: () => onClinicTap(clinic.id),
        ),
      );
    }).toSet();
  }
}

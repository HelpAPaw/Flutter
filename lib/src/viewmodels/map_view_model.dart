import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../models/vet_clinic.dart';
import '../repositories/repository_provider.dart';
import '../repositories/signal_repository.dart';
import '../services/app_preferences_service.dart';
import '../services/vet_clinic_service.dart';
import '../state/map_state.dart';

/// Provider for test mode state. Toggling this invalidates the signals stream.
final testModeProvider = StateProvider<bool>((ref) {
  return AppPreferencesService().isTestMode();
});

/// Provider for the map view model
final mapViewModelProvider =
    StateNotifierProvider<MapViewModel, MapScreenState>((ref) {
  return MapViewModel();
});

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

/// ViewModel for the map screen using Riverpod StateNotifier
class MapViewModel extends StateNotifier<MapScreenState> {
  MapViewModel() : super(const MapScreenState());

  final _vetClinicService = VetClinicService.instance;
  Timer? _searchButtonDebounce;

  @override
  void dispose() {
    _searchButtonDebounce?.cancel();
    super.dispose();
  }

  // ============================================================
  // Location Management
  // ============================================================

  /// Update the map center location
  void updateMapCenter(double latitude, double longitude) {
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
      updateMapCenter(position.latitude, position.longitude);
    } catch (e) {
      // Silently fail - keep default location
    }
  }

  // ============================================================
  // Filter Management
  // ============================================================

  /// Toggle a signal type filter
  void toggleSignalType(int type) {
    state = state.copyWith(
      filterState: state.filterState.toggleSignalType(type),
    );
  }

  /// Toggle a status filter
  void toggleStatus(int status) {
    state = state.copyWith(
      filterState: state.filterState.toggleStatus(status),
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

  /// Check if a signal passes the current filter
  bool signalPassesFilter(int signalType, int status) {
    return state.filterState.signalPassesFilter(signalType, status);
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

  /// Set form signal type
  void setFormSignalType(int type) {
    state = state.copyWith(
      formState: state.formState.copyWith(signalType: type),
    );
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
  /// Returns a tuple of (success, errorMessage)
  Future<(bool success, String? errorMessage)> submitSignal({
    required double latitude,
    required double longitude,
  }) async {
    if (!state.formState.isValid) {
      if (state.formState.isTitleEmpty) {
        return (false, 'title_empty');
      }
      if (state.formState.isDescriptionEmpty) {
        return (false, 'description_empty');
      }
      return (false, 'invalid_form');
    }

    state = state.copyWith(
      formState: state.formState.copyWith(isSubmitting: true),
    );

    try {
      final userRepo = RepositoryProvider.instance.userRepository;
      final userId = userRepo.currentUserId;

      if (userId == null) {
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
        signalType: state.formState.signalType,
        latitude: latitude,
        longitude: longitude,
        reporterUserId: userId,
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
      if (state.formState.selectedImage != null) {
        try {
          final storageRepo = RepositoryProvider.instance.storageRepository;
          final uploadResult = await storageRepo.uploadSignalImage(
            signalId: result.signalId,
            imageFile: File(state.formState.selectedImage!.path),
          );

          if (uploadResult.success && uploadResult.downloadUrl != null) {
            await signalRepo.addPhotoUrl(result.signalId, uploadResult.downloadUrl!);
          }
        } catch (e) {
          // Photo upload failed but signal was created
          // Return partial success
          state = state.copyWith(
            isAddingNewSignal: false,
            newlyCreatedSignalId: result.signalId,
            formState: const NewSignalFormState(),
          );
          return (true, 'photo_upload_failed');
        }
      }

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

  // ============================================================
  // Vet Clinic Management
  // ============================================================

  /// Toggle vet clinics visibility
  void toggleVetClinics() {
    final show = !state.vetClinicState.showVetClinics;
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

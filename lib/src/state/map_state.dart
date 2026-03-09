import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../models/vet_clinic.dart';

/// Time range options for filtering signals by creation date
enum TimeRange {
  last24Hours,
  last7Days,
  last30Days,
  allTime;

  /// Returns the cutoff DateTime for this range, or null for allTime
  DateTime? get cutoffDate {
    final now = DateTime.now();
    switch (this) {
      case TimeRange.last24Hours:
        return now.subtract(const Duration(hours: 24));
      case TimeRange.last7Days:
        return now.subtract(const Duration(days: 7));
      case TimeRange.last30Days:
        return now.subtract(const Duration(days: 30));
      case TimeRange.allTime:
        return null;
    }
  }
}

/// Default time range for the map
const defaultTimeRange = TimeRange.last30Days;

/// Immutable state for signal type and status filters
@immutable
class MapFilterState {
  final Set<int> selectedSignalTypes;
  final Set<int> selectedStatuses;
  final TimeRange selectedTimeRange;

  const MapFilterState({
    this.selectedSignalTypes = const {0, 1, 2, 3, 4, 5, 6},
    this.selectedStatuses = const {0, 1, 2},
    this.selectedTimeRange = defaultTimeRange,
  });

  /// All signal types selected (no filter active)
  static const allSignalTypes = {0, 1, 2, 3, 4, 5, 6};

  /// All statuses selected (no filter active)
  static const allStatuses = {0, 1, 2};

  /// Check if any filter is active
  bool get hasActiveFilters =>
      selectedSignalTypes.length < 7 ||
      selectedStatuses.length < 3 ||
      selectedTimeRange != defaultTimeRange;

  /// Check if a signal passes the current filter
  bool signalPassesFilter(int signalType, int status) {
    return selectedSignalTypes.contains(signalType) &&
        selectedStatuses.contains(status);
  }

  MapFilterState copyWith({
    Set<int>? selectedSignalTypes,
    Set<int>? selectedStatuses,
    TimeRange? selectedTimeRange,
  }) {
    return MapFilterState(
      selectedSignalTypes: selectedSignalTypes ?? this.selectedSignalTypes,
      selectedStatuses: selectedStatuses ?? this.selectedStatuses,
      selectedTimeRange: selectedTimeRange ?? this.selectedTimeRange,
    );
  }

  /// Toggle a signal type on/off
  MapFilterState toggleSignalType(int type) {
    final newTypes = Set<int>.from(selectedSignalTypes);
    if (newTypes.contains(type)) {
      newTypes.remove(type);
    } else {
      newTypes.add(type);
    }
    return copyWith(selectedSignalTypes: newTypes);
  }

  /// Toggle a status on/off
  MapFilterState toggleStatus(int status) {
    final newStatuses = Set<int>.from(selectedStatuses);
    if (newStatuses.contains(status)) {
      newStatuses.remove(status);
    } else {
      newStatuses.add(status);
    }
    return copyWith(selectedStatuses: newStatuses);
  }

  /// Select all filters
  MapFilterState selectAll() {
    return MapFilterState(
      selectedSignalTypes: const {0, 1, 2, 3, 4, 5, 6},
      selectedStatuses: const {0, 1, 2},
      selectedTimeRange: selectedTimeRange,
    );
  }

  /// Clear all filters
  MapFilterState clearAll() {
    return MapFilterState(
      selectedSignalTypes: const {},
      selectedStatuses: const {},
      selectedTimeRange: selectedTimeRange,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MapFilterState &&
        setEquals(other.selectedSignalTypes, selectedSignalTypes) &&
        setEquals(other.selectedStatuses, selectedStatuses) &&
        other.selectedTimeRange == selectedTimeRange;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(selectedSignalTypes),
        Object.hashAll(selectedStatuses),
        selectedTimeRange,
      );
}

/// Immutable state for the new signal form
@immutable
class NewSignalFormState {
  final String title;
  final String description;
  final String phoneNumber;
  final int signalType;
  final XFile? selectedImage;
  final bool isSubmitting;

  const NewSignalFormState({
    this.title = '',
    this.description = '',
    this.phoneNumber = '',
    this.signalType = 0,
    this.selectedImage,
    this.isSubmitting = false,
  });

  /// Check if the form is valid for submission
  bool get isValid => title.trim().isNotEmpty && description.trim().isNotEmpty;

  /// Check if title is empty
  bool get isTitleEmpty => title.trim().isEmpty;

  /// Check if description is empty
  bool get isDescriptionEmpty => description.trim().isEmpty;

  NewSignalFormState copyWith({
    String? title,
    String? description,
    String? phoneNumber,
    int? signalType,
    XFile? selectedImage,
    bool? isSubmitting,
    bool clearImage = false,
  }) {
    return NewSignalFormState(
      title: title ?? this.title,
      description: description ?? this.description,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      signalType: signalType ?? this.signalType,
      selectedImage: clearImage ? null : (selectedImage ?? this.selectedImage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
    );
  }

  /// Reset the form to initial state
  NewSignalFormState reset() {
    return const NewSignalFormState();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NewSignalFormState &&
        other.title == title &&
        other.description == description &&
        other.phoneNumber == phoneNumber &&
        other.signalType == signalType &&
        other.selectedImage?.path == selectedImage?.path &&
        other.isSubmitting == isSubmitting;
  }

  @override
  int get hashCode => Object.hash(
        title,
        description,
        phoneNumber,
        signalType,
        selectedImage?.path,
        isSubmitting,
      );
}

/// Immutable state for vet clinic display
@immutable
class VetClinicState {
  final bool showVetClinics;
  final List<VetClinic> clinics;
  final Set<Marker> clinicMarkers;
  final LatLng? lastSearchCenter;
  final double? lastSearchZoom;
  final bool showSearchThisAreaButton;
  final bool isLoading;

  const VetClinicState({
    this.showVetClinics = false,
    this.clinics = const [],
    this.clinicMarkers = const {},
    this.lastSearchCenter,
    this.lastSearchZoom,
    this.showSearchThisAreaButton = false,
    this.isLoading = false,
  });

  VetClinicState copyWith({
    bool? showVetClinics,
    List<VetClinic>? clinics,
    Set<Marker>? clinicMarkers,
    LatLng? lastSearchCenter,
    double? lastSearchZoom,
    bool? showSearchThisAreaButton,
    bool? isLoading,
    bool clearLastSearch = false,
  }) {
    return VetClinicState(
      showVetClinics: showVetClinics ?? this.showVetClinics,
      clinics: clinics ?? this.clinics,
      clinicMarkers: clinicMarkers ?? this.clinicMarkers,
      lastSearchCenter:
          clearLastSearch ? null : (lastSearchCenter ?? this.lastSearchCenter),
      lastSearchZoom:
          clearLastSearch ? null : (lastSearchZoom ?? this.lastSearchZoom),
      showSearchThisAreaButton:
          showSearchThisAreaButton ?? this.showSearchThisAreaButton,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// Clear all vet clinic data
  VetClinicState clear() {
    return const VetClinicState();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VetClinicState &&
        other.showVetClinics == showVetClinics &&
        listEquals(other.clinics, clinics) &&
        setEquals(other.clinicMarkers, clinicMarkers) &&
        other.lastSearchCenter == lastSearchCenter &&
        other.lastSearchZoom == lastSearchZoom &&
        other.showSearchThisAreaButton == showSearchThisAreaButton &&
        other.isLoading == isLoading;
  }

  @override
  int get hashCode => Object.hash(
        showVetClinics,
        Object.hashAll(clinics),
        Object.hashAll(clinicMarkers),
        lastSearchCenter,
        lastSearchZoom,
        showSearchThisAreaButton,
        isLoading,
      );
}

/// Main state for the map screen
@immutable
class MapScreenState {
  final double centerLatitude;
  final double centerLongitude;
  final bool isAddingNewSignal;
  final String? newlyCreatedSignalId;
  final bool hasLocationPermission;
  final MapFilterState filterState;
  final NewSignalFormState formState;
  final VetClinicState vetClinicState;

  const MapScreenState({
    this.centerLatitude = 42.6977,
    this.centerLongitude = 23.3219,
    this.isAddingNewSignal = false,
    this.newlyCreatedSignalId,
    this.hasLocationPermission = false,
    this.filterState = const MapFilterState(),
    this.formState = const NewSignalFormState(),
    this.vetClinicState = const VetClinicState(),
  });

  /// Default center: Sofia, Bulgaria
  static const defaultLatitude = 42.6977;
  static const defaultLongitude = 23.3219;

  MapScreenState copyWith({
    double? centerLatitude,
    double? centerLongitude,
    bool? isAddingNewSignal,
    String? newlyCreatedSignalId,
    bool? hasLocationPermission,
    MapFilterState? filterState,
    NewSignalFormState? formState,
    VetClinicState? vetClinicState,
  }) {
    return MapScreenState(
      centerLatitude: centerLatitude ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      isAddingNewSignal: isAddingNewSignal ?? this.isAddingNewSignal,
      newlyCreatedSignalId:
          newlyCreatedSignalId ?? this.newlyCreatedSignalId,
      hasLocationPermission:
          hasLocationPermission ?? this.hasLocationPermission,
      filterState: filterState ?? this.filterState,
      formState: formState ?? this.formState,
      vetClinicState: vetClinicState ?? this.vetClinicState,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MapScreenState &&
        other.centerLatitude == centerLatitude &&
        other.centerLongitude == centerLongitude &&
        other.isAddingNewSignal == isAddingNewSignal &&
        other.newlyCreatedSignalId == newlyCreatedSignalId &&
        other.hasLocationPermission == hasLocationPermission &&
        other.filterState == filterState &&
        other.formState == formState &&
        other.vetClinicState == vetClinicState;
  }

  @override
  int get hashCode => Object.hash(
        centerLatitude,
        centerLongitude,
        isAddingNewSignal,
        newlyCreatedSignalId,
        hasLocationPermission,
        filterState,
        formState,
        vetClinicState,
      );
}

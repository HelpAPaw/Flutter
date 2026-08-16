import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../models/help_tag.dart';
import '../models/new_signal_step.dart';
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

/// Immutable state for signal type, status and urgency filters
@immutable
class MapFilterState {
  final Set<int> selectedSignalTypes;
  final Set<int> selectedStatuses;
  final Set<int> selectedUrgencies;
  final TimeRange selectedTimeRange;

  const MapFilterState({
    this.selectedSignalTypes = allSignalTypes,
    this.selectedStatuses = allStatuses,
    this.selectedUrgencies = allUrgencies,
    this.selectedTimeRange = defaultTimeRange,
  });

  /// All signal types selected (no filter active).
  ///
  /// These three sets have to stay `const` (they are default arguments all the
  /// way up to `MapScreenState`), so they can't be derived from their enums
  /// here. `test/map_filter_state_test.dart` fails the build if one of them
  /// drifts out of step — without that guard, appending a status or urgency
  /// would silently leave it filtered off the map with no error anywhere.
  static const allSignalTypes = {0, 1, 2, 3, 4, 5, 6};

  /// All statuses selected (no filter active)
  static const allStatuses = {0, 1, 2};

  /// All urgencies selected (no filter active)
  static const allUrgencies = {0, 1, 2};

  /// Check if any filter is active
  bool get hasActiveFilters =>
      selectedSignalTypes.length < allSignalTypes.length ||
      selectedStatuses.length < allStatuses.length ||
      selectedUrgencies.length < allUrgencies.length ||
      selectedTimeRange != defaultTimeRange;

  /// Check if a signal passes the current filter
  bool signalPassesFilter(int signalType, int status, int urgency) {
    return selectedSignalTypes.contains(signalType) &&
        selectedStatuses.contains(status) &&
        selectedUrgencies.contains(urgency);
  }

  MapFilterState copyWith({
    Set<int>? selectedSignalTypes,
    Set<int>? selectedStatuses,
    Set<int>? selectedUrgencies,
    TimeRange? selectedTimeRange,
  }) {
    return MapFilterState(
      selectedSignalTypes: selectedSignalTypes ?? this.selectedSignalTypes,
      selectedStatuses: selectedStatuses ?? this.selectedStatuses,
      selectedUrgencies: selectedUrgencies ?? this.selectedUrgencies,
      selectedTimeRange: selectedTimeRange ?? this.selectedTimeRange,
    );
  }

  /// [set] with [value] added if absent, removed if present.
  static Set<int> _toggled(Set<int> set, int value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  /// Toggle a signal type on/off
  MapFilterState toggleSignalType(int type) =>
      copyWith(selectedSignalTypes: _toggled(selectedSignalTypes, type));

  /// Toggle a status on/off
  MapFilterState toggleStatus(int status) =>
      copyWith(selectedStatuses: _toggled(selectedStatuses, status));

  /// Toggle an urgency on/off
  MapFilterState toggleUrgency(int urgency) =>
      copyWith(selectedUrgencies: _toggled(selectedUrgencies, urgency));

  /// Select all filters
  MapFilterState selectAll() {
    return MapFilterState(
      selectedSignalTypes: allSignalTypes,
      selectedStatuses: allStatuses,
      selectedUrgencies: allUrgencies,
      selectedTimeRange: selectedTimeRange,
    );
  }

  /// Clear all filters
  MapFilterState clearAll() {
    return MapFilterState(
      selectedSignalTypes: const {},
      selectedStatuses: const {},
      selectedUrgencies: const {},
      selectedTimeRange: selectedTimeRange,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MapFilterState &&
        setEquals(other.selectedSignalTypes, selectedSignalTypes) &&
        setEquals(other.selectedStatuses, selectedStatuses) &&
        setEquals(other.selectedUrgencies, selectedUrgencies) &&
        other.selectedTimeRange == selectedTimeRange;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(selectedSignalTypes),
        Object.hashAll(selectedStatuses),
        Object.hashAll(selectedUrgencies),
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

  /// Chosen urgency, or null if the reporter has not picked one yet.
  ///
  /// Nullable on purpose: the spec makes urgency a required field on every
  /// case, so defaulting it would let people publish a level they never
  /// actually chose — which is exactly how an urgency system stops meaning
  /// anything. [isValid] keeps submit disabled until it is set.
  final int? urgency;

  /// What the case needs — [HelpTag.code] values, in the order chosen.
  ///
  /// Order is the priority the reporter assigned and is preserved on write.
  /// A list rather than a set for exactly that reason.
  final List<String> helpTags;

  /// Which animal, or null until the reporter picks. Nullable for the same
  /// reason as [urgency]: defaulting it publishes a claim nobody made.
  final String? animalType;

  final XFile? selectedImage;
  final bool isSubmitting;

  /// Where the reporter placed the pin, or null until they confirm it on the
  /// map.
  ///
  /// The location used to be read from the map camera at the instant of submit
  /// and never stored, which is why nothing could show it back to the reporter
  /// or let them revise it. It is a real answer like any other now, so the
  /// review step can display it and the wizard can be reached from a route that
  /// has no map of its own.
  final double? latitude;
  final double? longitude;

  /// Which question the reporter is on.
  ///
  /// Lives in state rather than in the wizard widget so it survives the trip
  /// back to the map for a location change — the wizard route is popped and
  /// re-pushed, and resumes where it left off.
  final NewSignalStep step;

  const NewSignalFormState({
    this.title = '',
    this.description = '',
    this.phoneNumber = '',
    this.signalType = 0,
    this.urgency,
    this.helpTags = const [],
    this.animalType,
    this.selectedImage,
    this.isSubmitting = false,
    this.latitude,
    this.longitude,
    this.step = NewSignalStep.location,
  });

  /// Check if the form is valid for submission
  bool get isValid =>
      !isLocationUnset &&
      title.trim().isNotEmpty &&
      description.trim().isNotEmpty &&
      urgency != null &&
      helpTags.isNotEmpty &&
      animalType != null;

  /// Whether the reporter has entered anything worth warning them about before
  /// discarding. The signal type is excluded deliberately: it has a default, so
  /// its presence says nothing about whether anyone typed or tapped.
  bool get isDirty =>
      title.trim().isNotEmpty ||
      description.trim().isNotEmpty ||
      phoneNumber.trim().isNotEmpty ||
      urgency != null ||
      helpTags.isNotEmpty ||
      animalType != null ||
      selectedImage != null;

  /// Check if title is empty
  bool get isTitleEmpty => title.trim().isEmpty;

  /// Check if description is empty
  bool get isDescriptionEmpty => description.trim().isEmpty;

  /// Check if no urgency has been chosen
  bool get isUrgencyUnset => urgency == null;

  /// Check if no kind of help has been chosen
  bool get isHelpTagsEmpty => helpTags.isEmpty;

  /// Check if no animal has been chosen
  bool get isAnimalTypeUnset => animalType == null;

  /// Check if the pin has not been confirmed
  bool get isLocationUnset => latitude == null || longitude == null;

  /// Whether [step] has been answered well enough to move past it.
  ///
  /// This is what disables the wizard's Next button, so it must agree with
  /// [isValid] — anything [isValid] rejects has to be caught by exactly one
  /// step here, or the reporter can reach the review screen and be refused at
  /// submit with no way to see which answer is missing. [NewSignalStep.photo]
  /// and [NewSignalStep.signalType] are always complete: one is optional, the
  /// other has a default.
  bool isStepComplete(NewSignalStep step) => switch (step) {
        NewSignalStep.location => !isLocationUnset,
        NewSignalStep.photo => true,
        NewSignalStep.details => !isTitleEmpty && !isDescriptionEmpty,
        NewSignalStep.animal => !isAnimalTypeUnset,
        NewSignalStep.signalType => true,
        NewSignalStep.urgency => !isUrgencyUnset,
        NewSignalStep.helpTags => !isHelpTagsEmpty,
        NewSignalStep.review => isValid,
      };

  /// [helpTags] with [code] added or removed.
  ///
  /// Adding past [HelpTag.maxPerSignal] is a no-op rather than an error — the
  /// UI disables the remaining chips, and this is the backstop.
  List<String> toggledHelpTag(String code) =>
      toggledCode(helpTags, code, max: HelpTag.maxPerSignal);

  NewSignalFormState copyWith({
    String? title,
    String? description,
    String? phoneNumber,
    int? signalType,
    int? urgency,
    List<String>? helpTags,
    String? animalType,
    XFile? selectedImage,
    bool? isSubmitting,
    bool clearImage = false,
    double? latitude,
    double? longitude,
    NewSignalStep? step,
  }) {
    return NewSignalFormState(
      title: title ?? this.title,
      description: description ?? this.description,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      signalType: signalType ?? this.signalType,
      urgency: urgency ?? this.urgency,
      helpTags: helpTags ?? this.helpTags,
      animalType: animalType ?? this.animalType,
      selectedImage: clearImage ? null : (selectedImage ?? this.selectedImage),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      step: step ?? this.step,
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
        other.urgency == urgency &&
        listEquals(other.helpTags, helpTags) &&
        other.animalType == animalType &&
        other.selectedImage?.path == selectedImage?.path &&
        other.isSubmitting == isSubmitting &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.step == step;
  }

  @override
  int get hashCode => Object.hash(
        title,
        description,
        phoneNumber,
        signalType,
        urgency,
        Object.hashAll(helpTags),
        animalType,
        selectedImage?.path,
        isSubmitting,
        latitude,
        longitude,
        step,
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

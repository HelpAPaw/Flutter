import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../models/help_tag.dart';
import '../repositories/signal_repository.dart';
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

/// Immutable state for the map's help-tag, species, status and urgency filters
@immutable
class MapFilterState {
  final Set<String> selectedHelpTags;
  final Set<String> selectedAnimalTypes;
  final Set<int> selectedStatuses;
  final Set<int> selectedUrgencies;
  final TimeRange selectedTimeRange;

  const MapFilterState({
    this.selectedHelpTags = allHelpTags,
    this.selectedAnimalTypes = allAnimalTypes,
    this.selectedStatuses = allStatuses,
    this.selectedUrgencies = allUrgencies,
    this.selectedTimeRange = defaultTimeRange,
  });

  /// Every help tag selected (no filter active).
  ///
  /// These four sets have to stay `const` (they are default arguments all the
  /// way up to `MapScreenState`), so they can't be derived from their enums
  /// here. `test/map_filter_state_test.dart` fails the build if one of them
  /// drifts out of step — without that guard, appending a tag, species, status
  /// or urgency would silently leave it filtered off the map with no error
  /// anywhere.
  static const allHelpTags = {
    'rescue',
    'vetCare',
    'bloodDonation',
    'foster',
    'adoption',
    'transport',
    'food',
    'trapping',
    'neutering',
    'babyCare',
    'fundraising',
    'lostFound',
    'dangerWarning',
  };

  /// Every species selected (no filter active)
  static const allAnimalTypes = {'cat', 'dog', 'other'};

  /// All statuses selected (no filter active)
  static const allStatuses = {0, 1, 2};

  /// All urgencies selected (no filter active)
  static const allUrgencies = {0, 1, 2};

  /// Check if any filter is active
  bool get hasActiveFilters =>
      selectedHelpTags.length < allHelpTags.length ||
      selectedAnimalTypes.length < allAnimalTypes.length ||
      selectedStatuses.length < allStatuses.length ||
      selectedUrgencies.length < allUrgencies.length ||
      selectedTimeRange != defaultTimeRange;

  /// Whether [signal] passes the current filter.
  ///
  /// The form the marker builder calls, so the four axes are destructured in one
  /// place rather than threaded through every layer as positional arguments —
  /// `status` and `urgency` are adjacent ints, and a swap at any call site would
  /// compile and silently mis-filter.
  bool passes(SignalWithId signal) => signalPassesFilter(
        signal.helpNeededTags,
        signal.animalType,
        signal.status,
        signal.urgency,
      );

  /// Check if a signal passes the current filter.
  ///
  /// A signal matches the tag filter if **any** of its needs is selected — it
  /// declares up to three, and someone filtering for `foster` still wants to see
  /// a case that needs rescue *and* fostering.
  bool signalPassesFilter(
    List<String> helpNeededTags,
    String? animalType,
    int status,
    int urgency,
  ) {
    // Cheapest checks first: this runs once per signal on every map rebuild, and
    // the tag scan is the only branch that can loop.
    if (!selectedStatuses.contains(status)) return false;
    if (!selectedUrgencies.contains(urgency)) return false;
    // Absent species matches every filter: hiding legacy signals from anyone who
    // has picked a species would be a silent disappearance.
    if (animalType != null && !selectedAnimalTypes.contains(animalType)) {
      return false;
    }

    // A signal written before tags existed asks for the fallback, matching what
    // the fan-out substitutes — so the map and the notifications agree about
    // what an untagged signal is.
    if (helpNeededTags.isEmpty) {
      return selectedHelpTags.contains(HelpTag.fallback.code);
    }
    for (final code in helpNeededTags) {
      if (selectedHelpTags.contains(code)) return true;
    }
    return false;
  }

  MapFilterState copyWith({
    Set<String>? selectedHelpTags,
    Set<String>? selectedAnimalTypes,
    Set<int>? selectedStatuses,
    Set<int>? selectedUrgencies,
    TimeRange? selectedTimeRange,
  }) {
    return MapFilterState(
      selectedHelpTags: selectedHelpTags ?? this.selectedHelpTags,
      selectedAnimalTypes: selectedAnimalTypes ?? this.selectedAnimalTypes,
      selectedStatuses: selectedStatuses ?? this.selectedStatuses,
      selectedUrgencies: selectedUrgencies ?? this.selectedUrgencies,
      selectedTimeRange: selectedTimeRange ?? this.selectedTimeRange,
    );
  }

  /// [set] with [value] added if absent, removed if present.
  static Set<T> _toggled<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  /// Toggle a help tag on/off
  MapFilterState toggleHelpTag(String code) =>
      copyWith(selectedHelpTags: _toggled(selectedHelpTags, code));

  /// Toggle a species on/off
  MapFilterState toggleAnimalType(String code) =>
      copyWith(selectedAnimalTypes: _toggled(selectedAnimalTypes, code));

  /// Toggle a status on/off
  MapFilterState toggleStatus(int status) =>
      copyWith(selectedStatuses: _toggled(selectedStatuses, status));

  /// Toggle an urgency on/off
  MapFilterState toggleUrgency(int urgency) =>
      copyWith(selectedUrgencies: _toggled(selectedUrgencies, urgency));

  /// Select all filters
  MapFilterState selectAll() {
    return MapFilterState(
      selectedHelpTags: allHelpTags,
      selectedAnimalTypes: allAnimalTypes,
      selectedStatuses: allStatuses,
      selectedUrgencies: allUrgencies,
      selectedTimeRange: selectedTimeRange,
    );
  }

  /// Clear all filters
  MapFilterState clearAll() {
    return MapFilterState(
      selectedHelpTags: const {},
      selectedAnimalTypes: const {},
      selectedStatuses: const {},
      selectedUrgencies: const {},
      selectedTimeRange: selectedTimeRange,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MapFilterState &&
        setEquals(other.selectedHelpTags, selectedHelpTags) &&
        setEquals(other.selectedAnimalTypes, selectedAnimalTypes) &&
        setEquals(other.selectedStatuses, selectedStatuses) &&
        setEquals(other.selectedUrgencies, selectedUrgencies) &&
        other.selectedTimeRange == selectedTimeRange;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(selectedHelpTags),
        Object.hashAll(selectedAnimalTypes),
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

  const NewSignalFormState({
    this.title = '',
    this.description = '',
    this.phoneNumber = '',
    this.urgency,
    this.helpTags = const [],
    this.animalType,
    this.selectedImage,
    this.isSubmitting = false,
  });

  /// Check if the form is valid for submission
  bool get isValid =>
      title.trim().isNotEmpty &&
      description.trim().isNotEmpty &&
      urgency != null &&
      helpTags.isNotEmpty &&
      animalType != null;

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
    int? urgency,
    List<String>? helpTags,
    String? animalType,
    XFile? selectedImage,
    bool? isSubmitting,
    bool clearImage = false,
  }) {
    return NewSignalFormState(
      title: title ?? this.title,
      description: description ?? this.description,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      urgency: urgency ?? this.urgency,
      helpTags: helpTags ?? this.helpTags,
      animalType: animalType ?? this.animalType,
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
        other.urgency == urgency &&
        listEquals(other.helpTags, helpTags) &&
        other.animalType == animalType &&
        other.selectedImage?.path == selectedImage?.path &&
        other.isSubmitting == isSubmitting;
  }

  @override
  int get hashCode => Object.hash(
        title,
        description,
        phoneNumber,
        urgency,
        Object.hashAll(helpTags),
        animalType,
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

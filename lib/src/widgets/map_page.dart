import 'package:adaptive_components/adaptive_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import '../repositories/repository_provider.dart';
import '../repositories/signal_repository.dart';
import '../services/app_preferences_service.dart';
import '../state/map_state.dart';
import '../utils/map_marker_builder.dart';
import '../viewmodels/map_view_model.dart';
import 'home_route_drawer.dart';
import 'map/filter_bottom_sheet.dart';
import 'map/new_signal_form.dart';
import 'notification_onboarding_button.dart';
import 'notification_onboarding_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fabAnimationController;
  late GoogleMapController _mapController;
  final _markerBuilder = MapMarkerBuilder();
  bool _showOnboardingButton = false;
  bool _onboardingSheetShown = false;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _markerBuilder.loadAllPins();

    // Initialize location in ViewModel
    ref.read(mapViewModelProvider.notifier).getUserLocation();

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkOnboardingState());
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    super.dispose();
  }

  Future<void> _checkOnboardingState() async {
    final prefs = AppPreferencesService();

    if (prefs.shouldShowOnboardingSheet()) {
      _showOnboardingSheet();
    } else if (prefs.shouldShowOnboardingButton()) {
      setState(() => _showOnboardingButton = true);
    }
  }

  void _showOnboardingSheet() {
    if (_onboardingSheetShown) return;
    _onboardingSheetShown = true;

    showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => NotificationOnboardingSheet(
        onComplete: () {
          Navigator.pop(context);
          setState(() => _showOnboardingButton = false);
          ref.read(mapViewModelProvider.notifier).getUserLocation();
        },
        onDismiss: () async {
          Navigator.pop(context);
          await AppPreferencesService().setOnboardingDismissed(true);
          setState(() => _showOnboardingButton = true);
        },
      ),
    ).whenComplete(() {
      _onboardingSheetShown = false;
    });
  }

  Future<(double, double)> _getMapCenter() async {
    final visibleRegion = await _mapController.getVisibleRegion();
    final centerLatitude = (visibleRegion.northeast.latitude +
            visibleRegion.southwest.latitude) /
        2;
    final centerLongitude = (visibleRegion.northeast.longitude +
            visibleRegion.southwest.longitude) /
        2;
    return (centerLatitude, centerLongitude);
  }

  void _onCameraIdle() async {
    final viewModel = ref.read(mapViewModelProvider.notifier);
    final region = await _mapController.getVisibleRegion();
    final centerLat =
        (region.northeast.latitude + region.southwest.latitude) / 2;
    final centerLng =
        (region.northeast.longitude + region.southwest.longitude) / 2;
    final zoom = await _mapController.getZoomLevel();

    viewModel.checkVetClinicSearchButton(
      currentCenter: LatLng(centerLat, centerLng),
      currentZoom: zoom,
    );
  }

  Future<void> _loadVetClinics() async {
    final l10n = AppLocalizations.of(context);
    final viewModel = ref.read(mapViewModelProvider.notifier);

    try {
      final region = await _mapController.getVisibleRegion();
      final centerLat =
          (region.northeast.latitude + region.southwest.latitude) / 2;
      final centerLng =
          (region.northeast.longitude + region.southwest.longitude) / 2;
      final zoom = await _mapController.getZoomLevel();

      await viewModel.loadVetClinics(
        center: LatLng(centerLat, centerLng),
        zoomLevel: zoom,
        hospitalPin: _markerBuilder.hospitalPin,
        onClinicTap: (clinicId) => context.push('/clinic_details/$clinicId'),
      );

      if (mounted) {
        final clinics = ref.read(mapViewModelProvider).vetClinicState.clinics;
        if (clinics.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.noVetClinicsFound),
              backgroundColor: Colors.grey,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMessage = l10n.failedToLoadVetClinics;
        if (e.toString().contains('Network error')) {
          errorMessage = l10n.networkError;
        } else if (e.toString().contains('timed out')) {
          errorMessage = l10n.requestTimedOut;
        } else if (e.toString().contains('Rate limit')) {
          errorMessage = l10n.tooManySearches;
        } else if (e.toString().contains('API access denied')) {
          errorMessage = l10n.serviceUnavailable;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showSignInDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.signInRequired),
          content: Text(l10n.signInToCreateSignals),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/sign_in');
              },
              child: Text(l10n.signIn),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mapState = ref.watch(mapViewModelProvider);
    final signalsAsync = ref.watch(signalsStreamProvider);

    return _buildScaffold(context, l10n, mapState, signalsAsync);
  }

  Widget _buildScaffold(
    BuildContext context,
    AppLocalizations l10n,
    MapScreenState mapState,
    AsyncValue<List<SignalWithId>> signalsAsync,
  ) {
    // Build signal markers from stream
    Set<Marker> signalMarkers = {};
    signalsAsync.whenData((signals) {
      signalMarkers = _markerBuilder.buildSignalMarkers(
        signals: signals,
        filterPredicate: (signalType, status) =>
            mapState.filterState.signalPassesFilter(signalType, status),
        onSignalTap: (signalId) => context.push('/signal_details/$signalId'),
        newlyCreatedSignalId: mapState.newlyCreatedSignalId,
        onNewlyCreatedSignalFound: (signalId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _mapController.showMarkerInfoWindow(MarkerId(signalId));
            ref.read(mapViewModelProvider.notifier).clearNewlyCreatedSignalId();
          });
        },
      );
    });

    final allMarkers = {
      ...signalMarkers,
      ...mapState.vetClinicState.clinicMarkers,
    };

    return PopScope(
      canPop: !mapState.isAddingNewSignal,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && mapState.isAddingNewSignal) {
          ref.read(mapViewModelProvider.notifier).cancelAddingNewSignal();
          _fabAnimationController.reverse();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: AdaptiveContainer(
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  bearing: 0.0,
                  target: LatLng(
                    mapState.centerLatitude,
                    mapState.centerLongitude,
                  ),
                  tilt: 0.0,
                  zoom: 11.0,
                ),
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                },
                onCameraIdle: _onCameraIdle,
                zoomControlsEnabled: true,
                myLocationEnabled: mapState.hasLocationPermission,
                markers: allMarkers,
              ),
              // Crosshair for new signal placement
              if (mapState.isAddingNewSignal)
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.center,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 100),
                      child: const Icon(Icons.gps_fixed, size: 50.0),
                    ),
                  ),
                ),
              // New signal form
              if (mapState.isAddingNewSignal)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: NewSignalForm(
                    getMapCenter: _getMapCenter,
                    onSubmitSuccess: () {
                      _fabAnimationController.reverse();
                    },
                  ),
                ),
              // Search this area button
              if (mapState.vetClinicState.showSearchThisAreaButton)
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search, color: Colors.white),
                      label: Text(l10n.searchThisArea,
                          style: const TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        elevation: 6,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      onPressed: () {
                        ref
                            .read(mapViewModelProvider.notifier)
                            .hideSearchThisAreaButton();
                        _loadVetClinics();
                      },
                    ),
                  ),
                ),
              // Loading clinics indicator
              if (mapState.vetClinicState.isLoading)
                Positioned(
                  bottom: 80,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(l10n.loadingClinics),
                        ],
                      ),
                    ),
                  ),
                ),
              // Onboarding button
              if (_showOnboardingButton)
                NotificationOnboardingButton(
                  onTap: _showOnboardingSheet,
                ),
            ],
          ),
        ),
        appBar: AppBar(
          title: const Text('Help a Paw'),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          actions: <Widget>[
            IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.filter_list_outlined),
                  if (mapState.filterState.hasActiveFilters)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () => showFilterBottomSheet(context, ref),
            ),
            IconButton(
              icon: Icon(
                Icons.local_hospital,
                color: mapState.vetClinicState.showVetClinics
                    ? Colors.white
                    : Colors.white70,
              ),
              style: mapState.vetClinicState.showVetClinics
                  ? IconButton.styleFrom(
                      backgroundColor: Colors.orange[800])
                  : null,
              onPressed: () {
                final viewModel = ref.read(mapViewModelProvider.notifier);
                viewModel.toggleVetClinics();
                if (!mapState.vetClinicState.showVetClinics) {
                  // Was off, now toggled on
                  _loadVetClinics();
                }
              },
            ),
          ],
        ),
        drawer: const HomeRouteDrawer(),
        floatingActionButton: Semantics(
          label: l10n.addNewSignal,
          button: true,
          enabled: true,
          child: FloatingActionButton(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            elevation: 6,
            enableFeedback: true,
            shape: const CircleBorder(),
            onPressed: () {
              if (!RepositoryProvider.instance.userRepository.canCreateSignals) {
                _showSignInDialog();
              } else {
                final viewModel = ref.read(mapViewModelProvider.notifier);
                viewModel.toggleAddingNewSignal();
                if (!mapState.isAddingNewSignal) {
                  _fabAnimationController.forward();
                } else {
                  _fabAnimationController.reverse();
                }
              }
            },
            tooltip: l10n.addNewSignal,
            child: AnimatedBuilder(
              animation: _fabAnimationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _fabAnimationController.value * 0.785398,
                  child: const Icon(Icons.add),
                );
              },
            ),
          ),
        ),
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}

import 'dart:io' show Platform;

import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import '../repositories/repository_provider.dart';
import '../repositories/signal_repository.dart';
import '../services/app_preferences_service.dart';
import '../services/notification_service.dart';
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
  // Approximate native InfoWindow dimensions for invisible tap target
  static const _kInfoWindowWidth = 220.0;
  static const _kInfoWindowHeight = 80.0;
  static const _kPinHeight = 29.0;

  late AnimationController _fabAnimationController;
  late GoogleMapController _mapController;
  final _markerBuilder = MapMarkerBuilder();
  bool _showOnboardingButton = false;
  bool _onboardingSheetShown = false;

  // Invisible tap-target state for the native InfoWindow workaround.
  // Native InfoWindow.onTap is broken with ClusterManager
  // (flutter/flutter#159636), so we show the native InfoWindow for display
  // and overlay an invisible GestureDetector for tap handling.
  SignalWithId? _selectedSignal;
  double? _overlayX;
  double? _overlayY;

  // Listener that waits for a specific signal to appear in the stream
  // before showing its info window (used after signal creation / notification).
  ProviderSubscription<AsyncValue<List<SignalWithId>>>? _pendingInfoWindowSub;

  // Test mode toggle state
  int _titleTapCount = 0;
  DateTime? _lastTitleTap;

  static const _signalClusterManagerId = ClusterManagerId('signals');
  late final ClusterManager _signalClusterManager = ClusterManager(
    clusterManagerId: _signalClusterManagerId,
    onClusterTap: _onClusterTap,
  );
  late final Set<ClusterManager> _clusterManagers = {_signalClusterManager};

  void _onClusterTap(Cluster cluster) {
    _mapController.animateCamera(
      CameraUpdate.newLatLngBounds(cluster.bounds, 50),
    );
  }

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
    _pendingInfoWindowSub?.close();
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

  void _handleTitleTap() async {
    final now = DateTime.now();
    if (_lastTitleTap != null &&
        now.difference(_lastTitleTap!).inSeconds > 2) {
      _titleTapCount = 0;
    }
    _lastTitleTap = now;
    _titleTapCount++;

    if (_titleTapCount >= 7) {
      _titleTapCount = 0;
      final prefs = AppPreferencesService();
      final newTestMode = !prefs.isTestMode();
      await prefs.setTestMode(newTestMode);

      // Update Riverpod state — this invalidates the signals stream
      ref.read(testModeProvider.notifier).toggle(newTestMode);

      // Reset the signal repository so it picks up the new collection
      RepositoryProvider.instance.resetSignalRepository();

      // Sync testMode flag to Firestore user document
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'testMode': newTestMode},
          SetOptions(merge: true),
        ).catchError((_) {});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newTestMode
                ? 'Test mode enabled'
                : 'Test mode disabled'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
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

  /// Convert a [ScreenCoordinate] to logical pixels.
  /// Android returns physical pixels; iOS returns logical points.
  (double x, double y) _screenCoordToLogical(ScreenCoordinate coord) {
    final dpr = Platform.isAndroid
        ? MediaQuery.of(context).devicePixelRatio
        : 1.0;
    return (coord.x.toDouble() / dpr, coord.y.toDouble() / dpr);
  }

  Future<void> _showSignalOverlay(SignalWithId signal) async {
    // Show the native InfoWindow (moves perfectly with the map).
    // Fire-and-forget — independent of screen coordinate calculation.
    _mapController.showMarkerInfoWindow(MarkerId(signal.id));

    final screenCoord = await _mapController.getScreenCoordinate(
      LatLng(signal.location.latitude, signal.location.longitude),
    );
    if (!mounted) return;
    final (x, y) = _screenCoordToLogical(screenCoord);
    setState(() {
      _selectedSignal = signal;
      _overlayX = x;
      _overlayY = y;
    });
  }

  void _dismissOverlay() {
    if (_selectedSignal != null) {
      _mapController.hideMarkerInfoWindow(MarkerId(_selectedSignal!.id));
      setState(() {
        _selectedSignal = null;
        _overlayX = null;
        _overlayY = null;
      });
    }
  }

  Future<void> _updateOverlayPosition() async {
    if (_selectedSignal == null) return;
    final signal = _selectedSignal!;
    final screenCoord = await _mapController.getScreenCoordinate(
      LatLng(signal.location.latitude, signal.location.longitude),
    );
    if (!mounted || _selectedSignal?.id != signal.id) return;
    final (x, y) = _screenCoordToLogical(screenCoord);
    setState(() {
      _overlayX = x;
      _overlayY = y;
    });
  }

  /// Show overlay after a short delay for the native map to render the marker.
  void _showOverlayAfterRender(SignalWithId signal) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _showSignalOverlay(signal);
    });
  }

  void _showSignalInfoWindow(String signalId) {
    // Listen for the signal to appear in the stream. fireImmediately replays
    // the current value, so if the signal is already present it's found
    // without waiting for the next emission (also avoids a race between a
    // separate ref.read and the listener setup).
    _pendingInfoWindowSub?.close();
    _pendingInfoWindowSub = ref.listenManual(signalsStreamProvider, (_, next) {
      final signal = next.value
          ?.where((s) => s.id == signalId)
          .firstOrNull;
      if (signal != null) {
        _pendingInfoWindowSub?.close();
        _pendingInfoWindowSub = null;
        _showOverlayAfterRender(signal);
      }
    }, fireImmediately: true);

    // Safety timeout: stop listening if the signal never arrives
    Future.delayed(const Duration(seconds: 10), () {
      _pendingInfoWindowSub?.close();
      _pendingInfoWindowSub = null;
    });
  }

  Future<void> _focusSignalOnMap(String signalId) async {
    // Try to find the signal in the already-loaded stream first
    final signals = ref.read(signalsStreamProvider).value;
    GeoPoint? geoPoint;
    if (signals != null) {
      for (final s in signals) {
        if (s.id == signalId) {
          geoPoint = s.location;
          break;
        }
      }
    }

    // Fall back to a direct Firestore fetch and re-center the geo-query
    // so the signal's marker will be included in the stream
    if (geoPoint == null) {
      final fetched = await RepositoryProvider
          .instance.signalRepository
          .getSignalById(signalId);
      if (fetched == null || !mounted) return;
      geoPoint = fetched.location;
      ref.read(mapViewModelProvider.notifier).updateMapCenter(
            geoPoint.latitude,
            geoPoint.longitude,
          );
    }

    if (!mounted) return;

    final lat = geoPoint.latitude;
    final lng = geoPoint.longitude;

    await _mapController.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(lat, lng), 14.0),
    );

    if (!mounted) return;
    _showSignalInfoWindow(signalId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mapState = ref.watch(mapViewModelProvider);
    final signalsAsync = ref.watch(signalsStreamProvider);

    // After returning from notification-opened signal details, focus the map
    final pendingId = NotificationService().pendingFocusSignalId;
    if (pendingId != null) {
      NotificationService().pendingFocusSignalId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusSignalOnMap(pendingId);
      });
    }

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
        onMarkerTap: _showSignalOverlay,
        clusterManagerId: _signalClusterManagerId,
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
                onTap: (_) => _dismissOverlay(),
                onCameraIdle: () {
                  _onCameraIdle();
                  _updateOverlayPosition();
                },
                zoomControlsEnabled: true,
                myLocationEnabled: mapState.hasLocationPermission,
                markers: allMarkers,
                clusterManagers: _clusterManagers,
              ),
              // Invisible tap target over the native InfoWindow.
              // The native InfoWindow renders & tracks the marker perfectly,
              // but its onTap is broken with ClusterManager
              // (flutter/flutter#159636). This transparent overlay catches taps.
              if (_selectedSignal != null &&
                  _overlayX != null &&
                  _overlayY != null)
                Positioned(
                  left: (_overlayX! - _kInfoWindowWidth / 2).clamp(
                      0.0, MediaQuery.of(context).size.width - _kInfoWindowWidth),
                  top: (_overlayY! - _kInfoWindowHeight - _kPinHeight)
                      .clamp(0.0, double.infinity),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      final signal = _selectedSignal!;
                      context.push('/signal_details/${signal.id}').then((_) {
                        // Re-show the native InfoWindow when returning;
                        // the platform hides it during route transitions.
                        if (mounted && _selectedSignal?.id == signal.id) {
                          _mapController.showMarkerInfoWindow(
                            MarkerId(signal.id),
                          );
                          _updateOverlayPosition();
                        }
                      });
                    },
                    child: const SizedBox(
                      width: _kInfoWindowWidth,
                      height: _kInfoWindowHeight,
                    ),
                  ),
                ),
              // Crosshair for new signal placement
              if (mapState.isAddingNewSignal)
                IgnorePointer(
                  child: const Center(
                    child: Icon(Icons.gps_fixed, size: 50.0),
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
                      final signalId = ref
                          .read(mapViewModelProvider)
                          .newlyCreatedSignalId;
                      if (signalId != null) {
                        _showSignalInfoWindow(signalId);
                      }
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
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTitleTap,
            child: Text(
              ref.watch(testModeProvider) ? 'Help a Paw (TEST)' : 'Help a Paw',
            ),
          ),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          actions: <Widget>[
            Semantics(
              label: l10n.filterSignals,
              button: true,
              enabled: true,
              child: IconButton(
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
            ),
            Semantics(
              label: l10n.toggleVetClinics,
              button: true,
              enabled: true,
              child: IconButton(
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

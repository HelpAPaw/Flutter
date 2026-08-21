import 'dart:async';
import 'dart:io' show Platform;

import 'package:adaptive_components/adaptive_components.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

import '../config/routes.dart';
import '../repositories/repository_provider.dart';
import '../repositories/signal_repository.dart';
import '../services/app_preferences_service.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/signal_navigator.dart';
import '../state/map_state.dart';
import '../utils/map_marker_builder.dart';
import '../viewmodels/map_view_model.dart';
import 'home_route_drawer.dart';
import 'map/filter_bottom_sheet.dart';
import 'map/new_signal_location_bar.dart';
import 'notification_onboarding_button.dart';
import 'helper_tags_gate.dart';
import 'notification_onboarding_sheet.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  // Approximate native InfoWindow dimensions for invisible tap target
  static const _kInfoWindowWidth = 220.0;
  static const _kInfoWindowHeight = 80.0;
  static const _kPinHeight = 29.0;

  // Null until the platform view calls onMapCreated, and never null again.
  // Deliberately nullable rather than `late` + a separate readiness bool: the
  // flag was a convention the compiler didn't enforce, and forgetting it is
  // what shipped a LateInitializationError to production (see
  // _focusSignalOnMap). Now every use has to say what it does without a map —
  // `!` where a live map is a precondition, a null check where it isn't.
  GoogleMapController? _mapController;
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

  // A signal we were asked to focus before the map's platform view was ready.
  // Replayed from [onMapCreated]; see [_focusSignalOnMap].
  String? _deferredFocusSignalId;

  // Set once a deep link has put the camera on a signal, so the fly-to-user
  // that [initState] schedules doesn't yank it away when the fix lands late.
  bool _deepLinkOwnsCamera = false;

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
    // Dispatched by the GoogleMap widget, so the map exists by construction.
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(cluster.bounds, 50),
    );
  }

  @override
  void initState() {
    super.initState();
    _markerBuilder.loadAllPins();

    // Initialize location in ViewModel, then animate camera to it — unless a
    // deep link got there first. The GPS fix can land seconds after the map,
    // long after a notification tap has already focused its signal.
    ref.read(mapViewModelProvider.notifier).getUserLocation().then((_) {
      if (_deepLinkOwnsCamera) return;
      _flyToUserLocation();
    });

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkOnboardingState());
  }

  @override
  void dispose() {
    _pendingInfoWindowSub?.close();
    super.dispose();
  }

  Future<void> _checkOnboardingState() async {
    final prefs = AppPreferencesService();

    // Local and synchronous, so ask it before awaiting anything. For the common
    // case — an existing user with nothing to show — this returns without ever
    // touching the network.
    if (!prefs.shouldShowOnboardingSheet() &&
        !prefs.shouldShowOnboardingButton()) {
      return;
    }

    // Then wait for the *resolved* preferences, not a single read of them.
    //
    // A one-shot `ref.read` here always lost: this runs from a post-frame
    // callback in initState, when the provider is still loading, so it returned
    // early every time. That was fine for an untagged user — the gate swaps in,
    // and coming back rebuilds this subtree so initState runs again. But for a
    // user who *already has* tags the gate returns the very same child widget in
    // both its loading and data branches, so the element is reused, initState
    // never runs a second time, and the notification onboarding was silently
    // never offered again.
    //
    // Staying out of the gate's way matters because the gate renders this screen
    // while it is still reading (so a slow read never blanks the map) — without
    // this, onboarding is pushed onto the navigator first and then sits on top
    // of the mandatory tag picker.
    final resolved = await ref.read(helperTagsPreferencesProvider.future);
    if (!mounted || !(resolved?.hasChosenHelperTags ?? false)) return;

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

      // Android's background receiver keys its pre-filter gate by mode and
      // can't read this preference itself, so push it now rather than leaving
      // background checks on the old mode's gate until the next launch.
      await LocationService().syncTestMode();

      // Stamp the new mode on the account, through the same writer startup and
      // sign-in use so there is one place that knows how `users/{uid}.testMode`
      // is maintained — and so the write-avoidance cache behind it stays in
      // step with what was actually written (#72).
      unawaited(AuthService().syncTestMode());

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
          ref.read(mapViewModelProvider.notifier).getUserLocation().then((_) {
            _flyToUserLocation();
          });
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

  /// Call after [getUserLocation] completes to move the camera to the
  /// resolved position. Safe to call before the map controller is ready
  /// (the [onMapCreated] handler covers that race).
  void _flyToUserLocation() {
    final map = _mapController;
    if (!mounted || map == null) return;
    final s = ref.read(mapViewModelProvider);
    if (s.centerLatitude == MapScreenState.defaultLatitude &&
        s.centerLongitude == MapScreenState.defaultLongitude) {
      return;
    }
    map.animateCamera(
      CameraUpdate.newLatLng(LatLng(s.centerLatitude, s.centerLongitude)),
    );
  }

  /// Precondition: the map exists — this is only reached from
  /// [NewSignalLocationBar], which is rendered over an already-built map.
  Future<(double, double)> _getMapCenter() async {
    final visibleRegion = await _mapController!.getVisibleRegion();
    final centerLatitude = (visibleRegion.northeast.latitude +
            visibleRegion.southwest.latitude) /
        2;
    final centerLongitude = (visibleRegion.northeast.longitude +
            visibleRegion.southwest.longitude) /
        2;
    return (centerLatitude, centerLongitude);
  }

  void _cancelAddingNewSignal() {
    ref.read(mapViewModelProvider.notifier).cancelAddingNewSignal();
  }

  /// Abandon the draft from the map, confirming first if there is anything to
  /// lose — the same contract as the wizard's `×`.
  ///
  /// Step 1 is on the map, so both exits from it (the back gesture and the
  /// location bar's Cancel) land here. That used to discard unconditionally,
  /// which was harmless only while the map could not be reached with a filled
  /// draft. It can now: "Change" beside Location on the review step pops back
  /// here with the whole draft still held in the view model, so an unguarded
  /// back press threw away seven answered steps with no prompt — while the
  /// wizard's own × asked about the very same draft.
  ///
  /// A fresh FAB tap leaves [NewSignalFormState.isDirty] false, so the common
  /// case still exits in one press without a dialog.
  Future<void> _cancelAddingNewSignalConfirmed() async {
    if (ref.read(mapViewModelProvider).formState.isDirty) {
      final l10n = AppLocalizations.of(context);
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.newSignalDiscardTitle),
          content: Text(l10n.newSignalDiscardMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.newSignalDiscardKeep),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.newSignalDiscardConfirm),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    _cancelAddingNewSignal();
  }

  /// Accept the pin under the crosshair and hand over to the wizard route.
  ///
  /// The draft lives in the view model, so pushing rather than replacing keeps
  /// the map — and this state — alive underneath. The reporter can come back
  /// here from the review step to move the pin and be returned to where they
  /// were, because [MapViewModel.confirmLocation] only advances the step when
  /// it is still on the location question.
  Future<void> _confirmSignalLocation() async {
    final (latitude, longitude) = await _getMapCenter();
    if (!mounted) return;

    // Compared rather than null-checked on return: `newlyCreatedSignalId`
    // survives a cancel, so a reporter who submits one signal and then abandons
    // the next would otherwise have the *first* signal's info window pop open
    // at them.
    final idBefore = ref.read(mapViewModelProvider).newlyCreatedSignalId;

    ref.read(mapViewModelProvider.notifier).confirmLocation(latitude, longitude);
    await context.push(Routes.newSignal);
    if (!mounted) return;

    final idAfter = ref.read(mapViewModelProvider).newlyCreatedSignalId;
    if (idAfter != null && idAfter != idBefore) {
      _showSignalInfoWindow(idAfter);
    }
  }

  /// Monotonically increasing token so that stale [_onCameraIdle] callbacks
  /// (from earlier pans that are still awaiting [getVisibleRegion]) are
  /// discarded when a newer idle event has already been dispatched.
  int _cameraIdleToken = 0;

  /// Precondition: the map exists. Dispatched by the GoogleMap widget.
  void _onCameraIdle() async {
    final map = _mapController!;
    final token = ++_cameraIdleToken;
    final region = await map.getVisibleRegion();
    if (!mounted || token != _cameraIdleToken) return;

    final centerLat =
        (region.northeast.latitude + region.southwest.latitude) / 2;
    final centerLng =
        (region.northeast.longitude + region.southwest.longitude) / 2;
    final zoom = await map.getZoomLevel();
    if (!mounted || token != _cameraIdleToken) return;

    final viewModel = ref.read(mapViewModelProvider.notifier);

    // Update the map center so the signals geo-query follows the viewport
    viewModel.updateMapCenter(centerLat, centerLng);

    viewModel.checkVetClinicSearchButton(
      currentCenter: LatLng(centerLat, centerLng),
      currentZoom: zoom,
    );
  }

  Future<void> _loadVetClinics() async {
    // Reached from toolbar buttons, which are painted with the Scaffold and so
    // can be tapped before the platform view has come up.
    final map = _mapController;
    if (map == null) return;

    final l10n = AppLocalizations.of(context);
    final viewModel = ref.read(mapViewModelProvider.notifier);

    try {
      final region = await map.getVisibleRegion();
      final centerLat =
          (region.northeast.latitude + region.southwest.latitude) / 2;
      final centerLng =
          (region.northeast.longitude + region.southwest.longitude) / 2;
      final zoom = await map.getZoomLevel();

      await viewModel.loadVetClinics(
        center: LatLng(centerLat, centerLng),
        zoomLevel: zoom,
        hospitalPin: _markerBuilder.hospitalPin,
        onClinicTap: (clinicId) => context.push(Routes.clinicDetails(clinicId)),
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
                context.push(Routes.signIn);
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

  /// Best-effort native InfoWindow show. Throws [PlatformException]
  /// ("Invalid markerId") if the marker was removed from the map between the
  /// overlay opening and this call — e.g. the signal was deleted, filtered
  /// out, or moved outside the geo-query radius while its window was open.
  /// The window is gone anyway, so swallow it rather than crashing.
  Future<void> _showMarkerInfoWindow(String signalId) async {
    final map = _mapController;
    if (map == null) return;
    try {
      await map.showMarkerInfoWindow(MarkerId(signalId));
    } on PlatformException {
      // Marker no longer on the map — nothing to show.
    }
  }

  /// Best-effort native InfoWindow hide. See [_showMarkerInfoWindow].
  Future<void> _hideMarkerInfoWindow(String signalId) async {
    final map = _mapController;
    if (map == null) return;
    try {
      await map.hideMarkerInfoWindow(MarkerId(signalId));
    } on PlatformException {
      // Marker no longer on the map — nothing to hide.
    }
  }

  /// Re-show the native InfoWindow for [signalId] after a marker-set rebuild
  /// closed it. Android's ClusterManager reclusters asynchronously, so an
  /// immediate re-show can be undone once the background clustering finishes;
  /// a short follow-up re-show outlasts it. Both calls are no-ops when the
  /// window is already open (programmatic show never auto-pans, so there is no
  /// re-query loop).
  void _reassertSelectedInfoWindow(String signalId) {
    _showMarkerInfoWindow(signalId);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && _selectedSignal?.id == signalId) {
        _showMarkerInfoWindow(signalId);
      }
    });
  }

  Future<void> _showSignalOverlay(SignalWithId signal) async {
    // Show the native InfoWindow (moves perfectly with the map).
    // Fire-and-forget — independent of screen coordinate calculation.
    _showMarkerInfoWindow(signal.id);

    // Precondition: the map exists — this comes from tapping one of its markers.
    final screenCoord = await _mapController!.getScreenCoordinate(
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
      _hideMarkerInfoWindow(_selectedSignal!.id);
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
    // Precondition: a selected signal implies its marker was tapped on a map.
    final screenCoord = await _mapController!.getScreenCoordinate(
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

  /// Moves the camera to [signalId] and opens its info window.
  ///
  /// Returns whether the camera ended up on the signal, so the [onMapCreated]
  /// replay can fall back to the user's own location when it did not.
  Future<bool> _focusSignalOnMap(String signalId) async {
    // This runs from a post-frame callback, which on a cold launch fires
    // before the map's platform view has called onMapCreated — so the
    // controller may not exist yet. Hand the request over to onMapCreated
    // rather than dropping it, or the deep link silently does nothing.
    final map = _mapController;
    if (map == null) {
      _deferredFocusSignalId = signalId;
      return false;
    }

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
      if (fetched == null || !mounted) return false;
      geoPoint = fetched.location;
      ref.read(mapViewModelProvider.notifier).updateMapCenter(
            geoPoint.latitude,
            geoPoint.longitude,
            force: true,
          );
    }

    if (!mounted) return false;

    _deepLinkOwnsCamera = true;
    await map.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(geoPoint.latitude, geoPoint.longitude),
        14.0,
      ),
    );

    if (mounted) _showSignalInfoWindow(signalId);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mapState = ref.watch(mapViewModelProvider);
    final signalsAsync = ref.watch(signalsStreamProvider);

    // After returning from a signal opened from outside the map (notification
    // tap, shared link, or deferred install hand-off), focus that pin.
    final pendingId = SignalNavigator.instance.pendingFocusSignalId;
    if (pendingId != null) {
      SignalNavigator.instance.pendingFocusSignalId = null;
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
        filterPredicate: mapState.filterState.passes,
        onMarkerTap: _showSignalOverlay,
        clusterManagerId: _signalClusterManagerId,
      );

      // Reconcile the open info window against the rebuilt marker set.
      // Guarded by whenData so a transient reload (empty markers during a
      // re-query) doesn't act on stale data.
      final selected = _selectedSignal;
      if (selected != null) {
        final stillRendered =
            signalMarkers.any((m) => m.markerId.value == selected.id);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _selectedSignal?.id != selected.id) return;
          if (stillRendered) {
            // The marker set was rebuilt while its window was open. Rebuilding
            // makes the native ClusterManager recluster (remove + re-add the
            // markers), which tears down the open native InfoWindow. This is
            // what makes the window vanish after tapping a *distant* pin: the
            // SDK auto-pans to center it, and that pan re-centers the geo-query
            // past updateMapCenter's re-query threshold. Re-assert the window
            // so it survives the rebuild. (Near pins pan too little to trigger
            // a re-query, so they never hit this.)
            _reassertSelectedInfoWindow(selected.id);
          } else {
            // Signal is no longer rendered — deleted, filtered out, or moved
            // outside the geo-query radius — so its native InfoWindow has
            // vanished for good. Dismiss the orphaned invisible tap target so
            // it can't navigate to a signal that's gone.
            _dismissOverlay();
          }
        });
      }
    });

    final allMarkers = {
      ...signalMarkers,
      ...mapState.vetClinicState.clinicMarkers,
    };

    return PopScope(
      canPop: !mapState.isAddingNewSignal,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && mapState.isAddingNewSignal) {
          _cancelAddingNewSignalConfirmed();
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
                onMapCreated: (GoogleMapController controller) async {
                  _mapController = controller;

                  // A deep link that arrived before the map existed outranks
                  // the initial move to the user's own location — but fall
                  // back to it if the signal turns out to be gone, rather
                  // than stranding the camera on the Sofia default.
                  final deferredId = _deferredFocusSignalId;
                  _deferredFocusSignalId = null;
                  if (deferredId != null && await _focusSignalOnMap(deferredId)) {
                    return;
                  }

                  _flyToUserLocation();
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
                      context.push(Routes.signalDetails(signal.id)).then((_) {
                        // Re-show the native InfoWindow when returning;
                        // the platform hides it during route transitions.
                        if (mounted && _selectedSignal?.id == signal.id) {
                          _showMarkerInfoWindow(signal.id);
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
              // Step 1 of the new-signal wizard. The remaining steps live on
              // the /new_signal route, pushed once the pin is confirmed.
              if (mapState.isAddingNewSignal)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: NewSignalLocationBar(
                    onCancel: _cancelAddingNewSignalConfirmed,
                    onContinue: _confirmSignalLocation,
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
        // Hidden while the location bar is up: the bar sits in the same place
        // and carries its own Cancel, so leaving the FAB there would put two
        // competing ways out on top of each other.
        floatingActionButton: mapState.isAddingNewSignal
            ? null
            : Semantics(
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
                    if (!RepositoryProvider
                        .instance.userRepository.canModifyData) {
                      _showSignInDialog();
                    } else {
                      ref
                          .read(mapViewModelProvider.notifier)
                          .toggleAddingNewSignal();
                    }
                  },
                  tooltip: l10n.addNewSignal,
                  child: const Icon(Icons.add),
                ),
              ),
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}

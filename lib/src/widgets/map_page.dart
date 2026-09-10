import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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
import '../models/vet_clinic.dart';
import '../utils/bubble_layout.dart';
import '../utils/cluster_bubble_icons.dart';
import '../utils/map_clusterer.dart';
import '../utils/map_marker_builder.dart';
import '../utils/map_projection.dart';
import '../viewmodels/map_view_model.dart';
import 'home_route_drawer.dart';
import 'map/filter_bottom_sheet.dart';
import 'map/map_legend_sheet.dart';
import 'map/clinic_info_card.dart';
import 'map/cluster_items_sheet.dart';
import 'map/map_bubble.dart';
import 'map/new_signal_location_bar.dart';
import 'map/signal_info_card.dart';
import 'notification_onboarding_button.dart';
import 'helper_tags_gate.dart';
import 'notification_onboarding_sheet.dart';
import 'sign_in_required_dialog.dart';
import 'map/map_style_builder.dart';
import 'app_bar_title.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with WidgetsBindingObserver {
  /// Inset the bubble keeps from the left and right edges of the map.
  static const _kBubbleEdgeInset = 8.0;

  /// Gap between the bubble's tail and the pin it points at. Without it the
  /// tail lands exactly on the pin's rounded top and reads as a notch cut out
  /// of the pin rather than as a pointer.
  static const _kBubbleGap = 6.0;

  /// Zoom the map opens at before the user has moved it.
  static const _kInitialZoom = 11.0;

  // Null until the platform view calls onMapCreated, and never null again.
  // Deliberately nullable rather than `late` + a separate readiness bool: the
  // flag was a convention the compiler didn't enforce, and forgetting it is
  // what shipped a LateInitializationError to production (see
  // _focusSignalOnMap). Now every use has to say what it does without a map —
  // `!` where a live map is a precondition, a null check where it isn't.
  GoogleMapController? _mapController;
  final _markerBuilder = MapMarkerBuilder();

  // The Maps SDK picks its label language when the platform view is created and
  // never revisits it, so a locale change leaves the map drawing the old
  // language until the app restarts. We rebuild the view under a locale-keyed
  // Key instead, which means replaying the camera ourselves.
  //
  // It has to be recorded here rather than read back from the view model:
  // updateMapCenter deliberately ignores moves under its 30km re-query
  // threshold, so the centre it holds can be up to 30km from where the user
  // actually is. Restoring from it would teleport someone who panned a couple
  // of streets. onCameraMove hands over target, zoom, bearing and tilt
  // together, so the rebuilt view resumes exactly where the old one stood.
  CameraPosition? _lastCamera;

  // The locale the live platform view was created for; a change is what
  // triggers the rebuild. Maintained in didChangeDependencies, which is where
  // an inherited Localizations change surfaces.
  String? _mapLocale;

  bool _showOnboardingButton = false;
  bool _onboardingSheetShown = false;

  // The open bubble, if any, and where its pin currently is on screen.
  //
  // Deliberately two different mechanisms. Which signal is selected changes
  // only on a tap, so it is ordinary state. Its screen position changes on
  // every frame of a pan, and setState for that would rebuild _buildScaffold —
  // which rebuilds the entire marker set — sixty times a second. The notifier
  // keeps the per-frame update inside the bubble's own subtree.
  //
  // Exactly one of these is set at a time: opening either bubble closes the
  // other, because they share the single anchor below.
  SignalWithId? _selectedSignal;
  VetClinic? _selectedClinic;
  final ValueNotifier<Offset?> _bubbleAnchor = ValueNotifier<Offset?>(null);

  /// The point the open bubble is anchored to, or null when none is open.
  LatLng? get _bubblePoint {
    final signal = _selectedSignal;
    if (signal != null) {
      return LatLng(signal.location.latitude, signal.location.longitude);
    }
    final clinic = _selectedClinic;
    if (clinic != null) return LatLng(clinic.latitude, clinic.longitude);
    return null;
  }

  /// How far above the anchor the bubble sits. A clinic pin is shorter than a
  /// signal pin, and offsetting both by the taller one leaves the clinic bubble
  /// floating clear of its marker.
  double get _bubblePinHeight => _selectedClinic != null
      ? MapMarkerBuilder.clinicPinHeight
      : MapMarkerBuilder.pinHeight;

  /// Key on the map's Stack, so the bubble's own arithmetic can read the size
  /// of the box it is positioned in. See [_mapSize].
  final GlobalKey _mapStackKey = GlobalKey();

  /// Size of the map's box, or null before its first layout.
  Size? get _mapSize {
    final box = _mapStackKey.currentContext?.findRenderObject() as RenderBox?;
    return (box != null && box.hasSize) ? box.size : null;
  }

  // Listener that waits for a specific signal to appear in the stream before
  // opening its bubble (used after signal creation / notification).
  ProviderSubscription<AsyncValue<List<SignalWithId>>>? _pendingBubbleSub;

  // A signal we were asked to focus before the map's platform view was ready.
  // Replayed from [onMapCreated]; see [_focusSignalOnMap].
  String? _deferredFocusSignalId;

  // Set once a deep link has put the camera on a signal, so the fly-to-user
  // that [initState] schedules doesn't yank it away when the fix lands late.
  bool _deepLinkOwnsCamera = false;

  // Test mode toggle state
  int _titleTapCount = 0;
  DateTime? _lastTitleTap;

  // Every marker on the map — signal pins, signal bubbles, clinic pins, clinic
  // bubbles — as last computed by [_recluster]. Held as state rather than
  // derived in build: clustering depends on the camera zoom and the bubble
  // bitmaps are rendered asynchronously, so it is redone when something that
  // feeds it changes, not on every rebuild.
  Set<Marker> _markers = const {};
  final _bubbleIcons = ClusterBubbleIcons();

  /// Discards a [_recluster] that was overtaken while awaiting its bitmaps.
  int _reclusterToken = 0;

  /// What the marker set was last built from — see the top of [_recluster].
  Object? _reclusteredFrom;

  /// The screen's pixel ratio, read where an inherited value may be read.
  double _devicePixelRatio = 1.0;

  /// Where the camera is, for anything that has to answer before the platform
  /// has reported a move.
  double get _currentZoom => _lastCamera?.zoom ?? _kInitialZoom;

  /// Respond to a tap on a cluster bubble of either layer: zoom into it if that
  /// would separate its members, otherwise list them.
  ///
  /// Whether zooming helps is [splitsByZoomingIn]'s to answer — it is the merge
  /// rule read backwards, and lives beside it. When it cannot help, the camera
  /// would arrive at max zoom with the bubble still a bubble and every further
  /// tap a no-op, so the members are listed instead; without that, a cluster of
  /// co-located signals is unreachable from the map.
  void _onClusterTap<T>(
    MapCluster<T> cluster, {
    required String Function(int count) title,
    required Widget Function(BuildContext sheetContext, T item) row,
  }) {
    // A bubble is `consumeTapEvents`, so `GoogleMap.onTap` never fires for it
    // and an open bubble would otherwise survive the tap — riding the camera to
    // wherever the zoom lands, or sitting under the sheet.
    _dismissBubble();
    if (splitsByZoomingIn(cluster.bounds, currentZoom: _currentZoom)) {
      // Dispatched by the GoogleMap widget, so the map exists by construction.
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(cluster.bounds, 50),
      );
      return;
    }
    showClusterItemsSheet<T>(
      context: context,
      title: title(cluster.count),
      items: cluster.members,
      row: row,
    );
  }

  /// Leave a cluster sheet for the screen one of its rows points at.
  void _openFromSheet(BuildContext sheetContext, String route) {
    Navigator.of(sheetContext).pop();
    context.push(route);
  }

  /// Regroup both marker layers for the current camera, filter and selection,
  /// and publish the resulting marker set.
  ///
  /// Everything that feeds the grouping calls this: a stream emission, a filter
  /// change, a clinic search, a camera idle, a bubble opening or closing, a
  /// locale change, and the pins finishing loading. The bubble bitmaps are
  /// rendered before the markers are built so a cluster never shows up as a
  /// default pin; that render is the one await, and a call overtaken during it
  /// drops its result.
  Future<void> _recluster() async {
    final mapState = ref.read(mapViewModelProvider);
    final signalsAsync = ref.read(signalsStreamProvider);
    final selectedSignalId = _selectedSignal?.id;
    final selectedClinicId = _selectedClinic?.id;

    // Everything the marker set is a function of. Clustering buckets at whole
    // zoom levels, so most camera idles — every pan, and every pinch that lands
    // in the same bucket — produce a byte-identical result; and a single tap
    // reclusters twice, once for the selection and once for the recentre the
    // SDK does in response. Comparing the inputs turns those into nothing at
    // all, instead of a pass over every visible signal plus a marker diff
    // across the platform channel.
    final inputs = (
      signalsAsync,
      mapState.filterState,
      mapState.vetClinicState.clinics,
      _currentZoom.round(),
      selectedSignalId,
      selectedClinicId,
      _markerBuilder.arePinsLoaded,
      _devicePixelRatio,
    );
    if (inputs == _reclusteredFrom) return;

    final token = ++_reclusterToken;

    // A reload draws no signals at all, deliberately.
    //
    // `AsyncValue.value` does not go null while a provider recomputes:
    // Riverpod carries the previous list through the `AsyncLoading` transition
    // (`copyWithPrevious`), and keeps it through an `AsyncError` too. Most
    // reloads are the same query re-running — a >30km recentre, a time-range
    // change — where drawing the carried-over list would be harmless. **A
    // test-mode flip is not**: it re-points the query at a different
    // collection, so the carried-over list is the *other* mode's signals, and
    // drawing them would put live prod pins on a test-mode map, each one
    // tappable through to its details. A failed new query would leave them
    // there indefinitely.
    //
    // There is nothing in the value to say which query produced it, so a reload
    // is treated as "no signals" whatever caused it. The map blanks for as long
    // as the query takes and the open bubble hides with it — which is what the
    // screen did before clustering moved into Dart.
    final visible = signalsAsync.isLoading
        ? null
        : signalsAsync.value?.where(mapState.filterState.passes).toList();
    final clusteredSignals = clusterPoints<SignalWithId>(
      visible ?? const [],
      position: (s) {
        final at = s.location;
        return LatLng(at.latitude, at.longitude);
      },
      zoom: _currentZoom,
      // Whatever the bubble is open on stays its own pin, whatever the zoom —
      // a bubble whose tail points at a cluster bubble points at nothing.
      keepSeparate: (s) => s.id == selectedSignalId,
    );
    final clusteredClinics = clusterPoints<VetClinic>(
      mapState.vetClinicState.clinics,
      position: (c) => LatLng(c.latitude, c.longitude),
      zoom: _currentZoom,
      keepSeparate: (c) => c.id == selectedClinicId,
    );

    final icons = await _bubbleIcons.ensure(
      [
        ...clusteredSignals.clusters.map(MapMarkerBuilder.signalBubbleKey),
        ...clusteredClinics.clusters.map(MapMarkerBuilder.clinicBubbleKey),
      ],
      devicePixelRatio: _devicePixelRatio,
    );
    if (!mounted || token != _reclusterToken) return;

    final l10n = AppLocalizations.of(context);
    setState(() {
      _reclusteredFrom = inputs;
      _markers = {
        ..._markerBuilder.buildSignalMarkers(
          clustered: clusteredSignals,
          bubbleIcons: icons,
          onMarkerTap: _showSignalBubble,
          onClusterTap: (cluster) => _onClusterTap<SignalWithId>(
            cluster,
            title: l10n.clusterSignalsHere,
            row: (sheetContext, signal) => SignalClusterRow(
              signal: signal,
              onTap: () =>
                  _openFromSheet(sheetContext, Routes.signalDetails(signal.id)),
            ),
          ),
        ),
        ..._markerBuilder.buildClinicMarkers(
          clustered: clusteredClinics,
          bubbleIcons: icons,
          onMarkerTap: _showClinicBubble,
          onClusterTap: (cluster) => _onClusterTap<VetClinic>(
            cluster,
            title: l10n.clusterClinicsHere,
            row: (sheetContext, clinic) => ClinicClusterRow(
              clinic: clinic,
              onTap: () =>
                  _openFromSheet(sheetContext, Routes.clinicDetails(clinic.id)),
            ),
          ),
        ),
      };
    });

    // A selected clinic that is no longer on the map — the layer was switched
    // off, or a fresh search came back without it — must not leave a bubble
    // behind that still navigates to it. Unlike the signals below there is no
    // loading state to wait for: the clinic list is whatever the last search
    // returned, and toggling the layer off empties it outright.
    if (selectedClinicId != null &&
        !mapState.vetClinicState.clinics
            .any((c) => c.id == selectedClinicId)) {
      _dismissBubble();
      return;
    }

    // Only once a query has actually answered: a reload empties the map without
    // meaning the signal is gone.
    if (visible == null || selectedSignalId == null) return;

    // A selected signal that is no longer rendered — deleted, filtered out, or
    // moved outside the geo-query radius — must not leave a bubble on screen
    // that navigates to a signal the map has stopped showing.
    if (!visible.any((s) => s.id == selectedSignalId)) _dismissBubble();
  }

  @override
  void initState() {
    super.initState();
    // Pins load asynchronously; until they have, a marker built from them gets
    // the SDK's default pin. Re-cluster once they are in so no signal is left
    // wearing it.
    _markerBuilder.loadAllPins().then((_) {
      if (mounted) _recluster();
    });
    WidgetsBinding.instance.addObserver(this);

    // Every input to the marker set that is not the camera: the signals
    // themselves, the filter they are drawn through, and the clinic layer. The
    // camera is handled from [_onCameraIdle]. Riverpod closes a `listenManual`
    // from a ConsumerState on unmount, so neither needs holding onto.
    ref.listenManual(signalsStreamProvider, (_, __) => _recluster());
    ref.listenManual(
      mapViewModelProvider
          .select((s) => (s.filterState, s.vetClinicState.clinics)),
      (_, __) => _recluster(),
    );

    // Initialize location in ViewModel, then animate camera to it — unless a
    // deep link got there first. The GPS fix can land seconds after the map,
    // long after a notification tap has already focused its signal.
    unawaited(_locateAndFly());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkOnboardingState();
      _recluster();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read here rather than in _recluster, which is not a build method and has
    // no business registering a dependency on an inherited widget.
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final locale = Localizations.localeOf(context).languageCode;
    if (_mapLocale != null && _mapLocale != locale) {
      // The locale-keyed GoogleMap below is about to discard the platform
      // view and create a new one. Close the bubble rather than let it hang
      // over a map that is about to be replaced: its anchor was computed
      // against the outgoing view, and _updateBubbleAnchor would go looking
      // for the pin through a disposed controller.
      // Through the fields rather than _dismissBubble: this runs inside
      // didChangeDependencies, where the build that setState would schedule is
      // already coming. The recluster still has to happen by hand, or whatever
      // was held out of clustering stays a lone pin beside the cluster it
      // belongs in — a locale change rebuilds the platform view without moving
      // the camera, so no onCameraIdle arrives to correct it.
      _selectedSignal = null;
      _selectedClinic = null;
      _bubbleAnchor.value = null;
      unawaited(_recluster());
    }
    _mapLocale = locale;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingBubbleSub?.close();
    _bubbleAnchor.dispose();
    super.dispose();
  }

  /// Take a fix and centre the map on it, unless a deep link owns the camera.
  ///
  /// [_flyToUserLocation] declines on its own when the widget is gone, the map
  /// isn't built yet, or no fix ever landed.
  Future<void> _locateAndFly() async {
    await ref.read(mapViewModelProvider.notifier).getUserLocation();
    if (_deepLinkOwnsCamera) return;
    _flyToUserLocation();
  }

  /// Re-read the location permission whenever the app comes forward.
  ///
  /// The permission the map draws its my-location layer from was decided in
  /// [initState] and never revisited, so someone who granted location from
  /// system Settings — or switched the GPS on — came back to a map still
  /// convinced it had nothing, and no "locate me" button, until the next cold
  /// start.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState != AppLifecycleState.resumed) return;
    unawaited(_refreshLocationPermission());
  }

  Future<void> _refreshLocationPermission() async {
    if (ref.read(mapViewModelProvider).hasLocationPermission) {
      // Already granted before we went away, so there is nothing new to fly
      // to. Just keep the flag honest — this is what catches a revoke.
      await ref.read(mapViewModelProvider.notifier).checkLocationPermission();
      return;
    }

    // It may have arrived while we were away, and while the map is up nothing
    // in the app asks — so it came from system Settings, which is exactly the
    // moment someone expects the map to find them. [getUserLocation] re-reads
    // the permission itself and takes the fix in the same pass, so the grant
    // costs one platform read rather than two.
    await _locateAndFly();
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
          unawaited(_locateAndFly());
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
      _openBubbleWhenSignalArrives(idAfter);
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
    // Independent method-channel round trips; no reason to queue them.
    final (region, zoom) = await (map.getVisibleRegion(), map.getZoomLevel()).wait;
    if (!mounted || token != _cameraIdleToken) return;

    final centerLat =
        (region.northeast.latitude + region.southwest.latitude) / 2;
    final centerLng =
        (region.northeast.longitude + region.southwest.longitude) / 2;

    // The zoom has settled, so regroup for it. Clusters form and split only
    // here, at idle — mid-gesture the markers ride the map as they are.
    unawaited(_recluster());

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
      );

      if (mounted) {
        final clinics = ref.read(mapViewModelProvider).vetClinicState.clinics;
        if (clinics.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.noVetClinicsFound),
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

  void _showSignInDialog() => showSignInRequiredDialog(
        context,
        reason: AppLocalizations.of(context).signInToCreateSignals,
      );

  /// Convert a [ScreenCoordinate] to logical pixels.
  /// Android returns physical pixels; iOS returns logical points.
  (double x, double y) _screenCoordToLogical(ScreenCoordinate coord) {
    final dpr = Platform.isAndroid
        ? MediaQuery.of(context).devicePixelRatio
        : 1.0;
    return (coord.x.toDouble() / dpr, coord.y.toDouble() / dpr);
  }

  /// Open the bubble for [clinic], anchored to its pin.
  Future<void> _showClinicBubble(VetClinic clinic) async {
    setState(() {
      _selectedSignal = null;
      _selectedClinic = clinic;
    });
    // The grouping depends on the selection — see `keepSeparate` in
    // [_recluster] — so it changes with it.
    unawaited(_recluster());
    await _anchorBubble();
  }

  /// Open the bubble for [signal], anchored to its pin.
  Future<void> _showSignalBubble(SignalWithId signal) async {
    setState(() {
      _selectedClinic = null;
      _selectedSignal = signal;
    });
    unawaited(_recluster());
    // Place it from the last known camera before asking the platform, so a
    // bubble opened while another one is closing never paints a frame at the
    // previous pin's position. Null until the camera has moved once, in which
    // case the bubble simply waits for the authoritative answer below.
    await _anchorBubble();
  }

  /// Place a freshly-opened bubble.
  ///
  /// Projects from the last known camera first so a bubble opened while another
  /// is closing never paints a frame at the previous pin's position, then asks
  /// the platform for the authoritative answer.
  Future<void> _anchorBubble() async {
    final camera = _lastCamera;
    _bubbleAnchor.value = null;
    if (camera != null) _projectBubbleAnchor(camera);
    await _updateBubbleAnchor();
  }

  /// Open what the bubble points at, and re-anchor it on the way back.
  ///
  /// The route transition can leave the camera somewhere else, so the position
  /// we left with is not to be trusted. Guarded on the bubble still being the
  /// same one, in case it was dismissed or replaced while the route was up.
  void _openBubbleTarget(String location) {
    final point = _bubblePoint;
    context.push(location).then((_) {
      if (mounted && _bubblePoint == point) _updateBubbleAnchor();
    });
  }

  void _dismissBubble() {
    if (_selectedSignal == null && _selectedClinic == null) return;
    setState(() {
      _selectedSignal = null;
      _selectedClinic = null;
    });
    _bubbleAnchor.value = null;
    // Lets the pin rejoin whatever cluster it was held out of.
    unawaited(_recluster());
  }

  /// Re-anchor the bubble by asking the platform where the pin actually is.
  ///
  /// This is the authoritative answer and a method-channel round trip, so it
  /// runs when the camera settles. [_projectBubbleAnchor] carries the bubble
  /// through the gesture itself, and any drift it accumulated is corrected
  /// here the moment the gesture ends.
  Future<void> _updateBubbleAnchor() async {
    final point = _bubblePoint;
    if (point == null) return;
    // Precondition: an open bubble implies its marker was tapped on a map.
    final screenCoord = await _mapController!.getScreenCoordinate(point);
    if (!mounted || _bubblePoint != point) return;
    final (x, y) = _screenCoordToLogical(screenCoord);
    _bubbleAnchor.value = Offset(x, y);
  }

  /// Keep the bubble glued to its pin while the camera moves.
  ///
  /// Runs per frame, so it projects the pin in Dart rather than asking the
  /// platform — see [screenOffsetFromCamera] for why, and for the tilt
  /// precondition that [GoogleMap.tiltGesturesEnabled] `false` maintains.
  void _projectBubbleAnchor(CameraPosition camera) {
    final point = _bubblePoint;
    if (point == null) return;
    final size = _mapSize;
    if (size == null) return;
    final offset = screenOffsetFromCamera(
      point: point,
      camera: camera,
      viewport: size,
    );
    // Null only for a tilted camera, which nothing produces; leave the bubble
    // where it is and let the on-idle reconcile place it.
    if (offset != null) _bubbleAnchor.value = offset;
  }

  /// Open the bubble after a short delay, to let the native map render the
  /// marker it anchors to.
  void _showBubbleAfterRender(SignalWithId signal) {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _showSignalBubble(signal);
    });
  }

  void _openBubbleWhenSignalArrives(String signalId) {
    // Listen for the signal to appear in the stream. fireImmediately replays
    // the current value, so if the signal is already present it's found
    // without waiting for the next emission (also avoids a race between a
    // separate ref.read and the listener setup).
    _pendingBubbleSub?.close();
    final sub = _pendingBubbleSub =
        ref.listenManual(signalsStreamProvider, (_, next) {
      final signal = next.value
          ?.where((s) => s.id == signalId)
          .firstOrNull;
      if (signal != null) {
        _pendingBubbleSub?.close();
        _pendingBubbleSub = null;
        _showBubbleAfterRender(signal);
      }
    }, fireImmediately: true);

    // Safety timeout: stop listening if the signal never arrives. Closes the
    // subscription it was armed for, not whichever one is current — a second
    // request arriving inside the ten seconds replaces the field, and an
    // unconditional close here would cancel that newer wait instead.
    Future.delayed(const Duration(seconds: 10), () {
      sub.close();
      if (identical(_pendingBubbleSub, sub)) _pendingBubbleSub = null;
    });
  }

  /// Moves the camera to [signalId] and opens its bubble.
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

    if (mounted) _openBubbleWhenSignalArrives(signalId);
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
    // The open bubble's signal as of this build. Signal markers themselves are
    // not built here — see [_recluster] — but the bubble renders from
    // `selectedFresh`, looked up in the live stream, rather than from the
    // `_selectedSignal` snapshot taken at tap time: otherwise the pin would
    // recolour on an urgency change while the bubble above it kept the old
    // tint, title and tags. Deriving it costs nothing; re-adopting it into
    // state would cost a second full rebuild per stream emission, since the
    // repository allocates fresh SignalWithId objects every time and they have
    // no value equality. `_selectedSignal` stays as the record of what is open
    // and where its pin is. Guarded by whenData, which does not fire while the
    // provider is reloading, so the bubble hides for the duration — in step
    // with the pins, which [_recluster] also drops for a reload — and comes
    // back when the query answers. A signal that has really gone is dismissed
    // there.
    SignalWithId? selectedFresh;
    signalsAsync.whenData((signals) {
      final selected = _selectedSignal;
      if (selected != null) {
        selectedFresh = signals.where((s) => s.id == selected.id).firstOrNull;
      }
    });

    return PopScope(
      canPop: !mapState.isAddingNewSignal,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && mapState.isAddingNewSignal) {
          _cancelAddingNewSignalConfirmed();
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
            key: _mapStackKey,
            children: [
              MapStyleBuilder(
                builder: (context, mapStyle) => GoogleMap(
                // Discards and rebuilds the platform view when the app locale
                // changes, which is the only way to re-language the map's
                // labels. Nothing else changes this key, so the view is created
                // once per locale, not once per rebuild.
                key: ValueKey(_mapLocale),
                style: mapStyle,
                initialCameraPosition: _lastCamera ??
                    CameraPosition(
                      bearing: 0.0,
                      target: LatLng(
                        mapState.centerLatitude,
                        mapState.centerLongitude,
                      ),
                      tilt: 0.0,
                      zoom: _kInitialZoom,
                    ),
                onMapCreated: (GoogleMapController controller) async {
                  // Read before the assignment below overwrites it: the field
                  // is null only until the first platform view appears, which
                  // makes it the record of whether this is a rebuild.
                  final isFirstCreation = _mapController == null;
                  _mapController = controller;

                  // A rebuild for a locale change. Flying to the user's
                  // location is first-launch behaviour, and initialCameraPosition
                  // has already restored where they were, so leave it alone.
                  if (!isFirstCreation) return;

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
                onTap: (_) => _dismissBubble(),
                onCameraMove: (position) {
                  _lastCamera = position;
                  _projectBubbleAnchor(position);
                },
                onCameraIdle: () {
                  _onCameraIdle();
                  _updateBubbleAnchor();
                },
                zoomControlsEnabled: true,
                // The bubble is projected in Dart from the camera, which is
                // exact only for a flat map — see map_projection.dart. Nothing
                // in the app tilts the camera, so this costs no behaviour.
                tiltGesturesEnabled: false,
                myLocationEnabled: mapState.hasLocationPermission,
                markers: _markers,
              ),
              ),
              // The open bubble — a signal's or a clinic's — anchored to its
              // pin.
              //
              // Listens to the anchor rather than reading it from state, so a
              // pan repaints this subtree alone and leaves the marker set that
              // _buildScaffold assembles untouched.
              if (selectedFresh != null || _selectedClinic != null)
                ValueListenableBuilder<Offset?>(
                  valueListenable: _bubbleAnchor,
                  builder: (context, anchor, _) {
                    final signal = selectedFresh;
                    final clinic = _selectedClinic;
                    final mapSize = _mapSize;
                    if (anchor == null ||
                        mapSize == null ||
                        (signal == null && clinic == null)) {
                      return const SizedBox.shrink();
                    }

                    final layout = bubbleLayoutFor(
                      anchor: anchor,
                      viewport: mapSize,
                      bubbleWidth: MapBubble.width,
                      maxBubbleHeight: clinic != null
                          ? ClinicInfoCard.maxHeightFor(context)
                          : SignalInfoCard.maxHeightFor(context),
                      pinHeight: _bubblePinHeight,
                      gap: _kBubbleGap,
                      edgeInset: _kBubbleEdgeInset,
                    );
                    // Pin panned off the map: see bubbleLayoutFor. The
                    // selection is kept, so panning it back brings the bubble
                    // straight back.
                    if (layout == null) return const SizedBox.shrink();

                    return Positioned(
                      // Deliberately constant, with the whole offset in the
                      // Transform: changing `left` on a Positioned marks the
                      // Stack for relayout, and this moves every frame of a
                      // pan. A Transform is a paint-time translation.
                      left: 0,
                      top: 0,
                      child: Transform.translate(
                        offset: Offset(layout.left, layout.anchorY),
                        child: FractionalTranslation(
                          // Pulls the bubble up by its own height, which is
                          // content-dependent and unknown here — Bulgarian
                          // labels wrap to a second row where English does not.
                          translation:
                              layout.above ? const Offset(0, -1) : Offset.zero,
                          child: clinic != null
                              ? ClinicInfoCard(
                                  clinic: clinic,
                                  tailDown: layout.above,
                                  tailAlignment: layout.tailAlignment,
                                  onTap: () => _openBubbleTarget(
                                    Routes.clinicDetails(clinic.id),
                                  ),
                                )
                              : SignalInfoCard(
                                  signal: signal!,
                                  tailDown: layout.above,
                                  tailAlignment: layout.tailAlignment,
                                  onTap: () => _openBubbleTarget(
                                    Routes.signalDetails(signal.id),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              if (mapState.isAddingNewSignal) const _PlacementPin(),
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
                      icon: const Icon(Icons.search),
                      label: Text(l10n.searchThisArea),
                      style: ElevatedButton.styleFrom(
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
                    // A themed surface, not a white card. Floating over the map
                    // is not a reason to opt out of the theme — the signal
                    // bubble does the same and reads in both — and a white card
                    // with default-coloured text on a dark map was the one
                    // place the dark theme visibly broke.
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
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
                ),
              // Onboarding button
              if (_showOnboardingButton)
                NotificationOnboardingButton(
                  onTap: _showOnboardingSheet,
                ),
            ],
          ),
        appBar: AppBar(
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleTitleTap,
            // The one app bar title that was still a bare Text. With three
            // actions beside it, "Help a Paw (TEST)" ellipsises at 411dp and a
            // larger text size — and this title is also the seven-tap target
            // for test mode, so shrinking beats clipping the tap area.
            child: AppBarTitle(
              ref.watch(testModeProvider) ? 'Help a Paw (TEST)' : 'Help a Paw',
            ),
          ),
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
              label: l10n.mapLegend,
              button: true,
              enabled: true,
              child: IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: () => showMapLegendSheet(context),
              ),
            ),
            Semantics(
              label: l10n.toggleVetClinics,
              button: true,
              enabled: true,
              child: IconButton(
                // On/off is carried by the filled backing, not by a white
                // vs white70 icon — a 30% opacity difference is not a state.
                icon: const Icon(Icons.local_hospital),
                isSelected: mapState.vetClinicState.showVetClinics,
                style: IconButton.styleFrom(
                  backgroundColor: mapState.vetClinicState.showVetClinics
                      ? Theme.of(context).colorScheme.onPrimary.withAlpha(51)
                      : null,
                ),
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

/// The marker the reporter is about to drop, over the centre of the map.
///
/// This was `Icons.gps_fixed`, which is the standard "centre the map on me"
/// glyph: it said *where you are* at the one moment the reporter is saying
/// where the animal is. It is a pin now, in the shape they will see on the map
/// afterwards.
///
/// The pin's **tip** is the location, so it is lifted by half its height to
/// rest on the centre, and the dot underneath marks the exact point the tip
/// claims — a pin alone is ambiguous by about its own height, which is tens of
/// metres at this zoom.
///
/// White over a dark halo because it has to read on every tile: satellite,
/// park green, motorway, and the navy cluster bubble it lands on at the zoom
/// this mode opens at.
class _PlacementPin extends StatelessWidget {
  const _PlacementPin();

  /// `Icons.place` draws its tip just inside the bottom of its box.
  static const _lift = 22.0;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,  // theme-independent: over the map
                border: Border.all(
                  color: Colors.black.withAlpha(140),
                  width: 1.5,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -_lift),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.place,
                    size: 52.0,
                    color: Colors.black.withAlpha(120),
                  ),
                  const Icon(
                    Icons.place,
                    size: 48.0,
                    color: Colors.white,  // theme-independent: over the map
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

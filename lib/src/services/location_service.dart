import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../repositories/repository_provider.dart';
import 'app_preferences_service.dart';
import 'background_location_channel.dart';
import 'nearby_signal_checker.dart';


/// What [LocationService.startLocationTracking] actually managed to start.
///
/// Sourced from the native monitors rather than re-derived from geolocator's
/// [LocationPermission], because the native side decides this authoritatively
/// and knows more: Kotlin also checks `ACCESS_BACKGROUND_LOCATION` and
/// short-circuits below SDK Q, and Swift additionally requires
/// `significantLocationChangeMonitoringAvailable()`. A caller inferring the
/// outcome from the permission enum alone can therefore contradict what is
/// really running — on Android 9, or when "Always" was granted out-of-band
/// through Settings.
enum LocationTrackingResult {
  /// Foreground stream *and* native background monitoring are running.
  full,

  /// Foreground only. Location is reported while the app is open and stops
  /// when it is not — most often because only "While Using" was granted.
  foregroundOnly,

  /// Nothing started; permission was refused, but the OS will show the dialog
  /// again, so asking once more is a route back.
  denied,

  /// Nothing started; permission is refused permanently. The OS will not ask
  /// again, so the app's settings page is the only way back.
  deniedForever,

  /// Nothing started; location is off device-wide. The app's own permission may
  /// be perfectly fine, so this needs different words and a different settings
  /// page from the two above.
  serviceDisabled,
}

/// Whether this permission lets the app show or use the user's position.
///
/// `unableToDetermine` is the platform saying it does not know, which is not
/// a grant — the map must not draw someone's position on the strength of it.
///
/// Named once because several screens ask this question and their inline
/// answers had begun to drift: the sites still written as
/// `!= denied && != deniedForever` additionally count `unableToDetermine` as
/// a grant. Whether they should adopt this reading is a separate audit.
extension LocationPermissionGrant on LocationPermission {
  bool get grantsLocation =>
      this == LocationPermission.always ||
      this == LocationPermission.whileInUse;
}

class LocationService with WidgetsBindingObserver {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionSubscription;
  bool _observingLifecycle = false;

  /// Refresh location and run the catch-up check when the app comes forward.
  ///
  /// The geolocator stream only fires on movement, so without this a user who
  /// travelled with the app closed would see nothing until they happened to
  /// move another 500m after opening it.
  ///
  /// Registered only while tracking is on. Observing unconditionally from the
  /// app root would take a GPS fix and write `userLocations/{uid}` on every
  /// resume for users who merely granted location for map centring and never
  /// enabled tracking — storing their position server-side without asking.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(updateLocationNow()
        .catchError((e) => debugPrint('Resume location update failed: $e')));
  }

  /// Default radius in km for checking nearby signals
  static const double defaultRadiusKm = 10.0;

  /// Distance filter in meters - only trigger on meaningful movement
  static const int distanceFilterMeters = 500;

  /// Installs the native background-location channel handler.
  ///
  /// Split out of [initialize] and called from `main()` before `runApp`, for
  /// the same reason `DeepLinkService.initialize()` is: it needs no uid, no
  /// Firestore and no preferences, so it must not sit behind the time-boxed
  /// anonymous sign-in. On iOS a significant-change relaunch can deliver a
  /// location while the app is still starting, and until this handler exists
  /// the native side has to buffer.
  ///
  /// Deliberately synchronous, so it can be called ahead of `runApp` without
  /// risking the launch screen hanging on an await.
  void attachBackgroundChannel() {
    // iOS delivers significant-change updates into this isolate (the relaunch
    // boots the app). Android has no engine at that point and boots a headless
    // one instead, which is what the entrypoint is for.
    BackgroundLocationChannel()
        .ensureHandlerInstalled(onUpdate: _onBackgroundLocation);

    // Not awaited: this is called ahead of runApp, and the mode only affects a
    // background delivery, which cannot arrive this early.
    unawaited(syncTestMode());
  }

  /// Mirrors the current test-mode flag into native-owned preferences.
  ///
  /// Android's background receiver keys its pre-filter gate by mode — exactly
  /// as [NearbySignalChecker] and [NotifiedSignalsStore] do — and it cannot
  /// read Dart's `shared_preferences` to discover the mode, so it has to be
  /// pushed.
  ///
  /// Called on every launch as well as on every flip. The launch call is what
  /// makes it self-healing: a push that failed while the app was being killed
  /// corrects itself on the next start rather than leaving the two sides
  /// disagreeing indefinitely.
  Future<void> syncTestMode() =>
      BackgroundLocationChannel().setTestMode(AppPreferencesService().isTestMode());

  /// Restore location tracking on launch if the user has it enabled.
  ///
  /// Called from `_bootstrapServices` in main.dart. Before that wiring existed
  /// this method was dead code, which is why tracking silently stopped after
  /// every app restart.
  Future<void> initialize({Function? headlessEntrypoint}) async {
    // Registering the headless entrypoint stays here rather than moving up with
    // the handler: it only persists a callback handle natively for *future*
    // background deliveries, so it is not racing this launch.
    if (headlessEntrypoint != null) {
      await BackgroundLocationChannel()
          .registerHeadlessEntrypoint(headlessEntrypoint);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // A failed read leaves tracking off for this launch rather than starting it
    // on an assumption — this is the consent flag for storing someone's
    // position. The next launch retries.
    final prefs = await RepositoryProvider.instance.userRepository
        .getNotificationPreferences(user.uid);
    if (prefs?.locationTrackingEnabled != true) return;

    // No permission pre-check: [startLocationTracking] only ever checks, so
    // calling it from the launch bootstrap cannot put an OS dialog in front of
    // someone who revoked location in system Settings. It reports what stopped
    // it and leaves tracking off; the settings toggle is where the asking
    // happens, in response to a tap.
    final result = await startLocationTracking();
    if (result != LocationTrackingResult.full &&
        result != LocationTrackingResult.foregroundOnly) {
      debugPrint('Location tracking is enabled but did not restore: $result');
    }
  }

  /// Request location permission.
  ///
  /// Says nothing about whether location is switched on device-wide — that is
  /// [startLocationTracking]'s to report. This used to answer `denied` when the
  /// service was off, which is true only in the sense that nothing was granted
  /// and left callers unable to tell "you refused" from "location is off".
  Future<LocationPermission> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    FirebaseCrashlytics.instance.log('Location: Permission result - $permission');

    return permission;
  }

  /// Request always permission for background location
  Future<LocationPermission> requestAlwaysPermission() async {
    LocationPermission permission = await requestPermission();

    if (permission == LocationPermission.whileInUse) {
      // Request upgrade to always
      permission = await Geolocator.requestPermission();
    }

    return permission;
  }

  /// Start listening to location changes.
  ///
  /// **Checks the permission, never requests it.** Callers that want a prompt
  /// call [requestAlwaysPermission] first, from a user-initiated action, and
  /// then read the returned [LocationTrackingResult] to find out what actually
  /// started. Asking here would both put a dialog on the launch path, which has
  /// no user action behind it, and — since every prompting caller has just
  /// asked — show a second dialog for one tap. On Android that second refusal
  /// is the one that blocks the permission for good.
  Future<LocationTrackingResult> startLocationTracking() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint('Location services are disabled');
      return LocationTrackingResult.serviceDisabled;
    }

    final permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permission denied permanently');
      return LocationTrackingResult.deniedForever;
    }

    if (permission == LocationPermission.denied) {
      debugPrint('Location permission denied');
      return LocationTrackingResult.denied;
    }

    // Drop any existing foreground stream, but deliberately *not* via
    // stopLocationTracking(): that also tears down the native monitor, which
    // clears the persisted enabled flag and cancels the reconcile job. Doing
    // that on every launch opens a window where a process death would leave
    // BootReceiver with nothing to re-arm — silently disabling background
    // tracking, which is the exact failure this feature exists to fix.
    // Re-registering the native monitor below is idempotent, so there is
    // nothing to stop first.
    await _cancelPositionStream();

    // Configure location settings for battery efficiency
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.medium,
      distanceFilter: distanceFilterMeters,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      _onLocationChanged,
      onError: (error) {
        debugPrint('Location stream error: $error');
      },
    );

    // The geolocator stream above only survives while the app process does.
    // Start the native monitor too — iOS significant-change and Android
    // PendingIntent updates — which is what keeps reporting once the app is
    // backgrounded or terminated.
    final backgroundStarted = await BackgroundLocationChannel().start();
    if (!backgroundStarted) {
      debugPrint(
        'Background location monitor did not start; foreground-only tracking. '
        'Most often this means "Always" location permission was not granted.',
      );
      FirebaseCrashlytics.instance
          .log('Location: Background monitor unavailable');
    }

    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }

    FirebaseCrashlytics.instance.log('Location: Tracking started');
    debugPrint('Location tracking started');

    // Get initial position and update
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      await _updateLocationInFirestore(position);
    } catch (e) {
      debugPrint('Error getting initial position: $e');
    }

    return backgroundStarted
        ? LocationTrackingResult.full
        : LocationTrackingResult.foregroundOnly;
  }

  /// Whether background delivery is really running, asked of the native
  /// monitors rather than inferred from the stored preference.
  Future<bool> isBackgroundTrackingActive() =>
      BackgroundLocationChannel().isBackgroundActive();

  /// Re-arm background tracking if the OS now allows it, **without prompting**.
  ///
  /// The permission can be granted from system Settings, where nothing tells
  /// the app about it — so a screen that has just been resumed has to ask.
  /// Returns whether background delivery is running afterwards.
  ///
  /// Never requests permission, for the reason [initialize] does not either: a
  /// system dialog must follow a tap, not a resume. If the permission is still
  /// short of "always" this reports false and leaves the user to grant it.
  Future<bool> rearmBackgroundTrackingIfPermitted() async {
    if (await isBackgroundTrackingActive()) return true;

    if (await Geolocator.checkPermission() != LocationPermission.always) {
      return false;
    }

    return await startLocationTracking() == LocationTrackingResult.full;
  }

  /// Cancels only the foreground position stream.
  Future<void> _cancelPositionStream() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Stop tracking entirely, foreground and background.
  ///
  /// This represents the user turning the feature off, so it also clears the
  /// native enabled flag — meaning nothing will re-arm on the next launch or
  /// reboot. Don't call it to merely restart the foreground stream.
  Future<void> stopLocationTracking() async {
    FirebaseCrashlytics.instance.log('Location: Tracking disabled by user');
    await _cancelPositionStream();
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    await BackgroundLocationChannel().stop();

    // Only once nothing can write it any more, so an in-flight delivery can't
    // recreate the document we are about to remove.
    await _deleteStoredLocation();

    debugPrint('Location tracking stopped');
  }

  /// Removes `userLocations/{uid}` when the user opts out.
  ///
  /// Not optional bookkeeping: the notification fan-out selects candidates by
  /// running a geohash range query straight over `userLocations`, and only then
  /// loads the user document for preferences. It never consults
  /// `locationTrackingEnabled`. So a document left behind here keeps matching
  /// the user forever, against a position that stops being updated the moment
  /// they turn tracking off — they keep being notified about "nearby" signals
  /// from wherever they happened to be, and their location stays stored after
  /// they asked us not to store it.
  Future<void> _deleteStoredLocation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('userLocations')
          .doc(user.uid)
          .delete()
          .timeout(const Duration(seconds: 10));
      debugPrint('Deleted stored location');
    } catch (e) {
      debugPrint('Error deleting stored location: $e');
    }
  }

  /// Handle location change
  Future<void> _onLocationChanged(Position position) async {
    debugPrint('Location changed: ${position.latitude}, ${position.longitude}');

    // _updateLocationInFirestore handles its own errors.
    await _updateLocationInFirestore(position);
    await _runNearbyCheck(position.latitude, position.longitude);
  }

  /// Handles a position delivered by the *native* background monitor.
  ///
  /// On iOS the `userLocations/{uid}` write has to happen here rather than in
  /// Swift: the first native `Firestore.firestore()` use starts the shared
  /// default client, and the cloud_firestore plugin then assigns settings to
  /// that started client on its first call and aborts the process. See the
  /// comment on `BackgroundLocationManager`. Android keeps its native write —
  /// its deliveries land in a process with no engine at all — so writing again
  /// here would only duplicate it.
  Future<void> _onBackgroundLocation(double latitude, double longitude) async {
    if (Platform.isIOS) {
      await _updateLocationInFirestore(
        Position(
          latitude: latitude,
          longitude: longitude,
          timestamp: DateTime.now(),
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
    }
    await _runNearbyCheck(latitude, longitude);
  }

  /// Catch up on signals the server fan-out couldn't have reached us about,
  /// because we were out of range when they were created.
  ///
  /// Rate-limited inside the checker, so calling it on every location delivery
  /// is cheap. Shared by the geolocator stream, the resume hook and the native
  /// background channel.
  Future<void> _runNearbyCheck(double latitude, double longitude) async {
    try {
      await NearbySignalChecker().check(
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      debugPrint('Nearby signal check failed: $e');
    }
  }

  /// Update user's current location in Firestore.
  ///
  /// Written to the dedicated `userLocations/{uid}` collection rather than the
  /// user doc, so these high-frequency writes don't invoke the token-dedupe
  /// Cloud Function that watches `users/{uid}`. The notification fan-out reads
  /// location from here.
  Future<void> _updateLocationInFirestore(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final geoPoint = GeoPoint(position.latitude, position.longitude);
    final geoFirePoint = GeoFirePoint(geoPoint);

    try {
      await FirebaseFirestore.instance
          .collection('userLocations')
          .doc(user.uid)
          .set(
        {
          'geopoint': geoPoint,
          'geohash': geoFirePoint.geohash,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(const Duration(seconds: 10));
      debugPrint('Updated location in Firestore: ${geoFirePoint.geohash}');
    } catch (e) {
      debugPrint('Error updating location in Firestore: $e');
    }
  }

  /// Refresh the stored location and run a catch-up check.
  ///
  /// Called when the app is resumed. The geolocator stream only fires on
  /// movement, so without this a user who travelled with the app closed would
  /// not be checked until they moved another 500m after opening it.
  ///
  /// Does nothing unless tracking is running: resume fires many times a day
  /// (unlock, task switch, dismissing a system dialog), and taking a GPS fix
  /// plus a Firestore write each time would be wasteful — and would store the
  /// location of users who never enabled tracking.
  Future<void> updateLocationNow() async {
    if (_positionSubscription == null) return;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      await _updateLocationInFirestore(position);

      // Gated and deduped internally, so resuming repeatedly is cheap.
      await NearbySignalChecker().check(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }
}

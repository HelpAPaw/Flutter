import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'background_location_channel.dart';
import 'nearby_signal_checker.dart';


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

  /// Restore location tracking on launch if the user has it enabled.
  ///
  /// Called from `_bootstrapServices` in main.dart. Before that wiring existed
  /// this method was dead code, which is why tracking silently stopped after
  /// every app restart.
  Future<void> initialize({Function? headlessEntrypoint}) async {
    final channel = BackgroundLocationChannel();

    // iOS delivers significant-change updates into this isolate (the relaunch
    // boots the app). Android has no engine at that point and boots a headless
    // one instead, which is what the entrypoint is for.
    channel.ensureHandlerInstalled(onUpdate: _runNearbyCheck);
    if (headlessEntrypoint != null) {
      await channel.registerHeadlessEntrypoint(headlessEntrypoint);
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if user has enabled location tracking. Time-boxed like every other
    // Firestore call on this path: this runs on the launch bootstrap, and
    // offline the read can stay pending indefinitely.
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get()
        .timeout(const Duration(seconds: 10));

    final prefs = userDoc.data()?['notificationPreferences'];
    if (prefs != null && prefs['locationTrackingEnabled'] == true) {
      await startLocationTracking();
    }
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled');
      return LocationPermission.denied;
    }

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

  /// Start listening to location changes
  Future<bool> startLocationTracking() async {
    final permission = await requestPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('Location permission denied');
      return false;
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

    return true;
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

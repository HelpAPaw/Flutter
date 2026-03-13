import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'app_preferences_service.dart';


class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionSubscription;
  final Set<String> _notifiedSignalIds = {};

  /// Default radius in km for checking nearby signals
  static const double defaultRadiusKm = 10.0;

  /// Distance filter in meters - only trigger on meaningful movement
  static const int distanceFilterMeters = 500;

  /// Initialize location tracking if enabled by user
  Future<void> initialize() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Check if user has enabled location tracking
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

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

    // Cancel existing subscription if any
    await stopLocationTracking();

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

    debugPrint('Location tracking started');

    // Get initial position and update
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      await _updateLocationInFirestore(position);
    } catch (e) {
      debugPrint('Error getting initial position: $e');
    }

    return true;
  }

  /// Stop listening to location changes
  Future<void> stopLocationTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    debugPrint('Location tracking stopped');
  }

  /// Handle location change
  Future<void> _onLocationChanged(Position position) async {
    debugPrint('Location changed: ${position.latitude}, ${position.longitude}');

    // Update location in Firestore
    await _updateLocationInFirestore(position);

    // Check for nearby signals
    await _checkForNearbySignals(position);
  }

  /// Update user's current location in Firestore
  Future<void> _updateLocationInFirestore(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final geoPoint = GeoPoint(position.latitude, position.longitude);
    final geoFirePoint = GeoFirePoint(geoPoint);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'currentLocation': {
          'geopoint': geoPoint,
          'geohash': geoFirePoint.geohash,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
      SetOptions(merge: true),
    );

    debugPrint('Updated location in Firestore: ${geoFirePoint.geohash}');
  }

  /// Check for signals created in the last 24 hours near this location
  Future<void> _checkForNearbySignals(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Get user's notification preferences
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final prefs = userDoc.data()?['notificationPreferences'];
    if (prefs == null || prefs['enabled'] != true) return;

    final radiusKm = (prefs['locationRadiusKm'] as num?)?.toDouble() ?? defaultRadiusKm;
    final signalTypes = (prefs['signalTypes'] as List<dynamic>?)?.cast<int>() ?? [];

    // Calculate time 24 hours ago
    final twentyFourHoursAgo = DateTime.now().subtract(const Duration(hours: 24));

    // Query for nearby signals
    final geoPoint = GeoPoint(position.latitude, position.longitude);
    final geoFirePoint = GeoFirePoint(geoPoint);

    final signalsCollection = FirebaseFirestore.instance.collection(AppPreferencesService().signalsCollectionName);

    // Use GeoFlutterFire to query nearby signals
    final stream = GeoCollectionReference(signalsCollection).subscribeWithin(
      center: geoFirePoint,
      radiusInKm: radiusKm,
      field: 'location',
      geopointFrom: (data) => (data['location'] as Map<String, dynamic>)['geopoint'] as GeoPoint,
    );

    // Get first emission and process
    final signals = await stream.first;

    for (final doc in signals) {
      final signalId = doc.id;
      final data = doc.data() as Map<String, dynamic>;

      // Skip if already notified
      if (_notifiedSignalIds.contains(signalId)) continue;

      // Check if signal is within last 24 hours
      final createdAt = data['createdAt'] as Timestamp?;
      if (createdAt == null) continue;
      if (createdAt.toDate().isBefore(twentyFourHoursAgo)) continue;

      // Check if signal type is in user's preferences
      final signalType = data['signalType'] as int?;
      if (signalTypes.isNotEmpty && signalType != null && !signalTypes.contains(signalType)) {
        continue;
      }

      // Check if this is user's own signal
      final reporter = data['reporter'] as DocumentReference?;
      if (reporter != null && reporter.id == user.uid) continue;

      // Mark as notified (local notification not yet implemented)
      _notifiedSignalIds.add(signalId);
      debugPrint('New signal nearby: $signalId');
    }
  }

  /// Update location when user opens the map (foreground update)
  Future<void> updateLocationNow() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      await _updateLocationInFirestore(position);
    } catch (e) {
      debugPrint('Error updating location: $e');
    }
  }

  /// Save location tracking preference
  Future<void> setLocationTrackingEnabled(bool enabled) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      {
        'notificationPreferences': {
          'locationTrackingEnabled': enabled,
        },
      },
      SetOptions(merge: true),
    );

    if (enabled) {
      await startLocationTracking();
    } else {
      await stopLocationTracking();
      // Clear current location
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'currentLocation': FieldValue.delete(),
      });
    }
  }
}

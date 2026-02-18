import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../models/vet_clinic.dart';

class VetClinicService {
  static final VetClinicService instance = VetClinicService._();
  VetClinicService._();

  final Map<String, VetClinic> _clinicCache = {};
  DateTime? _lastSearchTime;
  LatLng? _lastSearchLocation;

  static const int _cacheExpiryMinutes = 15;
  static const double _cacheLocationThresholdMeters = 1000;

  bool _isCacheValid(LatLng location) {
    if (_lastSearchTime == null || _lastSearchLocation == null) {
      return false;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastSearchTime!);

    if (elapsed.inMinutes >= _cacheExpiryMinutes) {
      return false;
    }

    final distance = Geolocator.distanceBetween(
      _lastSearchLocation!.latitude,
      _lastSearchLocation!.longitude,
      location.latitude,
      location.longitude,
    );

    return distance < _cacheLocationThresholdMeters;
  }

  Future<List<VetClinic>> searchNearby(LatLng center, double radiusMeters) async {
    if (_isCacheValid(center)) {
      return _clinicCache.values.toList();
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'searchVetClinics',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      final result = await callable.call<Map<String, dynamic>>({
        'latitude': center.latitude,
        'longitude': center.longitude,
        'radius': radiusMeters,
      });

      final places = (_castList(result.data['places']));

      if (places == null || places.isEmpty) {
        _lastSearchTime = DateTime.now();
        _lastSearchLocation = center;
        return [];
      }

      _clinicCache.clear();
      final clinics = places.map((place) {
        final clinic = VetClinic.fromJson(place as Map<String, dynamic>);
        _clinicCache[clinic.id] = clinic;
        return clinic;
      }).toList();

      _lastSearchTime = DateTime.now();
      _lastSearchLocation = center;

      return clinics;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Cloud Function error: ${e.code} - ${e.message}');
      if (e.code == 'resource-exhausted') {
        throw Exception('Rate limit exceeded. Please wait and try again.');
      } else if (e.code == 'invalid-argument') {
        throw Exception('Invalid search parameters.');
      }
      throw Exception('Failed to search clinics. Please try again.');
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      debugPrint('Vet clinic search error: $e');
      throw Exception('Failed to search clinics. Please try again.');
    }
  }

  VetClinic? getClinicById(String clinicId) {
    return _clinicCache[clinicId];
  }

  void clearCache() {
    _clinicCache.clear();
    _lastSearchTime = null;
    _lastSearchLocation = null;
  }

  static Map<String, dynamic> _castMap(Object? value) {
    final map = value as Map;
    return map.map((k, v) => MapEntry(k as String, v is Map ? _castMap(v) : v is List ? _castList(v) : v));
  }

  static List<dynamic> _castList(Object? value) {
    final list = value as List;
    return list.map((e) => e is Map ? _castMap(e) : e is List ? _castList(e) : e).toList();
  }
}

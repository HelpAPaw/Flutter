import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/vet_clinic.dart';

class VetClinicService {
  static final VetClinicService instance = VetClinicService._();
  VetClinicService._();

  // Accumulates all clinics found across searches in this session.
  // Keyed by Place ID so overlapping searches don't produce duplicates.
  final Map<String, VetClinic> _clinics = {};
  final Set<String> _clinicsWithDetails = {};

  Future<List<VetClinic>> searchNearby(LatLng center, double radiusMeters) async {
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

      for (final place in places) {
        final clinic = VetClinic.fromJson(place as Map<String, dynamic>);
        _clinics[clinic.id] = clinic;
      }

      return _clinics.values.toList();
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
    return _clinics[clinicId];
  }

  Future<VetClinic?> fetchClinicDetails(String clinicId) async {
    if (_clinicsWithDetails.contains(clinicId) && _clinics.containsKey(clinicId)) {
      return _clinics[clinicId];
    }

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'getVetClinicDetails',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      final result = await callable.call<Map<String, dynamic>>({'placeId': clinicId});
      final place = _castMap(result.data['place']);
      final clinic = VetClinic.fromJson(place);

      _clinics[clinicId] = clinic;
      _clinicsWithDetails.add(clinicId);
      return clinic;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Cloud Function error: ${e.code} - ${e.message}');
      return _clinics[clinicId];
    } catch (e) {
      debugPrint('Vet clinic details error: $e');
      return _clinics[clinicId];
    }
  }

  void clearSession() {
    _clinics.clear();
    _clinicsWithDetails.clear();
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

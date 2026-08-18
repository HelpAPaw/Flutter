import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/vet_clinic.dart';
import 'callable_client.dart';

class VetClinicService {
  static final VetClinicService instance = VetClinicService._();
  VetClinicService._();

  // Accumulates all clinics found across searches in this session.
  // Keyed by Place ID so overlapping searches don't produce duplicates.
  final Map<String, VetClinic> _clinics = {};
  final Set<String> _clinicsWithDetails = {};

  /// Calls a callable function through the shared [CallableClient].
  ///
  /// The transport (plain HTTPS rather than the `cloud_functions` plugin, to
  /// dodge a Swift runtime crash in release builds) now lives in one place —
  /// see the doc comment there. This wrapper survives only to keep the two
  /// error messages this service's callers already expect.
  Future<Map<String, dynamic>> _callFunction(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    try {
      return await CallableClient.call(functionName, data);
    } on CallableException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw Exception('Rate limit exceeded. Please wait and try again.');
      }
      if (e.code == 'invalid-argument') {
        throw Exception('Invalid search parameters.');
      }
      throw Exception('Failed to call $functionName. Please try again.');
    }
  }

  Future<List<VetClinic>> searchNearby(LatLng center, double radiusMeters) async {
    try {
      final result = await _callFunction('searchVetClinics', {
        'latitude': center.latitude,
        'longitude': center.longitude,
        'radius': radiusMeters,
      });

      final places = result['places'] as List<dynamic>? ?? [];

      for (final place in places) {
        final clinic = VetClinic.fromJson(place as Map<String, dynamic>);
        _clinics[clinic.id] = clinic;
      }

      return _clinics.values.toList();
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      if (e is Exception) rethrow;
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
      final result = await _callFunction('getVetClinicDetails', {
        'placeId': clinicId,
      });

      final place = result['place'] as Map<String, dynamic>?;
      if (place == null) return _clinics[clinicId];

      final clinic = VetClinic.fromJson(place);
      _clinics[clinicId] = clinic;
      _clinicsWithDetails.add(clinicId);
      return clinic;
    } catch (e) {
      debugPrint('Vet clinic details error: $e');
      return _clinics[clinicId];
    }
  }
}

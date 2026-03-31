import 'dart:async';
import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/vet_clinic.dart';

class VetClinicService {
  static final VetClinicService instance = VetClinicService._();
  VetClinicService._();

  // Accumulates all clinics found across searches in this session.
  // Keyed by Place ID so overlapping searches don't produce duplicates.
  final Map<String, VetClinic> _clinics = {};
  final Set<String> _clinicsWithDetails = {};

  /// Build the callable function URL for the given function name.
  /// Firebase v2 callable functions use the project ID and default region.
  String _callableUrl(String functionName) {
    final projectId = Firebase.app().options.projectId;
    return 'https://us-central1-$projectId.cloudfunctions.net/$functionName';
  }

  /// Call a Firebase callable function via direct HTTP, bypassing the
  /// cloud_functions Flutter plugin. The native FirebaseFunctions iOS SDK
  /// uses Swift `async let` patterns that trigger a Swift runtime memory
  /// corruption bug in release builds (swift_task_dealloc SIGABRT).
  /// Debug builds are unaffected because they skip compiler optimizations.
  /// See: https://forums.swift.org/t/suggested-tips-for-swift-concurrency-fatalerror-crashes/80723
  /// TODO: Revert to cloud_functions plugin once the Swift runtime fix ships.
  Future<Map<String, dynamic>> _callFunction(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final url = _callableUrl(functionName);

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    // Add Firebase Auth token if signed in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final idToken = await user.getIdToken();
      if (idToken != null) {
        headers['Authorization'] = 'Bearer $idToken';
      }
    }

    // Add App Check token
    try {
      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      if (appCheckToken != null) {
        headers['X-Firebase-AppCheck'] = appCheckToken;
      }
    } catch (e) {
      debugPrint('App Check token error: $e');
    }

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: jsonEncode({'data': data}),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 429) {
      throw Exception('Rate limit exceeded. Please wait and try again.');
    }

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final error = body['error'];
      if (error != null) {
        final code = error['status'] ?? error['code'] ?? '';
        final message = error['message'] ?? 'Unknown error';
        debugPrint('Cloud Function error: $code - $message');
        if (code == 'INVALID_ARGUMENT') {
          throw Exception('Invalid search parameters.');
        }
      }
      throw Exception('Failed to call $functionName. Please try again.');
    }

    final body = jsonDecode(response.body);
    return (body['result'] as Map<String, dynamic>?) ?? {};
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

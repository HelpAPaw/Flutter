import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/vet_clinic.dart';

class VetClinicService {
  static final VetClinicService instance = VetClinicService._();
  VetClinicService._();

  final Map<String, VetClinic> _clinicCache = {};
  DateTime? _lastSearchTime;
  LatLng? _lastSearchLocation;

  static const String _apiKey = 'AIzaSyAyFtEitLbPStFFtIb940Ms141RWxx2_rU';
  static const String _placesApiUrl = 'https://places.googleapis.com/v1/places:searchNearby';
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
      final requestBody = {
        'includedTypes': ['veterinary_care'],
        'maxResultCount': 20,
        'locationRestriction': {
          'circle': {
            'center': {
              'latitude': center.latitude,
              'longitude': center.longitude,
            },
            'radius': radiusMeters,
          },
        },
      };

      final response = await http
          .post(
            Uri.parse(_placesApiUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': _apiKey,
              'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,places.location,places.internationalPhoneNumber,places.rating,places.googleMapsUri,places.regularOpeningHours',
            },
            body: jsonEncode(requestBody),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Request timed out'),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final places = data['places'] as List<dynamic>?;

        if (places == null || places.isEmpty) {
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
      } else if (response.statusCode == 429) {
        throw Exception('Rate limit exceeded. Please wait and try again.');
      } else if (response.statusCode == 403) {
        print('Places API 403 Error - Response body: ${response.body}');
        throw Exception('API access denied. Service temporarily unavailable.');
      } else {
        print('Places API Error ${response.statusCode} - Response: ${response.body}');
        throw Exception('Failed to search clinics: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Network error. Please check your internet connection.');
    } on TimeoutException {
      throw Exception('Request timed out. Please try again.');
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Unexpected error: $e');
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
}

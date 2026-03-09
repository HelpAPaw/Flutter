import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../repositories/signal_repository.dart';

/// Utility for loading map pins and building signal markers
class MapMarkerBuilder {
  BitmapDescriptor? redPin;
  BitmapDescriptor? orangePin;
  BitmapDescriptor? greenPin;
  BitmapDescriptor? hospitalPin;

  bool _pinsLoaded = false;
  bool _hospitalPinLoaded = false;

  bool get arePinsLoaded => _pinsLoaded;
  bool get isHospitalPinLoaded => _hospitalPinLoaded;

  /// Load signal status pins (red, orange, green)
  Future<void> loadSignalPins() async {
    redPin = await _loadPin('red');
    orangePin = await _loadPin('orange');
    greenPin = await _loadPin('green');
    _pinsLoaded = true;
  }

  /// Load hospital/clinic pin
  Future<void> loadHospitalPin() async {
    hospitalPin = await BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(24, 24)),
      'assets/icons/local_hospital_blue.png',
    );
    _hospitalPinLoaded = true;
  }

  /// Load all pins at once
  Future<void> loadAllPins() async {
    await Future.wait([loadSignalPins(), loadHospitalPin()]);
  }

  Future<BitmapDescriptor> _loadPin(String color) async {
    return BitmapDescriptor.asset(
      const ImageConfiguration(size: Size(24, 24)),
      'assets/icons/pin_$color.png',
    );
  }

  /// Get the pin for a signal status
  BitmapDescriptor getSignalPin(int status) {
    final pins = [redPin, orangePin, greenPin];
    return (status >= 0 && status < pins.length)
        ? (pins[status] ?? BitmapDescriptor.defaultMarker)
        : BitmapDescriptor.defaultMarker;
  }

  /// Build a set of markers from a list of signals
  Set<Marker> buildSignalMarkers({
    required List<SignalWithId> signals,
    required bool Function(int signalType, int status) filterPredicate,
    required void Function(String signalId) onSignalTap,
  }) {
    return signals.where((signal) {
      return filterPredicate(signal.signalType, signal.status);
    }).map((signal) {
      final GeoPoint location = signal.location;

      return Marker(
        markerId: MarkerId(signal.id),
        position: LatLng(location.latitude, location.longitude),
        infoWindow: InfoWindow(
          title: signal.signal.title,
          snippet: signal.signal.description,
          onTap: () => onSignalTap(signal.id),
        ),
        icon: getSignalPin(signal.status),
      );
    }).toSet();
  }
}

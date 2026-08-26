import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/signal_urgency.dart';
import '../repositories/signal_repository.dart';

/// Utility for loading map pins and building signal markers
class MapMarkerBuilder {
  /// Loaded signal pins keyed by [SignalUrgency.code].
  ///
  /// Pin color encodes **urgency, not status** — see [SignalUrgency].
  final Map<int, BitmapDescriptor> _urgencyPins = {};
  BitmapDescriptor? hospitalPin;

  bool _pinsLoaded = false;
  bool _hospitalPinLoaded = false;

  bool get arePinsLoaded => _pinsLoaded;
  bool get isHospitalPinLoaded => _hospitalPinLoaded;

  /// Load a map pin for every [SignalUrgency]. Adding an urgency automatically
  /// loads its pin — nothing to change here.
  Future<void> loadSignalPins() async {
    for (final urgency in SignalUrgency.values) {
      _urgencyPins[urgency.code] = await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(24, 29)),
        urgency.pinAsset,
      );
    }
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

  /// Get the loaded pin for a signal urgency code.
  BitmapDescriptor getSignalPin(int urgency) =>
      _urgencyPins[SignalUrgency.fromCode(urgency).code] ??
      BitmapDescriptor.defaultMarker;

  /// Build a set of markers from a list of signals.
  ///
  /// Native [InfoWindow.onTap] is broken when markers use [ClusterManager]
  /// (flutter/flutter#159636). As a workaround, the native InfoWindow is kept
  /// for display (it tracks the map perfectly), and [onMarkerTap] is called
  /// via [Marker.onTap] so the caller can overlay an invisible tap target.
  Set<Marker> buildSignalMarkers({
    required List<SignalWithId> signals,
    required bool Function(SignalWithId signal) filterPredicate,
    required void Function(SignalWithId signal) onMarkerTap,
    ClusterManagerId? clusterManagerId,
  }) {
    return signals.where((signal) {
      return filterPredicate(signal);
    }).map((signal) {
      final GeoPoint location = signal.location;

      return Marker(
        markerId: MarkerId(signal.id),
        position: LatLng(location.latitude, location.longitude),
        infoWindow: InfoWindow(
          title: signal.signal.title,
          snippet: signal.signal.description,
        ),
        icon: getSignalPin(signal.urgency),
        clusterManagerId: clusterOf(signal.urgency, clusterManagerId),
        onTap: () => onMarkerTap(signal),
      );
    }).toSet();
  }

  /// Which cluster a signal's marker joins — or `null`, meaning "stay a pin".
  ///
  /// Clustering hides urgency. A cluster bubble is drawn natively by the Maps
  /// SDK in its own colour, and `ClusterManager` exposes no way to restyle it
  /// (the Dart type carries an id and a tap callback, nothing else), so at the
  /// zoom the app opens at — where nearly every signal is inside a bubble —
  /// the map cannot say that anything on it is critical.
  ///
  /// [SignalUrgency.red] therefore opts out. A signal where an animal may die
  /// if nobody moves now is always its own red pin, at every zoom, and the
  /// count on the neighbouring bubble is one lower. That is the whole point of
  /// the colour: a screen of red pins has to mean "these animals may die".
  ///
  /// Green and amber still cluster, which is what keeps a busy city readable.
  static ClusterManagerId? clusterOf(int urgency, ClusterManagerId? id) =>
      SignalUrgency.fromCode(urgency) == SignalUrgency.red ? null : id;
}

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

  /// Height the pin bitmaps are rendered at. Load-bearing beyond the icon
  /// itself: the map screen offsets the signal bubble by it so the bubble sits
  /// above the pin rather than over it.
  static const double pinHeight = 29;

  /// Size the pin bitmaps are rendered at.
  static const Size pinSize = Size(24, pinHeight);

  /// Height of the clinic pin. Shorter than a signal pin, so the clinic bubble
  /// has to be offset by less or it floats clear of the marker.
  static const double clinicPinHeight = 24;

  /// Size the clinic pin bitmap is rendered at.
  static const Size clinicPinSize = Size(24, clinicPinHeight);

  bool _pinsLoaded = false;
  bool _hospitalPinLoaded = false;

  bool get arePinsLoaded => _pinsLoaded;
  bool get isHospitalPinLoaded => _hospitalPinLoaded;

  /// Load a map pin for every [SignalUrgency]. Adding an urgency automatically
  /// loads its pin — nothing to change here.
  Future<void> loadSignalPins() async {
    for (final urgency in SignalUrgency.values) {
      _urgencyPins[urgency.code] = await BitmapDescriptor.asset(
        const ImageConfiguration(size: pinSize),
        urgency.pinAsset,
      );
    }
    _pinsLoaded = true;
  }

  /// Load hospital/clinic pin
  Future<void> loadHospitalPin() async {
    hospitalPin = await BitmapDescriptor.asset(
      const ImageConfiguration(size: clinicPinSize),
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
  /// Markers carry **no [InfoWindow]**. The bubble is `SignalInfoCard`, a
  /// Flutter widget the map screen positions over the pin — the native window
  /// could only render two lines of text, and its `onTap` never fired for
  /// clustered markers (flutter/flutter#159636). [Marker.onTap] does fire, and
  /// is what opens the bubble.
  ///
  /// Dropping the native window also removed a bug rather than moving it. A
  /// marker tap still recentres the camera — that is the SDK's default, not the
  /// window's doing — so a distant pin still crosses the map's 30km re-query
  /// threshold and rebuilds the marker set. But Android's asynchronous
  /// reclustering used to tear the open native window down with it, and a
  /// Flutter bubble is not the ClusterManager's to remove.
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

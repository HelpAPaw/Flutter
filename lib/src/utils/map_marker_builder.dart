import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/signal_urgency.dart';
import '../models/vet_clinic.dart';
import '../repositories/signal_repository.dart';
import 'cluster_bubble_icons.dart';
import 'map_clusterer.dart';

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

  /// Build the signal layer's markers: one pin per single, one bubble per
  /// cluster.
  ///
  /// Markers carry **no [InfoWindow]**. The bubble is `SignalInfoCard`, a
  /// Flutter widget the map screen positions over the pin — the native window
  /// could only render two lines of text, and its `onTap` never fired for
  /// clustered markers (flutter/flutter#159636). [Marker.onTap] does fire, and
  /// is what opens the bubble.
  ///
  /// Clustering is the app's own ([clusterPoints]) rather than the SDK's,
  /// because the SDK's bubble could not be restyled and so could not say
  /// anything about urgency. Here a bubble takes the colour of its **most
  /// urgent member**: a cluster holding one critical signal is red at every
  /// zoom, exactly as its pin would be. Its bitmap must already be in
  /// [bubbleIcons] — the screen calls `ensure` before building — and a cluster
  /// whose bitmap is somehow missing is left off the map for this frame
  /// rather than drawn as a default pin pretending to be one signal.
  Set<Marker> buildSignalMarkers({
    required ClusterResult<SignalWithId> clustered,
    required ClusterBubbleIcons bubbleIcons,
    required void Function(SignalWithId signal) onMarkerTap,
    required void Function(MapCluster<SignalWithId> cluster) onClusterTap,
  }) {
    final markers = <Marker>{};
    for (final signal in clustered.singles) {
      final GeoPoint location = signal.location;
      markers.add(Marker(
        markerId: MarkerId(signal.id),
        position: LatLng(location.latitude, location.longitude),
        icon: getSignalPin(signal.urgency),
        onTap: () => onMarkerTap(signal),
      ));
    }
    for (final cluster in clustered.clusters) {
      final icon = bubbleIcons.get(bubbleKeyFor(cluster));
      if (icon == null) continue;
      markers.add(Marker(
        markerId: MarkerId('$clusterMarkerIdPrefix${cluster.key}'),
        position: cluster.position,
        icon: icon,
        // A bubble is centred on its centroid; a pin's tip is its point.
        anchor: const Offset(0.5, 0.5),
        // The SDK recentres the camera on any marker it handles the tap for.
        // The cluster handler animates the camera itself (or opens a sheet),
        // so let it have the tap outright rather than fight a second animation.
        consumeTapEvents: true,
        // Above the pins: a bubble is a summary of what is under it.
        zIndexInt: 1,
        onTap: () => onClusterTap(cluster),
      ));
    }
    return markers;
  }

  /// Marker ids of cluster bubbles start with this, so the screen can tell a
  /// bubble from a signal pin in the marker set without parsing signal ids.
  static const clusterMarkerIdPrefix = 'signal-cluster:';

  /// The blue of `local_hospital_blue.png`, so a clinic bubble is recognisably
  /// the clinic pin's colour and never one of the three urgency colours — a
  /// clinic bubble must not be readable as "several signals".
  static const clinicBlue = Color(0xFF2854C5); // theme-independent: over the map

  /// Build the vet clinic layer's markers: the hospital pin per single clinic
  /// and a blue bubble per cluster. Clinics are clustered separately from
  /// signals, so a signal never shares a bubble with a clinic.
  ///
  /// Clinics keep their native [InfoWindow] (name and address, tap for
  /// details). The SDK consumes a tap on a marker that has one rather than
  /// passing it to `GoogleMap.onTap`, so [onClinicMarkerTap] exists to let the
  /// screen close an open signal bubble — when both windows were native, the
  /// SDK's one-at-a-time rule did that for us.
  Set<Marker> buildClinicMarkers({
    required ClusterResult<VetClinic> clustered,
    required ClusterBubbleIcons bubbleIcons,
    required void Function(String clinicId) onClinicTap,
    required VoidCallback onClinicMarkerTap,
    required void Function(MapCluster<VetClinic> cluster) onClusterTap,
  }) {
    final markers = <Marker>{};
    for (final clinic in clustered.singles) {
      markers.add(Marker(
        markerId: MarkerId('clinic_${clinic.id}'),
        position: LatLng(clinic.latitude, clinic.longitude),
        icon: hospitalPin ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: clinic.name,
          snippet: clinic.address,
          onTap: () => onClinicTap(clinic.id),
        ),
        onTap: onClinicMarkerTap,
      ));
    }
    for (final cluster in clustered.clusters) {
      final icon = bubbleIcons.get(clinicBubbleKeyFor(cluster));
      if (icon == null) continue;
      markers.add(Marker(
        markerId: MarkerId('clinic-cluster:${cluster.key}'),
        position: cluster.position,
        icon: icon,
        anchor: const Offset(0.5, 0.5),
        consumeTapEvents: true,
        zIndexInt: 1,
        onTap: () => onClusterTap(cluster),
      ));
    }
    return markers;
  }

  static ClusterBubbleKey clinicBubbleKeyFor(MapCluster<VetClinic> cluster) =>
      ClusterBubbleKey.count(fill: clinicBlue, count: cluster.count);

  /// The bubble a signal cluster is drawn with: the colour of its most urgent
  /// member, and its count.
  ///
  /// "Most urgent" is by [SignalUrgency] declaration order — least to most —
  /// never by code, which is an opaque identifier (see [SignalUrgency.code]).
  static ClusterBubbleKey bubbleKeyFor(MapCluster<SignalWithId> cluster) =>
      ClusterBubbleKey.count(
        fill: highestUrgency(cluster.members.map((s) => s.urgency)).color,
        count: cluster.count,
      );

  /// The most urgent of [urgencyCodes], by declaration order. Unknown codes
  /// take their [SignalUrgency.fromCode] fallback (amber), so a signal from a
  /// newer build tints its bubble as "needs help", never as "fine".
  static SignalUrgency highestUrgency(Iterable<int> urgencyCodes) {
    var highest = SignalUrgency.values.first;
    for (final code in urgencyCodes) {
      final urgency = SignalUrgency.fromCode(code);
      if (urgency.index > highest.index) highest = urgency;
    }
    return highest;
  }
}

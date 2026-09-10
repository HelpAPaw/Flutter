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
  BitmapDescriptor? _hospitalPin;

  /// Height the pin bitmaps are rendered at. Load-bearing beyond the icon
  /// itself: the map screen offsets the signal bubble by it so the bubble sits
  /// above the pin rather than over it.
  static const double pinHeight = 29;

  /// Size the pin bitmaps are rendered at.
  static const Size pinSize = Size(24, pinHeight);

  /// Height the clinic pin is rendered at — shorter than a signal pin, so the
  /// bubble over it is offset by less.
  static const double clinicPinHeight = 24;

  /// Size the clinic pin bitmap is rendered at.
  static const Size clinicPinSize = Size(24, clinicPinHeight);

  bool _pinsLoaded = false;

  /// Whether the pin bitmaps have arrived. Read by the map screen, which has to
  /// rebuild its markers once they have — a marker built before then wears the
  /// SDK's default red pin whatever its urgency.
  bool get arePinsLoaded => _pinsLoaded;

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
    _hospitalPin = await BitmapDescriptor.asset(
      const ImageConfiguration(size: clinicPinSize),
      'assets/icons/local_hospital_blue.png',
    );
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
  /// zoom, exactly as its pin would be.
  Set<Marker> buildSignalMarkers({
    required ClusterResult<SignalWithId> clustered,
    required Map<ClusterBubbleKey, BitmapDescriptor> bubbleIcons,
    required void Function(SignalWithId signal) onMarkerTap,
    required void Function(MapCluster<SignalWithId> cluster) onClusterTap,
  }) {
    return {
      for (final signal in clustered.singles)
        Marker(
          markerId: MarkerId(signal.id),
          position: _latLngOf(signal.location),
          icon: getSignalPin(signal.urgency),
          onTap: () => onMarkerTap(signal),
        ),
      ..._bubbleMarkers(
        clustered.clusters,
        idPrefix: 'signal-cluster:',
        idOf: (signal) => signal.id,
        keyOf: signalBubbleKey,
        icons: bubbleIcons,
        onTap: onClusterTap,
      ),
    };
  }

  /// Build the vet clinic layer's markers: the hospital pin per single clinic
  /// and a blue bubble per cluster. Clinics are clustered separately from
  /// signals, so a signal never shares a bubble with a clinic.
  ///
  /// A clinic pin carries **no native [InfoWindow]**: it opens a
  /// `ClinicInfoCard`, the same bubble a signal opens. Two window styles on one
  /// map read as two different apps, and the native one could only ever render
  /// two lines of platform-styled text.
  Set<Marker> buildClinicMarkers({
    required ClusterResult<VetClinic> clustered,
    required Map<ClusterBubbleKey, BitmapDescriptor> bubbleIcons,
    required void Function(VetClinic clinic) onMarkerTap,
    required void Function(MapCluster<VetClinic> cluster) onClusterTap,
  }) {
    return {
      for (final clinic in clustered.singles)
        Marker(
          markerId: MarkerId('clinic_${clinic.id}'),
          position: LatLng(clinic.latitude, clinic.longitude),
          icon: _hospitalPin ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          onTap: () => onMarkerTap(clinic),
        ),
      ..._bubbleMarkers(
        clustered.clusters,
        idPrefix: 'clinic-cluster:',
        idOf: (clinic) => clinic.id,
        keyOf: clinicBubbleKey,
        icons: bubbleIcons,
        onTap: onClusterTap,
      ),
    };
  }

  /// One bubble marker per cluster, however the layer colours them.
  ///
  /// Written once for both layers so a change to how a bubble behaves — the
  /// anchor, the tap, the drawing order — cannot be made to signals and
  /// forgotten for clinics.
  static Iterable<Marker> _bubbleMarkers<T>(
    List<MapCluster<T>> clusters, {
    required String idPrefix,
    required String Function(T member) idOf,
    required ClusterBubbleKey Function(MapCluster<T> cluster) keyOf,
    required Map<ClusterBubbleKey, BitmapDescriptor> icons,
    required void Function(MapCluster<T> cluster) onTap,
  }) sync* {
    for (final cluster in clusters) {
      yield Marker(
        markerId: MarkerId('$idPrefix${clusterMarkerId(cluster, idOf)}'),
        position: cluster.position,
        // `icons` came from `ensure` for exactly these clusters, so the lookup
        // is total by construction.
        icon: icons[keyOf(cluster)]!,
        // A bubble is centred on its centroid; a pin's tip is its point.
        anchor: const Offset(0.5, 0.5),
        // The SDK recentres the camera on any marker it handles the tap for.
        // The cluster handler animates the camera itself (or opens a sheet),
        // so let it have the tap outright rather than fight a second animation.
        consumeTapEvents: true,
        // Above the pins: a bubble is a summary of what is under it.
        zIndexInt: 1,
        onTap: () => onTap(cluster),
      );
    }
  }

  /// A cluster's marker id: the lowest member id it holds.
  ///
  /// Membership, not position — so a bubble that survives a zoom step keeps its
  /// marker, and the plugin does not remove and re-upload its PNG for every
  /// notch of the zoom control. Unique because no point is in two clusters.
  static String clusterMarkerId<T>(
    MapCluster<T> cluster,
    String Function(T member) idOf,
  ) {
    var lowest = idOf(cluster.members.first);
    for (final member in cluster.members.skip(1)) {
      final id = idOf(member);
      if (id.compareTo(lowest) < 0) lowest = id;
    }
    return lowest;
  }

  /// The blue of `local_hospital_blue.png`, so a clinic bubble is recognisably
  /// the clinic pin's colour and never one of the three urgency colours — a
  /// clinic bubble must not be readable as "several signals".
  static const clinicBlue = Color(0xFF2854C5); // theme-independent: over the map

  static ClusterBubbleKey clinicBubbleKey(MapCluster<VetClinic> cluster) =>
      clusterBubbleKey(fill: clinicBlue, count: cluster.count);

  /// The bubble a signal cluster is drawn with: the colour of its most urgent
  /// member, and its count.
  static ClusterBubbleKey signalBubbleKey(MapCluster<SignalWithId> cluster) =>
      clusterBubbleKey(
        fill: SignalUrgency.highest(cluster.members.map((s) => s.urgency)).color,
        count: cluster.count,
      );

  static LatLng _latLngOf(GeoPoint point) =>
      LatLng(point.latitude, point.longitude);
}

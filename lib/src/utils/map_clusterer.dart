import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_projection.dart';

/// Groups map points that would overlap on screen, in Dart.
///
/// The Maps SDK has its own clustering, and the app used it until it turned
/// out to have no styling hook at all: `ClusterManager` in Dart is an id and a
/// tap callback, and neither platform plugin overrides the bubble renderer. The
/// bubble was Google's navy at every zoom, and at the zoom the map opens at —
/// where nearly every signal is inside one — that meant urgency, the one thing
/// pin colour exists to say, was invisible for most of what was on screen.
///
/// So clustering is done here, and the result is drawn as ordinary markers the
/// caller styles however it likes. The algorithm is a grid: the world is cut
/// into cells of [cellSizePx] screen pixels at the camera's (rounded) zoom, and
/// every cell holding two or more points becomes one cluster at their centroid.
/// It is `O(n)`, deterministic, and matches what the SDK's own algorithm does
/// closely enough — that one also works at an integer zoom, merging points
/// within 100px.
///
/// Two properties the caller has to live with, both shared with the native
/// algorithm:
///
/// - **Points on either side of a cell edge do not merge**, however close.
///   A near-miss draws two pins a few pixels apart rather than one bubble.
/// - **Identical coordinates never separate**, at any zoom. Two reporters at
///   the same spot are one bubble all the way to zoom 21, so a cluster tap
///   needs an answer other than "zoom in" — see the cluster items sheet.
///
/// Generic over the point type: the signal layer and the vet clinic layer both
/// use it, separately, so a signal never shares a bubble with a clinic.
ClusterResult<T> clusterPoints<T>(
  Iterable<T> items, {
  required LatLng Function(T item) position,
  required double zoom,
  double cellSizePx = 80.0,
  bool Function(T item)? exclude,
}) {
  final discreteZoom = zoom.round();
  final scale = math.pow(2.0, discreteZoom).toDouble();

  final cells = <_CellKey, List<T>>{};
  final singles = <T>[];
  for (final item in items) {
    if (exclude != null && exclude(item)) {
      singles.add(item);
      continue;
    }
    final px = worldPoint(position(item)) * scale;
    final key = _CellKey(
      discreteZoom,
      (px.dx / cellSizePx).floor(),
      (px.dy / cellSizePx).floor(),
    );
    (cells[key] ??= <T>[]).add(item);
  }

  final clusters = <MapCluster<T>>[];
  for (final entry in cells.entries) {
    final members = entry.value;
    if (members.length < 2) {
      singles.addAll(members);
      continue;
    }
    var latSum = 0.0, lngSum = 0.0;
    var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
    for (final m in members) {
      final p = position(m);
      latSum += p.latitude;
      lngSum += p.longitude;
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    clusters.add(MapCluster<T>(
      key: '${entry.key.zoom}:${entry.key.x}:${entry.key.y}',
      members: List.unmodifiable(members),
      position: LatLng(latSum / members.length, lngSum / members.length),
      bounds: LatLngBounds(
        southwest: LatLng(south, west),
        northeast: LatLng(north, east),
      ),
    ));
  }

  return ClusterResult<T>(
    singles: List.unmodifiable(singles),
    clusters: List.unmodifiable(clusters),
  );
}

/// What [clusterPoints] produced: the points to draw as themselves, and the
/// groups to draw as one bubble each.
class ClusterResult<T> {
  const ClusterResult({required this.singles, required this.clusters});

  final List<T> singles;
  final List<MapCluster<T>> clusters;
}

/// Two or more points sharing a grid cell.
class MapCluster<T> {
  const MapCluster({
    required this.key,
    required this.members,
    required this.position,
    required this.bounds,
  });

  /// Stable within a zoom level: `zoom:cellX:cellY`. Used for the marker id, so
  /// a re-cluster after a pan that did not change the grouping re-sends
  /// nothing for this bubble.
  final String key;

  final List<T> members;

  /// Centroid of the members — where the bubble is drawn.
  final LatLng position;

  /// Tight bounds of the members. Degenerate (a point) when they are
  /// co-located, which is the case a cluster tap has to recognise.
  final LatLngBounds bounds;

  int get count => members.length;
}

class _CellKey {
  const _CellKey(this.zoom, this.x, this.y);
  final int zoom;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is _CellKey && other.zoom == zoom && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(zoom, x, y);
}

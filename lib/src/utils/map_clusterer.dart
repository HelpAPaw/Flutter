import 'dart:math' as math;
import 'dart:ui' show Offset;

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
/// caller styles however it likes. The algorithm is the SDK's own idea at a
/// smaller radius: points are taken in input order, and each one not yet
/// grouped gathers every other ungrouped point within [mergeDistancePx] screen
/// pixels of it at the camera's (rounded) zoom; two or more make a cluster at
/// their centroid. A grid of [mergeDistancePx]-sized cells is only the lookup
/// index — a candidate can be at most one cell away — so this is `O(n)` in
/// practice and deterministic for a given input order.
///
/// Merging by distance rather than by grid cell matters at the end of a zoom:
/// two pins a metre apart on either side of a cell edge would otherwise be
/// drawn on top of each other at zoom 21, the lower one unreachable — the same
/// defect the cluster sheet exists to prevent, in miniature.
///
/// One property the caller still has to live with, shared with the native
/// algorithm: **identical coordinates never separate**, at any zoom. Two
/// reporters at the same spot are one bubble all the way to zoom 21, so a
/// cluster tap needs an answer other than "zoom in" — see the cluster items
/// sheet.
///
/// Generic over the point type: the signal layer and the vet clinic layer both
/// use it, separately, so a signal never shares a bubble with a clinic.
ClusterResult<T> clusterPoints<T>(
  Iterable<T> items, {
  required LatLng Function(T item) position,
  required double zoom,
  double mergeDistancePx = 60.0,
  bool Function(T item)? exclude,
}) {
  final discreteZoom = zoom.round();
  final scale = math.pow(2.0, discreteZoom).toDouble();

  final singles = <T>[];
  final points = <_Point<T>>[];
  final cells = <_CellKey, List<int>>{};
  for (final item in items) {
    if (exclude != null && exclude(item)) {
      singles.add(item);
      continue;
    }
    final at = position(item);
    final px = worldPoint(at) * scale;
    final index = points.length;
    points.add(_Point(item, at, px));
    (cells[_cellOf(px, mergeDistancePx, discreteZoom)] ??= <int>[]).add(index);
  }

  final grouped = List<bool>.filled(points.length, false);
  final clusters = <MapCluster<T>>[];
  final usedKeys = <String, int>{};
  for (var seed = 0; seed < points.length; seed++) {
    if (grouped[seed]) continue;
    final seedPx = points[seed].px;
    final cell = _cellOf(seedPx, mergeDistancePx, discreteZoom);

    final members = <int>[];
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final neighbours = cells[_CellKey(cell.zoom, cell.x + dx, cell.y + dy)];
        if (neighbours == null) continue;
        for (final i in neighbours) {
          if (grouped[i]) continue;
          if ((points[i].px - seedPx).distance <= mergeDistancePx) {
            members.add(i);
          }
        }
      }
    }

    if (members.length < 2) {
      grouped[seed] = true;
      singles.add(points[seed].item);
      continue;
    }

    var latSum = 0.0, lngSum = 0.0;
    var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
    for (final i in members) {
      grouped[i] = true;
      final p = points[i].at;
      latSum += p.latitude;
      lngSum += p.longitude;
      south = math.min(south, p.latitude);
      north = math.max(north, p.latitude);
      west = math.min(west, p.longitude);
      east = math.max(east, p.longitude);
    }
    // Keyed by the seed's cell. Two seeds can share a cell without being within
    // range of each other (a cell's diagonal is longer than its side), so a
    // repeat gets an ordinal rather than a duplicate marker id.
    var key = '${cell.zoom}:${cell.x}:${cell.y}';
    final repeat = usedKeys.update(key, (n) => n + 1, ifAbsent: () => 1);
    if (repeat > 1) key = '$key#$repeat';

    clusters.add(MapCluster<T>(
      key: key,
      members: List.unmodifiable(members.map((i) => points[i].item)),
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

_CellKey _cellOf(Offset px, double size, int zoom) =>
    _CellKey(zoom, (px.dx / size).floor(), (px.dy / size).floor());

class _Point<T> {
  const _Point(this.item, this.at, this.px);
  final T item;
  final LatLng at;
  final Offset px;
}

/// What [clusterPoints] produced: the points to draw as themselves, and the
/// groups to draw as one bubble each.
class ClusterResult<T> {
  const ClusterResult({required this.singles, required this.clusters});

  final List<T> singles;
  final List<MapCluster<T>> clusters;
}

/// Two or more points within merge distance of a common seed.
class MapCluster<T> {
  const MapCluster({
    required this.key,
    required this.members,
    required this.position,
    required this.bounds,
  });

  /// `zoom:cellX:cellY` of the point the cluster grew from — stable while the
  /// grouping is, so a re-cluster after a pan that did not change it re-sends
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

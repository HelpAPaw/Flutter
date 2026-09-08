import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'map_projection.dart';

/// How close two points have to be on screen — in logical pixels, at the
/// camera's rounded zoom — to be drawn as one bubble.
///
/// The Maps SDK's own algorithm uses 100px. This is tighter, so a bubble covers
/// less of the map than the SDK's did at the same zoom.
const double kClusterMergeDistancePx = 60.0;

/// The deepest zoom worth asking the camera for.
///
/// Google's maximum is 21 where imagery allows and lower where it does not, so
/// a cluster tap treats a camera already at 20 as arrived rather than asking it
/// to try again and land nowhere.
const double kMaxUsefulZoom = 20.0;

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
/// cluster tap needs an answer other than "zoom in" — see [splitsByZoomingIn]
/// and the cluster items sheet.
///
/// Generic over the point type: the signal layer and the vet clinic layer both
/// use it, separately, so a signal never shares a bubble with a clinic.
ClusterResult<T> clusterPoints<T>(
  Iterable<T> items, {
  required LatLng Function(T item) position,
  required double zoom,
  double mergeDistancePx = kClusterMergeDistancePx,
  bool Function(T item)? keepSeparate,
}) {
  final scale = math.pow(2.0, zoom.round()).toDouble();

  final singles = <T>[];
  final points = <({T item, LatLng at, Offset px})>[];
  final cells = <(int, int), List<int>>{};
  for (final item in items) {
    if (keepSeparate != null && keepSeparate(item)) {
      singles.add(item);
      continue;
    }
    final at = position(item);
    final px = worldPoint(at) * scale;
    (cells[_cellOf(px, mergeDistancePx)] ??= <int>[]).add(points.length);
    points.add((item: item, at: at, px: px));
  }

  final grouped = List<bool>.filled(points.length, false);
  final clusters = <MapCluster<T>>[];
  for (var seed = 0; seed < points.length; seed++) {
    if (grouped[seed]) continue;
    final seedPx = points[seed].px;
    final (cellX, cellY) = _cellOf(seedPx, mergeDistancePx);

    final members = <int>[];
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final neighbours = cells[(cellX + dx, cellY + dy)];
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

    clusters.add(MapCluster<T>(
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

/// Whether zooming in can break [bounds] apart into separate markers.
///
/// Lives here because it is the same rule as the merge, read backwards: members
/// separate only once they are more than [mergeDistancePx] apart on screen, and
/// the deepest the camera can usefully go is [kMaxUsefulZoom]. Asking it in
/// pixels keeps the one rule in one place — the alternative, a threshold in
/// ground metres, has to be re-derived by hand whenever the merge distance
/// changes and is only right at the latitude it was worked out for.
///
/// Deliberately conservative — twice the merge distance, and measured at
/// [kMaxUsefulZoom] rather than at Google's occasional 21. Answering "no" when
/// zooming would in fact have worked costs a sheet the user could have avoided;
/// answering "yes" when it would not costs a tap that does nothing at all, and
/// leaves whatever is inside unreachable.
bool splitsByZoomingIn(
  LatLngBounds bounds, {
  required double currentZoom,
  double mergeDistancePx = kClusterMergeDistancePx,
}) {
  if (currentZoom >= kMaxUsefulZoom) return false;
  final span = (worldPoint(bounds.northeast) - worldPoint(bounds.southwest)) *
      math.pow(2.0, kMaxUsefulZoom).toDouble();
  return span.distance >= 2 * mergeDistancePx;
}

/// What [clusterPoints] produced: the points to draw as themselves, and the
/// groups to draw as one bubble each.
class ClusterResult<T> {
  const ClusterResult({required this.singles, required this.clusters});

  final List<T> singles;
  final List<MapCluster<T>> clusters;
}

/// Two or more points close enough together to be drawn as one bubble.
class MapCluster<T> {
  const MapCluster({
    required this.members,
    required this.position,
    required this.bounds,
  });

  final List<T> members;

  /// Centroid of the members — where the bubble is drawn.
  final LatLng position;

  /// Tight bounds of the members. Degenerate (a point) when they are
  /// co-located, which is the case a cluster tap has to recognise.
  final LatLngBounds bounds;

  int get count => members.length;
}

(int, int) _cellOf(Offset px, double size) =>
    ((px.dx / size).floor(), (px.dy / size).floor());

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:help_a_paw/src/utils/map_clusterer.dart';

/// The grid clusterer that replaced the SDK's ClusterManager. Its contract is
/// small but every part of it is load-bearing for the map: what merges, what
/// does not, where the bubble lands, and that the bubble's id is stable.
void main() {
  // pl. Sv. Nedelya, Sofia — where four co-located test signals live.
  const nedelya = LatLng(42.697435865676695, 23.32189992070198);

  LatLng east(LatLng from, double metres) => LatLng(
        from.latitude,
        from.longitude + metres / (111320.0 * 0.7347), // cos(42.7°)
      );

  ClusterResult<LatLng> cluster(
    List<LatLng> points, {
    double zoom = 11,
    bool Function(LatLng)? exclude,
  }) =>
      clusterPoints<LatLng>(
        points,
        position: (p) => p,
        zoom: zoom,
        exclude: exclude,
      );

  test('a lone point is a single', () {
    final r = cluster([nedelya]);
    expect(r.singles, [nedelya]);
    expect(r.clusters, isEmpty);
  });

  test('identical coordinates are one cluster at every zoom', () {
    for (final zoom in [3.0, 11.0, 17.0, 21.0]) {
      final r = cluster([nedelya, nedelya, nedelya, nedelya], zoom: zoom);
      expect(r.singles, isEmpty, reason: 'zoom $zoom');
      expect(r.clusters, hasLength(1), reason: 'zoom $zoom');
      expect(r.clusters.single.count, 4);
      // Degenerate bounds: exactly what the cluster tap has to recognise.
      expect(r.clusters.single.bounds.southwest, nedelya);
      expect(r.clusters.single.bounds.northeast, nedelya);
    }
  });

  test('points far apart on screen stay singles', () {
    // 2 km apart is ~24px at zoom 11 — inside the 60px merge distance — but
    // 3000px at zoom 18.
    final far = east(nedelya, 2000);
    expect(cluster([nedelya, far], zoom: 11).clusters, hasLength(1));
    final r = cluster([nedelya, far], zoom: 18);
    expect(r.clusters, isEmpty);
    expect(r.singles, unorderedEquals([nedelya, far]));
  });

  test('closeness is by distance, not by grid cell', () {
    // At zoom 21 a 60px cell is ~3.3 m at this latitude. Walk a pair of points
    // 1 m apart across a kilometre so they straddle many cell edges: every
    // pair must still merge. A grid-only clusterer fails this at the edges.
    for (var m = 0; m < 1000; m += 7) {
      final a = east(nedelya, m.toDouble());
      final b = east(nedelya, m + 1.0);
      final r = cluster([a, b], zoom: 21);
      expect(r.clusters, hasLength(1), reason: 'pair at ${m}m');
    }
  });

  test('a point is grouped once, with the first seed that reaches it', () {
    // Three in a row, each 40px from the next at zoom 21 (~2.2 m): the middle
    // one is within range of both ends, but the ends are 80px apart. The
    // first seed takes the middle; the far end is left a single, never
    // double-counted.
    const zoom = 21.0;
    const metresPerPx = 4.4 / 80; // 80px ≈ 4.4 m at zoom 21, 42.7°N
    final a = nedelya;
    final b = east(nedelya, 40 * metresPerPx);
    final c = east(nedelya, 80 * metresPerPx);
    final r = cluster([a, b, c], zoom: zoom);
    expect(r.clusters, hasLength(1));
    expect(r.clusters.single.members, unorderedEquals([a, b]));
    expect(r.singles, [c]);
    final total = r.singles.length +
        r.clusters.fold<int>(0, (n, cl) => n + cl.count);
    expect(total, 3);
  });

  test('the bubble sits at the centroid with bounds around the members', () {
    final b = east(nedelya, 100);
    final r = cluster([nedelya, b], zoom: 11);
    final c = r.clusters.single;
    expect(c.position.latitude, closeTo(nedelya.latitude, 1e-9));
    expect(c.position.longitude,
        closeTo((nedelya.longitude + b.longitude) / 2, 1e-9));
    expect(c.bounds.southwest.longitude, nedelya.longitude);
    expect(c.bounds.northeast.longitude, b.longitude);
  });

  test('an excluded item is a single even inside a cluster', () {
    // Distinct items on one spot, so exclusion can name one of them — the
    // selected signal, whose open bubble must keep pointing at its own pin.
    final a = _Pt('a', nedelya), b = _Pt('b', nedelya), c = _Pt('c', nedelya);
    final r = clusterPoints<_Pt>(
      [a, b, c],
      position: (p) => p.at,
      zoom: 11,
      exclude: (p) => p.id == 'a',
    );
    expect(r.singles, [a]);
    expect(r.clusters.single.members, unorderedEquals([b, c]));
  });

  test('a cluster left with one member after exclusion collapses', () {
    final a = _Pt('a', nedelya), b = _Pt('b', nedelya);
    final r = clusterPoints<_Pt>(
      [a, b],
      position: (p) => p.at,
      zoom: 11,
      exclude: (p) => p.id == 'a',
    );
    expect(r.clusters, isEmpty);
    expect(r.singles, unorderedEquals([a, b]));
  });

  test('the cluster key is stable across calls at the same zoom', () {
    final k1 = cluster([nedelya, nedelya], zoom: 11.2).clusters.single.key;
    final k2 = cluster([nedelya, nedelya], zoom: 11.4).clusters.single.key;
    final k3 = cluster([nedelya, nedelya], zoom: 12.0).clusters.single.key;
    expect(k1, k2, reason: 'both round to zoom 11');
    expect(k1, isNot(k3), reason: 'a different zoom is a different index');
    expect(k1, startsWith('11:'));
  });
}

class _Pt {
  const _Pt(this.id, this.at);
  final String id;
  final LatLng at;
}

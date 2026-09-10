import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/utils/cluster_bubble_icons.dart';
import 'package:help_a_paw/src/utils/map_clusterer.dart';
import 'package:help_a_paw/src/utils/map_marker_builder.dart';

/// A cluster bubble is the colour of its most urgent member. This is the
/// whole reason clustering moved into Dart: the SDK's navy bubble could not
/// say that anything inside it was critical.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensure returns a bitmap for every key, rendering each once', () async {
    final icons = ClusterBubbleIcons();
    final red3 = clusterBubbleKey(fill: Colors.red, count: 3);
    final amber120 = clusterBubbleKey(fill: Colors.orange, count: 120);

    final first =
        await icons.ensure([red3, amber120, red3], devicePixelRatio: 3.0);
    expect(first.keys, unorderedEquals([red3, amber120]));
    expect(first[red3], isNotNull);

    // A second ensure is a no-op for cached keys — same instance back.
    final second = await icons.ensure([red3], devicePixelRatio: 3.0);
    expect(identical(second[red3], first[red3]), isTrue);
  });

  test('a bubble with one red member is red', () {
    expect(
      SignalUrgency.highest([
        SignalUrgency.green.code,
        SignalUrgency.amber.code,
        SignalUrgency.red.code,
        SignalUrgency.green.code,
      ]),
      SignalUrgency.red,
    );
  });

  test('amber and green together read amber', () {
    expect(
      SignalUrgency.highest(
          [SignalUrgency.green.code, SignalUrgency.amber.code]),
      SignalUrgency.amber,
    );
  });

  test('all green reads green', () {
    expect(
      SignalUrgency.highest(
          [SignalUrgency.green.code, SignalUrgency.green.code]),
      SignalUrgency.green,
    );
  });

  test('an unknown code follows its fallback, so it never reads green', () {
    // `fromCode` falls back to amber — a signal from a newer build might be
    // real, so its bubble says "needs help" rather than "fine".
    expect(
      SignalUrgency.highest([SignalUrgency.green.code, 99]),
      SignalUrgency.amber,
    );
  });

  test('order is by declaration, not by code value', () {
    // Codes are opaque identifiers. Renumbering them must not reorder the
    // scale, so the comparison goes through the enum index.
    final byIndex = SignalUrgency.values.last;
    expect(
      SignalUrgency.highest(
          SignalUrgency.values.map((u) => u.code).toList().reversed),
      byIndex,
    );
  });

  test('the count label saturates at 99+', () {
    expect(ClusterBubbleIcons.labelFor(2), '2');
    expect(ClusterBubbleIcons.labelFor(99), '99');
    expect(ClusterBubbleIcons.labelFor(100), '99+');
    expect(ClusterBubbleIcons.labelFor(1200), '99+');
  });

  test('bubble keys compare by fill and label', () {
    expect(
      clusterBubbleKey(fill: Colors.red, count: 3),
      (Colors.red, '3'),
    );
    expect(
      clusterBubbleKey(fill: Colors.red, count: 150),
      (Colors.red, '99+'),
    );
    expect(
      clusterBubbleKey(fill: Colors.red, count: 3),
      isNot(clusterBubbleKey(fill: Colors.green, count: 3)),
    );
  });

  test('a cluster is identified by its lowest member, not by where it is', () {
    // The marker id has to survive a zoom step that leaves the grouping alone,
    // or every bubble is removed and its bitmap re-uploaded for each notch of
    // the zoom control.
    MapCluster<String> clusterOf(List<String> members) => MapCluster(
          members: members,
          position: const LatLng(42.69, 23.32),
          bounds: LatLngBounds(
            southwest: const LatLng(42.69, 23.32),
            northeast: const LatLng(42.69, 23.32),
          ),
        );
    String idOf(MapCluster<String> c) =>
        MapMarkerBuilder.clusterMarkerId(c, (m) => m);

    expect(idOf(clusterOf(['c', 'a', 'b'])), 'a');
    expect(idOf(clusterOf(['b', 'c', 'a'])), 'a',
        reason: 'order within the cluster must not change the id');
    expect(idOf(clusterOf(['c', 'b'])), 'b',
        reason: 'a different membership is a different bubble');
  });
}

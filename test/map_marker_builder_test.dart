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
    final red3 = clusterBubbleKey(parts: [(Colors.red, 3)]);
    final amber120 = clusterBubbleKey(parts: [(Colors.orange, 120)]);

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

  test('bubble keys compare by ring and label', () {
    expect(
      clusterBubbleKey(parts: [(Colors.red, 3)]),
      clusterBubbleKey(parts: [(Colors.red, 3)]),
    );
    expect(clusterBubbleKey(parts: [(Colors.red, 150)]).label, '99+');
    expect(
      clusterBubbleKey(parts: [(Colors.red, 3)]),
      isNot(clusterBubbleKey(parts: [(Colors.green, 3)])),
      reason: 'a different colour is a different bitmap',
    );
    expect(
      clusterBubbleKey(parts: [(Colors.red, 3)]),
      isNot(clusterBubbleKey(parts: [(Colors.red, 2), (Colors.green, 1)])),
      reason: 'a different split is a different bitmap',
    );
  });

  group('the ring a cluster is drawn with', () {
    List<Color> coloursOf(ClusterBubbleKey k) =>
        [for (final (colour, _) in k.ring) colour];
    double sum(List<ClusterBubbleSegment> ring) =>
        ring.fold(0.0, (t, seg) => t + seg.$2);

    test('is one full circle when every member is at one urgency', () {
      final key = clusterBubbleKey(parts: [(SignalUrgency.green.color, 2)]);
      expect(key.ring, [(SignalUrgency.green.color, 360.0)]);
      expect(key.label, '2');
    });

    test('holds one arc per urgency present, most urgent first', () {
      final key = clusterBubbleKey(parts: [
        (SignalUrgency.red.color, 1),
        (SignalUrgency.green.color, 2),
      ]);
      expect(coloursOf(key),
          [SignalUrgency.red.color, SignalUrgency.green.color]);
      expect(key.ring.first.$1, SignalUrgency.red.color,
          reason: 'ring.first is the disc fill — the most urgent member');
    });

    test('always closes at exactly 360 degrees', () {
      for (final counts in [
        [1, 1], [1, 1, 1], [7, 3], [1, 40], [1, 4, 2], [13, 7, 3], [1, 1, 97],
      ]) {
        final key = clusterBubbleKey(parts: [
          for (var i = 0; i < counts.length; i++)
            (SignalUrgency.values[i % 3].color, counts[i]),
        ]);
        expect(sum(key.ring), closeTo(360.0, 1e-9), reason: '$counts');
      }
    });

    test('splits evenly when the members do', () {
      final key = clusterBubbleKey(parts: [
        (Colors.red, 1),
        (Colors.orange, 1),
        (Colors.green, 1),
      ]);
      expect([for (final (_, s) in key.ring) s], [120.0, 120.0, 120.0]);
    });

    test('lifts a tiny arc to the floor and takes it from the big one', () {
      final key =
          clusterBubbleKey(parts: [(Colors.red, 1), (Colors.green, 40)]);
      expect(key.ring.first.$2, ClusterBubbleIcons.minSweepDegrees);
      expect(key.ring.last.$2, 360.0 - ClusterBubbleIcons.minSweepDegrees,
          reason: 'the floor is paid for by the others, not added on top');
    });

    test('rounds every arc to the quantum', () {
      for (final (_, sweep) in clusterBubbleKey(
          parts: [(Colors.red, 7), (Colors.green, 5)]).ring) {
        expect(sweep % ClusterBubbleIcons.sweepQuantumDegrees, 0.0);
      }
    });

    test('the same proportions draw the same ring at any size', () {
      expect(
        clusterBubbleKey(parts: [(Colors.red, 2), (Colors.green, 2)]).ring,
        clusterBubbleKey(parts: [(Colors.red, 30), (Colors.green, 30)]).ring,
      );
    });

    test('fills the disc with the most urgent member, as the pin would', () {
      // `ring.first` is the disc fill, so this is the invariant the whole
      // ordering exists for — and it has to keep agreeing with
      // `SignalUrgency.highest`, which is where the severity ordering lives.
      final codes = [
        SignalUrgency.green.code,
        SignalUrgency.amber.code,
        SignalUrgency.red.code,
        SignalUrgency.green.code,
      ];
      final counts = <SignalUrgency, int>{};
      for (final code in codes) {
        final u = SignalUrgency.fromCode(code);
        counts[u] = (counts[u] ?? 0) + 1;
      }
      final key = clusterBubbleKey(parts: [
        for (final u in SignalUrgency.values.reversed)
          if (counts[u] != null) (u.color, counts[u]!),
      ]);
      expect(key.ring.first.$1, SignalUrgency.highest(codes).color);
      expect(key.ring.first.$1, SignalUrgency.red.color);
    });

    test('a clinic cluster is one plain ring of clinic blue', () {
      final key = clusterBubbleKey(parts: [(MapMarkerBuilder.clinicBlue, 3)]);
      expect(key.ring, [(MapMarkerBuilder.clinicBlue, 360.0)]);
      expect(key.label, '3');
    });
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

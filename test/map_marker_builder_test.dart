import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/utils/cluster_bubble_icons.dart';
import 'package:help_a_paw/src/utils/map_marker_builder.dart';

/// A cluster bubble is the colour of its most urgent member. This is the
/// whole reason clustering moved into Dart: the SDK's navy bubble could not
/// say that anything inside it was critical.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ensure renders each key once and get returns it', () async {
    final icons = ClusterBubbleIcons();
    final red3 = ClusterBubbleKey.count(fill: Colors.red, count: 3);
    final amber120 = ClusterBubbleKey.count(fill: Colors.orange, count: 120);
    expect(icons.get(red3), isNull);

    await icons.ensure([red3, amber120, red3], devicePixelRatio: 3.0);
    final first = icons.get(red3);
    expect(first, isNotNull);
    expect(icons.get(amber120), isNotNull);

    // A second ensure is a no-op for cached keys — same instance back.
    await icons.ensure([red3], devicePixelRatio: 3.0);
    expect(identical(icons.get(red3), first), isTrue);
  });

  test('a bubble with one red member is red', () {
    expect(
      MapMarkerBuilder.highestUrgency([
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
      MapMarkerBuilder.highestUrgency(
          [SignalUrgency.green.code, SignalUrgency.amber.code]),
      SignalUrgency.amber,
    );
  });

  test('all green reads green', () {
    expect(
      MapMarkerBuilder.highestUrgency(
          [SignalUrgency.green.code, SignalUrgency.green.code]),
      SignalUrgency.green,
    );
  });

  test('an unknown code follows its fallback, so it never reads green', () {
    // `fromCode` falls back to amber — a signal from a newer build might be
    // real, so its bubble says "needs help" rather than "fine".
    expect(
      MapMarkerBuilder.highestUrgency([SignalUrgency.green.code, 99]),
      SignalUrgency.amber,
    );
  });

  test('order is by declaration, not by code value', () {
    // Codes are opaque identifiers. Renumbering them must not reorder the
    // scale, so the comparison goes through the enum index.
    final byIndex = SignalUrgency.values.last;
    expect(
      MapMarkerBuilder.highestUrgency(
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
      const ClusterBubbleKey(fill: Colors.red, label: '3'),
      const ClusterBubbleKey(fill: Colors.red, label: '3'),
    );
    expect(
      ClusterBubbleKey.count(fill: Colors.red, count: 150),
      const ClusterBubbleKey(fill: Colors.red, label: '99+'),
    );
    expect(
      const ClusterBubbleKey(fill: Colors.red, label: '3'),
      isNot(const ClusterBubbleKey(fill: Colors.green, label: '3')),
    );
  });
}

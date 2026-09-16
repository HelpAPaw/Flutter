import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/utils/cluster_bubble_icons.dart';

/// Every [ClusterBubbleStyle] has to render. The styles the app is not
/// currently set to are the ones worth guarding: nothing else exercises them,
/// so without this a change to the painter could break a style silently and it
/// would only be found by someone switching to it months later.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final chosen = ClusterBubbleIcons.style;
  tearDown(() => ClusterBubbleIcons.style = chosen);

  final mixed = clusterBubbleKey(parts: [
    (SignalUrgency.red.color, 1),
    (SignalUrgency.amber.color, 4),
    (SignalUrgency.green.color, 7),
  ]);
  final single = clusterBubbleKey(parts: [(SignalUrgency.green.color, 2)]);

  for (final style in ClusterBubbleStyle.values) {
    test('$style renders a bitmap for a mixed and a single-urgency cluster',
        () async {
      ClusterBubbleIcons.style = style;
      final icons = ClusterBubbleIcons();
      final rendered =
          await icons.ensure([mixed, single], devicePixelRatio: 3.0);
      expect(rendered[mixed], isNotNull);
      expect(rendered[single], isNotNull);
    });

    test('$style leaves room around the disc for what it draws there', () {
      // A bitmap is `disc + 2 * pad` wide, so anything the style draws outside
      // the disc — the ring, or the shadow a ringless one needs instead — is
      // clipped square if the pad does not cover it.
      expect(style.pad, greaterThanOrEqualTo(style.ringWidth));
      if (!style.hasRing) {
        expect(style.pad, greaterThanOrEqualTo(3 * ClusterBubbleIcons.shadowSigma),
            reason: 'a Gaussian is not spent until about three sigma');
      }
    });

    test('$style inks the count legibly against its own disc', () {
      final urgency = SignalUrgency.red.color;
      expect(style.ink(urgency), isNot(style.discFill(urgency)),
          reason: 'ink the same colour as the disc would be invisible');
    });
  }

  test('the cache evicts what is off screen and still answers for what is on',
      () async {
    // Keying by the ring means the number of distinct bitmaps grows with the
    // data, not with the palette, so the cache has to be bounded. It evicts by
    // working set, so what this call asks for survives its own eviction.
    final icons = ClusterBubbleIcons();
    final keys = [
      for (var i = 1; i <= ClusterBubbleIcons.maxCachedBitmaps + 1; i++)
        clusterBubbleKey(parts: [
          (SignalUrgency.red.color, i),
          (SignalUrgency.green.color, 1),
        ]),
    ];
    for (final key in keys) {
      final got = await icons.ensure([key, single], devicePixelRatio: 1.0);
      expect(got[key], isNotNull);
      expect(got[single], isNotNull,
          reason: 'a key dropped mid-call must still come back');
    }
  });

  test('the style the app ships with keeps the most urgent member on the disc',
      () {
    // The invariant the whole encoding rests on: a cluster holding one critical
    // signal is red, exactly as that signal's pin would be. `colouredPie` is
    // the one style that gives this up, so it must not be what ships unnoticed.
    expect(chosen.isPie, isFalse);
    expect(chosen.isWhite, isFalse);
  });
}

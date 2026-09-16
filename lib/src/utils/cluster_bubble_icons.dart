import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// One arc of a bubble's ring: a colour and how much of the circle it takes.
typedef ClusterBubbleSegment = (Color color, double sweepDegrees);

/// How a cluster bubble is drawn.
///
/// The choice is between two things a bubble can say and cannot both say
/// loudest: **the worst thing inside it** — a saturated disc, read across a
/// whole screen at once — and **how its members split between urgencies** — a
/// ring of arcs, read one bubble at a time. Each value is a different answer,
/// and [ClusterBubbleIcons.style] picks one. Everything that draws a bubble
/// asks these getters rather than deciding for itself, so the marker bitmap and
/// the legend's copy of it cannot disagree.
enum ClusterBubbleStyle {
  /// Saturated disc in the most urgent member's colour, ring of arcs around it.
  colouredDisc(ringWidth: ClusterBubbleIcons.haloWidth),

  /// Disc is a pie of the members' urgencies, ring of arcs around it. Says the
  /// proportions twice, and loses the "worst thing here" read to the most
  /// *common* urgency.
  colouredPie(ringWidth: ClusterBubbleIcons.haloWidth, isPie: true),

  /// White disc, near-black count, wide ring of arcs carrying the split.
  whiteRing(
      ringWidth: ClusterBubbleIcons.whiteDiscRingWidth, isWhite: true),

  /// White disc, near-black count, no ring. Says only how many — the urgency
  /// encoding is gone.
  whitePlain(isWhite: true),

  /// White disc, no ring, count inked in the most urgent member's colour. That
  /// count is then the only coloured mark, at 2.2:1 contrast for amber.
  whiteUrgencyInk(isWhite: true, inkIsUrgency: true),

  /// White disc, no ring, outlined in the most urgent member's colour — and the
  /// count inked in it too, so the contrast [ClusterBubbleIcons.inkFor] warns
  /// about applies here as much as to [whiteUrgencyInk].
  whiteUrgencyBorder(
      isWhite: true, inkIsUrgency: true, edgeWidth: 2.5, edgeIsUrgency: true);

  const ClusterBubbleStyle({
    this.ringWidth = 0,
    this.isWhite = false,
    this.isPie = false,
    this.inkIsUrgency = false,
    this.edgeWidth = ClusterBubbleIcons.hairlineWidth,
    this.edgeIsUrgency = false,
  });

  /// Width of the ring of arcs, or zero for a style that draws none.
  final double ringWidth;

  /// Whether the disc is white rather than a colour of its own.
  final bool isWhite;

  /// Whether the disc is divided into wedges.
  final bool isPie;

  /// Whether the count is inked in the most urgent member's colour.
  final bool inkIsUrgency;

  /// Width of the line around the disc.
  final double edgeWidth;

  /// Whether that line is the most urgent member's colour rather than the
  /// default for the disc it sits on.
  final bool edgeIsUrgency;

  /// Whether a ring of arcs surrounds the disc — the only thing that carries
  /// the split between urgencies. Derived, so it cannot disagree with
  /// [ringWidth].
  bool get hasRing => ringWidth > 0;

  /// Space the bitmap leaves around the disc for whatever the style draws
  /// there: the ring, or the shadow a ringless disc needs instead.
  double get pad => hasRing ? ringWidth : ClusterBubbleIcons.shadowPad;

  /// The disc's fill, for a bubble whose most urgent member is [urgency].
  Color discFill(Color urgency) => isWhite
      ? Colors.white // theme-independent: over map tiles
      : urgency;

  /// The line around the disc: white to separate a saturated disc from the map,
  /// the urgency colour where that is the only place colour appears, and
  /// otherwise a hairline to keep a white disc off a white street.
  Color edgeColor(Color urgency) => edgeIsUrgency
      ? urgency
      : isWhite
          ? const Color(0x33000000) // theme-independent: over map tiles
          : Colors.white; // theme-independent: over map tiles

  /// The colour the count is written in.
  ///
  /// Over a saturated fill white is the ink that reads in both light and dark
  /// mode. Over a white disc it is near-black, unless the style has nothing
  /// else carrying colour and leans on the count to do it — which costs
  /// contrast: amber on white is 2.2:1, under every WCAG threshold.
  Color ink(Color urgency) => inkIsUrgency
      ? urgency
      : isWhite
          ? const Color(0xFF1F1F1F) // theme-independent: over map tiles
          : Colors.white; // theme-independent: over map tiles
}

/// What distinguishes one bubble bitmap from another: the ring drawn around it
/// and the number printed on it.
///
/// Keyed by what is *drawn* rather than by what it is drawn from — quantised
/// sweeps, and a label that saturates at "99+". Two clusters with the same
/// proportions and the same label render the same pixels, so they share one
/// bitmap however different their membership is.
@immutable
class ClusterBubbleKey {
  const ClusterBubbleKey({required this.ring, required this.label})
      : assert(ring.length > 0, 'a bubble with no arcs has nothing to draw');

  /// The arcs, in draw order, most urgent first.
  ///
  /// [ring].first is also the disc fill, so "a bubble is the colour of its most
  /// urgent member" needs no second field: order already carries it. Never
  /// empty for a key that reaches a marker — a cluster has two members or it is
  /// not a cluster.
  final List<ClusterBubbleSegment> ring;

  /// The count printed in the middle. See [ClusterBubbleIcons.labelFor].
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClusterBubbleKey &&
          other.label == label &&
          listEquals(other.ring, ring);

  @override
  int get hashCode => Object.hash(Object.hashAll(ring), label);

  @override
  String toString() => 'ClusterBubbleKey($label, $ring)';
}

/// The bubble for a cluster made of [parts]: (colour, member count) in draw
/// order, most urgent first. The label is their sum.
///
/// A layer with nothing to say about composition — the clinics — passes a
/// single part and gets a plain ring of one colour.
ClusterBubbleKey clusterBubbleKey({required List<(Color, int)> parts}) {
  var total = 0;
  for (final (_, count) in parts) {
    total += count;
  }
  return ClusterBubbleKey(
    ring: ClusterBubbleIcons.ringOf(parts),
    label: ClusterBubbleIcons.labelFor(total),
  );
}

/// Draws and caches the marker bitmaps for cluster bubbles.
///
/// A bubble is a disc with the member count on it, and — depending on [style] —
/// a ring of arcs saying how its members split between urgencies. The disc is
/// the layer's headline colour: the most urgent member for signals, the clinic
/// blue for clinics. A layer that passes one part gets a ring of one colour,
/// which is what a clinic bubble is.
///
/// Marker icons have to be bitmaps, and rendering one is asynchronous
/// (`Picture.toImage`), so [ensure] renders whatever a marker set is about to
/// need and hands back the bitmaps for it.
class ClusterBubbleIcons {
  final Map<ClusterBubbleKey, BitmapDescriptor> _cache = {};

  /// Bitmaps kept before the cache is dropped.
  ///
  /// The old key was `(fill, label)` — three colours by a hundred labels, a few
  /// hundred entries at worst, so never worth bounding. Keying by the ring as
  /// well makes the ceiling the number of distinct *splits*, which grows with
  /// the data rather than with the palette: cluster "12" as 1r/4a/7g and as
  /// 2r/3a/7g are different bitmaps. A map screen holds one of these for its
  /// whole life, so without a bound a long session in a dense city accumulates
  /// PNGs indefinitely.
  ///
  /// Far above what a screenful needs (a few dozen bubbles), so in normal use
  /// this never trips; when it does, dropping the lot costs a re-render of
  /// whatever is on screen and nothing else.
  static const int maxCachedBitmaps = 512;

  /// Which bubble style is in force. One word to change.
  ///
  /// A field rather than a `const` so the styles it does not select are still
  /// reachable: as a const, every other branch below would be code no test can
  /// run and nothing would notice it rotting. Production never assigns it —
  /// only the tests that render each style do, and they put it back.
  static ClusterBubbleStyle style = ClusterBubbleStyle.colouredDisc;

  /// Largest count printed as a number; anything above reads "99+".
  static const int maxLabelledCount = 99;

  /// Opacity of the ring around the disc, out of 255.
  ///
  /// The ring carries meaning, and green against amber in a 5px band is not
  /// tellable apart until the arcs are close to opaque.
  static const int ringAlpha = 190;

  /// Width of the line around a saturated disc, separating it from the arcs.
  static const double ringWidth = 2.0;

  /// Width of the line around a white disc — enough to hold an edge against a
  /// white street, little enough not to read as a border.
  static const double hairlineWidth = 0.8;

  /// Weight of the count. Heavy enough to read at 14px over map tiles.
  static const FontWeight labelWeight = FontWeight.w700;

  /// Width of the ring of arcs around the disc, in logical pixels.
  static const double haloWidth = 5.0;

  /// Ring width when the disc is white: the ring is then the only thing
  /// carrying colour, so it is given room to do it.
  static const double whiteDiscRingWidth = 8.0;

  /// Blur sigma of the shadow under a ringless disc.
  static const double shadowSigma = 2.0;

  /// Room a shadow needs outside the disc, for styles that carry no ring and so
  /// have nothing else lifting them off the map.
  ///
  /// Three sigma, because a Gaussian is all but spent by then: at the 3.0 this
  /// used to be, the blur ran past the edge of the bitmap and the shadow was
  /// cut off square on all four sides.
  static const double shadowPad = 3 * shadowSigma;

  /// Outline under the count, for the pie disc where the ink sits over wedges
  /// of three different colours.
  static const List<Shadow> labelShadows = [
    Shadow(color: Color(0x99000000), blurRadius: 2),
  ];

  /// Smallest sweep a part with any members at all is drawn with.
  ///
  /// One red among forty greens is the most important thing about that cluster
  /// and its honest 9° would be a scratch, so a small part is lifted to this and
  /// the difference is taken from the others in proportion. Always feasible:
  /// there are at most three urgencies, and 3 × 15° is a twelfth of the circle.
  static const double minSweepDegrees = 15.0;

  /// Sweeps are rounded to a multiple of this before they reach the cache key.
  ///
  /// The bitmap cache is the point: at 5° nobody can see the difference between
  /// 7 of 12 and 8 of 13, and rounding lets both use one bitmap instead of one
  /// per distinct membership. Same reasoning as [labelFor]'s "99+".
  static const double sweepQuantumDegrees = 5.0;

  static String labelFor(int count) =>
      count > maxLabelledCount ? '$maxLabelledCount+' : '$count';

  /// Logical diameter of the solid disc: grows a little with the label so
  /// "99+" is not squeezed against the edge.
  static double discDiameter(String label) => 34.0 + 4.0 * (label.length - 1);

  /// The colour the count is written in. See [ClusterBubbleStyle.ink].
  static Color inkFor(Color urgency) => style.ink(urgency);

  /// The arcs for [parts]: sweeps proportional to the counts, each non-empty
  /// part at least [minSweepDegrees], each quantised to [sweepQuantumDegrees],
  /// and the whole thing summing to exactly 360°.
  ///
  /// Pure and public so the legend can draw the same ring from the same numbers
  /// — the legend redraws the bubble in widgets, and the two must not be able to
  /// drift apart.
  static List<ClusterBubbleSegment> ringOf(List<(Color, int)> parts) {
    // Reuse the caller's list unless something has to be dropped: no production
    // caller ever passes an empty part, so the copy is usually pure waste.
    final present = parts.any((p) => p.$2 <= 0)
        ? [
            for (final part in parts)
              if (part.$2 > 0) part,
          ]
        : parts;
    if (present.isEmpty) return const [];

    var total = 0;
    for (final (_, count) in present) {
      total += count;
    }
    final sweeps = [for (final (_, count) in present) 360.0 * count / total];

    // Lift every part that falls under the floor, and take what that costs out
    // of the parts above it in proportion to how far above they are — so the
    // big slices shrink and no lifted slice is pushed back under. With at most
    // three parts summing to 360, anything below the floor guarantees something
    // above it, so `surplus` is never zero when `deficit` is not.
    var deficit = 0.0, surplus = 0.0;
    for (final sweep in sweeps) {
      if (sweep < minSweepDegrees) {
        deficit += minSweepDegrees - sweep;
      } else {
        surplus += sweep - minSweepDegrees;
      }
    }
    if (deficit > 0) {
      for (var i = 0; i < sweeps.length; i++) {
        sweeps[i] = sweeps[i] < minSweepDegrees
            ? minSweepDegrees
            : sweeps[i] - deficit * (sweeps[i] - minSweepDegrees) / surplus;
      }
    }

    // Quantise, then put the rounding residue on the largest arc: it is the one
    // where a few degrees are least visible, and it keeps the ring closed.
    var used = 0.0, largest = 0;
    for (var i = 0; i < sweeps.length; i++) {
      sweeps[i] =
          (sweeps[i] / sweepQuantumDegrees).round() * sweepQuantumDegrees;
      used += sweeps[i];
      if (sweeps[i] > sweeps[largest]) largest = i;
    }
    sweeps[largest] += 360.0 - used;

    return [
      for (var i = 0; i < present.length; i++) (present[i].$1, sweeps[i]),
    ];
  }

  /// Render whatever [keys] are not cached yet, and return the bitmap for every
  /// one of them.
  ///
  /// Returning the bitmaps rather than leaving the caller to look them up again
  /// is what makes the marker builders total: they cannot be handed a cluster
  /// whose bubble is missing. [devicePixelRatio] is the screen's, so a bubble
  /// is crisp on a 3× phone and not oversized on a 1× tablet.
  Future<Map<ClusterBubbleKey, BitmapDescriptor>> ensure(
    Iterable<ClusterBubbleKey> keys, {
    required double devicePixelRatio,
  }) async {
    final result = <ClusterBubbleKey, BitmapDescriptor>{};
    final missing = <ClusterBubbleKey>{};
    for (final key in keys) {
      final cached = _cache[key];
      if (cached != null) {
        result[key] = cached;
      } else {
        missing.add(key);
      }
    }

    // Over budget: drop what this screen is not asking for, rather than
    // everything. `keys` is the working set by construction — the map screen
    // passes exactly the bubbles it is about to draw — so nothing currently
    // visible is thrown away and re-rendered.
    if (_cache.length + missing.length > maxCachedBitmaps) {
      _cache.removeWhere((key, _) => !result.containsKey(key));
    }

    // Independent renders, each two async round trips (raster, then a PNG
    // encode) — sequentially that is the whole batch's latency before the first
    // bubble appears.
    final rendered = await Future.wait(
      missing.map((key) => _render(key, devicePixelRatio)),
    );
    var i = 0;
    for (final key in missing) {
      // Into `result` as well as the cache: a concurrent `ensure` may evict
      // during the await, and what this call returns has to be total.
      _cache[key] = result[key] = rendered[i++];
    }
    return result;
  }

  static Future<BitmapDescriptor> _render(
    ClusterBubbleKey key,
    double dpr,
  ) async {
    final disc = discDiameter(key.label);
    final size = disc + 2 * style.pad;
    final px = (size * dpr).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);

    paintBubble(
      canvas,
      key,
      centre: Offset(size / 2, size / 2),
      discDiameter: disc,
    );

    // Both handles are native resources, and neither is freed by going out of
    // scope — they wait on GC finalization.
    final picture = recorder.endRecording();
    final image = await picture.toImage(px, px);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: dpr,
    );
  }

  /// Paint a whole bubble — ring, disc, edge and count — centred on [centre].
  ///
  /// One routine for the marker bitmap and the legend, so a restyle cannot
  /// reach one and miss the other. [drawLabel] is false for the legend, which
  /// overlays the count as a widget so it follows the reader's text scaling.
  static void paintBubble(
    Canvas canvas,
    ClusterBubbleKey key, {
    required Offset centre,
    required double discDiameter,
    double? ringWidthOverride,
    double fontSize = 14,
    bool drawLabel = true,
  }) {
    if (key.ring.isEmpty) return;
    final urgency = key.ring.first.$1;

    if (style.hasRing) {
      paintRing(canvas, key.ring,
          centre: centre,
          discDiameter: discDiameter,
          width: ringWidthOverride ?? style.ringWidth);
    } else {
      // Nothing around the disc to lift it off the map, so it casts a shadow
      // instead — without one a white bubble dissolves into a white street.
      canvas.drawCircle(
          centre.translate(0, 0.8),
          discDiameter / 2,
          Paint()
            ..color = const Color(0x40000000) // theme-independent: over tiles
            ..maskFilter =
                const MaskFilter.blur(BlurStyle.normal, shadowSigma));
    }

    if (style.isPie) {
      paintPie(canvas, key.ring, centre: centre, discDiameter: discDiameter);
    } else {
      canvas.drawCircle(
          centre, discDiameter / 2, Paint()..color = style.discFill(urgency));
    }

    // The line around the disc, from the style's own spec — see
    // [ClusterBubbleStyle.edgeColor]. Inset by half its width unless it is a
    // hairline, so a thick edge sits inside the disc rather than over the ring.
    final edgeWidth = style.isWhite ? style.edgeWidth : ringWidth;
    canvas.drawCircle(
      centre,
      discDiameter / 2 - (edgeWidth > 1 ? edgeWidth / 2 : 0),
      Paint()
        ..color = style.edgeColor(urgency)
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth,
    );

    if (!drawLabel) return;
    final text = TextPainter(
      text: TextSpan(
        text: key.label,
        style: TextStyle(
          color: inkFor(urgency),
          fontSize: fontSize,
          fontWeight: labelWeight,
          // On a pie the count sits over whichever wedges happen to be under
          // it, so it needs an edge of its own to stay legible against amber
          // and green alike.
          shadows: style.isPie ? labelShadows : null,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - Offset(text.width / 2, text.height / 2));
  }

  /// Fill the disc as a pie of [ring]'s wedges, in the ring's own order and
  /// sweeps.
  static void paintPie(
    Canvas canvas,
    List<ClusterBubbleSegment> ring, {
    required Offset centre,
    required double discDiameter,
  }) =>
      _paintArcs(
        canvas,
        ring,
        box: Rect.fromCircle(center: centre, radius: discDiameter / 2),
        paint: Paint(),
        alpha: 255,
      );

  /// Paint [ring] as a band of arcs just outside a disc of [discDiameter].
  static void paintRing(
    Canvas canvas,
    List<ClusterBubbleSegment> ring, {
    required Offset centre,
    required double discDiameter,
    double width = haloWidth,
  }) =>
      _paintArcs(
        canvas,
        ring,
        // Centred on the band, so the stroke fills it exactly.
        box: Rect.fromCircle(
            center: centre, radius: discDiameter / 2 + width / 2),
        paint: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
        alpha: ringAlpha,
      );

  /// Walk [ring] clockwise from twelve o'clock, drawing each segment into
  /// [box]. Written once so the wedges and the band cannot start at different
  /// angles or run in different directions.
  ///
  /// [paint] is reused across segments — only its colour changes — and its
  /// style decides whether a segment is a filled wedge or a stroked arc.
  static void _paintArcs(
    Canvas canvas,
    List<ClusterBubbleSegment> ring, {
    required Rect box,
    required Paint paint,
    required int alpha,
  }) {
    final filled = paint.style == PaintingStyle.fill;
    var start = -math.pi / 2; // twelve o'clock
    for (final (color, sweepDegrees) in ring) {
      final sweep = _radians(sweepDegrees);
      paint.color = alpha == 255 ? color : color.withAlpha(alpha);
      canvas.drawArc(box, start, sweep, filled, paint);
      start += sweep;
    }
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
}

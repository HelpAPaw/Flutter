import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// What distinguishes one bubble bitmap from another: its fill and the number
/// printed on it.
///
/// Keyed by the label rather than the count because the label saturates at
/// "99+", so a city's worth of distinct counts costs at most a hundred small
/// images per colour.
typedef ClusterBubbleKey = (Color fill, String label);

ClusterBubbleKey clusterBubbleKey({required Color fill, required int count}) =>
    (fill, ClusterBubbleIcons.labelFor(count));

/// Draws and caches the marker bitmaps for cluster bubbles.
///
/// A bubble is a filled circle with a translucent halo and the member count
/// in white. The fill is whatever the layer says it means — the most urgent
/// member's colour for signals, the clinic blue for clinics — so the same
/// painter serves both and the two can never be confused for one another.
///
/// Marker icons have to be bitmaps, and rendering one is asynchronous
/// (`Picture.toImage`), so [ensure] renders whatever a marker set is about to
/// need and hands back the bitmaps for it.
class ClusterBubbleIcons {
  final Map<ClusterBubbleKey, BitmapDescriptor> _cache = {};

  /// Largest count printed as a number; anything above reads "99+".
  static const int maxLabelledCount = 99;

  /// Opacity of the halo around the disc, out of 255.
  static const int haloAlpha = 90;

  /// Width of the white ring separating disc from halo, in logical pixels.
  static const double ringWidth = 2.0;

  /// Weight of the count. Heavy enough to read at 14px over map tiles.
  static const FontWeight labelWeight = FontWeight.w700;

  /// Extra radius of the translucent halo around the disc.
  static const double haloWidth = 5.0;

  static String labelFor(int count) =>
      count > maxLabelledCount ? '$maxLabelledCount+' : '$count';

  /// Logical diameter of the solid disc: grows a little with the label so
  /// "99+" is not squeezed against the edge.
  static double discDiameter(String label) => 34.0 + 4.0 * (label.length - 1);

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
    final missing = {
      for (final key in keys)
        if (!_cache.containsKey(key)) key,
    };
    // Independent renders, each two async round trips (raster, then a PNG
    // encode) — sequentially that is the whole batch's latency before the first
    // bubble appears.
    final rendered = await Future.wait(
      missing.map((key) => _render(key, devicePixelRatio)),
    );
    var i = 0;
    for (final key in missing) {
      _cache[key] = rendered[i++];
    }
    return {for (final key in keys) key: _cache[key]!};
  }

  static Future<BitmapDescriptor> _render(
    ClusterBubbleKey key,
    double dpr,
  ) async {
    final (fill, label) = key;
    final disc = discDiameter(label);
    final size = disc + 2 * haloWidth;
    final px = (size * dpr).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final centre = Offset(size / 2, size / 2);

    canvas.drawCircle(centre, size / 2, Paint()..color = fill.withAlpha(haloAlpha));
    canvas.drawCircle(centre, disc / 2, Paint()..color = fill);
    canvas.drawCircle(
      centre,
      disc / 2,
      Paint()
        ..color = Colors.white // theme-independent: over map tiles
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth,
    );

    final text = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          // Painted over map tiles onto a saturated fill, on which white is
          // the ink that reads in both light and dark mode.
          color: Colors.white, // theme-independent
          fontSize: 14,
          fontWeight: labelWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - Offset(text.width / 2, text.height / 2));

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
}

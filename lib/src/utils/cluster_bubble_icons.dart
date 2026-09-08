import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Draws and caches the marker bitmaps for cluster bubbles.
///
/// A bubble is a filled circle with a translucent halo and the member count
/// in white. The fill is whatever the layer says it means — the most urgent
/// member's colour for signals, the clinic blue for clinics — so the same
/// painter serves both and the two can never be confused for one another.
///
/// Marker icons have to be bitmaps, and rendering one is asynchronous
/// (`Picture.toImage`), so bubbles are produced ahead of the marker set with
/// [ensure] and read synchronously with [get]. The cache is keyed by fill and
/// label, not by count: past 99 the label saturates, so a city's worth of
/// distinct counts costs at most a hundred small images per colour.
class ClusterBubbleIcons {
  final Map<ClusterBubbleKey, BitmapDescriptor> _cache = {};

  /// Largest count printed as a number; anything above reads "99+".
  static const int maxLabelledCount = 99;

  static String labelFor(int count) =>
      count > maxLabelledCount ? '$maxLabelledCount+' : '$count';

  BitmapDescriptor? get(ClusterBubbleKey key) => _cache[key];

  /// Render every key not yet cached. [devicePixelRatio] is the screen's, so a
  /// bubble is crisp on a 3× phone and not oversized on a 1× tablet.
  Future<void> ensure(
    Iterable<ClusterBubbleKey> keys, {
    required double devicePixelRatio,
  }) async {
    for (final key in keys.toSet()) {
      if (_cache.containsKey(key)) continue;
      _cache[key] = await _render(key, devicePixelRatio);
    }
  }

  /// Logical diameter of the solid disc: grows a little with the label so
  /// "99+" is not squeezed against the edge.
  static double discDiameter(String label) => 34.0 + 4.0 * (label.length - 1);

  /// Extra radius of the translucent halo around the disc.
  static const double haloWidth = 5.0;

  static Future<BitmapDescriptor> _render(
    ClusterBubbleKey key,
    double dpr,
  ) async {
    final disc = discDiameter(key.label);
    final size = disc + 2 * haloWidth;
    final px = (size * dpr).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final centre = Offset(size / 2, size / 2);

    canvas.drawCircle(centre, size / 2, Paint()..color = key.fill.withAlpha(90));
    canvas.drawCircle(centre, disc / 2, Paint()..color = key.fill);
    canvas.drawCircle(
      centre,
      disc / 2,
      Paint()
        ..color = Colors.white // theme-independent: over map tiles
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final text = TextPainter(
      text: TextSpan(
        text: key.label,
        style: const TextStyle(
          // Painted over map tiles onto a saturated fill, on which white is
          // the ink that reads in both light and dark mode.
          color: Colors.white, // theme-independent
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(
      canvas,
      centre - Offset(text.width / 2, text.height / 2),
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
}

/// What distinguishes one bubble bitmap from another.
@immutable
class ClusterBubbleKey {
  const ClusterBubbleKey({required this.fill, required this.label});

  ClusterBubbleKey.count({required this.fill, required int count})
      : label = ClusterBubbleIcons.labelFor(count);

  final Color fill;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is ClusterBubbleKey && other.fill == fill && other.label == label;

  @override
  int get hashCode => Object.hash(fill, label);
}

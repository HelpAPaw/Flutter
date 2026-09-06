import 'dart:ui' show Offset, Size;

/// Where the signal bubble goes for a pin at [anchor].
///
/// Pure geometry, deliberately separated from the widget that consumes it. All
/// the interesting cases here are edge cases — a pin near the side of the map,
/// a pin too close to the top for the bubble to fit above it, a pin panned off
/// screen entirely — and inside a build method none of them can be tested
/// except by hand on a device.
class BubbleLayout {
  const BubbleLayout({
    required this.left,
    required this.anchorY,
    required this.above,
    required this.tailAlignment,
  });

  /// x of the bubble's left edge, in the map box's coordinate space.
  final double left;

  /// y the bubble is pinned at: its **bottom** edge when [above], its top edge
  /// otherwise. The bubble's height is unknown until it lays out, which is why
  /// this is an edge rather than a rect.
  final double anchorY;

  /// Whether the bubble sits above the pin (tail pointing down) or below it.
  final bool above;

  /// Where along the bubble's width the tail sits, as an `Alignment` x from -1
  /// to 1. Zero whenever the bubble is centred on its pin, which is the normal
  /// case; only a bubble clamped against the side of the map needs it.
  final double tailAlignment;
}

/// Lay the bubble out for a pin at [anchor], or return null when the pin is
/// outside [viewport] and the bubble should not be drawn at all.
///
/// [anchor] is the pin's tip. [maxBubbleHeight] only decides above-vs-below, so
/// an over-estimate is safe: it flips a bubble that would just have fitted,
/// which nobody can see, where an under-estimate clips the bubble off the top
/// of the map.
BubbleLayout? bubbleLayoutFor({
  required Offset anchor,
  required Size viewport,
  required double bubbleWidth,
  required double maxBubbleHeight,
  required double pinHeight,
  required double gap,
  required double edgeInset,
}) {
  // An open bubble whose pin has been panned away would otherwise sit clamped
  // against the edge with its tail pointing at bare map, still tappable, still
  // navigating to a signal that is nowhere on screen.
  if (anchor.dx < 0 ||
      anchor.dx > viewport.width ||
      anchor.dy < 0 ||
      anchor.dy > viewport.height) {
    return null;
  }

  final topOfPin = anchor.dy - pinHeight - gap;
  final above = topOfPin - maxBubbleHeight >= 0;

  final maxLeft = viewport.width - bubbleWidth - edgeInset;
  final left = maxLeft <= edgeInset
      // Map narrower than the bubble: centre it and give up on pointing at
      // anything.
      ? (viewport.width - bubbleWidth) / 2
      : (anchor.dx - bubbleWidth / 2).clamp(edgeInset, maxLeft);

  // Stops short of the rounded corners, where a tail reads as a chipped edge
  // rather than a pointer.
  final tailAlignment =
      (((anchor.dx - left) / bubbleWidth) * 2 - 1).clamp(-0.8, 0.8);

  return BubbleLayout(
    left: left,
    anchorY: above ? topOfPin : anchor.dy + gap,
    above: above,
    tailAlignment: tailAlignment,
  );
}

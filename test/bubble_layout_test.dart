import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/utils/bubble_layout.dart';

/// The signal bubble's placement is all edge cases — a pin against the side of
/// the map, a pin too near the top for the bubble to fit above it, a pin panned
/// off screen — and while this arithmetic lived inside a build method the only
/// way to check any of it was to tap pins on a device.
void main() {
  const viewport = Size(400, 800);
  const width = 260.0;
  const pinHeight = 29.0;
  const gap = 6.0;
  const inset = 8.0;

  BubbleLayout? layoutAt(
    double x,
    double y, {
    double maxHeight = 176,
    Size size = viewport,
  }) =>
      bubbleLayoutFor(
        anchor: Offset(x, y),
        viewport: size,
        bubbleWidth: width,
        maxBubbleHeight: maxHeight,
        pinHeight: pinHeight,
        gap: gap,
        edgeInset: inset,
      );

  test('a pin with room above gets the bubble above it, centred', () {
    final l = layoutAt(200, 600)!;
    expect(l.above, isTrue);
    expect(l.left, 200 - width / 2);
    // Its bottom edge sits a gap clear of the pin's head, so the tail reads as
    // a pointer rather than a notch cut out of the pin.
    expect(l.anchorY, 600 - pinHeight - gap);
    expect(l.tailAlignment, 0);
  });

  test('a pin near the top flips the bubble below it', () {
    final l = layoutAt(200, 150)!;
    expect(l.above, isFalse);
    expect(l.anchorY, 150 + gap);
  });

  test('the flip threshold follows the height it is given', () {
    // Exactly enough room, then one pixel less.
    expect(layoutAt(200, 176 + pinHeight + gap)!.above, isTrue);
    expect(layoutAt(200, 176 + pinHeight + gap - 1)!.above, isFalse);
    // A taller bubble — bigger system font — flips sooner.
    expect(layoutAt(200, 300, maxHeight: 176)!.above, isTrue);
    expect(layoutAt(200, 300, maxHeight: 300)!.above, isFalse);
  });

  test('a bubble clamped against an edge keeps its tail on the pin', () {
    final left = layoutAt(60, 600)!;
    expect(left.left, inset, reason: 'clamped to the left inset');
    // The pin is 52px right of the bubble's left edge, so the tail sits toward
    // the left end of a 260-wide bubble: (52 / 260) * 2 - 1.
    expect(left.tailAlignment, closeTo((52 / width) * 2 - 1, 0.0001));

    final right = layoutAt(340, 600)!;
    expect(right.left, viewport.width - width - inset);
    expect(right.tailAlignment, closeTo(((340 - 132) / width) * 2 - 1, 0.0001));
  });

  test('the tail stops short of the rounded corners', () {
    // Hard against the very edge the tail would otherwise sit on the corner
    // radius, where it reads as a chipped edge rather than a pointer.
    expect(layoutAt(0, 600)!.tailAlignment, -0.8);
    expect(layoutAt(400, 600)!.tailAlignment, 0.8);
  });

  test('a pin panned off the map gets no bubble at all', () {
    // Otherwise the clamp parks the card against the edge, tail pointing at
    // bare map, still tappable, still navigating to a signal nobody can see.
    expect(layoutAt(-1, 600), isNull);
    expect(layoutAt(401, 600), isNull);
    expect(layoutAt(200, -1), isNull);
    expect(layoutAt(200, 801), isNull);
    // The boundary itself still counts as on screen.
    expect(layoutAt(0, 0), isNotNull);
    expect(layoutAt(400, 800), isNotNull);
  });

  test('a map narrower than the bubble centres it instead of clamping', () {
    final l = layoutAt(100, 600, size: const Size(200, 800))!;
    expect(l.left, (200 - width) / 2, reason: 'centred, and overhanging both sides');
  });
}

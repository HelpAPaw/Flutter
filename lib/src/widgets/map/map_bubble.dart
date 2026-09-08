import 'package:flutter/material.dart';

/// The shell every map bubble shares: a fixed-width surface with a pointer
/// tying it to the pin below (or above) it.
///
/// Replaces the native Maps `InfoWindow`, which could render two lines of
/// platform-styled text and nothing else, and whose `onTap` never fired for
/// clustered markers (flutter/flutter#159636) — so the old window needed an
/// invisible [GestureDetector] laid on top of it just to be tappable. A Flutter
/// widget takes its own taps.
///
/// The width is **fixed**, not content-sized. The map screen has to clamp the
/// bubble inside the viewport and centre it over a pin before it has laid out,
/// and a known width is what makes that arithmetic possible; only the height is
/// left to the content, because Bulgarian labels wrap where English does not.
class MapBubble extends StatelessWidget {
  const MapBubble({
    super.key,
    required this.semanticIdentifier,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.tailDown = true,
    this.tailAlignment = 0.0,
  });

  /// Fixed bubble width, in logical pixels. See the class doc.
  static const double width = 260.0;

  /// Height of the pointer triangle below (or above) the bubble.
  static const double tailHeight = 8.0;

  /// Identifier the device tests target. The old native window had none, and
  /// was found by hunting its cream background colour pixel by pixel.
  final String semanticIdentifier;
  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;

  /// Whether the pointer sits under the bubble (bubble above the pin) or over
  /// it (bubble below the pin, for pins near the top edge).
  final bool tailDown;

  /// Where along the bubble's width the pointer sits, as an [Alignment] x from
  /// -1 (left edge) to 1 (right). Normally 0, because the bubble is centred on
  /// its pin — but a bubble clamped against the side of the screen is not, and
  /// a pointer left in the middle of it would be pointing at nothing.
  final double tailAlignment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tail = Align(
      alignment: Alignment(tailAlignment, 0),
      child: CustomPaint(
        size: const Size(16, tailHeight),
        painter: _TailPainter(tailDown: tailDown, color: scheme.surface),
      ),
    );

    return SizedBox(
      width: width,
      child: Semantics(
        identifier: semanticIdentifier,
        label: semanticLabel,
        button: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!tailDown) tail,
            Material(
              color: scheme.surface,
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: child,
                ),
              ),
            ),
            if (tailDown) tail,
          ],
        ),
      ),
    );
  }
}

/// The pointer that ties the bubble to its pin.
class _TailPainter extends CustomPainter {
  const _TailPainter({required this.tailDown, required this.color});

  final bool tailDown;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // The tail is a triangle from one edge of the box to a point on the other:
    // which edge is the base is the only thing the flip changes.
    final base = tailDown ? 0.0 : size.height;
    final tip = size.height - base;
    final path = Path()
      ..moveTo(0, base)
      ..lineTo(size.width, base)
      ..lineTo(size.width / 2, tip)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter oldDelegate) =>
      oldDelegate.tailDown != tailDown || oldDelegate.color != color;
}

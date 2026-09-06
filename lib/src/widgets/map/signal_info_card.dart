import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/help_tag.dart';
import '../../models/signal_urgency.dart';
import '../../repositories/signal_repository.dart';
import '../help_tag_pill.dart';
import '../urgency_tag_avatar.dart';

/// The bubble that opens above a signal's pin on the map.
///
/// Replaces the native Maps `InfoWindow`, which could render two lines of
/// platform-styled text and nothing else — no photo, no needs, no brand. It is
/// a plain Flutter widget positioned over the map, which also means it takes
/// its own taps: native `InfoWindow.onTap` never fired for clustered markers
/// (flutter/flutter#159636), so the old window needed an invisible
/// [GestureDetector] laid on top of it just to be tappable.
///
/// The width is **fixed**, not content-sized. The caller has to clamp the
/// bubble inside the viewport and centre it over a pin before it has laid out,
/// and a known width is what makes that arithmetic possible; only the height
/// is left to the content, because Bulgarian needs-labels wrap to a second row
/// and English usually does not.
class SignalInfoCard extends StatelessWidget {
  const SignalInfoCard({
    super.key,
    required this.signal,
    required this.onTap,
    this.tailDown = true,
    this.tailAlignment = 0.0,
  });

  /// Fixed bubble width, in logical pixels. See the class doc.
  static const double width = 260.0;

  /// Height of the pointer triangle below (or above) the bubble.
  static const double tailHeight = 8.0;

  /// The part of the bubble's height that does not grow with the text: the
  /// 64px thumbnail, the padding around it and the tail.
  static const double _fixedHeight = 92.0;

  /// The part that does — a three-line title beside the thumbnail, then three
  /// two-word needs wrapping onto two rows, which is the Bulgarian worst case.
  static const double _textHeight = 84.0;

  /// Upper bound on the whole bubble's height, tail included.
  ///
  /// Only used to decide whether the bubble fits above the pin or has to flip
  /// below it, so an estimate is enough: being wrong flips a bubble that would
  /// just have fitted, which nobody can see. Measuring properly would need a
  /// layout pass before the first paint.
  ///
  /// It has to follow the text scaler, though. At 200% system font the card is
  /// half as tall again, and a fixed constant would leave `fitsAbove` true for
  /// a pin close to the top — where the Stack's `Clip.hardEdge` then cuts the
  /// title off the screen entirely.
  static double maxHeightFor(BuildContext context) =>
      _fixedHeight + _textHeight * MediaQuery.textScalerOf(context).scale(1.0);

  final SignalWithId signal;
  final VoidCallback onTap;

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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final urgency = SignalUrgency.fromCode(signal.urgency);
    // Unknown codes are dropped: one means the signal came from a newer build,
    // and there is no label for it here. Same rule as SignalStateCard, so the
    // bubble and the details screen can't disagree about what a signal needs.
    final tags = HelpTag.fromCodes(signal.helpNeededTags);
    final title = signal.signal.displayTitle(l10n);

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
        identifier: 'signalInfoCard',
        label: title,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Thumbnail(signal: signal, urgency: urgency),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                      // Across the full card rather than beside the photo: a
                      // Bulgarian need is a two-word phrase, and in the column
                      // left over next to a 64px thumbnail all three stack one
                      // per row, leaving the card tall and half empty.
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final tag in tags)
                              HelpTagPill(
                                  icon: tag.icon, label: tag.label(l10n)),
                          ],
                        ),
                      ],
                    ],
                  ),
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

/// The signal's first photo, or — for the many signals reported without one —
/// an [UrgencyTagAvatar].
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.signal, required this.urgency});

  final SignalWithId signal;
  final SignalUrgency urgency;

  static const double _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final photoUrls = signal.photoUrls;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: _size,
        height: _size,
        child: photoUrls.isEmpty
            ? _placeholder(context)
            : CachedNetworkImage(
                imageUrl: photoUrls.first,
                fit: BoxFit.cover,
                // Signal photos are stored at up to 1920px and there is no
                // thumbnail variant, so decoding one at full size for a 64px
                // box costs about 11MB of RAM per bubble. This caps the
                // *decode*, not the download: the disk cache still holds the
                // original, which is what the details screen's carousel reads.
                memCacheWidth:
                    (_size * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (context, _) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                ),
                errorWidget: (context, _, __) => _placeholder(context),
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) => UrgencyTagAvatar(
        urgency: urgency,
        tag: signal.primaryTag,
        size: _size,
      );
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

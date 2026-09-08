import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/help_tag.dart';
import '../../models/signal_urgency.dart';
import '../../repositories/signal_repository.dart';
import '../help_tag_pill.dart';
import '../urgency_tag_avatar.dart';
import 'map_bubble.dart';

/// The bubble that opens on a signal's pin: photo, title, and what it needs.
///
/// The shell — surface, pointer, fixed width, tap target — is [MapBubble],
/// shared with the vet-clinic bubble.
class SignalInfoCard extends StatelessWidget {
  const SignalInfoCard({
    super.key,
    required this.signal,
    required this.onTap,
    this.tailDown = true,
    this.tailAlignment = 0.0,
  });

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
  final bool tailDown;
  final double tailAlignment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final urgency = SignalUrgency.fromCode(signal.urgency);
    // Unknown codes are dropped: one means the signal came from a newer build,
    // and there is no label for it here. Same rule as SignalStateCard, so the
    // bubble and the details screen can't disagree about what a signal needs.
    final tags = HelpTag.fromCodes(signal.helpNeededTags);
    final title = signal.signal.displayTitle(l10n);

    return MapBubble(
      semanticIdentifier: 'signalInfoCard',
      semanticLabel: title,
      onTap: onTap,
      tailDown: tailDown,
      tailAlignment: tailAlignment,
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
          // Across the full card rather than beside the photo: a Bulgarian need
          // is a two-word phrase, and in the column left over next to a 64px
          // thumbnail all three stack one per row, leaving the card tall and
          // half empty.
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in tags)
                  HelpTagPill(
                    icon: tag.icon,
                    label: tag.label(l10n),
                    emphasis: true,
                  ),
              ],
            ),
          ],
        ],
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

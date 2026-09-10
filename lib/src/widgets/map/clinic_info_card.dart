import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/vet_clinic.dart';
import 'map_bubble.dart';

/// The bubble that opens on a vet clinic's pin.
///
/// Same shell as the signal bubble, because they sit on the same map and a
/// clinic that opened a platform-styled window while a signal opened a card
/// read as two different apps. The content differs — a clinic has no photo and
/// nothing to ask for — but the surface, the pointer and the tap target are
/// [MapBubble]'s.
class ClinicInfoCard extends StatelessWidget {
  const ClinicInfoCard({
    super.key,
    required this.clinic,
    required this.onTap,
    this.tailDown = true,
    this.tailAlignment = 0.0,
  });

  /// The part of the height that never grows: the bubble's own padding and its
  /// tail.
  static const double _fixedHeight = 28.0;

  /// The clinic's pin badge. Constant too, but it sets the floor — at a small
  /// text scale it is taller than the two-line name and address beside it.
  static const double _badgeHeight = 44.0;

  /// The part that does grow: two lines of name, the gap under it, and two
  /// lines of address, which is what a Bulgarian street address needs at this
  /// width. Line heights round to whole pixels, so this is a couple of pixels
  /// above the measured 1.0 case to stay a bound at every scale.
  static const double _textHeight = 76.0;

  /// Upper bound on the bubble's height, tail included — see
  /// [SignalInfoCard.maxHeightFor] for why this is an estimate and why it has
  /// to follow the text scaler.
  ///
  /// The badge and the text sit side by side in a [Row], so the content is as
  /// tall as the taller of the two rather than the sum. Adding them — or
  /// counting the name in both halves — over-estimates by half a bubble, and an
  /// over-estimate flips the bubble below a pin that it would have cleared.
  static double maxHeightFor(BuildContext context) =>
      _fixedHeight +
      math.max(
        _badgeHeight,
        _textHeight * MediaQuery.textScalerOf(context).scale(1.0),
      );

  final VetClinic clinic;
  final VoidCallback onTap;
  final bool tailDown;
  final double tailAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return MapBubble(
      semanticIdentifier: 'clinicInfoCard',
      semanticLabel: clinic.name,
      onTap: onTap,
      tailDown: tailDown,
      tailAlignment: tailAlignment,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The clinic's own pin, not a themed icon. The map teaches blue =
          // clinic, and a brand-orange badge on a bubble hanging off a blue pin
          // said the two were unrelated. Drawn from the same asset the marker
          // uses, so the bubble and the pin cannot drift — the legend sheet
          // renders its rows from these assets for exactly this reason. It sits
          // on a neutral ground rather than an urgency tint: a clinic has no
          // severity, and reusing the traffic light here would imply one.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: _badgeHeight,
              height: _badgeHeight,
              child: ColoredBox(
                color: scheme.surfaceContainerHigh,
                child: Center(
                  child: Image.asset(
                    'assets/icons/local_hospital_blue.png',
                    width: 24,
                    height: 24,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  clinic.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  clinic.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// A small coloured pill naming one level of a signal — its urgency or its
/// status.
///
/// One widget for both because they render side by side in the same row (My
/// Signals, the details header). While the status chip was built inline and
/// the urgency chip was a widget, they had already drifted on padding and font
/// weight; two pills that disagree about their own shape read as a bug in a
/// feature whose whole point is that colour means one specific thing.
class LevelChip extends StatelessWidget {
  /// Accent colour — `SignalUrgency.color` or `SignalStatus.color`.
  final Color color;

  final String label;

  /// Optional leading icon. Urgency passes its map pin (the map is where that
  /// colour is defined); status has no pin by design — see [SignalStatus].
  final String? iconAsset;

  const LevelChip({
    super.key,
    required this.color,
    required this.label,
    this.iconAsset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(51),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconAsset != null) ...[
            Image.asset(iconAsset!, width: 14, height: 14),
            const SizedBox(width: 6),
          ],
          // Flexible, not bare: these labels are whole sentences, and the
          // Bulgarian amber label ("Оранжево — нужна е помощ скоро") lays out
          // at 403px — wider than a 411dp phone. An unconstrained Row inside a
          // Wrap will happily overflow, and a release build clips it with no
          // overflow stripe to notice, so the chip has to be able to give.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

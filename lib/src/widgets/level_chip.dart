import 'package:flutter/material.dart';

/// A small pill naming one level of a signal — its urgency or its status.
///
/// The two look deliberately *unalike*, and that is the whole point. They sit
/// side by side in the same row (My Signals, the details header), and while
/// both were traffic-light coloured a reader had two colour scales to hold at
/// once, running in opposite directions: red urgency means "act now", red
/// status means "nobody has acted". Green+red, red+green, green+green and
/// red+red all appear on one list.
///
/// So the app keeps one colour axis:
///
/// * [LevelChip.urgency] is **coloured and filled**, and carries the map pin —
///   the same vocabulary the map uses, because it is the same fact.
/// * [LevelChip.status] is **neutral and outlined**, and carries a progress
///   glyph. It reads as a state, not as a severity.
///
/// The shape alone tells you which axis you are looking at before you have
/// read either label, which matters most in Bulgarian, where the labels are
/// near-homographs.
class LevelChip extends StatelessWidget {
  /// The coloured, filled variant — severity.
  const LevelChip.urgency({
    super.key,
    required this.color,
    required this.label,
    this.iconAsset,
  })  : icon = null,
        _filled = true;

  /// The neutral, outlined variant — progress.
  const LevelChip.status({
    super.key,
    required this.label,
    required this.icon,
  })  : color = null,
        iconAsset = null,
        _filled = false;

  /// Accent colour. Urgency only; status has none by design.
  final Color? color;

  final String label;

  /// Leading image. Urgency passes its map pin.
  final String? iconAsset;

  /// Leading glyph. Status passes its progress icon.
  final IconData? icon;

  final bool _filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = _filled ? color! : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _filled ? ink.withAlpha(51) : null,
        border: _filled ? null : Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconAsset != null) ...[
            Image.asset(iconAsset!, width: 14, height: 14),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: ink),
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
                color: ink,
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

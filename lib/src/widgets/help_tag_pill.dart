import 'package:flutter/material.dart';

/// A help-needed or species tag.
///
/// Lighter than a Material [Chip]: these are labels on a surface that already
/// has a border, and chip-on-card was two nested containers of nearly the same
/// tone.
///
/// Shared rather than private to one screen: the same pill is what the details
/// card and the map bubble both render, and duplicating thirty lines is how the
/// two would quietly stop looking like the same thing.
class HelpTagPill extends StatelessWidget {
  const HelpTagPill({
    super.key,
    required this.icon,
    required this.label,
    this.emphasis = false,
  });

  final IconData icon;
  final String label;

  /// Whether this pill is the *ask* — what the signal needs — rather than a
  /// piece of description.
  ///
  /// An emphasised pill is filled with the brand's tonal container rather than
  /// outlined in neutral. Deliberately **not** filled with `primary` itself: on
  /// a light ground the only ink that reads on `#FF9800` manages 2.16:1, so a
  /// solid-brand pill is legible in dark mode and not in light. The tonal pair
  /// is 10.38:1 and 8.66:1 — more prominent *and* more legible than either the
  /// neutral outline or a solid fill.
  ///
  /// It also has to stay clear of the map's own colour language, where a
  /// saturated orange means amber urgency. The container tone is far enough
  /// from the pin hue not to be read as a severity.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        emphasis ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: emphasis ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: emphasis ? scheme.primaryContainer : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

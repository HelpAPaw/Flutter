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
  const HelpTagPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

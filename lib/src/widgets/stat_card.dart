import 'package:flutter/material.dart';

/// One contribution statistic: a glyph, a number and a label.
///
/// Lifted out of `profile_page.dart`, where it was private, when the read-only
/// view of another user's profile started showing the same numbers. Two copies
/// of a stat tile is how the same figure ends up formatted two ways.
///
/// Sized by its parent, not by its content — see [StatCardRow], which is how
/// every caller should place these.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;

  /// The number, or null when the query behind it failed.
  ///
  /// Null renders as a dash rather than "0": a zero here is a real, meaningful
  /// answer — nobody has reported anything yet — and showing one for a read
  /// that did not happen states something false about the person.
  final int? value;

  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        // Horizontal padding is small because [StatCardRow] gives every card an
        // equal share of the row. It used to be 32, which sized the card to its
        // content — fine for the two cards this started with, and an overflow
        // as soon as there were three with a two-word label between them.
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              value?.toString() ?? '—',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              // Two lines, so a long Bulgarian label wraps instead of being
              // clipped: the number above it is meaningless without it.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row of [StatCard]s, each given an equal share of the width.
///
/// Equal shares rather than `spaceEvenly` over content-sized cards: the labels
/// are translated and their widths are not knowable here, so anything that
/// sizes to content is one long translation away from overflowing.
class StatCardRow extends StatelessWidget {
  const StatCardRow({super.key, required this.cards});

  final List<StatCard> cards;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

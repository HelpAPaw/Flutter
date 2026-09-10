import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../services/user_stats_service.dart';

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

/// One account's contribution statistics, as a row of [StatCard]s.
///
/// **Which glyph and which word belong to which number is decided here, once.**
/// `UserStatsService` was extracted so the two profile screens could not
/// disagree about what a figure *counts*; this is the other half — without it
/// they can still disagree about what it is *called*, which is the same bug
/// wearing a different hat.
///
/// Equal shares rather than `spaceEvenly` over content-sized cards: the labels
/// are translated and their widths are not knowable here, so anything that
/// sizes to content is one long Bulgarian translation away from overflowing a
/// 411dp phone — see `test/widgets/bulgarian_layout_test.dart`.
class UserStatsRow extends StatelessWidget {
  const UserStatsRow({super.key, required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cards = [
      StatCard(
        icon: Icons.pin_drop,
        value: stats.signalsPosted,
        label: l10n.signals,
      ),
      StatCard(
        icon: Icons.volunteer_activism,
        value: stats.signalsOwned,
        label: l10n.helpingNow,
      ),
      StatCard(
        icon: Icons.comment,
        value: stats.commentsPosted,
        label: l10n.comments,
      ),
    ];

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

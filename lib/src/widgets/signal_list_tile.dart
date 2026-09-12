import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../models/signal.dart';
import '../models/signal_status.dart';
import '../models/signal_urgency.dart';
import 'level_chip.dart';
import 'urgency_picker.dart';

/// One signal in a list.
///
/// Extracted from My Signals so the Watching tab reads identically rather than
/// growing a second copy of the urgency/status/date layout that drifts from it.
class SignalListTile extends StatelessWidget {
  const SignalListTile({
    super.key,
    required this.signal,
    required this.onTap,
    this.trailing,
    this.badge,
  });

  final Signal signal;
  final VoidCallback onTap;

  /// Replaces the default chevron — an unfollow menu, for instance.
  final Widget? trailing;

  /// An extra chip in the metadata row, e.g. "You hold this".
  final Widget? badge;

  /// Cached per locale: this is called once per row, per build, and
  /// constructing a `DateFormat` resolves the locale and parses the pattern
  /// every time — identical work for every row on screen.
  static final Map<String, DateFormat> _formats = <String, DateFormat>{};

  static String formatDate(BuildContext context, DateTime date) {
    final code = Localizations.localeOf(context).languageCode;
    final format =
        _formats.putIfAbsent(code, () => DateFormat('MMM d, yyyy', code));
    return format.format(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final urgencyColor = SignalUrgency.fromCode(signal.urgency).color;
    final createdAt = signal.createdAt as Timestamp?;
    final dateStr = createdAt != null
        ? formatDate(context, createdAt.toDate())
        : l10n.unknownDate;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        // Tinted by urgency, not status: colour means "how bad is it" everywhere
        // in the app now, and a row whose avatar and chip disagreed about what
        // red meant would reintroduce exactly the confusion this replaces.
        leading: CircleAvatar(
          backgroundColor: urgencyColor.withAlpha(51),
          child: Icon(
            // The tag already carries an icon, so the row and the chips on the
            // details screen cannot drift.
            signal.primaryTag.icon,
            color: urgencyColor,
          ),
        ),
        title: Text(
          signal.displayTitle(l10n),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              signal.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                UrgencyChip(urgency: signal.urgency),
                LevelChip.status(
                  icon: SignalStatus.fromCode(signal.status).icon,
                  label: SignalStatus.fromCode(signal.status).label(l10n),
                ),
                if (badge != null) badge!,
                Text(
                  dateStr,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
        trailing: trailing ?? const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

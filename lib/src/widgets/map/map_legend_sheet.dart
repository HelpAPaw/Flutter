import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../../models/signal_urgency.dart';
import '../section_header.dart';

/// Explains the map's colour code.
///
/// Pin colour is the only thing on the map that says how bad a signal is, and
/// the three pins are the same paw in three hues — so a user who cannot
/// separate red from green, or who simply has not been told, reads a screen of
/// markers with no idea which one is dying. Nothing anywhere in the app said
/// what the colours meant.
///
/// A legend does not fix hue-only encoding on its own; it does mean the
/// encoding is at least teachable, and it is reachable from the screen where
/// the question comes up. Each row shows the real pin asset, so this cannot
/// drift from what the map draws.
void showMapLegendSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => const _MapLegendSheet(),
  );
}

class _MapLegendSheet extends StatelessWidget {
  const _MapLegendSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.mapLegend, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            SectionHeader(l10n.urgency),
            const SizedBox(height: 8),
            // Most urgent first: the legend is read to answer "which of these
            // needs me", so the answer is at the top.
            for (final urgency in SignalUrgency.values.reversed)
              _LegendRow(
                icon: Image.asset(urgency.pinAsset, width: 28, height: 28),
                label: urgency.label(l10n),
                description: urgency.description(l10n),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.mapLegendUrgencyNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _LegendRow(
              icon: Image.asset(
                'assets/icons/local_hospital_blue.png',
                width: 28,
                height: 28,
              ),
              label: l10n.mapLegendVetClinic,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.icon,
    required this.label,
    this.description,
  });

  final Widget icon;
  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 32, child: Center(child: icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (description != null)
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

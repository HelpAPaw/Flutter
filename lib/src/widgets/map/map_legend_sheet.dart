import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../../models/signal_urgency.dart';
import '../../utils/cluster_bubble_icons.dart';
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
    // The sheet is as tall as its content, and its content is nine lines of
    // prose whose length depends on the language and the reader's text size.
    // Left to the default half-screen it overflowed by 43px in Bulgarian at
    // 411dp — the vet clinic row simply gone, with a debug stripe where it
    // should have been. Scroll-controlled and scrollable, so it can be as
    // tall as it needs and still never clip.
    isScrollControlled: true,
    // Required *because* of the line above: `isScrollControlled` lets the sheet
    // reach the top of the screen, and `ModalBottomSheetRoute` removes the top
    // padding in that mode, so the SafeArea below cannot keep the title out
    // from under the status bar on its own.
    useSafeArea: true,
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
      child: SingleChildScrollView(
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
            // The bubble is drawn here in Flutter rather than shown as the
            // marker bitmap, but with the same geometry (disc, halo, white
            // count) so it is recognisably the thing on the map. Amber, as the
            // urgency an unknown signal defaults to and the middle of the scale.
            _LegendRow(
              icon: _LegendBubble(count: 3, color: SignalUrgency.amber.color),
              label: l10n.mapLegendCluster,
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

/// A cluster bubble as the legend shows it: the marker bitmap's geometry
/// ([ClusterBubbleIcons.discDiameter] and halo), scaled to the legend's 28px
/// icon column, drawn with widgets so it follows text scaling like its row.
class _LegendBubble extends StatelessWidget {
  const _LegendBubble({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withAlpha(90),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(
                color: Colors.white, // theme-independent: as on the map
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  // As on the map: white on a saturated fill reads in both
                  // modes.
                  color: Colors.white, // theme-independent
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

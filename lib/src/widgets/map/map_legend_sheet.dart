import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../../models/signal_urgency.dart';
import '../../utils/cluster_bubble_icons.dart';
import '../../utils/map_marker_builder.dart';
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
            // Drawn here in Flutter rather than shown as the marker bitmap,
            // at the legend's own 28px scale but from the bubble's own colours
            // and weight, so a restyle cannot leave the two disagreeing. Amber,
            // as the urgency an unknown signal defaults to and the middle of
            // the scale.
            _LegendRow(
              icon: _LegendBubble(parts: [
                // Most urgent first, from the same ordering
                // `MapMarkerBuilder.signalBubbleKey` builds the real ring with,
                // so adding a level cannot leave the legend disagreeing.
                for (final urgency in SignalUrgency.values.reversed)
                  (urgency.color, _exampleCounts[urgency]!),
              ]),
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
            _LegendRow(
              icon: const _LegendBubble(
                parts: [(MapMarkerBuilder.clinicBlue, 2)],
              ),
              label: l10n.mapLegendClinicCluster,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// The cluster the legend's example bubble stands for. One red among seven is
/// the case worth teaching: the disc is red for a cluster that is mostly not.
const _exampleCounts = {
  SignalUrgency.red: 1,
  SignalUrgency.amber: 4,
  SignalUrgency.green: 2,
};

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

/// A cluster bubble as the legend shows it: painted by the marker bitmap's own
/// routine at the legend's 28px icon column, so it cannot drift from what the
/// map draws whatever style is in force. Only the count is a widget, so it
/// still follows text scaling like the row it sits in.
class _LegendBubble extends StatelessWidget {
  /// [parts] is (colour, member count), most urgent first — the order
  /// [MapMarkerBuilder.signalBubbleKey] builds. One part is a clinic cluster.
  const _LegendBubble({required this.parts});

  final List<(Color, int)> parts;

  /// Diameter of the disc inside the 28px icon box, leaving room for whatever
  /// the style puts around it.
  static const double _disc = 22;

  @override
  Widget build(BuildContext context) {
    final key = clusterBubbleKey(parts: parts);
    return SizedBox(
      width: 28,
      height: 28,
      child: CustomPaint(
        painter: _LegendBubblePainter(key),
        child: Center(
          child: Text(
            key.label,
            style: TextStyle(
              // As on the map, from the map's own rule.
              color: ClusterBubbleIcons.inkFor(key.ring.first.$1),
              fontSize: 11,
              fontWeight: ClusterBubbleIcons.labelWeight,
            ),
          ),
        ),
      ),
    );
  }
}

/// The legend's bubble, minus its count — the marker bitmap's own painter, at
/// the legend's scale.
class _LegendBubblePainter extends CustomPainter {
  const _LegendBubblePainter(this.key);

  final ClusterBubbleKey key;

  @override
  void paint(Canvas canvas, Size size) {
    ClusterBubbleIcons.paintBubble(
      canvas,
      key,
      centre: size.center(Offset.zero),
      discDiameter: _LegendBubble._disc,
      // The legend's bubble is smaller than the map's, so anything around the
      // disc is scaled to it rather than borrowing the map's absolute width.
      ringWidthOverride: (size.shortestSide - _LegendBubble._disc) / 2,
      drawLabel: false,
    );
  }

  @override
  bool shouldRepaint(_LegendBubblePainter oldDelegate) =>
      oldDelegate.key != key;
}

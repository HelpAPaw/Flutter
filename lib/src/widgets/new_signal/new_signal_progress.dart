import 'package:flutter/material.dart';

import 'package:help_a_paw/l10n/app_localizations.dart';

import '../../models/new_signal_step.dart';

/// "Step 3 of 7" and the bar under it, for every step of the new-signal flow.
///
/// Step 1 happens on the live map and steps 2-7 on the wizard route, and the
/// two had drifted into looking like different features: step 1 drew a counter
/// and a bar in the body, while the wizard welded a bar to the bottom of the
/// orange app bar with no counter at all. On a device that bar is white on
/// pale orange and reads as a seam rather than as progress — so the indicator
/// appeared to *vanish* between step 1 and step 2, exactly where a user is
/// deciding whether this is going to take all day.
///
/// One widget, on the page ground, in both places.
class NewSignalProgress extends StatelessWidget {
  const NewSignalProgress({super.key, required this.step});

  final NewSignalStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // Total read from `count`, never written out — the enum's own doc
          // said "of 8" while there were seven.
          l10n.newSignalStepCounter(step.displayNumber, NewSignalStep.count),
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: step.displayNumber / NewSignalStep.count,
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
            minHeight: 4,
          ),
        ),
      ],
    );
  }
}

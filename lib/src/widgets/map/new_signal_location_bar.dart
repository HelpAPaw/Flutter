import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../models/new_signal_step.dart';

/// Step 1 of the create-a-signal wizard, rendered over the live map.
///
/// The location question stays on the real map rather than moving into the
/// wizard route: it reuses the `GoogleMap` that is already on screen — no
/// second map instance, no second set of tile loads — and the reporter keeps
/// the zoom and the surrounding signals they were already looking at.
///
/// It carries the same step counter and progress bar as the wizard pages so
/// the two halves read as one flow rather than two features.
class NewSignalLocationBar extends ConsumerWidget {
  const NewSignalLocationBar({
    super.key,
    required this.onCancel,
    required this.onContinue,
  });

  final VoidCallback onCancel;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    const step = NewSignalStep.location;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.newSignalStepCounter(
                    step.displayNumber,
                    NewSignalStep.count,
                  ),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: step.displayNumber / NewSignalStep.count,
                    backgroundColor: Colors.orange.shade100,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.orange),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  step.question(l10n),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  step.hint(l10n)!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Semantics(
                      identifier: 'newSignal.cancelLocation',
                      button: true,
                      child: TextButton(
                        onPressed: onCancel,
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Semantics(
                        identifier: 'newSignal.confirmLocation',
                        button: true,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: onContinue,
                          child: Text(l10n.next),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

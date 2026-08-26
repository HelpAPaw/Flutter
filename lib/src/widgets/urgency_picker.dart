import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/signal_urgency.dart';
import 'level_chip.dart';
import 'red_alert_confirmation_dialog.dart';

/// Urgency selector used by the create form, the edit screen and the details
/// screen.
///
/// Owns the Red Alert confirmation rule (spec 5.2.1) so no caller can forget
/// it: [onChanged] is only called once a promotion to Red has been confirmed.
/// Selecting a level that is already selected, or moving *down* from Red, never
/// prompts.
class UrgencyPicker extends StatelessWidget {
  /// Currently selected urgency, or null if the user has not chosen yet
  /// (create form only — urgency is a required field, so there is no default).
  final int? value;

  /// Called with the new urgency code once any required confirmation is done.
  final void Function(int urgency) onChanged;

  /// Whether to show the per-level explanation under each option. On by
  /// default; the compact create form turns it off for space.
  final bool showDescriptions;

  final bool enabled;

  const UrgencyPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.showDescriptions = true,
    this.enabled = true,
  });

  Future<void> _select(BuildContext context, SignalUrgency urgency) async {
    if (urgency.code == value) return;

    if (urgency.requiresConfirmation) {
      final confirmed = await showRedAlertConfirmationDialog(context);
      if (!confirmed) return;
      // The dialog is awaited, so the owning screen can be gone by now (a
      // back gesture behind it, a deep link). Callers setState, so firing
      // into a disposed State would throw.
      if (!context.mounted) return;
    }

    onChanged(urgency.code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // The group owns selection so the individual Radios stay on the
    // non-deprecated API; every change routes through _select, which is what
    // enforces the Red confirmation.
    return RadioGroup<int>(
      groupValue: value,
      onChanged: (code) {
        if (code == null) return;
        _select(context, SignalUrgency.fromCode(code));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: SignalUrgency.values.map((urgency) {
          final isSelected = urgency.code == value;

          return Semantics(
            label: urgency.label(l10n),
            selected: isSelected,
            button: true,
            enabled: enabled,
            child: InkWell(
              onTap: enabled ? () => _select(context, urgency) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Radio<int>(
                      value: urgency.code,
                      activeColor: urgency.color,
                      enabled: enabled,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Image.asset(urgency.pinAsset,
                                    width: 18, height: 18),
                                const SizedBox(width: 8),
                                Text(
                                  urgency.label(l10n),
                                  style: TextStyle(
                                    color: urgency.color,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                            if (showDescriptions)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  urgency.description(l10n),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Compact read-only urgency chip, for list rows and the details header.
class UrgencyChip extends StatelessWidget {
  final int urgency;

  const UrgencyChip({super.key, required this.urgency});

  @override
  Widget build(BuildContext context) {
    final level = SignalUrgency.fromCode(urgency);
    return LevelChip.urgency(
      color: level.color,
      label: level.label(AppLocalizations.of(context)),
      iconAsset: level.pinAsset,
    );
  }
}

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../models/signal.dart';
import '../models/signal_status.dart';
import 'section_header.dart';
import 'urgency_picker.dart';

/// Every control that *changes* a case, in one sheet.
///
/// The details screen used to lay these out inline, one under the next, each
/// with its own heading — an urgency radio group six lines tall, a full-width
/// status dropdown, a "Change" link beside the help tags. Read-only visitors
/// (almost everyone who opens a signal) scrolled past all of it, and nothing
/// distinguished the controls they could use from the ones they could not.
///
/// So the card on the screen shows the current values and this sheet owns the
/// editing. The affordance is one button, and it is only drawn for someone who
/// may actually coordinate.
///
/// The sheet does **not** apply anything itself: it calls back into the screen,
/// which owns the write guard, the update-note dialog and the timeline append.
/// It closes on the way out because the [Signal] it was handed is a snapshot —
/// leaving it open would show pre-write values over a screen that had already
/// moved on.
Future<void> showManageCaseSheet(
  BuildContext context, {
  required Signal signal,
  required bool busy,
  required void Function(int urgency) onUrgencyChanged,
  required void Function(int status) onStatusChanged,
  required VoidCallback onEditTags,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => _ManageCaseSheet(
      signal: signal,
      busy: busy,
      onUrgencyChanged: onUrgencyChanged,
      onStatusChanged: onStatusChanged,
      onEditTags: onEditTags,
    ),
  );
}

class _ManageCaseSheet extends StatelessWidget {
  const _ManageCaseSheet({
    required this.signal,
    required this.busy,
    required this.onUrgencyChanged,
    required this.onStatusChanged,
    required this.onEditTags,
  });

  final Signal signal;
  final bool busy;
  final void Function(int urgency) onUrgencyChanged;
  final void Function(int status) onStatusChanged;
  final VoidCallback onEditTags;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SectionHeader(l10n.urgency),
            const SizedBox(height: 4),
            // The picker, not a copy of it: it owns the Red Alert confirmation
            // (spec 5.2.1), so routing through it is what keeps that rule from
            // being forgettable.
            UrgencyPicker(
              value: signal.urgency,
              enabled: !busy,
              onChanged: (value) {
                Navigator.of(context).pop();
                onUrgencyChanged(value);
              },
            ),
            const SizedBox(height: 20),
            SectionHeader(l10n.status),
            const SizedBox(height: 8),
            // Three tappable rows rather than the old dropdown. A dropdown hides
            // two of the three choices behind a tap and gave this screen its
            // tallest single control; the options are few enough to just show.
            for (final status in SignalStatus.values)
              _StatusOption(
                status: status,
                selected: status.code == signal.status,
                enabled: !busy,
                onTap: () {
                  Navigator.of(context).pop();
                  onStatusChanged(status.code);
                },
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                SectionHeader(l10n.helpNeeded),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.edit, size: 16),
                  label: Text(l10n.change),
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          onEditTags();
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One status choice. Deliberately the same anatomy as an [UrgencyPicker] row —
/// a selection control, a glyph, a label — so the two fields in this sheet read
/// as the same kind of decision.
class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.status,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SignalStatus status;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: status.label(l10n),
      selected: selected,
      button: true,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 20,
                color: selected ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 12),
              Icon(status.icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.label(l10n),
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Mandatory confirmation shown before a signal is published or promoted to
/// Red (spec 5.2.1).
///
/// Red Alert only works while it stays rare: if it becomes the default choice,
/// the whole urgency system stops meaning anything and attention is pulled away
/// from animals actually at risk. So the confirmation is deliberately a speed
/// bump — the confirm button stays disabled until the tick-box is ticked, and
/// the copy names the consequence of misuse.
///
/// Shown only on a *transition into* Red, never on re-saving a signal that is
/// already Red — otherwise editing a genuine Red Alert's phone number would
/// nag, and people learn to dismiss the thing without reading it.
///
/// Returns `true` only if the user confirmed.
Future<bool> showRedAlertConfirmationDialog(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => const _RedAlertConfirmationDialog(),
  );
  return confirmed ?? false;
}

class _RedAlertConfirmationDialog extends StatefulWidget {
  const _RedAlertConfirmationDialog();

  @override
  State<_RedAlertConfirmationDialog> createState() =>
      _RedAlertConfirmationDialogState();
}

class _RedAlertConfirmationDialogState
    extends State<_RedAlertConfirmationDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 32),
      title: Text(l10n.redAlertConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.redAlertConfirmBody),
          const SizedBox(height: 16),
          // Tapping the label toggles too — a bare Checkbox next to text is a
          // small target, and this dialog is often opened one-handed in a hurry.
          Semantics(
            label: l10n.redAlertConfirmCheckbox,
            checked: _acknowledged,
            child: InkWell(
              onTap: () => setState(() => _acknowledged = !_acknowledged),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _acknowledged,
                    activeColor: Colors.red,
                    onChanged: (value) =>
                        setState(() => _acknowledged = value ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(l10n.redAlertConfirmCheckbox),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        Semantics(
          label: l10n.redAlertConfirmAction,
          button: true,
          enabled: _acknowledged,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: _acknowledged
                ? () => Navigator.of(context).pop(true)
                : null,
            child: Text(l10n.redAlertConfirmAction),
          ),
        ),
      ],
    );
  }
}

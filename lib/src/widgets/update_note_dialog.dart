import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../models/signal_event.dart';

/// Asks for the mandatory update note that accompanies a status or urgency
/// change (spec §4.6: "Every status change requires an update note").
///
/// The note is what makes the signal's history worth reading. Without it the
/// timeline says *"Milen changed the status to Resolved"* and the next person to
/// pick the signal up learns nothing — which is exactly the Facebook-thread
/// problem the signal system exists to replace.
///
/// It is required rather than optional on purpose. An optional field on a
/// one-tap dropdown is left empty essentially always, which is the state the app
/// was already in; making it mandatory is the entire behaviour change.
///
/// Shown *after* [showRedAlertConfirmationDialog] on the urgency path — confirm
/// the intent first, then explain it. Returns the trimmed note, or null if the
/// user backed out, in which case the caller must not write anything.
///
/// [headline] is the finished sentence shown above the field, and it must name
/// the state the signal is moving *to* — "Changing to: Resolved", "Taking
/// responsibility for this case". Callers on the status and urgency paths build
/// it with `l10n.updateNoteChangingTo`; the ownership paths have their own
/// strings. It takes a whole sentence rather than a label precisely so it
/// cannot be handed a button verb: passing `confirmLabel` here once produced
/// "Changing to: Take it on", which names the button the user just pressed
/// instead of what is about to happen.
Future<String?> showUpdateNoteDialog(
  BuildContext context, {
  required String headline,
  required Widget badge,
}) =>
    showDialog<String>(
      context: context,
      builder: (context) => _UpdateNoteDialog(
        headline: headline,
        badge: badge,
      ),
    );

class _UpdateNoteDialog extends StatefulWidget {
  const _UpdateNoteDialog({required this.headline, required this.badge});

  final String headline;
  final Widget badge;

  @override
  State<_UpdateNoteDialog> createState() => _UpdateNoteDialogState();
}

class _UpdateNoteDialogState extends State<_UpdateNoteDialog> {
  final TextEditingController _controller = TextEditingController();

  /// Whitespace does not count as a note, so the button tracks the *trimmed*
  /// text rather than `_controller.text.isNotEmpty`.
  String get _note => _controller.text.trim();

  @override
  void initState() {
    super.initState();
    // Rebuilds on every keystroke so Confirm enables the moment the note stops
    // being blank. Cheap — this dialog is two widgets deep.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canSubmit = _note.isNotEmpty;

    return AlertDialog(
      title: Text(l10n.updateNoteTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              widget.badge,
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.headline,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // No Semantics wrapper: the field's hint and the buttons' labels
          // already expose exactly those strings. The project's Semantics
          // convention is for controls with no text of their own — icons, map
          // pins, chips — not for restating a label a control already has.
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            // Mirrors the 500-char bound in firestore.rules. The two are
            // guarded together — see signal_event_vocabulary_guard_test.dart.
            inputFormatters: [
              LengthLimitingTextInputFormatter(SignalEventType.maxNoteLength),
            ],
            decoration: InputDecoration(
              hintText: l10n.updateNoteHint,
              border: const OutlineInputBorder(),
              // Shown from the start rather than only after a failed submit:
              // the Confirm button is disabled until the note is written, so
              // without this the dialog would look broken rather than
              // unfinished.
              //
              // Always present, never conditional on `canSubmit`. Removing it
              // on the first keystroke shrank the field and jumped the whole
              // dialog upward under the user's finger — and put it back if they
              // deleted down to empty again.
              helperText: l10n.updateNoteRequired,
              helperMaxLines: 2,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: canSubmit ? () => Navigator.of(context).pop(_note) : null,
          child: Text(l10n.confirm),
        ),
      ],
    );
  }
}

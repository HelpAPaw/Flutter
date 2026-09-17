import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../models/report_reason.dart';
import '../services/moderation_service.dart';

/// Lets a user report a signal or a comment (master spec §18.1).
///
/// The affordance the app has been telling people about and not providing: the
/// FAQ has said *"please use the report function on the signal"* since long
/// before any such function existed.
///
/// A reason is **required** and the free-text detail is optional, which is the
/// opposite weighting to most report forms and is deliberate. A moderator
/// triaging a queue needs the category to sort by far more than they need
/// prose, and demanding an explanation is what stops people reporting things at
/// all.
///
/// The one exception is [ReportReason.other], where the category carries no
/// information at all: "something else" plus an empty details box tells a
/// moderator only that *someone* objected to *something*. So that reason — and
/// only that reason — requires the text.
///
/// Returns true only when a report was actually filed, so the caller can show
/// the confirmation without repeating the outcome logic. Every other case —
/// cancelled, already reported, failed — is reported to the user from inside
/// this dialog and returns false.
Future<bool> showReportDialog(
  BuildContext context, {
  required ReportTarget target,
}) async {
  final filed = await showDialog<bool>(
    context: context,
    builder: (context) => _ReportDialog(target: target),
  );
  return filed ?? false;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.target});

  final ReportTarget target;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _details = TextEditingController();
  ReportReason? _reason;

  /// Guards against a double tap firing two writes — the second would come back
  /// as "already reported" and confuse the person who only pressed once.
  bool _submitting = false;

  /// Which reasons need the text is [ReportReason.requiresDetails]' business,
  /// not this dialog's — it sits beside `code` and `label` so a reason added
  /// later cannot inherit "optional" by saying nothing.
  bool get _detailsRequired => _reason?.requiresDetails ?? false;

  /// The one definition of "may be sent" — the button, and `_submit`'s own
  /// guard, both ask this rather than restating the parts. Trimmed, because
  /// whitespace is not an explanation.
  bool get _canSubmit =>
      _reason != null &&
      !_submitting &&
      (!_detailsRequired || _details.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    // Rebuilds so the submit button un-greys as soon as the first character of
    // a required explanation is typed, rather than on the next unrelated
    // setState.
    _details.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final reason = _reason!;
    setState(() => _submitting = true);

    // Captured before the await: this dialog pops on the way out, so `context`
    // is not safe to read afterwards.
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final outcome = await ModerationService.instance.report(
      target: widget.target,
      reason: reason,
      details: _details.text,
    );

    if (!mounted) return;
    navigator.pop(outcome == ReportOutcome.submitted);

    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          ReportOutcome.submitted => l10n.reportSubmitted,
          ReportOutcome.alreadyReported => l10n.reportAlreadySubmitted,
          ReportOutcome.notSignedIn => l10n.reportSignInRequired,
          ReportOutcome.failed => l10n.reportFailed,
        }),
        backgroundColor:
            outcome == ReportOutcome.submitted ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.reportTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.reportReasonPrompt,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Scrolls inside the dialog rather than growing it: twelve reasons
            // do not fit on a small phone, and an AlertDialog that overflows
            // clips its actions rather than scrolling them into reach.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // RadioGroup rather than per-tile groupValue/onChanged:
                    // those are deprecated as of 3.32, and the whole point of
                    // this list is that the selection is single and shared.
                    RadioGroup<ReportReason>(
                      groupValue: _reason,
                      // Guarded rather than nulled out: RadioGroup's onChanged
                      // is non-nullable, so "disabled while submitting" has to
                      // be a no-op handler.
                      onChanged: (value) {
                        if (_submitting) return;
                        setState(() => _reason = value);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final reason in ReportReason.values)
                            // `identifier` rather than `label`: the row already
                            // exposes its own text, and a stable id is what
                            // element-based device automation targets (see
                            // CLAUDE.md).
                            Semantics(
                              identifier: 'report.reason.${reason.code}',
                              selected: _reason == reason,
                              child: RadioListTile<ReportReason>(
                                value: reason,
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                secondary: Icon(reason.icon, size: 20),
                                title: Text(reason.label(l10n)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _details,
                      enabled: !_submitting,
                      maxLines: 3,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      // Mirrors the 1000-char bound in firestore.rules — see
                      // the field-length invariant in docs/SPECIFICATION.md §12.
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          ModerationService.maxDetailsLength,
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: _detailsRequired
                            ? l10n.reportDetailsLabelRequired
                            : l10n.reportDetailsLabel,
                        // Only shown when it is actually a rule: a permanent
                        // nag under an optional field reads as a demand. It
                        // appears and disappears on a *radio tap*, never on a
                        // keystroke, so it cannot shift the field under a
                        // typing finger — which is why `update_note_dialog`
                        // keeps its own copy unconditional and this one does
                        // not.
                        //
                        // A `helper` widget rather than `helperText` for the
                        // reason that dialog documents at length: `helperText`
                        // is drawn with a hardcoded `TextOverflow.ellipsis` and
                        // clipped to one line unless `helperMaxLines` says
                        // otherwise, so this sentence lost its end at a large
                        // font scale — in Bulgarian, at any scale.
                        helper: _detailsRequired
                            ? Text(
                                l10n.reportDetailsRequired,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(l10n.reportSubmit),
        ),
      ],
    );
  }
}

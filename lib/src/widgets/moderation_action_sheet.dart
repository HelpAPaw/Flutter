import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../models/moderation_label.dart';
import '../models/moderation_target.dart';
import '../models/signal.dart';
import '../models/report_reason.dart';
import '../models/signal_urgency.dart';
import '../services/callable_client.dart';
import '../services/moderation_service.dart';
import 'section_header.dart';

/// What happened to the content, for the screen the moderator acted from.
///
/// Returned instead of the raw action name because the only thing a caller
/// needs to decide is whether the screen behind the sheet is still showing
/// something that exists — and a string comparison against `'hideSignal'` would
/// put a copy of the callable's action vocabulary in the widget layer.
enum ModerationOutcome {
  /// The content changed in place. The screen behind is still valid.
  applied,

  /// The target is gone — `hideSignal` moves the document to quarantine, so a
  /// details screen standing on it must not stay there.
  targetRemoved,
}

/// The moderator's action menu (master spec §18.3).
///
/// Every action here goes through the `moderateAction` callable rather than a
/// direct Firestore write, because every one has to leave an audit entry the
/// acting moderator cannot forge (§18.7). That is also why **the note is
/// mandatory**: the audit log's value is the reasoning, and an optional field
/// on a one-tap menu is empty essentially always — the same argument that made
/// the status-change note mandatory in `showUpdateNoteDialog`.
///
/// Which actions are offered depends on what [target] points at: a comment
/// target cannot lock a signal, and a target this build cannot decode is
/// narrowed to the actions that cannot mis-fire.
///
/// [reportId] is **optional**, and that is what lets a moderator act on their
/// own judgement. When it is present the action also resolves that report;
/// when it is absent the moderator is acting on something they came across
/// while browsing, and the server simply skips the report half (see
/// `functions/src/moderation.ts`). The "Dismiss report" row is hidden in that
/// case — there is nothing to dismiss.
///
/// [signal] lets a caller that has already parsed the document hand it over
/// rather than making the sheet re-read it.
Future<ModerationOutcome?> showModerationActionSheet(
  BuildContext context, {
  required ModerationTarget target,
  String? reportId,
  Signal? signal,
}) =>
    showModalBottomSheet<ModerationOutcome>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ModerationActionSheet(
        target: target,
        reportId: reportId,
        signal: signal,
      ),
    );

class _ModerationActionSheet extends StatefulWidget {
  const _ModerationActionSheet({
    required this.target,
    this.reportId,
    this.signal,
  });

  final ModerationTarget target;
  final String? reportId;
  final Signal? signal;

  @override
  State<_ModerationActionSheet> createState() => _ModerationActionSheetState();
}

class _ModerationActionSheetState extends State<_ModerationActionSheet> {
  final TextEditingController _note = TextEditingController();
  bool _busy = false;

  /// Current moderation state of the target signal, loaded once when the sheet
  /// opens unless the caller supplied it.
  ///
  /// Without it every action here was one-directional — "Lock comments" and a
  /// `disputed` label with no way back, because any action resolves the report
  /// and takes it out of the queue, so a second report only ever re-offered the
  /// same one-way rows. A lock applied by mistake was permanent.
  ///
  /// Null while loading and on failure; the rows then default to their "apply"
  /// direction, which is the safe reading — a moderator who cannot see the
  /// current state should not be told the content is already locked.
  ///
  /// Held as a parsed [Signal] rather than the raw map, so these predicates are
  /// the model's and cannot drift from the details screen's.
  Signal? _signal;
  bool _loadingModeration = true;

  bool get _commentsLocked => _signal?.commentsLocked ?? false;

  /// [Signal.hasModerationLabel], **not** `moderationLabel != null`: a toggle
  /// must offer "Clear" for a label code this build cannot decode, or a
  /// moderator on an older build could never remove a newer one.
  bool get _hasLabel => _signal?.hasModerationLabel ?? false;

  /// Whether an action row may fire: a note is written, nothing is in flight,
  /// and the current moderation state is known so the toggles point the right
  /// way. One definition used by the rows, their enabled state and `_run`.
  bool get _canAct =>
      !_busy && !_loadingModeration && _note.text.trim().isNotEmpty;

  ModerationTarget get _target => widget.target;

  @override
  void initState() {
    super.initState();
    // Enables the action rows the moment the note stops being blank.
    _note.addListener(() => setState(() {}));

    // A caller that already holds the document — the details screen is looking
    // at it — hands it over rather than paying for a second read of it.
    if (widget.signal != null) {
      _signal = widget.signal;
      _loadingModeration = false;
    } else {
      _loadModeration();
    }
  }

  /// Reads the target signal's `moderation` map so the toggles can point the
  /// right way. Signals are world-readable, so this needs no privilege.
  Future<void> _loadModeration() async {
    final signalId = _target.signalId;
    final collection = _target.collection;
    if (signalId == null || signalId.isEmpty || collection == null) {
      if (mounted) setState(() => _loadingModeration = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection(collection)
          .doc(signalId)
          .get();
      if (!mounted) return;
      setState(() {
        // `fromJson` is fully defaulted, so a partial document is safe.
        _signal = doc.exists ? Signal.fromJson(doc.data() ?? {}) : null;
        _loadingModeration = false;
      });
    } catch (e) {
      debugPrint('Could not read moderation state: $e');
      if (mounted) setState(() => _loadingModeration = false);
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Runs [action], reporting the outcome and closing the sheet on success.
  ///
  /// One funnel so no action can forget the busy guard, the mounted check or
  /// the error mapping. Two codes get their own message because both have a
  /// specific and actionable meaning here:
  ///
  /// - `permission-denied` — the role was revoked while the sheet was open,
  ///   exactly the case a document-based role makes possible and a cached auth
  ///   claim would have hidden until the token expired.
  /// - `failed-precondition` — the target is the moderator's own content. The
  ///   UI does not offer that, so reaching it means the content changed hands
  ///   or the caller skipped the check; either way "you cannot moderate your
  ///   own content" is the honest answer rather than a generic failure.
  Future<void> _run(
    ModerationOutcome outcome,
    Future<void> Function() action,
  ) async {
    if (!_canAct) return;
    setState(() => _busy = true);

    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      if (!mounted) return;
      navigator.pop(outcome);
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.moderationActionApplied),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final code = e is CallableException ? e.code : null;
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (code) {
            'permission-denied' => l10n.moderationPermissionDenied,
            'failed-precondition' => l10n.moderationSelfBlocked,
            _ => l10n.moderationActionFailed,
          }),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final service = ModerationService.instance;
    final note = _note.text.trim();
    final reportId = widget.reportId;
    // Both the collection and the signal id are required before any
    // signal-targeting row is offered — see ModerationTarget.fromReport for why
    // a missing collection must not default.
    final hasSignal = _target.canActOnSignal;
    final collection = _target.collection;
    final signalId = _target.signalId;

    return Padding(
      // Lifts the sheet above the keyboard — the note field is the first thing
      // a moderator touches, and every action is disabled until it is filled.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SectionHeader rather than the style inline: that widget exists
              // precisely because two private copies of this heading drifted.
              SectionHeader(l10n.moderation),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                enabled: !_busy,
                autofocus: true,
                maxLines: 3,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                // Mirrors MAX_EVENT_NOTE_LENGTH in functions/src/events.ts and
                // isValidEventNote() in the rules — a setUrgency note is
                // written straight into a timeline event.
                inputFormatters: [
                  LengthLimitingTextInputFormatter(
                    ModerationService.maxNoteLength,
                  ),
                ],
                decoration: InputDecoration(
                  labelText: l10n.moderationNoteLabel,
                  helperText: l10n.moderationNoteRequired,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              if (hasSignal && _target.type == ReportTargetType.signal) ...[
                _action(
                  icon: Icons.visibility_off,
                  label: l10n.moderationHideSignal,
                  // The signal document leaves `signals` entirely, so whatever
                  // screen opened this sheet is now looking at nothing.
                  onTap: () => _run(
                      ModerationOutcome.targetRemoved,
                      () => service.hideSignal(
                            collection: collection!,
                            signalId: signalId!,
                            note: note,
                            reportId: reportId,
                          )),
                ),
                // Both of these toggle off the signal's current state. Offering
                // only the "apply" direction made a lock or a label permanent:
                // acting resolves the report, so the queue never surfaced the
                // signal again to undo it.
                _action(
                  icon: _commentsLocked ? Icons.lock_open : Icons.lock_outline,
                  label: _commentsLocked
                      ? l10n.moderationUnlockComments
                      : l10n.moderationLockComments,
                  onTap: () => _run(
                      ModerationOutcome.applied,
                      () => service.setCommentsLocked(
                            collection: collection!,
                            signalId: signalId!,
                            locked: !_commentsLocked,
                            note: note,
                            reportId: reportId,
                          )),
                ),
                _action(
                  icon: _hasLabel
                      ? Icons.label_off_outlined
                      : Icons.label_outline,
                  label: _hasLabel
                      ? l10n.moderationClearLabel
                      : l10n.moderationSetLabel,
                  onTap: () => _run(
                      ModerationOutcome.applied,
                      () => service.setLabel(
                            collection: collection!,
                            signalId: signalId!,
                            label:
                                _hasLabel ? null : ModerationLabel.disputed.code,
                            note: note,
                            reportId: reportId,
                          )),
                ),
                // Spec §5.3: downgrading a misused urgency is the moderator
                // power the rules have been describing all along.
                _action(
                  icon: Icons.low_priority,
                  label: l10n.moderationSetUrgency,
                  onTap: () => _run(
                      ModerationOutcome.applied,
                      () => service.setUrgency(
                            collection: collection!,
                            signalId: signalId!,
                            urgency: SignalUrgency.green.code,
                            note: note,
                            reportId: reportId,
                          )),
                ),
              ],
              if (hasSignal && _target.type == ReportTargetType.comment)
                _action(
                  icon: Icons.delete_outline,
                  label: l10n.moderationDeleteComment,
                  // The comment drops out of the timeline stream on its own;
                  // the signal behind it is untouched.
                  onTap: () => _run(
                      ModerationOutcome.applied,
                      () => service.deleteComment(
                            collection: collection!,
                            signalId: signalId!,
                            commentId: _target.targetId,
                            note: note,
                            reportId: reportId,
                          )),
                ),
              // Only offered once the target decodes — a report from a build
              // newer than this one has nothing here to act on.
              if (_target.type != null)
                _action(
                  icon: Icons.sticky_note_2_outlined,
                  label: l10n.moderationAddNote,
                  onTap: () => _run(
                      ModerationOutcome.applied,
                      () => service.addNote(
                            targetType: _target.type!,
                            targetId: _target.targetId,
                            note: note,
                            collection: collection,
                            reportId: reportId,
                          )),
                ),
              // Only when this sheet was opened from a report. Acting on
              // something found while browsing has no report to dismiss.
              if (reportId != null)
                _action(
                  icon: Icons.check_circle_outline,
                  label: l10n.moderationDismissReport,
                  onTap: () => _run(
                      ModerationOutcome.applied,
                      () => service.resolveReport(
                            reportId: reportId,
                            actioned: false,
                            note: note,
                          )),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// One action row. Disabled until the note is written, and while a call is in
  /// flight — a double tap here would apply the action twice and audit it twice.
  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final enabled = _canAct;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(label),
      onTap: enabled ? onTap : null,
    );
  }
}

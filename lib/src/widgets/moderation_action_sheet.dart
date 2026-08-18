import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../models/signal_urgency.dart';
import '../services/callable_client.dart';
import '../services/moderation_service.dart';

/// The moderator's action menu for one report (master spec §18.3).
///
/// Every action here goes through the `moderateAction` callable rather than a
/// direct Firestore write, because every one has to leave an audit entry the
/// acting moderator cannot forge (§18.7). That is also why **the note is
/// mandatory**: the audit log's value is the reasoning, and an optional field
/// on a one-tap menu is empty essentially always — the same argument that made
/// the status-change note mandatory in `showUpdateNoteDialog`.
///
/// Which actions are offered depends on what the report points at: a comment
/// report cannot lock a signal, and a user report can only be noted or
/// dismissed until the restriction tier (§18.5) exists.
Future<void> showModerationActionSheet(
  BuildContext context, {
  required String reportId,
  required Map<String, dynamic> report,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ModerationActionSheet(
        reportId: reportId,
        report: report,
      ),
    );

class _ModerationActionSheet extends StatefulWidget {
  const _ModerationActionSheet({required this.reportId, required this.report});

  final String reportId;
  final Map<String, dynamic> report;

  @override
  State<_ModerationActionSheet> createState() => _ModerationActionSheetState();
}

class _ModerationActionSheetState extends State<_ModerationActionSheet> {
  final TextEditingController _note = TextEditingController();
  bool _busy = false;

  /// Current moderation state of the target signal, loaded once when the sheet
  /// opens.
  ///
  /// Without it every action here was one-directional — "Lock comments" and a
  /// `disputed` label with no way back, because any action resolves the report
  /// and takes it out of the queue, so a second report only ever re-offered the
  /// same one-way rows. A lock applied by mistake was permanent.
  ///
  /// Null while loading and on failure; the rows then default to their "apply"
  /// direction, which is the safe reading — a moderator who cannot see the
  /// current state should not be told the content is already locked.
  Map<String, dynamic>? _moderation;
  bool _loadingModeration = true;

  bool get _commentsLocked => _moderation?['commentsLocked'] == true;
  bool get _hasLabel => _moderation?['label'] != null;

  String get _targetType => widget.report['targetType'] as String? ?? '';
  String get _collection =>
      widget.report['collection'] as String? ?? 'signals';
  String? get _signalId => widget.report['signalId'] as String?;
  String get _targetId => widget.report['targetId'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    // Enables the action rows the moment the note stops being blank.
    _note.addListener(() => setState(() {}));
    _loadModeration();
  }

  /// Reads the target signal's `moderation` map so the toggles can point the
  /// right way. Signals are world-readable, so this needs no privilege.
  Future<void> _loadModeration() async {
    final signalId = _signalId;
    if (signalId == null || signalId.isEmpty) {
      if (mounted) setState(() => _loadingModeration = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc(signalId)
          .get();
      if (!mounted) return;
      setState(() {
        _moderation =
            (doc.data()?['moderation'] as Map<dynamic, dynamic>?)
                ?.cast<String, dynamic>();
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
  /// the error mapping. A `permission-denied` gets its own message because it
  /// has a specific and actionable meaning here — the role was revoked while
  /// the sheet was open, which is exactly the case a document-based role makes
  /// possible and a cached auth claim would have hidden until the token expired.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy || _note.text.trim().isEmpty) return;
    setState(() => _busy = true);

    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await action();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.moderationActionApplied),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final denied = e is CallableException && e.code == 'permission-denied';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            denied ? l10n.moderationPermissionDenied : l10n.moderationActionFailed,
          ),
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
    final signalId = _signalId;
    final hasSignal = signalId != null && signalId.isNotEmpty;

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
              Text(
                l10n.moderation,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
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
              if (hasSignal && _targetType == 'signal') ...[
                _action(
                  icon: Icons.visibility_off,
                  label: l10n.moderationHideSignal,
                  onTap: () => _run(() => service.hideSignal(
                        collection: _collection,
                        signalId: signalId,
                        note: note,
                        reportId: widget.reportId,
                      )),
                ),
                // Both of these toggle off the signal's current state. Offering
                // only the "apply" direction made a lock or a label permanent:
                // acting resolves the report, so the queue never surfaces the
                // signal again to undo it.
                _action(
                  icon: _commentsLocked ? Icons.lock_open : Icons.lock_outline,
                  label: _commentsLocked
                      ? l10n.moderationUnlockComments
                      : l10n.moderationLockComments,
                  onTap: () => _run(() => service.setCommentsLocked(
                        collection: _collection,
                        signalId: signalId,
                        locked: !_commentsLocked,
                        note: note,
                        reportId: widget.reportId,
                      )),
                ),
                _action(
                  icon: _hasLabel
                      ? Icons.label_off_outlined
                      : Icons.label_outline,
                  label: _hasLabel
                      ? l10n.moderationClearLabel
                      : l10n.moderationSetLabel,
                  onTap: () => _run(() => service.setLabel(
                        collection: _collection,
                        signalId: signalId,
                        label: _hasLabel ? null : 'disputed',
                        note: note,
                        reportId: widget.reportId,
                      )),
                ),
                // Spec §5.3: downgrading a misused urgency is the moderator
                // power the rules have been describing all along.
                _action(
                  icon: Icons.low_priority,
                  label: l10n.moderationSetUrgency,
                  onTap: () => _run(() => service.setUrgency(
                        collection: _collection,
                        signalId: signalId,
                        urgency: SignalUrgency.green.code,
                        note: note,
                        reportId: widget.reportId,
                      )),
                ),
              ],
              if (hasSignal && _targetType == 'comment')
                _action(
                  icon: Icons.delete_outline,
                  label: l10n.moderationDeleteComment,
                  onTap: () => _run(() => service.deleteComment(
                        collection: _collection,
                        signalId: signalId,
                        commentId: _targetId,
                        note: note,
                        reportId: widget.reportId,
                      )),
                ),
              _action(
                icon: Icons.sticky_note_2_outlined,
                label: l10n.moderationAddNote,
                onTap: () => _run(() => service.addNote(
                      targetType: _targetType,
                      targetId: _targetId,
                      note: note,
                      collection: _collection,
                      reportId: widget.reportId,
                    )),
              ),
              _action(
                icon: Icons.check_circle_outline,
                label: l10n.moderationDismissReport,
                onTap: () => _run(() => service.resolveReport(
                      reportId: widget.reportId,
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
    // Also gated on the moderation read, so a toggle can never fire while its
    // label still points the wrong way.
    final enabled = !_busy && !_loadingModeration && _note.text.trim().isNotEmpty;
    return ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(label),
      onTap: enabled ? onTap : null,
    );
  }
}

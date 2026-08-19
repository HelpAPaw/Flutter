import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../models/quarantined_signal.dart';
import '../services/app_preferences_service.dart';
import '../services/callable_client.dart';
import '../services/moderation_service.dart';

/// The signals a moderator has hidden, and the way to put one back
/// (master spec §18.3 — hiding is "temporarily", which requires reversibility).
///
/// **This tab exists because hiding was a one-way door.** `hideSignal` resolves
/// its originating report, which drops it out of the report queue — and that
/// queue was the only route to any moderator action. A hidden signal could not
/// be restored from the app at all; the callable worked, but nothing could
/// reach it.
///
/// **A Future, not a Stream.** The list comes from the `listQuarantined`
/// callable, because `moderationQuarantine` has no client rule match: a hidden
/// signal is unreadable by everyone, moderators included, and the server sends
/// down a summary rather than the withheld content. Pull to refresh; there is
/// nothing here that changes under the moderator.
class ModerationHiddenTab extends StatefulWidget {
  const ModerationHiddenTab({super.key});

  @override
  State<ModerationHiddenTab> createState() => _ModerationHiddenTabState();
}

class _ModerationHiddenTabState extends State<ModerationHiddenTab> {
  late Future<List<QuarantinedSignal>> _hidden;

  /// The collection this moderator is looking at, fixed for the tab's life so a
  /// refresh cannot silently switch which quarantine is listed.
  final String _collection = AppPreferencesService().signalsCollectionName;

  @override
  void initState() {
    super.initState();
    _hidden = _load();
  }

  Future<List<QuarantinedSignal>> _load() =>
      ModerationService.instance.listQuarantined(collection: _collection);

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _hidden = future);
    await future.catchError((_) => <QuarantinedSignal>[]);
  }

  Future<void> _confirmRestore(QuarantinedSignal signal) async {
    final note = await _askForNote(signal);
    if (note == null || !mounted) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ModerationService.instance.restoreSignal(
        collection: signal.collection,
        signalId: signal.signalId,
        note: note,
      );
      if (!mounted) return;
      await _refresh();
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.moderationActionApplied),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      final denied = e is CallableException && e.code == 'permission-denied';
      messenger.showSnackBar(SnackBar(
        content: Text(denied
            ? l10n.moderationPermissionDenied
            : l10n.moderationActionFailed),
        backgroundColor: Colors.red,
      ));
    }
  }

  /// The same mandatory note every other moderator action requires — a restore
  /// is as much a moderation decision as the hide was, and the audit entry's
  /// value is the reasoning.
  Future<String?> _askForNote(QuarantinedSignal signal) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final note = controller.text.trim();
            return AlertDialog(
              title: Text(l10n.moderationRestoreTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(signal.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(l10n.moderationRestoreBody),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setDialogState(() {}),
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
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed:
                      note.isEmpty ? null : () => Navigator.of(context).pop(note),
                  child: Text(l10n.moderationRestore),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<QuarantinedSignal>>(
        future: _hidden,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _scrollableMessage(
              icon: Icons.error_outline,
              text: l10n.errorGeneric,
            );
          }
          final hidden = snapshot.data ?? const <QuarantinedSignal>[];
          if (hidden.isEmpty) {
            return _scrollableMessage(
              icon: Icons.visibility_off_outlined,
              text: l10n.moderationHiddenEmpty,
            );
          }
          return ListView.separated(
            itemCount: hidden.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) => _row(l10n, hidden[index]),
          );
        },
      ),
    );
  }

  Widget _row(AppLocalizations l10n, QuarantinedSignal signal) {
    final hiddenAt = signal.hiddenAt;
    return ListTile(
      isThreeLine: signal.note.isNotEmpty,
      leading: const Icon(Icons.visibility_off),
      title: Text(signal.title.isEmpty ? signal.signalId : signal.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (hiddenAt != null)
                DateFormat.yMd(Localizations.localeOf(context).languageCode)
                    .add_jm()
                    .format(hiddenAt),
              if (signal.hiddenBy.isNotEmpty)
                l10n.moderationHiddenBy(signal.hiddenBy),
            ].join(' · '),
            style: const TextStyle(fontSize: 12),
          ),
          if (signal.note.isNotEmpty)
            Text(signal.note, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: Semantics(
        label: l10n.moderationRestore,
        button: true,
        child: IconButton(
          icon: const Icon(Icons.restore_from_trash),
          onPressed: () => _confirmRestore(signal),
        ),
      ),
      onTap: () => _confirmRestore(signal),
    );
  }

  /// Always scrollable, so pull-to-refresh still works on an empty or errored
  /// list — which is exactly when a moderator wants to retry.
  Widget _scrollableMessage({required IconData icon, required String text}) =>
      LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(text, textAlign: TextAlign.center),
                ),
              ],
            ),
          ),
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../models/quarantined_signal.dart';
import '../services/app_preferences_service.dart';
import '../services/callable_client.dart';
import '../services/moderation_service.dart';
import '../services/public_profile_service.dart';

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
  /// The list, held directly rather than behind a `FutureBuilder`.
  ///
  /// The Future form looked natural and did not survive device testing: after a
  /// restore, `_load()` demonstrably returned zero items and `setState` ran on
  /// a mounted State, yet the builder never re-ran and the restored signal
  /// stayed on screen — leaving a moderator staring at a row they had just
  /// removed, with no way to tell whether it had worked. Three explicit fields
  /// are what a FutureBuilder was managing anyway, and they can be set from a
  /// completed call directly, which is the one thing that does reliably repaint.
  List<QuarantinedSignal> _hidden = const [];
  bool _loading = true;
  bool _failed = false;

  /// Owned by the State, not by the dialog that uses it.
  ///
  /// Disposing it in the dialog's `whenComplete` looked right and crashed the
  /// screen: that callback fires on `Navigator.pop`, while the route's exit
  /// animation is still running and the `TextField` still depends on the
  /// controller — `'_dependents.isEmpty': is not true`. The restore itself had
  /// already succeeded, so the failure was a red screen over completed work.
  final TextEditingController _noteController = TextEditingController();

  /// Display names for the `hiddenBy` uids, resolved once per load.
  ///
  /// Filled by [_refresh] and read synchronously by [_row] rather than through a
  /// per-row `FutureBuilder`, for the same reason the list itself is: a builder
  /// on this screen did not reliably re-run. There are at most a handful of
  /// moderators, so this is a couple of reads per refresh, not one per row.
  Map<String, String> _hiddenByNames = const {};

  /// The collection this moderator is looking at, fixed for the tab's life so a
  /// refresh cannot silently switch which quarantine is listed.
  final String _collection = AppPreferencesService().signalsCollectionName;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final items = await ModerationService.instance
          .listQuarantined(collection: _collection);
      final names = await _resolveHiddenByNames(items);
      if (!mounted) return;
      setState(() {
        _hidden = items;
        _hiddenByNames = names;
        _loading = false;
        _failed = false;
      });
    } catch (e) {
      debugPrint('Could not list hidden signals: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// Looks up the display name behind each distinct `hiddenBy` uid.
  ///
  /// Names that do not resolve are simply absent, and [_row] falls back to
  /// "Unknown" — the same fallback the signal timeline uses for an account with
  /// no `publicProfiles` document. Never the raw uid: it is unreadable, and it
  /// is the only place in the app that showed one.
  Future<Map<String, String>> _resolveHiddenByNames(
    List<QuarantinedSignal> items,
  ) async {
    final uids = {
      for (final item in items)
        if (item.hiddenBy.isNotEmpty) item.hiddenBy,
    };

    final entries = await Future.wait(uids.map((uid) async {
      final name = await PublicProfileService.getName(uid);
      return MapEntry(uid, name);
    }));

    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
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
    _noteController.clear();
    return showDialog<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final note = _noteController.text.trim();
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
                    controller: _noteController,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: _body(l10n),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return _scrollableMessage(
        icon: Icons.error_outline,
        text: l10n.errorGeneric,
      );
    }
    if (_hidden.isEmpty) {
      return _scrollableMessage(
        icon: Icons.visibility_off_outlined,
        text: l10n.moderationHiddenEmpty,
      );
    }
    return ListView.separated(
      // Always scrollable so pull-to-refresh works even with one short row.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _hidden.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _row(l10n, _hidden[index]),
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
                l10n.moderationHiddenBy(
                  _hiddenByNames[signal.hiddenBy] ?? l10n.unknown,
                ),
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

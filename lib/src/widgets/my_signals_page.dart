import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/models/signal_status.dart';
import 'package:help_a_paw/src/models/signal_urgency.dart';
import 'package:help_a_paw/src/widgets/level_chip.dart';
import 'package:help_a_paw/src/widgets/urgency_picker.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:intl/intl.dart';

import '../config/routes.dart';
import '../models/removed_signal.dart';
import '../services/signal_removal_service.dart';
import '../utils/nav_extensions.dart';

Color _statusColor(int status) => SignalStatus.fromCode(status).color;

Color _urgencyColor(int urgency) => SignalUrgency.fromCode(urgency).color;

String _formatDate(BuildContext context, DateTime date) => DateFormat(
      'MMM d, yyyy',
      Localizations.localeOf(context).languageCode,
    ).format(date);

/// An empty-state block: icon, headline, hint.
Widget _emptyState(IconData icon, String headline, String hint) => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(headline,
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(hint,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );

class MySignalsPage extends StatelessWidget {
  const MySignalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Two tabs, because a removed signal has to be *findable* to be
    // recoverable. Without somewhere to see them, "you can restore it for 30
    // days" is a promise the app never keeps — the user taps Remove, the signal
    // vanishes, and nothing they can reach says otherwise. This list is the
    // whole difference between a bin and a delete.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.popOrHome(),
          ),
          title: Text(l10n.mySignals),
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              // "Active", not "My Signals" — the app bar already says whose
              // these are, and a tab repeating the screen title tells the user
              // nothing about what distinguishes it from the one beside it.
              Tab(text: l10n.activeSignals),
              Tab(text: l10n.removedSignals),
            ],
          ),
        ),
        body: StreamBuilder<User?>(
          initialData: FirebaseAuth.instance.currentUser,
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            final user = authSnapshot.data;

            if (user == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.pin_drop, size: 80, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(l10n.pleaseSignInToViewSignals),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.push(Routes.signIn),
                      child: Text(l10n.signIn),
                    ),
                  ],
                ),
              );
            }

            return TabBarView(
              children: [
                _ActiveSignalsTab(uid: user.uid),
                // Keyed by uid so a change of account builds a fresh State.
                // The removals stream is `late final` and captures the uid it
                // was created under; without this key the State survives a
                // sign-out and keeps streaming the previous account's bin,
                // which the rules then deny — an error message rather than a
                // leak, but a confusing one.
                _RemovedSignalsTab(key: ValueKey(user.uid)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The signals still on the map.
class _ActiveSignalsTab extends StatelessWidget {
  const _ActiveSignalsTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(AppPreferencesService().signalsCollectionName)
          .where('reporter',
              isEqualTo:
                  FirebaseFirestore.instance.collection('users').doc(uid))
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(l10n.errorWithMessage(snapshot.error.toString())),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return _emptyState(Icons.pin_drop_outlined, l10n.noSignalsYet,
              l10n.submittedSignalsAppearHere);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final signal = Signal.fromJson(doc.data() as Map<String, dynamic>);
            final createdAt = signal.createdAt as Timestamp?;
            final dateStr = createdAt != null
                ? _formatDate(context, createdAt.toDate())
                : l10n.unknownDate;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                // Tinted by urgency, not status: colour means "how bad is it"
                // everywhere in the app now, and a row whose avatar and chip
                // disagreed about what red meant would reintroduce exactly the
                // confusion this replaces.
                leading: CircleAvatar(
                  backgroundColor: _urgencyColor(signal.urgency).withAlpha(51),
                  child: Icon(
                    // The tag already carries an icon, so the row and the chips
                    // on the details screen cannot drift.
                    signal.primaryTag.icon,
                    color: _urgencyColor(signal.urgency),
                  ),
                ),
                title: Text(
                  signal.title.isNotEmpty
                      ? signal.title
                      : signal.primaryTag.neededLabel(l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(signal.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        UrgencyChip(urgency: signal.urgency),
                        LevelChip(
                          color: _statusColor(signal.status),
                          label: SignalStatus.fromCode(signal.status).label(l10n),
                        ),
                        Text(dateStr,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.signalDetails(doc.id)),
              ),
            );
          },
        );
      },
    );
  }
}

/// Signals this user took down, still inside the recovery window.
///
/// Stateful for one reason: an in-flight restore or purge has to disable its own
/// row's buttons. Both are server round trips, and a double tap on Restore
/// races two writes at the same id — the second comes back `already-exists`,
/// reporting a failure for something that in fact succeeded.
class _RemovedSignalsTab extends StatefulWidget {
  const _RemovedSignalsTab({super.key});

  @override
  State<_RemovedSignalsTab> createState() => _RemovedSignalsTabState();
}

class _RemovedSignalsTabState extends State<_RemovedSignalsTab> {
  final _service = SignalRemovalService();

  /// The removals stream, subscribed **once**.
  ///
  /// `late final`, not a call inside `build()`. `StreamBuilder` keys off stream
  /// *identity*, so a fresh `watchMine()` per build cancels the Firestore
  /// listener and opens a new one — and `_run` calls `setState` twice, at the
  /// start and end of every action. The visible symptom is the whole list
  /// blinking back to a spinner the moment you tap Restore; the invisible one
  /// is a billed listen per rebuild.
  late final Stream<List<RemovedSignal>> _removals = _service.watchMine();

  /// Signal ids with an action in flight.
  final _busy = <String>{};

  Future<void> _run(
    String signalId,
    Future<void> Function() action,
    String Function(AppLocalizations) success,
    String Function(AppLocalizations) failure,
  ) async {
    if (_busy.contains(signalId)) return;
    setState(() => _busy.add(signalId));
    try {
      await action();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success(l10n)),
        backgroundColor: Colors.green,
      ));
    } catch (_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failure(l10n)),
        backgroundColor: Colors.red,
      ));
    } finally {
      // The row usually disappears from the stream on success, so this only
      // matters on failure — but a missed `mounted` check here would leave
      // every button on the tab permanently disabled.
      if (mounted) setState(() => _busy.remove(signalId));
    }
  }

  Future<void> _confirmPurge(RemovedSignal removed) async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deletePermanently),
        content: Text(l10n.confirmDeletePermanently),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _run(
      removed.signalId,
      () => _service.deletePermanently(removed.signalId),
      (l10n) => l10n.signalDeletedPermanently,
      (l10n) => l10n.errorGeneric,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<List<RemovedSignal>>(
      stream: _removals,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(l10n.errorWithMessage(snapshot.error.toString())),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final removals = snapshot.data ?? const <RemovedSignal>[];

        if (removals.isEmpty) {
          return _emptyState(Icons.delete_outline, l10n.removedSignals,
              l10n.noRemovedSignals);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: removals.length,
          itemBuilder: (context, index) {
            final removed = removals[index];
            final signal = removed.signal;
            final busy = _busy.contains(removed.signalId);
            final purgeAt = removed.purgeAt;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.withAlpha(51),
                      child: Icon(signal.primaryTag.icon, color: Colors.grey),
                    ),
                    title: Text(
                      signal.title.isNotEmpty
                          ? signal.title
                          : signal.primaryTag.neededLabel(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(signal.description,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        // The deadline, not the removal date: what the user
                        // needs from this row is how long they still have.
                        // `purgeAt` is null only while the server timestamp is
                        // still in flight, which resolves on its own.
                        if (purgeAt != null)
                          Text(
                            l10n.restorableUntil(
                                _formatDate(context, purgeAt)),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _confirmPurge(removed),
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red),
                          child: Text(l10n.deletePermanently),
                        ),
                        TextButton(
                          onPressed: () => _run(
                            removed.signalId,
                            () => _service.restore(removed.signalId),
                            (l10n) => l10n.signalRestored,
                            (l10n) => l10n.failedToRestoreSignal,
                          ),
                          child: Text(l10n.restoreSignalAction),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

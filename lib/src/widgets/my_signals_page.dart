import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/src/widgets/level_chip.dart';
import 'package:help_a_paw/src/services/app_providers.dart';

import '../config/routes.dart';
import '../models/removed_signal.dart';
import '../services/signal_removal_service.dart';
import 'app_bar_title.dart';
import 'signal_list_tile.dart';
import 'status_view.dart';
import 'page_width.dart';


class MySignalsPage extends ConsumerStatefulWidget {
  const MySignalsPage({super.key});

  @override
  ConsumerState<MySignalsPage> createState() => _MySignalsPageState();
}

class _MySignalsPageState extends ConsumerState<MySignalsPage> {
  late final Stream<User?> _auth = FirebaseAuth.instance.authStateChanges();

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
          // A tab root — nothing beneath it to escape to.
          automaticallyImplyLeading: false,
          title: AppBarTitle(l10n.mySignals),
          bottom: TabBar(
            // On the brand app bar, so the ink is onPrimary — white in light,
            // black in dark — not a hardcoded white.
            indicatorColor: Theme.of(context).colorScheme.onPrimary,
            labelColor: Theme.of(context).colorScheme.onPrimary,
            unselectedLabelColor: Theme.of(context).colorScheme.onPrimary.withAlpha(178),
            tabs: [
              // "Active", not "My Signals" — the app bar already says whose
              // these are, and a tab repeating the screen title tells the user
              // nothing about what distinguishes it from the one beside it.
              Tab(text: l10n.activeSignals),
              Tab(text: l10n.removedSignals),
            ],
          ),
        ),
        body: PageWidth(child: StreamBuilder<User?>(
          initialData: FirebaseAuth.instance.currentUser,
          // A held stream: `authStateChanges()` returns a new object per call,
          // and StreamBuilder compares by identity, so building it here would
          // cancel and re-listen on every rebuild.
          stream: _auth,
          builder: (context, authSnapshot) {
            final user = authSnapshot.data;

            if (user == null) {
              return StatusView.signIn(
                icon: Icons.pin_drop_outlined,
                title: l10n.pleaseSignInToViewSignals,
                onSignIn: () => context.push(Routes.signIn),
                signInLabel: l10n.signIn,
              );
            }

            return TabBarView(
              children: [
                const _ActiveSignalsTab(),
                // Keyed by uid so a change of account builds a fresh State.
                // The removals stream is `late final` and captures the uid it
                // was created under; without this key the State survives a
                // sign-out and keeps streaming the previous account's bin,
                // which the rules then deny — an error message rather than a
                // leak, but a confusing one.
                //
                // Keyed by test mode for the same reason: `watchMine` reads
                // `signalsCollectionName` when the stream is *created* and
                // filters on it in memory, so as a permanent tab this list
                // would go on showing the other mode's bin for the rest of the
                // session after the seven-tap gesture.
                const _RemovedSignalsTab(),
              ],
            );
          },
        ),
        ),
      ),
    );
  }
}

/// The signals still on the map: everything this user reported, plus everything
/// they hold.
///
/// "Plus everything they hold" is new — the list used to be `reporter == me`
/// alone, so a signal handed to you for coordination appeared nowhere you could
/// find it again.
class _ActiveSignalsTab extends ConsumerWidget {
  const _ActiveSignalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uid = ref.watch(sessionUidProvider).value;
    final userRef = uid == null
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);

    // No memoized stream and no ValueKey: `mySignalsProvider` declares its
    // dependency on the account and the collection, so Riverpod disposes and
    // rebuilds it when either changes — which is what the hand-rolled keys here
    // were reproducing.
    return ref.watch(mySignalsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            // The exception is for us, not for the reader — "PERMISSION_DENIED:
            // Missing or insufficient permissions" is a fact about our rules
            // that nobody can act on.
            debugPrint('My Signals stream failed: $error');
            return StatusView.error(
              title: l10n.couldNotLoadSignals,
              hint: l10n.couldNotLoadSignalsHint,
              onRetry: () => ref.invalidate(mySignalsProvider),
            );
          },
          data: (entries) {
            if (entries.isEmpty) {
              return StatusView.empty(
                icon: Icons.pin_drop_outlined,
                title: l10n.noSignalsYet,
                hint: l10n.submittedSignalsAppearHere,
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                // `entry.signal` is already parsed — `SignalWithId.fromDocument`
                // did it. Re-parsing per row, per build, is pure waste.
                final entry = entries[index];
                final signal = entry.signal;
                // Answers "why is this in my list" for a signal somebody else
                // reported and handed over.
                final heldNotReported = signal.reporter != userRef;

                return SignalListTile(
                  signal: signal,
                  badge: heldNotReported
                      ? LevelChip.status(
                          icon: Icons.assignment_ind_outlined,
                          label: l10n.ownedByYou,
                        )
                      : null,
                  onTap: () => context.push(Routes.signalDetails(entry.id)),
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
class _RemovedSignalsTab extends ConsumerStatefulWidget {
  const _RemovedSignalsTab();

  @override
  ConsumerState<_RemovedSignalsTab> createState() =>
      _RemovedSignalsTabState();
}

class _RemovedSignalsTabState extends ConsumerState<_RemovedSignalsTab> {
  final _service = SignalRemovalService();

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

    // The provider declares its own dependency on the account and the
    // collection, so the memoized stream and the two keys this used to carry are
    // Riverpod's job now.
    return ref.watch(removedSignalsProvider).when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) {
        debugPrint('Removed signals stream failed: $error');
        return StatusView.error(
          title: l10n.couldNotLoadSignals,
          hint: l10n.couldNotLoadSignalsHint,
          onRetry: () => ref.invalidate(removedSignalsProvider),
        );
      },
      data: (removals) {
        if (removals.isEmpty) {
          return StatusView.empty(
            icon: Icons.delete_outline,
            title: l10n.removedSignals,
            hint: l10n.noRemovedSignals,
          );
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
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                      child: Icon(signal.primaryTag.icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    title: Text(
                      signal.displayTitle(l10n),
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
                                SignalListTile.formatDate(context, purgeAt)),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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

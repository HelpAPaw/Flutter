import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../config/routes.dart';
import '../services/app_preferences_service.dart';
import '../services/signal_subscription_service.dart';
import '../utils/chunk.dart';
import '../utils/signal_merge.dart';
import '../utils/stream_merge.dart';
import '../viewmodels/map_view_model.dart';
import 'app_bar_title.dart';
import 'page_width.dart';
import 'signal_list_tile.dart';
import 'status_view.dart';

/// Signals the user follows — i.e. gets notified about — that are not their own.
///
/// "Not their own" is resolved **after** the documents are fetched, by asking
/// the parsed [Signal] rather than re-deriving the rule from the raw map. Doing
/// it here rather than by subtracting a second query costs nothing: the
/// documents are already in hand, and `Signal.isHeldBy` is exact for the
/// tri-state `signalOwner` (absent means the reporter holds it) in a way an
/// equality query is not.
class WatchingPage extends ConsumerWidget {
  const WatchingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // Watched, not read once: this screen lives for the whole session inside the
    // shell, so a mid-session test-mode toggle has to re-point every query. The
    // collection name is captured when a listener is *created*.
    final testMode = ref.watch(testModeProvider);

    return Scaffold(
      appBar: AppBar(
        // A tab root — nothing beneath it to go back to.
        automaticallyImplyLeading: false,
        title: AppBarTitle(l10n.watching),
      ),
      body: PageWidth(
        child: _WatchedList(
          // A new State, and so a fresh set of listeners, whenever the account
          // or the mode changes.
          key: ValueKey('$testMode:${FirebaseAuth.instance.currentUser?.uid}'),
          collection: AppPreferencesService().signalsCollectionName,
        ),
      ),
    );
  }
}

class _WatchedList extends StatefulWidget {
  const _WatchedList({super.key, required this.collection});

  final String collection;

  @override
  State<_WatchedList> createState() => _WatchedListState();
}

class _WatchedListState extends State<_WatchedList> {
  /// How many followed signals are loaded. Two `whereIn` chunks to start.
  ///
  /// The subscription array is unbounded and nothing prunes it, so the tab must
  /// not be "one read per signal you have ever commented on". This caps the cost
  /// of opening it at 60 documents however long the array is.
  static const _pageSize = firestoreWhereInLimit * 2;

  int _limit = _pageSize;

  /// Ids whose unfollow is in flight, so the row does not linger while the
  /// write lands.
  final Set<String> _pendingUnfollow = <String>{};

  /// Held, not rebuilt. **Every one of these returns a new object per call** —
  /// `authStateChanges()` and `watchSubscriptions()` both do — and
  /// `StreamBuilder` compares streams by identity, so building them in `build`
  /// makes each rebuild cancel and re-listen. For the subscriptions stream that
  /// is not merely churn: its builder branches on `connectionState`, so the
  /// subtree below it is discarded, which cancels `mergeLatestList` and with it
  /// every `whereIn` chunk listener — turning one Unfollow tap into a re-read of
  /// the whole loaded window.
  late final Stream<User?> _auth = FirebaseAuth.instance.authStateChanges();
  late final Stream<Set<String>> _subscriptions =
      SignalSubscriptionService.instance.watchSubscriptions();

  /// The merged chunk queries, memoized against the id window they were built
  /// for — the same reason `_ActiveSignalsTab` and `_RemovedSignalsTab` memoize
  /// theirs.
  Stream<List<QuerySnapshot<Map<String, dynamic>>>>? _signals;
  List<String>? _window;

  Stream<List<QuerySnapshot<Map<String, dynamic>>>> _signalsFor(
    List<String> window,
  ) {
    if (_signals == null || !listEquals(_window, window)) {
      _window = window;
      _signals = mergeLatestList(
        chunked(window, firestoreWhereInLimit)
            .map((ids) => FirebaseFirestore.instance
                .collection(widget.collection)
                .where(FieldPath.documentId, whereIn: ids)
                .snapshots())
            .toList(),
      );
    }
    return _signals!;
  }

  Future<void> _unfollow(String signalId) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _pendingUnfollow.add(signalId));
    try {
      await SignalSubscriptionService.instance.unfollow(signalId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.unfollowedSignal),
          action: SnackBarAction(
            label: l10n.undo,
            onPressed: () => SignalSubscriptionService.instance.follow(signalId),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Unfollow failed: $e');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.followFailed)));
    } finally {
      if (mounted) setState(() => _pendingUnfollow.remove(signalId));
    }
  }

  Widget _emptyState(AppLocalizations l10n) => StatusView.empty(
        icon: Icons.visibility_outlined,
        title: l10n.noWatchedSignals,
        hint: l10n.watchedSignalsHint,
      );

  Widget _loadMoreButton(AppLocalizations l10n) => Center(
        child: TextButton(
          onPressed: () => setState(() => _limit += firestoreWhereInLimit),
          child: Text(l10n.loadMore),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<User?>(
      initialData: FirebaseAuth.instance.currentUser,
      stream: _auth,
      builder: (context, authSnapshot) {
        final user = authSnapshot.data;
        if (user == null || user.isAnonymous) {
          return StatusView.signIn(
            icon: Icons.visibility_outlined,
            title: l10n.pleaseSignInToViewSignals,
            onSignIn: () => context.push(Routes.signIn),
            signInLabel: l10n.signIn,
          );
        }
        return _buildList(context, l10n, user.uid);
      },
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n, String uid) {
    return StreamBuilder<Set<String>>(
      stream: _subscriptions,
      builder: (context, subsSnapshot) {
        if (subsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Newest-followed first: `arrayUnion` appends, and re-adding an id that
        // is already there does not move it, so the tail of the array is the
        // most recent interest.
        final all =
            (subsSnapshot.data ?? const <String>{}).toList().reversed.toList();
        if (all.isEmpty) return _emptyState(l10n);

        final window = all.take(_limit).toList();
        final hasMore = all.length > window.length;

        return StreamBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
          stream: _signalsFor(window),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('Watching stream failed: ${snapshot.error}');
              return StatusView.error(
                title: l10n.couldNotLoadWatched,
                hint: l10n.couldNotLoadSignalsHint,
                onRetry: () => setState(() {
                  _signals = null;
                  _window = null;
                }),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Ids that come back from no chunk are simply absent: a removed
            // signal, one purged after its recovery window, or an id belonging
            // to the other collection while test mode is the other way round.
            // Nothing to filter and nothing to report.
            final entries = sortNewestFirst(
              snapshot.data!.expand((s) => s.docs),
            );

            final userRef =
                FirebaseFirestore.instance.collection('users').doc(uid);
            final theirs = entries.where((entry) {
              if (_pendingUnfollow.contains(entry.id)) return false;
              final signal = entry.signal;
              return signal.reporter != userRef && !signal.isHeldBy(uid);
            }).toList();

            // `hasMore` is counted before the filter above, so a window can come
            // back entirely filtered out while there are still older ids to page
            // to. Reporting a signal subscribes you to it, and that is the main
            // way this array grows — so somebody who reported the last 60
            // signals they follow would otherwise be shown "you are not
            // following anything" with no way to reach the ones they are.
            if (theirs.isEmpty) {
              return hasMore ? _loadMoreButton(l10n) : _emptyState(l10n);
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: theirs.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == theirs.length) return _loadMoreButton(l10n);

                final entry = theirs[index];
                return SignalListTile(
                  signal: entry.signal,
                  onTap: () => context.push(Routes.signalDetails(entry.id)),
                  trailing: PopupMenuButton<void>(
                    // An explicit menu as well as a swipe: every other list in
                    // this app is tap-to-open, so a swipe-only action would be
                    // invisible to anyone who has not been told about it.
                    tooltip: l10n.unfollow,
                    itemBuilder: (context) => [
                      PopupMenuItem<void>(
                        onTap: () => _unfollow(entry.id),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.notifications_off_outlined),
                          title: Text(l10n.unfollow),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

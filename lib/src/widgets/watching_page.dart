import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../config/routes.dart';
import '../models/signal.dart';
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
/// "Not their own" is resolved **after** the documents are fetched, by comparing
/// `reporter` and `signalOwner` against the current uid. Doing it here rather
/// than by subtracting a second query costs nothing: the documents are already
/// in hand, and it is exact for the tri-state `signalOwner` (absent means the
/// reporter holds it) in a way an equality query is not.
class WatchingPage extends ConsumerStatefulWidget {
  const WatchingPage({super.key});

  @override
  ConsumerState<WatchingPage> createState() => _WatchingPageState();
}

class _WatchingPageState extends ConsumerState<WatchingPage> {
  /// How many followed signals are loaded. Two `whereIn` chunks to start.
  ///
  /// The subscription array is unbounded and nothing prunes it, so the tab must
  /// not be "one read per signal you have ever commented on". This caps the cost
  /// of opening it at 60 documents however long the array is.
  static const _pageSize = firestoreWhereInLimit * 2;

  int _limit = _pageSize;

  /// Bumped by Retry, to tear down a failed listen and start a fresh one.
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Watched, not read once: this screen lives for the whole session inside the
    // shell, so a mid-session test-mode toggle has to re-point every query. The
    // collection name is captured when a listener is *created*.
    final testMode = ref.watch(testModeProvider);
    final collection = AppPreferencesService().signalsCollectionName;

    return Scaffold(
      appBar: AppBar(
        // A tab root — nothing beneath it to go back to.
        automaticallyImplyLeading: false,
        title: AppBarTitle(l10n.watching),
      ),
      body: PageWidth(
        child: StreamBuilder<User?>(
          initialData: FirebaseAuth.instance.currentUser,
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            final user = authSnapshot.data;
            if (user == null || user.isAnonymous) {
              return _SignInWall(l10n: l10n);
            }
            return _WatchedList(
              key: ValueKey('$testMode:${user.uid}:$_limit:$_attempt'),
              uid: user.uid,
              collection: collection,
              limit: _limit,
              onRetry: () => setState(() => _attempt++),
              onLoadMore: () =>
                  setState(() => _limit += firestoreWhereInLimit),
            );
          },
        ),
      ),
    );
  }
}

class _SignInWall extends StatelessWidget {
  const _SignInWall({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 80,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
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
}

class _WatchedList extends StatefulWidget {
  const _WatchedList({
    super.key,
    required this.uid,
    required this.collection,
    required this.limit,
    required this.onRetry,
    required this.onLoadMore,
  });

  final String uid;
  final String collection;
  final int limit;
  final VoidCallback onRetry;
  final VoidCallback onLoadMore;

  @override
  State<_WatchedList> createState() => _WatchedListState();
}

class _WatchedListState extends State<_WatchedList> {
  /// Ids whose unfollow is in flight or has just been undone, so the row does
  /// not flicker back while the write lands.
  final Set<String> _pendingUnfollow = <String>{};

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<Set<String>>(
      stream: SignalSubscriptionService.instance.watchSubscriptions(),
      builder: (context, subsSnapshot) {
        if (subsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Newest-followed first: `arrayUnion` appends, and re-adding an id that
        // is already there does not move it, so the tail of the array is the
        // most recent interest.
        final all = (subsSnapshot.data ?? const <String>{}).toList().reversed
            .toList();
        if (all.isEmpty) {
          return StatusView.empty(
            icon: Icons.visibility_outlined,
            title: l10n.noWatchedSignals,
            hint: l10n.watchedSignalsHint,
          );
        }

        final window = all.take(widget.limit).toList();
        final hasMore = all.length > window.length;

        final chunks = chunked(window, firestoreWhereInLimit)
            .map((ids) => FirebaseFirestore.instance
                .collection(widget.collection)
                .where(FieldPath.documentId, whereIn: ids)
                .snapshots())
            .toList();

        return StreamBuilder<List<QuerySnapshot<Map<String, dynamic>>>>(
          stream: mergeLatestList(chunks),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint('Watching stream failed: ${snapshot.error}');
              return StatusView.error(
                title: l10n.couldNotLoadWatched,
                hint: l10n.couldNotLoadSignalsHint,
                onRetry: widget.onRetry,
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            // Ids that come back from no chunk are simply absent: a removed
            // signal, one purged after its recovery window, or an id belonging
            // to the other collection while test mode is the other way round.
            // Nothing to filter and nothing to report.
            final docs = snapshot.data!.expand((s) => s.docs).toList();

            final userRef =
                FirebaseFirestore.instance.collection('users').doc(widget.uid);
            final theirs = docs.where((doc) {
              final data = doc.data();
              if (data['reporter'] == userRef) return false;
              // Tri-state: only an explicit reference means somebody holds it.
              final owner = data['signalOwner'];
              return !(owner is DocumentReference && owner == userRef);
            }).toList();

            final signals = sortNewestFirst(theirs)
                .where((s) => !_pendingUnfollow.contains(s.id))
                .toList();

            if (signals.isEmpty) {
              return StatusView.empty(
                icon: Icons.visibility_outlined,
                title: l10n.noWatchedSignals,
                hint: l10n.watchedSignalsHint,
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: signals.length + (hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == signals.length) {
                  return Center(
                    child: TextButton(
                      onPressed: widget.onLoadMore,
                      child: Text(l10n.loadMore),
                    ),
                  );
                }

                final entry = signals[index];
                final signal = Signal.fromJson(entry.rawData);
                return SignalListTile(
                  signal: signal,
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

import '../config/routes.dart';
import '../services/app_providers.dart';
import '../services/signal_subscription_service.dart';
import '../services/watching_service.dart';
import 'app_bar_title.dart';
import 'page_width.dart';
import 'signal_list_tile.dart';
import 'status_view.dart';

/// Signals the user follows — i.e. gets notified about — that are not their own.
///
/// Renders; it does not query. The chunking, the own-signal filter and the
/// paging arithmetic live in [WatchingService], where they can be unit-tested,
/// and the account/mode invalidation is declared by the providers rather than
/// hand-tracked here.
class WatchingPage extends ConsumerWidget {
  const WatchingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final uid = ref.watch(sessionUidProvider).value;

    return Scaffold(
      appBar: AppBar(
        // A tab root — nothing beneath it to go back to.
        automaticallyImplyLeading: false,
        title: AppBarTitle(l10n.watching),
      ),
      body: PageWidth(
        child: uid == null
            ? StatusView.signIn(
                icon: Icons.visibility_outlined,
                title: l10n.pleaseSignInToViewSignals,
                onSignIn: () => context.push(Routes.signIn),
                signInLabel: l10n.signIn,
              )
            : _WatchedList(l10n: l10n),
      ),
    );
  }
}

class _WatchedList extends ConsumerStatefulWidget {
  const _WatchedList({required this.l10n});

  final AppLocalizations l10n;

  @override
  ConsumerState<_WatchedList> createState() => _WatchedListState();
}

class _WatchedListState extends ConsumerState<_WatchedList> {
  /// Ids whose unfollow is in flight, so the row does not linger while the
  /// write lands.
  final Set<String> _pendingUnfollow = <String>{};

  Future<void> _unfollow(String signalId) async {
    final l10n = widget.l10n;
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
    final l10n = widget.l10n;

    return ref.watch(watchingProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            debugPrint('Watching stream failed: $error');
            return StatusView.error(
              title: l10n.couldNotLoadWatched,
              hint: l10n.couldNotLoadSignalsHint,
              onRetry: () => ref.invalidate(watchingProvider),
            );
          },
          data: (page) {
            // The follow list as well as the pending set: the page without an
            // unfollowed row waits for a fresh query, which can lose the race
            // with the write's acknowledgement — and the follow list already
            // has the answer, from the write's local snapshot.
            final subscriptions = SignalSubscriptionService.instance;
            final signals = page.signals
                .where((entry) =>
                    !_pendingUnfollow.contains(entry.id) &&
                    subscriptions.isFollowing(entry.id))
                .toList();

            if (signals.isEmpty) {
              // `hasMore` is counted after the own-signal filter, so an empty
              // page with more to load genuinely means "keep going" rather than
              // "nothing here".
              return page.hasMore
                  ? _loadMore(l10n)
                  : StatusView.empty(
                      icon: Icons.visibility_outlined,
                      title: l10n.noWatchedSignals,
                      hint: l10n.watchedSignalsHint,
                    );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: signals.length + (page.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == signals.length) return _loadMore(l10n);

                final entry = signals[index];
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
  }

  Widget _loadMore(AppLocalizations l10n) => Center(
        child: TextButton(
          onPressed: () =>
              ref.read(watchingLimitProvider.notifier).loadMore(),
          child: Text(l10n.loadMore),
        ),
      );
}

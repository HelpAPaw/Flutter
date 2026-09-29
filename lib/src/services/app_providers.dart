import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/removed_signal.dart';
import '../repositories/signal_repository.dart';
import '../utils/chunk.dart';
import '../utils/stream_merge.dart';
import '../viewmodels/map_view_model.dart';
import 'my_signals_service.dart';
import 'signal_subscription_service.dart';
import 'notification_inbox_service.dart';
import 'signal_removal_service.dart';
import 'watching_service.dart';

/// The providers that carry the two things every per-account, per-mode query
/// depends on — **who is signed in** and **which mode the app is in** — so that
/// depending on them is something you declare rather than something you have to
/// remember.
///
/// Both are captured at subscription time by the queries underneath, so a stream
/// held across a sign-out or across the seven-tap test-mode gesture silently
/// serves the wrong account or the wrong collection. Before this, four screens
/// each hand-tracked that in nullable key fields and rebuild-if-changed checks,
/// and a fifth screen added later would have inherited none of it. Riverpod
/// disposes and rebuilds a provider when a watched dependency changes, which is
/// exactly the semantics those checks were open-coding.

/// The signed-in uid, as a stream.
final sessionUidProvider = StreamProvider<String?>(
  (ref) => FirebaseAuth.instance.authStateChanges().map((user) => user?.uid),
);

/// `signals` or `signals_test`, derived rather than re-read.
final signalsCollectionProvider = Provider<String>(
  (ref) => ref.watch(testModeProvider) ? 'signals_test' : 'signals',
);

/// Unread inbox entries, for the bottom bar's badge.
final unreadCountProvider = StreamProvider<int>((ref) {
  ref.watch(sessionUidProvider);
  return NotificationInboxService()
      .watchUnreadCount(testMode: ref.watch(testModeProvider));
});

/// The inbox list. Null means "nobody is signed in", which the screen renders
/// differently from an empty inbox.
final inboxProvider =
    StreamProvider<QuerySnapshot<Map<String, dynamic>>?>((ref) {
  ref.watch(sessionUidProvider);
  final stream = NotificationInboxService()
      .watchInbox(testMode: ref.watch(testModeProvider));
  return stream ?? Stream.value(null);
});

/// Signals the user reported or holds, newest first.
final mySignalsProvider = StreamProvider<List<SignalWithId>>((ref) {
  final uid = ref.watch(sessionUidProvider).value;
  if (uid == null) return Stream.value(const []);
  return MySignalsService(collection: ref.watch(signalsCollectionProvider))
      .watchMine(uid);
});

/// The user's own removed signals, still inside the recovery window.
final removedSignalsProvider = StreamProvider<List<RemovedSignal>>((ref) {
  ref.watch(sessionUidProvider);
  return SignalRemovalService()
      .watchMine(collection: ref.watch(signalsCollectionProvider));
});

/// How many followed signals the Watching tab has asked for.
///
/// Raised by "Load more", and reset whenever the account or the mode changes —
/// the `ref.watch` calls in [build] are what make that automatic, rather than
/// something the screen has to remember to undo.
class WatchingLimit extends Notifier<int> {
  @override
  int build() {
    ref.watch(sessionUidProvider);
    ref.watch(signalsCollectionProvider);
    return WatchingService.pageSize;
  }

  void loadMore() => state += firestoreWhereInLimit;
}

final watchingLimitProvider =
    NotifierProvider<WatchingLimit, int>(WatchingLimit.new);

/// Signals the user follows that are not their own.
final watchingProvider = StreamProvider<WatchedPage>((ref) {
  final uid = ref.watch(sessionUidProvider).value;
  if (uid == null) return Stream.value(WatchedPage.empty);

  final service = WatchingService(
    collection: ref.watch(signalsCollectionProvider),
    uid: uid,
  );
  final limit = ref.watch(watchingLimitProvider);

  // The follow list drives the query, so a follow or unfollow re-pages without
  // the screen having to ask. Switched rather than expanded: the query never
  // completes, and `asyncExpand` would wait on it forever (#86).
  //
  // An unfollowed row leaves at once, from the last page shown, rather than
  // when the fresh query answers — which can be after the write's own
  // acknowledgement, and the screen would show it again in between.
  WatchedPage? shown;
  return switchLatest(
    SignalSubscriptionService.instance.watchSubscriptions(),
    (Set<String> ids) async* {
      final previous = shown;
      if (previous != null) {
        final kept = previous.retainOnly(ids);
        if (kept.signals.length < previous.signals.length) yield kept;
      }
      yield* service.watch(ids.toList(), limit: limit);
    },
  ).map((page) => shown = page);
});

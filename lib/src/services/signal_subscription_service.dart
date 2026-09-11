import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../repositories/repository_provider.dart';

/// Which signals the user follows.
///
/// "Follow" here is not a bookmark — `users/{uid}.signalSubscriptions` **is** the
/// notification fan-out list that `functions/src/index.ts` queries with
/// `array-contains` when a signal changes. Following a signal means being told
/// about it; unfollowing means being left alone. Every label in the UI should
/// say so.
///
/// The array is written by four paths today, all `arrayUnion`: creating a
/// signal, posting a comment, changing a status or urgency, and claiming
/// ownership (server-side). It had **no reader in the app at all** until this
/// service — `getSignalSubscriptions` and `unsubscribeFromSignal` existed with
/// zero call sites.
class SignalSubscriptionService {
  SignalSubscriptionService._();

  static final SignalSubscriptionService instance =
      SignalSubscriptionService._();

  /// One `users/{uid}` listener, shared by the Watching tab and every follow
  /// button on screen: both are alive at once inside the tab shell, and each
  /// extra listener is a separate billed read of the same document.
  StreamController<Set<String>>? _controller;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _upstream;
  String? _uid;

  /// The last value seen, replayed to every late subscriber.
  ///
  /// **This is the part a plain `asBroadcastStream()` does not do**, and getting
  /// it wrong is invisible until two screens are open at once: a broadcast
  /// stream delivers the current snapshot to whoever listens first and nothing
  /// at all to anyone who arrives afterwards, so — depending on which order the
  /// user opened them — the follow button would sit on `initialData: false` and
  /// offer "Follow" for a signal already followed, or the Watching tab would
  /// spin forever on a tab that has data. Neither corrects itself until the
  /// document happens to change. Same shape, and the same reason, as
  /// `ModerationService.watchIsModerator`.
  Set<String> _latest = const <String>{};

  /// Every signal id the user follows, live.
  Stream<Set<String>> watchSubscriptions() async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      yield const <String>{};
      return;
    }

    _ensureSubscription(uid);
    yield _latest;
    yield* _controller!.stream;
  }

  /// Whether the user follows [signalId], as a stream that never emits the same
  /// answer twice in a row.
  Stream<bool> watchIsFollowing(String signalId) =>
      watchSubscriptions().map((ids) => ids.contains(signalId)).distinct();

  void _ensureSubscription(String uid) {
    if (_controller != null && _uid == uid) return;

    // An account switch: drop the previous uid's listener rather than leaking
    // it. Left running it would keep reading a document the signed-out user can
    // no longer access, and start erroring on every change.
    _teardown();

    _uid = uid;
    _controller = StreamController<Set<String>>.broadcast();
    _upstream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
      (doc) {
        final ids = _idsOf(doc);
        // Deduped: `users/{uid}` is written for reasons that have nothing to do
        // with following — an FCM token save, a test-mode sync — and a rebuild
        // per unrelated write is a re-read of every followed signal.
        if (setEquals(ids, _latest)) return;
        _latest = ids;
        _controller?.add(ids);
      },
      onError: (Object e) => debugPrint('Subscription stream failed: $e'),
    );
  }

  void _teardown() {
    unawaited(_upstream?.cancel());
    unawaited(_controller?.close());
    _upstream = null;
    _controller = null;
    _latest = const <String>{};
  }

  static Set<String> _idsOf(DocumentSnapshot<Map<String, dynamic>> doc) {
    final raw = doc.data()?['signalSubscriptions'];
    if (raw is! List) return const <String>{};
    return raw.whereType<String>().toSet();
  }

  Future<void> follow(String signalId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await RepositoryProvider.instance.userRepository
        .subscribeToSignal(userId: uid, signalId: signalId);
  }

  /// Stops notifications for [signalId].
  ///
  /// Tolerates `not-found`: the underlying write is an `update()`, which throws
  /// when the user document does not exist — and a user with no document is not
  /// subscribed to anything, so there is nothing to undo and nothing to report.
  Future<void> unfollow(String signalId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await RepositoryProvider.instance.userRepository
          .unsubscribeFromSignal(userId: uid, signalId: signalId);
    } on FirebaseException catch (e) {
      if (e.code != 'not-found') rethrow;
    }
  }

  /// Drops the cached listener, so the next read opens one for the new account.
  @visibleForTesting
  void reset() => _teardown();
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../repositories/repository_provider.dart';
import '../utils/cached_user_doc_stream.dart';

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
  ///
  /// The replay, the account switch and the dedupe all live in
  /// [CachedUserDocStream] — this used to hand-roll them, alongside a second
  /// copy in `ModerationService` that had already drifted on what a sign-out
  /// does.
  final CachedUserDocStream<Set<String>> _subscriptions =
      CachedUserDocStream<Set<String>>(
    collection: 'users',
    empty: const <String>{},
    equals: setEquals,
    debugLabel: 'Signal subscriptions',
    project: (doc) {
      final raw = doc.data()?['signalSubscriptions'];
      if (raw is! List) return const <String>{};
      return raw.whereType<String>().toSet();
    },
  );

  /// Every signal id the user follows, live.
  Stream<Set<String>> watchSubscriptions() => _subscriptions.watch();

  /// Whether the user follows [signalId] right now, from the cached value.
  ///
  /// Synchronous on purpose: the alternative at the one call site was a `get()`
  /// on `users/{uid}` — a billed read, on the comment-post path, of a document
  /// this service is already listening to.
  bool isFollowing(String signalId) =>
      _subscriptions.value.contains(signalId);

  /// Whether the user follows [signalId], as a stream that never emits the same
  /// answer twice in a row.
  Stream<bool> watchIsFollowing(String signalId) =>
      watchSubscriptions().map((ids) => ids.contains(signalId)).distinct();

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
  void reset() => _subscriptions.reset();
}

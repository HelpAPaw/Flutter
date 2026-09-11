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
  /// button on screen.
  ///
  /// Cached and broadcast rather than opened per caller: the details screen and
  /// the Watching tab are alive at the same time inside the shell, and each open
  /// listener is a separate billed read of the same document.
  Stream<Set<String>>? _cached;
  String? _cachedUid;

  Stream<Set<String>> watchSubscriptions() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const <String>{});

    if (_cached == null || _cachedUid != uid) {
      _cachedUid = uid;
      _cached = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .map(_idsOf)
          .handleError((Object e) {
            debugPrint('Subscription stream failed: $e');
          })
          .asBroadcastStream();
    }
    return _cached!;
  }

  /// Whether the user follows [signalId], as a stream that never emits the same
  /// answer twice in a row.
  Stream<bool> watchIsFollowing(String signalId) =>
      watchSubscriptions().map((ids) => ids.contains(signalId)).distinct();

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
  void reset() {
    _cached = null;
    _cachedUid = null;
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// One live projection of the signed-in user's own document, shared by every
/// subscriber and replayed to late ones.
///
/// Two services grew this independently — the moderator role and the follow
/// list — and both are the same machine: watch `{collection}/{uid}`, project the
/// snapshot to a small value, fan it out to N widgets, and re-point it when the
/// account changes. Extracted because the duplication had already drifted on the
/// part that is hardest to notice: one re-pointed on `authStateChanges`, the
/// other only when somebody next asked, so the two gave different answers to
/// "what happens on sign-out". Now there is one answer.
///
/// Three properties the callers depend on, each of which was a bug in one copy
/// or the other before it was written down:
///
/// * **Late subscribers get the current value.** A plain `asBroadcastStream()`
///   hands the first snapshot to whoever listens first and nothing at all to
///   anyone who arrives after, which is invisible until two screens want the
///   same answer at once.
/// * **The account switch is driven by `authStateChanges`, not `userChanges`.**
///   The latter also fires on the hourly ID-token refresh and on any profile
///   edit, and each emission would re-attach a snapshot listener for a uid that
///   never changed.
/// * **Equal values are not re-emitted.** `users/{uid}` is written for reasons
///   that have nothing to do with any one projection — an FCM token save, a
///   test-mode sync — and every duplicate emission costs whatever the
///   subscribers do in response.
class CachedUserDocStream<T> {
  CachedUserDocStream({
    required this.collection,
    required this.project,
    required this.empty,
    bool Function(T a, T b)? equals,
    this.debugLabel = 'user doc',
  }) : _equals = equals ?? ((a, b) => a == b);

  /// Top-level collection keyed by uid — `users`, `moderators`.
  final String collection;

  /// Snapshot → the value subscribers care about.
  final T Function(DocumentSnapshot<Map<String, dynamic>>) project;

  /// The value for "signed out", and for a read that failed. Offline, the right
  /// answer to "should I draw this" is the empty one.
  final T empty;

  final bool Function(T a, T b) _equals;
  final String debugLabel;

  final StreamController<T> _controller = StreamController<T>.broadcast();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSubscription;
  String? _watchedUid;

  late T _latest = empty;

  /// The current value without subscribing — for callers that need an answer
  /// inside a synchronous path and would otherwise pay a `get()` for a document
  /// this is already streaming.
  T get value => _latest;

  /// The value now, then every change.
  ///
  /// **Not `async*`.** The obvious spelling — `yield _latest; yield* stream;` —
  /// has a race that is invisible until it bites: `yield` suspends until the
  /// consumer asks for more, so the `yield*` subscribes to the broadcast
  /// controller only on a later turn of the event loop. An update landing in
  /// that gap has no listener and is dropped, and the subscriber keeps the stale
  /// value until the document happens to change again. Observed on device: the
  /// follow button offered "Follow" for a signal the user was already following,
  /// while Firestore said otherwise.
  ///
  /// Subscribing *before* replaying closes it; [replayThenFollow] does that, and
  /// makes the result safe to listen to more than once.
  Stream<T> watch() {
    _ensureSubscription();
    return replayThenFollow(_controller.stream, () => _latest);
  }

  void _ensureSubscription() {
    if (_authSubscription != null) return;
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      final uid = user?.uid;
      if (uid == _watchedUid) return;
      _watchedUid = uid;

      unawaited(_docSubscription?.cancel());
      _docSubscription = null;

      if (uid == null) {
        _emit(empty);
        return;
      }

      _docSubscription = FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .snapshots()
          .listen(
        (doc) => _emit(project(doc)),
        onError: (Object e) {
          debugPrint('$debugLabel stream failed: $e');
          _emit(empty);
        },
      );
    });
  }

  void _emit(T value) {
    if (_equals(value, _latest)) return;
    _latest = value;
    _controller.add(value);
  }

  /// Drops both subscriptions and the cached value, so the next [watch] opens a
  /// fresh one. Used by tests, and by services exposing their own `reset`.
  void reset() {
    unawaited(_authSubscription?.cancel());
    unawaited(_docSubscription?.cancel());
    _authSubscription = null;
    _docSubscription = null;
    _watchedUid = null;
    _latest = empty;
  }
}

/// [latest] now, then every event on [source], subscribing before replaying
/// (see [CachedUserDocStream.watch] for why the order matters).
///
/// Multi-listen: each `listen` gets its own subscription and replay, because
/// callers memoize the result and a recreated `StreamBuilder` element listens
/// to it again (#84). A single-subscription stream refuses a second listen even
/// after the first has been cancelled. [source] must be broadcast.
@visibleForTesting
Stream<T> replayThenFollow<T>(Stream<T> source, T Function() latest) {
  assert(source.isBroadcast, 'replayThenFollow needs a broadcast source');
  return Stream<T>.multi((out) {
    final sub = source.listen(out.add, onError: out.addError);
    out.add(latest());
    out.onCancel = sub.cancel;
  });
}

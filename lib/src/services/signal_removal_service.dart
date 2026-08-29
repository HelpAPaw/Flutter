import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/removed_signal.dart';
import 'app_preferences_service.dart';
import 'callable_client.dart';

/// Removing, restoring and erasing a signal you reported (HelpAPaw/Flutter#68).
///
/// **Why a callable and not a client cascade.** Deleting a signal used to be
/// done from here: best-effort Storage deletes, then a batch emptying every
/// subcollection by name, then the document. It could not be finished (an app
/// killed mid-cascade orphaned the subcollections forever, and the rules then
/// *errored* on the missing parent so nothing could go back for them), it
/// forced `comments`, `events` and `takeoverRequests` to grant the reporter a
/// delete they had no other reason to have, and it was irreversible — which is
/// why people used Delete to mean "this signal is finished" instead of marking it
/// Resolved. The server does all three parts now; see
/// `functions/src/removeSignal.ts`.
///
/// **Removal is a move.** The document goes to `removedSignals` and its
/// subcollections and photos stay where they are, so a restore is lossless.
/// After [RemovedSignal.retentionDays] a scheduled purge erases all of it.
class SignalRemovalService {
  SignalRemovalService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const String _function = 'signalRemoval';
  static const String _collection = 'removedSignals';

  String get _signalsCollection =>
      AppPreferencesService().signalsCollectionName;

  /// Takes a signal down. Recoverable until the purge.
  ///
  /// Throws [CallableException] with `failed-precondition` when the signal is
  /// under review — a signal somebody has reported cannot be withdrawn out from
  /// under the moderator looking at it.
  Future<void> remove(String signalId) => _act('remove', signalId);

  /// Puts a removed signal back where it was.
  Future<void> restore(String signalId) => _act('restore', signalId);

  /// Erases a removed signal now, without waiting out the recovery window.
  Future<void> deletePermanently(String signalId) =>
      _act('deletePermanently', signalId);

  Future<void> _act(String action, String signalId) =>
      CallableClient.call(_function, {
        'action': action,
        'collection': _signalsCollection,
        'signalId': signalId,
      });

  /// The caller's own removed signals, newest first.
  ///
  /// A plain Firestore query, unlike the moderator's `listQuarantined`. That
  /// one is a callable because a quarantined signal's content is withheld from
  /// everyone; this content belongs to the person reading it. The rules allow
  /// the read **only** with the `data.reporter` filter below — a query without
  /// it is denied outright.
  ///
  /// The test-mode split is applied in memory rather than as a second `where`:
  /// this is a short list, and one composite index is enough.
  Stream<List<RemovedSignal>> watchMine() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);

    final userRef = _firestore.collection('users').doc(uid);
    final collection = _signalsCollection;

    return _firestore
        .collection(_collection)
        .where('data.reporter', isEqualTo: userRef)
        .orderBy('removedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map(RemovedSignal.fromDocument)
            .whereType<RemovedSignal>()
            .where((removed) => removed.collection == collection)
            .toList());
  }
}

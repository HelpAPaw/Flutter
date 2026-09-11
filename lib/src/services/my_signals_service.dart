import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../repositories/signal_repository.dart';
import '../utils/signal_merge.dart';
import '../utils/stream_merge.dart';

/// The signals a user is responsible for: the ones they reported, plus the ones
/// they hold.
///
/// Two queries rather than one `Filter.or`. An OR query would still need a
/// composite index per disjunct, so it buys no index savings, and its ordering
/// and paging semantics are harder to reason about than a merge that can be unit
/// tested without Firestore.
class MySignalsService {
  MySignalsService({required this.collection});

  /// `signals` or `signals_test`, captured when the stream is created. Callers
  /// inside the tab shell must re-create the service when test mode flips.
  final String collection;

  /// Everything this user reported or holds, newest first.
  ///
  /// **Degrades rather than fails.** If the owner query errors — the usual cause
  /// is `FAILED_PRECONDITION` while its composite index is still building after
  /// a deploy — it contributes an empty list and the user still sees everything
  /// they reported. A missing index should cost missing rows, not a dead screen.
  /// An error on the reporter side is *not* swallowed: that one is the screen.
  Stream<List<SignalWithId>> watchMine(String uid) {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(uid);
    final signals = firestore.collection(collection);

    final reported = signals
        .where('reporter', isEqualTo: userRef)
        .orderBy('createdAt', descending: true)
        .snapshots();

    // `signalOwner` is tri-state — absent means the reporter holds it, an
    // explicit null means released — so an equality match finds only signals
    // somebody was actually handed. The ones you reported and still hold arrive
    // through the query above.
    final owned = signals
        .where('signalOwner', isEqualTo: userRef)
        .orderBy('createdAt', descending: true)
        .snapshots();

    // Both sides mapped to `.docs` so one merge helper serves them: they only
    // needed different types because one was left as a raw snapshot.
    return mergeLatestList<List<QueryDocumentSnapshot<Map<String, dynamic>>>>([
      reported.map((s) => s.docs),
      onErrorEmitPartial(
        owned.map((s) => s.docs),
        const [],
        onError: (e) => debugPrint('Owned signals stream failed: $e'),
      ),
    ]).map((sides) => mergeMine(sides[0], sides[1]));
  }
}

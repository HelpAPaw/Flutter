import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/signal_repository.dart';

/// Folds two queries over the same collection into one newest-first list.
///
/// Deduped by [idOf], with [primary] winning — when both sides carry the same
/// document, the caller's preferred snapshot is the one kept.
///
/// Sorted by [createdAtOf] descending. Documents with no timestamp sort **last**
/// rather than throwing, tie-broken by id so the order is stable across
/// rebuilds: `createdAt` is written by every create path, but a hand-edited or
/// half-written document must not take the screen down with it.
///
/// Generic over the element type purely so the ordering rules can be tested
/// without a Firestore instance — the interesting cases here are the overlap and
/// the missing timestamp, and neither needs a real snapshot to exercise.
List<T> mergeByIdNewestFirst<T>(
  Iterable<T> primary,
  Iterable<T> secondary, {
  required String Function(T) idOf,
  required Timestamp? Function(T) createdAtOf,
}) {
  final byId = <String, T>{};
  for (final item in primary) {
    byId[idOf(item)] = item;
  }
  for (final item in secondary) {
    byId.putIfAbsent(idOf(item), () => item);
  }

  return byId.values.toList()
    ..sort((a, b) {
      final at = createdAtOf(a);
      final bt = createdAtOf(b);
      if (at == null && bt == null) return idOf(a).compareTo(idOf(b));
      if (at == null) return 1;
      if (bt == null) return -1;
      final byTime = bt.compareTo(at);
      return byTime != 0 ? byTime : idOf(a).compareTo(idOf(b));
    });
}

/// The My Signals list: everything you reported, plus everything you hold.
///
/// Two queries rather than one `Filter.or`: an OR query still needs a composite
/// index per disjunct, and its paging semantics are harder to reason about.
///
/// **The overlap is the point.** A signal you reported *and* still hold comes
/// back from both, and `signalOwner` is tri-state — absent means the reporter
/// holds it, a reference means held, an explicit null means released (see
/// `Signal.signalOwnerFrom`) — so the two sides genuinely disagree about how
/// many rows exist. [reported] wins the tie, which is also the query that is
/// never missing an index.
List<SignalWithId> mergeMine(
  Iterable<DocumentSnapshot> reported,
  Iterable<DocumentSnapshot> owned,
) {
  final docs = mergeByIdNewestFirst<DocumentSnapshot>(
    reported,
    owned,
    idOf: (doc) => doc.id,
    createdAtOf: _createdAt,
  );
  return docs.map(SignalWithId.fromDocument).toList();
}

/// One query's documents, newest first — the same ordering [mergeMine] applies,
/// so every list of signals in the app reads the same way.
List<SignalWithId> sortNewestFirst(Iterable<DocumentSnapshot> docs) =>
    mergeMine(docs, const []);

Timestamp? _createdAt(DocumentSnapshot doc) {
  final data = doc.data();
  if (data is! Map<String, dynamic>) return null;
  final value = data['createdAt'];
  return value is Timestamp ? value : null;
}

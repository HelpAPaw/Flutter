import 'package:cloud_firestore/cloud_firestore.dart';

import '../repositories/signal_repository.dart';
import '../utils/chunk.dart';
import '../utils/signal_merge.dart';
import '../utils/stream_merge.dart';

/// One page of the Watching tab.
class WatchedPage {
  const WatchedPage({required this.signals, required this.hasMore});

  /// Signals the user follows that are not their own, newest first.
  final List<SignalWithId> signals;

  /// Whether older followed ids remain beyond the ones consumed for this page.
  ///
  /// Counted **after** the own-signal filter, which is the whole reason this
  /// lives in a service: when the widget computed it from the raw id window, a
  /// window that filtered down to nothing reported "more" with no rows, and the
  /// user had to tap Load More once per empty page.
  final bool hasMore;

  static const empty = WatchedPage(signals: [], hasMore: false);

  /// This page without the rows whose ids are not in [followedIds] — what to
  /// show while the query for a changed follow list is still on its way.
  WatchedPage retainOnly(Set<String> followedIds) => WatchedPage(
        signals:
            signals.where((entry) => followedIds.contains(entry.id)).toList(),
        hasMore: hasMore,
      );
}

/// The signals a user follows, minus the ones they are responsible for.
///
/// The mirror of [MySignalsService], and a service for the same reasons: the
/// ownership rule and the paging arithmetic are the parts worth unit-testing,
/// and both were previously inline in a `StreamBuilder` closure where neither
/// could be reached without a widget and a Firestore.
class WatchingService {
  WatchingService({required this.collection, required this.uid});

  /// `signals` or `signals_test` — passed in, never read ambiently, so a stream
  /// cannot outlive the mode it was built for without somebody saying so.
  final String collection;
  final String uid;

  /// How many surviving rows a page aims for.
  static const int pageSize = firestoreWhereInLimit * 2;

  /// Followed signals that are not the user's own, newest first.
  ///
  /// [followedIds] is the raw `signalSubscriptions` array. It is consumed
  /// newest-followed-first — `arrayUnion` appends, and re-adding an existing id
  /// does not move it, so the tail is the most recent interest.
  ///
  /// **Keeps consuming ids until it has [limit] rows that survive the filter**,
  /// or runs out. Reporting a signal subscribes you to it, and that is the main
  /// way this array grows, so a naive window is frequently all-own-signals; the
  /// read cost stays bounded because each extra chunk is only fetched when the
  /// previous one did not fill the page.
  Stream<WatchedPage> watch(List<String> followedIds, {int limit = pageSize}) {
    final ids = followedIds.reversed.toList();
    if (ids.isEmpty) return Stream.value(WatchedPage.empty);

    final chunks = chunked(ids, firestoreWhereInLimit);
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    // Enough chunks to stand a chance of filling the page, plus one — the filter
    // decides how many actually survive, and re-listening later would re-read
    // everything already loaded.
    final wanted = (limit / firestoreWhereInLimit).ceil() + 1;
    final loaded = chunks.take(wanted).toList();
    final exhausted = loaded.length == chunks.length;

    return mergeLatestList(
      loaded
          .map((chunk) => FirebaseFirestore.instance
              .collection(collection)
              .where(FieldPath.documentId, whereIn: chunk)
              .snapshots())
          .toList(),
    ).map((snapshots) {
      // Ids that come back from no chunk are simply absent: a removed signal,
      // one purged after its recovery window, or an id belonging to the other
      // collection while test mode is the other way round.
      final theirs = sortNewestFirst(snapshots.expand((s) => s.docs))
          .where((entry) => !isMine(entry, userRef, uid))
          .toList();

      return WatchedPage(
        signals: theirs.take(limit).toList(),
        hasMore: theirs.length > limit || !exhausted,
      );
    });
  }

  /// Whether [entry] is one the user is responsible for.
  ///
  /// The complement of `MySignalsService`'s two queries, and deliberately the
  /// only other place that rule is written: `signalOwner` is tri-state — absent
  /// means the reporter holds it, an explicit reference means somebody was
  /// handed it — so asking the parsed [Signal] is exact where re-deriving it
  /// from the raw map is a thing that drifts.
  static bool isMine(
    SignalWithId entry,
    DocumentReference<Map<String, dynamic>> userRef,
    String uid,
  ) =>
      entry.signal.reporter == userRef || entry.signal.isHeldBy(uid);
}

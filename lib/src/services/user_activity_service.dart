import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/signal_event.dart';
import '../repositories/signal_repository.dart';
import '../utils/chunk.dart';
import '../utils/signal_merge.dart';
import 'user_stats_service.dart';

/// Which of a profile's statistics a list is drilling into (master spec
/// §3.5.1). One per [UserStats] field, in the same order as `UserStatsRow`.
enum UserActivityKind {
  signals,
  helping,
  comments;

  /// Parses a route segment, or null for anything this build does not know —
  /// a mistyped deep link should land on the profile, not on a crash.
  static UserActivityKind? fromName(String? name) => values.asNameMap()[name];
}

/// One comment somebody wrote, with the signal it was written on.
class AuthoredComment {
  const AuthoredComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.signal,
  });

  final String id;
  final String text;
  final DateTime? createdAt;
  final SignalWithId signal;
}

/// One page of a drill-down list, plus where to resume.
class ActivityPage<T> {
  const ActivityPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  final List<T> items;

  /// The last document *read*, not the last one kept — a page whose tail was
  /// filtered out must still resume after it, or the next page re-reads it.
  final DocumentSnapshot? cursor;

  final bool hasMore;
}

/// The lists behind the numbers on a profile: what a user reported, what they
/// are helping with, and what they have said.
///
/// **The lists are narrower than the numbers, on purpose.** Each count is a
/// contribution that outlives its signal (see `UserStatsService`), but a list
/// can only show a signal that is still there to open. A signal the reporter
/// removed, a moderator hid, or the archive took has left the collection — and
/// the comments under it survive the move, but have nothing to link to. The
/// screens say so rather than letting the gap read as a bug.
///
/// Every query here works for any uid under the existing rules, like the
/// counts: `signals` is world-readable and the `{path=**}/comments` group read
/// is open to any signed-in session.
class UserActivityService {
  UserActivityService({required this.collection, required this.uid});

  /// `signals` or `signals_test`, captured once. Test mode cannot flip while a
  /// profile list is open — the gesture lives on the map title.
  final String collection;
  final String uid;

  static const int pageSize = 20;

  /// How many raw comment pages one [comments] call may read looking for rows
  /// to keep. A QA account in production mode has mostly test-mode comments,
  /// and without a cap one tap could walk its entire history.
  static const int maxCommentScans = 4;

  late final DocumentReference<Map<String, dynamic>> _userRef =
      FirebaseFirestore.instance.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> get _signals =>
      FirebaseFirestore.instance.collection(collection);

  /// Signals this user reported that are still in [collection], newest first.
  Future<ActivityPage<SignalWithId>> signals({DocumentSnapshot? after}) async {
    var query = _signals
        .where('reporter', isEqualTo: _userRef)
        .orderBy('createdAt', descending: true)
        .limit(pageSize);
    if (after != null) query = query.startAfterDocument(after);

    final snapshot = await query.get();
    return ActivityPage(
      items: snapshot.docs.map(SignalWithId.fromDocument).toList(),
      cursor: snapshot.docs.isEmpty ? after : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  /// Open signals this user holds, newest first — the same query the
  /// "Helping now" number counts ([UserStatsService.openSignalsHeldBy]).
  ///
  /// Unpaged: it is a present commitment, a handful of cases at most. Sorted
  /// here rather than by the query, which would need a third composite index
  /// (`signalOwner`, `status`, `createdAt`) for a list this short.
  Future<ActivityPage<SignalWithId>> helping() async {
    final snapshot =
        await UserStatsService.openSignalsHeldBy(_userRef, collection).get();
    return ActivityPage(
      items: sortNewestFirst(snapshot.docs),
      cursor: null,
      hasMore: false,
    );
  }

  /// Parent signals already read, by id — kept across pages so a user who
  /// commented ten times on one signal costs one read of it, not ten.
  final Map<String, SignalWithId?> _parents = {};

  /// Comments this user wrote on signals still in [collection], newest first.
  ///
  /// The group query cannot be narrowed to one collection *and* ordered by
  /// date without a second composite index, so it reads in date order and
  /// filters here — see [belongsTo]. Three kinds of row are dropped:
  ///   * comments in the other mode's collection;
  ///   * legacy status-change entries, which carry an `author` but decode as
  ///     events ([SignalHistoryEntry.fromDocument]) — they moved to `events`
  ///     long ago, but the old documents remain;
  ///   * comments whose signal is gone — removed, hidden or archived.
  ///
  /// Keeps reading until it has [pageSize] rows or has read [maxCommentScans]
  /// raw pages, so a window that filters down to nothing does not end the list.
  Future<ActivityPage<AuthoredComment>> comments({
    DocumentSnapshot? after,
  }) async {
    final kept = <AuthoredComment>[];
    var cursor = after;
    var hasMore = true;

    for (var scan = 0;
        scan < maxCommentScans && hasMore && kept.length < pageSize;
        scan++) {
      var query = FirebaseFirestore.instance
          .collectionGroup('comments')
          .where('author', isEqualTo: _userRef)
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (cursor != null) query = query.startAfterDocument(cursor);

      final snapshot = await query.get();
      hasMore = snapshot.docs.length == pageSize;
      if (snapshot.docs.isNotEmpty) cursor = snapshot.docs.last;

      // Decoded exactly as the thread decodes them, so "what counts as a
      // user comment" has one definition: a legacy status entry carries a
      // `type`, and an empty text is not something anyone wrote.
      final candidates = [
        for (final doc in snapshot.docs)
          if (belongsTo(doc.reference.path, collection))
            if (SignalHistoryEntry.fromDocument(doc.id, doc.data())
                case final entry?
                when entry.kind == SignalHistoryKind.comment &&
                    (entry.text?.isNotEmpty ?? false))
              (signalId: doc.reference.parent.parent!.id, entry: entry),
      ];

      await _loadParents({for (final c in candidates) c.signalId});

      for (final (:signalId, :entry) in candidates) {
        final parent = _parents[signalId];
        if (parent == null) continue;
        kept.add(AuthoredComment(
          id: entry.id,
          text: entry.text!,
          createdAt: entry.createdAt,
          signal: parent,
        ));
      }
    }

    return ActivityPage(items: kept, cursor: cursor, hasMore: hasMore);
  }

  Future<void> _loadParents(Set<String> ids) async {
    final missing = ids.where((id) => !_parents.containsKey(id)).toList();
    if (missing.isEmpty) return;

    final batches = await Future.wait([
      for (final chunk in chunked(missing, firestoreWhereInLimit))
        _signals.where(FieldPath.documentId, whereIn: chunk).get(),
    ]);
    for (final id in missing) {
      _parents[id] = null;
    }
    for (final batch in batches) {
      for (final doc in batch.docs) {
        _parents[doc.id] = SignalWithId.fromDocument(doc);
      }
    }
  }

  /// Whether the comment at [path] sits under a signal in [collection].
  ///
  /// By path segment, never by prefix: `signals` is a string prefix of
  /// `signals_test`, which is exactly the confusion this has to rule out.
  static bool belongsTo(String path, String collection) {
    final segments = path.split('/');
    return segments.length == 4 &&
        segments[0] == collection &&
        segments[2] == 'comments';
  }

  /// Narrows a `collectionGroup('comments')` query to one signals collection,
  /// on the server, so that `count()` can answer per mode.
  ///
  /// Document names order **segment by segment**, so every comment under
  /// `signals/…` sorts before every comment under `signals_test/…` (`signals` is
  /// a prefix of `signals_test`, and a prefix sorts first). `signals_test/!` is
  /// the boundary between them: `!` is the smallest printable character, and
  /// signal ids are Firestore auto-ids — alphanumeric. The upper bound on the
  /// test side is `signals_test0`, the next segment after `signals_test` with
  /// a printable suffix, so nothing further down the alphabet can leak in.
  ///
  /// Served by the existing collection-group index on `author`: every index
  /// entry ends in the document name, so an equality followed by a range on the
  /// name needs no composite index. Verified against the emulator; the count
  /// comes back null (a dash) rather than wrong if production ever disagrees.
  static Query<Map<String, dynamic>> scopeCommentsTo(
    Query<Map<String, dynamic>> query,
    String collection,
  ) {
    final firestore = FirebaseFirestore.instance;
    final boundary = firestore.doc('signals_test/!');
    if (collection == 'signals_test') {
      return query
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: boundary)
          .where(FieldPath.documentId,
              isLessThan: firestore.doc('signals_test0/!'));
    }
    return query.where(FieldPath.documentId, isLessThan: boundary);
  }
}

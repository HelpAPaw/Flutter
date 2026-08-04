import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'app_preferences_service.dart';

/// Reads and mutates the in-app notification inbox at
/// `users/{uid}/notifications`.
///
/// Most entries are written server-side by the notification fan-out, which uses
/// the Admin SDK and so bypasses the security rules. The one client-side writer
/// is the arrival catch-up ([recordNearbySignal]), and the rules only let it
/// create `nearby_signal` entries — see `firestore.rules`.
///
/// The rendered text is *not* read from the stored `title`/`body`: those are the
/// English strings the push carried, kept only as a fallback. The app builds the
/// display strings from the structured fields through its own localizations, so
/// a Bulgarian user gets a Bulgarian inbox even though the Cloud Function has no
/// i18n.
class NotificationInboxService {
  static final NotificationInboxService _instance =
      NotificationInboxService._internal();
  factory NotificationInboxService() => _instance;
  NotificationInboxService._internal();

  /// Newest-first page size.
  static const int pageSize = 50;

  /// Batch size for the bulk actions. Firestore commits at most 500 writes.
  static const int _batchSize = 450;

  /// Upper bound on the documents a single bulk action will walk.
  ///
  /// "Clear all" has to mean all, not "all of the page you can see", but an
  /// unbounded query over a 90-day backlog is an unbounded read bill. Ten passes
  /// of a full batch is far more than any real inbox holds.
  static const int _maxBulkPasses = 10;

  /// How long an entry written on-device survives.
  ///
  /// Must match `INBOX_RETENTION_DAYS` in `functions/src/index.ts`: both feed
  /// the same TTL policy on the `notifications` collection group, and the rules
  /// reject a create with no `expiresAt` precisely so a client entry cannot
  /// outlive it.
  static const Duration retention = Duration(days: 90);

  CollectionReference<Map<String, dynamic>>? _collection() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications');
  }

  DocumentReference<Map<String, dynamic>>? _counter() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('userCounters').doc(uid);
  }

  /// Entries for the mode the app is currently in.
  ///
  /// The mode filter is not cosmetic: a test-mode entry's `signalId` points into
  /// `signals_test`, so opening it from the production inbox would navigate to a
  /// document that does not exist.
  Query<Map<String, dynamic>> _scoped(
    CollectionReference<Map<String, dynamic>> collection,
  ) {
    return collection.where(
      'testMode',
      isEqualTo: AppPreferencesService().isTestMode(),
    );
  }

  /// Newest [pageSize] notifications for the current user and mode.
  ///
  /// Returns `null` when nobody is signed in, so the caller can render its
  /// signed-out state rather than an empty list.
  Stream<QuerySnapshot<Map<String, dynamic>>>? watchInbox() {
    final collection = _collection();
    if (collection == null) return null;
    return _scoped(collection)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots();
  }

  /// Unread count for the drawer badge, capped at [pageSize].
  ///
  /// A capped snapshot rather than a `count()` aggregation because this one is
  /// live: the badge has to clear the moment the user reads something.
  Stream<int> watchUnreadCount() {
    final collection = _collection();
    if (collection == null) return Stream.value(0);
    return _scoped(collection)
        .where('read', isEqualTo: false)
        .limit(pageSize)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Future<void> markRead(DocumentReference<Map<String, dynamic>> ref) {
    return ref.update({'read': true});
  }

  /// Marks every unread notification in the current mode as read.
  Future<void> markAllRead() async {
    final collection = _collection();
    if (collection == null) return;

    await _walkInBatches(
      _scoped(collection).where('read', isEqualTo: false),
      (batch, doc) => batch.update(doc.reference, {'read': true}),
    );
    await syncUnreadCounter();
  }

  /// Deletes every notification in the current mode.
  Future<void> clearAll() async {
    final collection = _collection();
    if (collection == null) return;

    await _walkInBatches(
      _scoped(collection),
      (batch, doc) => batch.delete(doc.reference),
    );
    await syncUnreadCounter();
  }

  /// Applies [apply] to every document [query] matches, a batch at a time.
  ///
  /// Re-runs the same query rather than paginating with a cursor, which works
  /// for both callers because each pass removes its documents from the result
  /// set — deleted outright, or no longer matching `read == false`.
  Future<void> _walkInBatches(
    Query<Map<String, dynamic>> query,
    void Function(WriteBatch batch, QueryDocumentSnapshot<Map<String, dynamic>>)
        apply,
  ) async {
    for (var pass = 0; pass < _maxBulkPasses; pass++) {
      final snapshot = await query.limit(_batchSize).get();
      if (snapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        apply(batch, doc);
      }
      await batch.commit();

      if (snapshot.docs.length < _batchSize) return;
    }
  }

  /// Records a notification the arrival catch-up posted on-device.
  ///
  /// Runs in the Android headless isolate, so it must not touch a
  /// `BuildContext`; the caller passes already-localized [title] and [body].
  ///
  /// Best-effort by design: the caller has already shown the notification and
  /// recorded it as announced, and a failure here must not undo either.
  Future<void> recordNearbySignals(
    List<NearbyInboxEntry> entries,
  ) async {
    final collection = _collection();
    if (collection == null || entries.isEmpty) return;

    final now = Timestamp.now();
    final expiresAt = Timestamp.fromDate(now.toDate().add(retention));
    final testMode = AppPreferencesService().isTestMode();

    try {
      for (var i = 0; i < entries.length; i += _batchSize) {
        final batch = FirebaseFirestore.instance.batch();
        for (final entry in entries.skip(i).take(_batchSize)) {
          // Deterministic id: a repeat post updates rather than duplicates,
          // matching the stable notification id the shade entry already uses.
          batch.set(collection.doc('nb_${entry.signalId}'), {
            'type': 'nearby_signal',
            'title': entry.title,
            'body': entry.body,
            'read': false,
            'signalId': entry.signalId,
            'signalTitle': entry.signalTitle,
            'signalType': entry.signalType,
            'testMode': testMode,
            'createdAt': now,
            'expiresAt': expiresAt,
          });
        }
        await batch.commit();
      }
      await _counter()?.set({
        'unread': FieldValue.increment(entries.length),
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('NotificationInboxService: inbox write failed: $error');
    }
  }

  /// Recomputes the stored unread count from the inbox itself.
  ///
  /// The server increments the counter but never decrements it, and TTL
  /// deletions are observed by nobody, so it drifts. One aggregation read on
  /// resume is the whole repair strategy — deliberately not a Cloud Function
  /// trigger, which would cost an invocation per read notification.
  ///
  /// Returns the true unread count, or 0 if it could not be determined.
  Future<int> syncUnreadCounter() async {
    final collection = _collection();
    final counter = _counter();
    if (collection == null || counter == null) return 0;

    try {
      final snapshot = await _scoped(collection)
          .where('read', isEqualTo: false)
          .count()
          .get();
      final unread = snapshot.count ?? 0;

      await counter.set({
        'unread': unread,
        'updatedAt': Timestamp.now(),
      }, SetOptions(merge: true));
      return unread;
    } catch (error) {
      debugPrint('NotificationInboxService: counter sync failed: $error');
      return 0;
    }
  }

}

/// One catch-up notification to persist, already localized by the caller.
@immutable
class NearbyInboxEntry {
  const NearbyInboxEntry({
    required this.signalId,
    required this.title,
    required this.body,
    required this.signalTitle,
    required this.signalType,
  });

  final String signalId;
  final String title;
  final String body;
  final String signalTitle;
  final int signalType;
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/models/signal.dart';
import 'package:help_a_paw/src/repositories/signal_repository.dart';
import 'package:help_a_paw/src/utils/chunk.dart';
import 'package:help_a_paw/src/services/watching_service.dart';

/// The paging arithmetic that used to live inside a StreamBuilder closure, where
/// it could not be reached without a widget and a Firestore.
///
/// The case that matters: reporting a signal subscribes you to it, so a window
/// of followed ids is frequently *all* your own, and the page has to know the
/// difference between "nothing to show" and "nothing survived this window".
void main() {
  test('a page aims for its limit in surviving rows', () {
    expect(WatchingService.pageSize, firestoreWhereInLimit * 2);
  });

  test('an empty follow list is an empty page, not a query', () {
    final service = WatchingService(collection: 'signals_test', uid: 'u1');
    expect(service.watch(const []), emits(same(WatchedPage.empty)));
  });

  group('WatchedPage', () {
    test('empty means no rows and nothing more to load', () {
      expect(WatchedPage.empty.signals, isEmpty);
      expect(WatchedPage.empty.hasMore, isFalse);
      // The distinction the widget renders on: hasMore false + no rows is the
      // real empty state; hasMore true + no rows is "keep paging".
      const stillPaging = WatchedPage(signals: [], hasMore: true);
      expect(stillPaging.signals, isEmpty);
      expect(stillPaging.hasMore, isTrue);
    });

    test('retainOnly drops unfollowed rows and keeps the rest in order', () {
      // What the Watching tab shows between an unfollow and the fresh query's
      // answer, so the row goes at once and cannot come back meanwhile (#86).
      final page = WatchedPage(
        signals: [signalWith('a'), signalWith('b'), signalWith('c')],
        hasMore: true,
      );

      final kept = page.retainOnly({'a', 'c', 'not-on-this-page'});

      expect(kept.signals.map((entry) => entry.id), ['a', 'c']);
      expect(kept.hasMore, isTrue);
    });
  });
}

SignalWithId signalWith(String id) => SignalWithId(
      id: id,
      signal: Signal(
        title: id,
        description: '',
        phoneNumber: '',
        location: const {},
        reporter: _FakeDocumentReference(),
        contactPhone: '',
        createdAt: null,
        urgency: 0,
      ),
      rawData: const {},
    );

class _FakeDocumentReference implements DocumentReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter_test/flutter_test.dart';
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
  });
}

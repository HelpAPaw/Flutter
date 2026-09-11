import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards `signals` and `signals_test` against carrying different indexes.
///
/// Test mode (7 taps on the map title) swaps one collection name for the other
/// and nothing else — `AppPreferencesService.signalsCollectionName` is the whole
/// mechanism. So every query the app runs is run against *both* collections over
/// its lifetime, and an index added to only one of them produces a screen that
/// works in production and throws `FAILED_PRECONDITION` in test mode.
///
/// That failure is invisible to almost everyone: it needs a deliberate gesture
/// to reach, it surfaces as an error state rather than a crash, and the people
/// who trip it are the ones testing something else at the time. Cheaper to fail
/// the build. Same class of guard as `firestore_settings_guard_test.dart`.
void main() {
  final file = File('firestore.indexes.json');

  test('firestore.indexes.json is where the guard expects it', () {
    expect(file.existsSync(), isTrue);
  });

  test('signals and signals_test carry identical index sets', () {
    final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final indexes = (config['indexes'] as List).cast<Map<String, dynamic>>();

    /// The index reduced to what Firestore actually keys on, so two entries that
    /// differ only in key order in the JSON still compare equal.
    String shapeOf(Map<String, dynamic> index) {
      final fields = (index['fields'] as List).cast<Map<String, dynamic>>();
      final parts = fields.map((f) {
        final path = f['fieldPath'];
        final mode = f['order'] ?? f['arrayConfig'];
        return '$path:$mode';
      });
      return '${index['queryScope']}|${parts.join(',')}';
    }

    Set<String> shapesFor(String collection) => indexes
        .where((i) => i['collectionGroup'] == collection)
        .map(shapeOf)
        .toSet();

    final live = shapesFor('signals');
    final test = shapesFor('signals_test');

    expect(live, isNotEmpty,
        reason: 'no indexes for `signals` at all — has the collection been '
            'renamed? This guard is comparing nothing against nothing.');

    expect(
      test.difference(live),
      isEmpty,
      reason: 'signals_test has indexes that `signals` does not. A query that '
          'works in test mode would fail for real users.',
    );
    expect(
      live.difference(test),
      isEmpty,
      reason: 'signals has indexes that `signals_test` does not. The query '
          'behind them throws FAILED_PRECONDITION once somebody taps the map '
          'title seven times.',
    );
  });
}

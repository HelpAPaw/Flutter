import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/config/routes.dart';
import 'package:help_a_paw/src/services/user_activity_service.dart';
import 'package:help_a_paw/src/services/user_stats_service.dart';

/// The two pieces of the profile drill-down that decide *which* rows a list
/// shows without touching Firestore.
void main() {
  group('UserActivityService.belongsTo', () {
    test('keeps a comment under the current collection', () {
      expect(
        UserActivityService.belongsTo('signals/abc/comments/c1', 'signals'),
        isTrue,
      );
      expect(
        UserActivityService.belongsTo(
            'signals_test/abc/comments/c1', 'signals_test'),
        isTrue,
      );
    });

    test('never confuses signals with signals_test', () {
      // `signals` is a string prefix of `signals_test` — a startsWith check
      // would file every test-mode comment under production.
      expect(
        UserActivityService.belongsTo(
            'signals_test/abc/comments/c1', 'signals'),
        isFalse,
      );
      expect(
        UserActivityService.belongsTo('signals/abc/comments/c1', 'signals_test'),
        isFalse,
      );
    });

    test('rejects a comments subcollection anywhere else', () {
      expect(
        UserActivityService.belongsTo(
            'signals/abc/other/x/comments/c1', 'signals'),
        isFalse,
      );
    });
  });

  group('UserActivityKind', () {
    test('round-trips through its route segment', () {
      for (final kind in UserActivityKind.values) {
        final path = Routes.userActivity('u1', kind);
        expect(path, '/user/u1/activity/${kind.name}');
        expect(UserActivityKind.fromName(path.split('/').last), kind);
      }
    });

    test('an unknown segment is null, not a throw', () {
      expect(UserActivityKind.fromName('likes'), isNull);
      expect(UserActivityKind.fromName(null), isNull);
    });
  });

  test('a re-read keeps the numbers it could not get', () {
    // Coming back from a list re-reads the stats; count() is server-only, and
    // a blip on the way back must not turn figures on screen into dashes.
    const before =
        UserStats(signalsPosted: 3, signalsOwned: 1, commentsPosted: 7);
    const reread =
        UserStats(signalsPosted: 4, signalsOwned: null, commentsPosted: null);
    final merged = reread.orElse(before);
    expect(merged.signalsPosted, 4);
    expect(merged.signalsOwned, 1);
    expect(merged.commentsPosted, 7);
    expect(reread.orElse(null).signalsOwned, isNull);
  });
}

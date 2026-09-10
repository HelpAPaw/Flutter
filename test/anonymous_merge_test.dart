import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/auth_service.dart';

/// The anonymous → account data merge (#79).
///
/// `firestore.rules` scopes `users/{uid}` reads to `request.auth.uid`. Both
/// merge paths run *after* the sign-in has switched identity, so the anonymous
/// document is unreadable by then: reading it there raised `permission-denied`,
/// which escaped `_onSignedIn` and skipped the navigation below it, leaving the
/// user on the sign-in screen with the sign-in already done and their
/// preferences silently lost.
///
/// The fix is a snapshot captured while the anonymous account is still the
/// caller, so these tests cover both halves of it: what the snapshot carries,
/// and the invariant that nothing re-reads it afterwards.
void main() {
  group('buildAnonymousTransfer', () {
    test('carries everything the user could configure while anonymous', () {
      final transfer = AuthService.buildAnonymousTransfer({
        'fcmTokens': ['token-a', 'token-b'],
        'notificationPreferences': {'enabled': true, 'radius': 5.0},
        'signalSubscriptions': ['signal-1'],
      });

      expect(transfer['fcmTokens'], ['token-a', 'token-b']);
      expect(transfer['notificationPreferences'],
          {'enabled': true, 'radius': 5.0});
      expect(transfer['signalSubscriptions'], ['signal-1']);
    });

    test('marks the destination account as no longer anonymous', () {
      expect(AuthService.buildAnonymousTransfer({})['isAnonymous'], isFalse);
    });

    test('omits absent fields rather than writing nulls over them', () {
      // The write is a set(merge), so a null here would erase a preference the
      // destination account already had.
      final transfer = AuthService.buildAnonymousTransfer({
        'fcmTokens': ['token-a'],
      });

      expect(transfer.containsKey('notificationPreferences'), isFalse);
      expect(transfer.containsKey('signalSubscriptions'), isFalse);
    });

    test('does not carry fields that belong to the anonymous identity', () {
      // Anything not explicitly transferred must be dropped: the destination
      // account has its own profile, and the live location lives in
      // userLocations/{uid} and self-heals on the next GPS fix.
      final transfer = AuthService.buildAnonymousTransfer({
        'displayName': 'Anonymous',
        'profileCompleted': true,
        'location': 'anything',
      });

      expect(transfer.keys, unorderedEquals(['isAnonymous', 'updatedAt']));
    });
  });

  group('post-sign-in merge reads nothing', () {
    /// Body of a two-space-indented method of `AuthService`, signature line
    /// included, up to its closing brace.
    String methodBody(String name) {
      final source = File('lib/src/services/auth_service.dart').readAsLinesSync();
      final start = source.indexWhere((line) => line.contains('> $name('));
      expect(start, isNot(-1), reason: 'AuthService.$name no longer exists');
      final end = source.indexWhere((line) => line == '  }', start);
      expect(end, isNot(-1), reason: 'could not find the end of $name');
      return source.sublist(start, end + 1).join('\n');
    }

    for (final name in const [
      'mergeAnonymousIntoExisting',
      'transferAnonymousData',
    ]) {
      test('$name performs no Firestore read', () {
        // Both run once the caller is already the destination account, so any
        // read of the anonymous document is denied. Take the data as a
        // parameter (from AuthService.captureAnonymousData, called before
        // authenticating) instead of reading it here.
        final body = methodBody(name);
        // Guards against the extraction silently matching the wrong lines.
        expect(body, contains('anonymousData'));
        expect(body, isNot(contains('.get()')));
      });
    }
  });
}

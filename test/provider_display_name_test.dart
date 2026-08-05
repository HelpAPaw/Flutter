import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/auth_service.dart';

/// Which name the app adopts for a Google user (R5-001).
///
/// The v7 sign-in flow leaves the top-level Auth `displayName` null, so this
/// pick decides what Profile Completion offers — and therefore what lands in
/// `publicProfiles` as the reporter/comment-author name everyone else sees.
/// The alternative, the email's local part, is what the bug shipped.
void main() {
  group('AuthService.pickProviderName', () {
    test('prefers the freshly-signed-in credential profile', () {
      expect(
        AuthService.pickProviderName('Milen Marinov', ['Stale Name']),
        'Milen Marinov',
      );
    });

    test('falls back to a linked provider record', () {
      expect(
        AuthService.pickProviderName(null, [null, 'Милен Маринов']),
        'Милен Маринов',
      );
    });

    test('skips blank and whitespace-only candidates', () {
      expect(
        AuthService.pickProviderName('   ', ['', '  ', 'Real Name']),
        'Real Name',
      );
    });

    test('trims the name it returns', () {
      expect(AuthService.pickProviderName('  Milen  ', []), 'Milen');
    });

    test('ignores a non-string profile value', () {
      // additionalUserInfo.profile is an untyped map straight off the wire.
      expect(AuthService.pickProviderName(42, ['Real Name']), 'Real Name');
    });

    test('returns null when nothing usable is on offer', () {
      // Password and anonymous accounts land here; the caller then falls back
      // to the email local part rather than writing an empty name.
      expect(AuthService.pickProviderName(null, [null, '']), isNull);
    });
  });
}

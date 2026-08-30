import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/l10n/app_localizations_en.dart';
import 'package:help_a_paw/src/utils/profile_validators.dart';

/// The rules existed twice and had drifted: "Complete your profile" required
/// two characters and a dialable phone number, while the editor one tap away
/// checked only that the name was non-blank. These pin the shared rules so
/// they cannot separate again.
void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  group('display name', () {
    test('is required', () {
      expect(validateDisplayName(l10n, null), l10n.nameIsRequired);
      expect(validateDisplayName(l10n, ''), l10n.nameIsRequired);
      // Whitespace is blank: it would save as an empty public name.
      expect(validateDisplayName(l10n, '   '), l10n.nameIsRequired);
    });

    test('needs two characters', () {
      expect(validateDisplayName(l10n, 'A'), l10n.nameTooShort);
      expect(validateDisplayName(l10n, ' A '), l10n.nameTooShort);
      expect(validateDisplayName(l10n, 'Ax'), isNull);
    });

    test('accepts an ordinary name', () {
      expect(validateDisplayName(l10n, 'Мария Петрова'), isNull);
    });
  });

  group('phone', () {
    test('is optional', () {
      expect(validatePhone(l10n, null), isNull);
      expect(validatePhone(l10n, ''), isNull);
      expect(validatePhone(l10n, '  '), isNull);
    });

    test('must be long enough to dial when given', () {
      expect(validatePhone(l10n, '1234567'), l10n.validPhoneNumber);
      expect(validatePhone(l10n, '12345678'), isNull);
      expect(validatePhone(l10n, '+359 88 812 3456'), isNull);
    });
  });
}

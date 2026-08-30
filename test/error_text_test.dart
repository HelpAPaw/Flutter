import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';
import 'package:help_a_paw/l10n/app_localizations_en.dart';
import 'package:help_a_paw/src/utils/error_text.dart';

/// [reportAndDescribe] is what stands between a caught exception and the
/// screen. These tests are about one rule: whatever comes in, what comes out
/// is a sentence we wrote.
void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  String describe(Object error, {String fallback = 'FALLBACK'}) =>
      reportAndDescribe(l10n, error, where: 'test', fallback: fallback);

  group('reportAndDescribe', () {
    test('never returns anything containing the exception', () {
      final errors = <Object>[
        FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'Missing or insufficient permissions.',
        ),
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'unauthorized',
          message: 'User does not have permission to access this object.',
        ),
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        FirebaseException(plugin: 'firebase_auth', code: 'unauthenticated'),
        FirebaseException(plugin: 'cloud_firestore', code: 'resource-exhausted'),
        PlatformException(code: 'camera_access_denied'),
        PlatformException(code: 'photo_access_denied'),
        StateError('Bad state: No element'),
        Exception('SocketException: Failed host lookup'),
        'a bare string',
      ];

      for (final error in errors) {
        final message = describe(error);
        expect(message, isNot(contains('Exception')), reason: '$error');
        expect(message, isNot(contains('permission-denied')), reason: '$error');
        expect(message, isNot(contains('unauthorized')), reason: '$error');
        expect(message, isNot(contains('[')), reason: '$error');
      }
    });

    test('maps the causes whose next action differs', () {
      expect(
        describe(FirebaseException(plugin: 'x', code: 'unavailable')),
        l10n.networkError,
      );
      expect(
        describe(FirebaseException(plugin: 'x', code: 'unauthenticated')),
        l10n.authenticationError,
      );
      expect(
        describe(FirebaseException(plugin: 'x', code: 'permission-denied')),
        l10n.notAllowedError,
      );
      expect(
        describe(FirebaseException(plugin: 'x', code: 'unauthorized')),
        l10n.notAllowedError,
      );
      expect(
        describe(FirebaseException(plugin: 'x', code: 'resource-exhausted')),
        l10n.serverBusyError,
      );
      expect(
        describe(PlatformException(code: 'camera_access_denied')),
        l10n.cameraPermissionDenied,
      );
      expect(
        describe(PlatformException(code: 'photo_access_denied')),
        l10n.photosPermissionDenied,
      );
    });

    test('a Firebase error carrying a socket failure still reads as offline',
        () {
      // Android Storage reports a connection lost mid-upload as `unknown` with
      // a SocketException inside, which used to fall out of the FirebaseException
      // branch before the text match could see it.
      expect(
        describe(FirebaseException(
          plugin: 'firebase_storage',
          code: 'unknown',
          message: 'SocketException: Connection reset by peer',
        )),
        l10n.networkError,
      );
    });

    test('falls back to the caller sentence for anything unrecognised', () {
      expect(describe(StateError('boom')), 'FALLBACK');
      expect(
        describe(FirebaseException(plugin: 'x', code: 'not-a-known-code')),
        'FALLBACK',
      );
    });

    test('recognises an offline socket failure by name', () {
      // Matched textually rather than by type so this file does not have to
      // import dart:io on web.
      expect(
        describe(const SocketException('Failed host lookup')),
        l10n.networkError,
      );
    });
  });

  /// The defect this whole change exists to remove was a *string* — an ARB
  /// entry with an `{error}` slot, which is an invitation to pass an
  /// exception. Fail the build if one comes back.
  test('no ARB string takes an {error} placeholder', () {
    for (final name in const ['app_en.arb', 'app_bg.arb']) {
      final arb = json.decode(File('lib/l10n/$name').readAsStringSync())
          as Map<String, dynamic>;
      final offenders = arb.entries
          .where((e) => !e.key.startsWith('@') && e.value is String)
          .where((e) => (e.value as String).contains('{error}'))
          .map((e) => e.key)
          .toList();
      expect(
        offenders,
        isEmpty,
        reason: '$name: pass a sentence and log the exception — see '
            'lib/src/utils/error_text.dart',
      );
    }
  });
}

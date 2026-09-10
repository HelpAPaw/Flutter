import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/public_profile_service.dart';

/// Guards the three copies of what `publicProfiles` accepts as a display name
/// and an avatar URL.
///
/// `firestore.rules` is the enforcement — for clients. The other two are not
/// decoration:
///
/// * **Dart** (`PublicProfileService`) clamps the name and drops an over-long
///   URL before writing. Set below the rules and a legitimate value is dropped
///   with no record kept, so `mirrorProviderPhoto` retries and drops it again
///   every launch, forever. Set above and the write is denied — and that
///   denial is cached as a permanent verdict, so the avatar never appears.
/// * **TypeScript** (`functions/src/publicProfilePhoto.ts`, shared with
///   `functions/scripts/backfill_public_photo_urls.js`) runs under the Admin
///   SDK, which bypasses rules entirely. It is the ONLY check on the backfill,
///   and a URL it lets through is one the owner can then never change.
///
/// So this parses `firestore.rules` rather than restating its numbers, the way
/// `takeover_cooldown_guard_test` and `urgency_derivation_guard_test` do — a
/// test that restated them could drift into agreeing with a stale copy.
void main() {
  final rules = File('firestore.rules').readAsStringSync();
  final shared = File('functions/src/publicProfilePhoto.ts');

  /// The body of a named rules function, so a `size()` bound or a `matches()`
  /// pattern can be read out of the one that actually runs.
  String ruleBody(String name) {
    final start = rules.indexOf('function $name(');
    expect(start, isNot(-1), reason: '$name() is gone from firestore.rules');
    final open = rules.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < rules.length; i++) {
      if (rules[i] == '{') depth++;
      if (rules[i] == '}') {
        depth--;
        if (depth == 0) return rules.substring(open, i);
      }
    }
    fail('$name() is not closed in firestore.rules');
  }

  int sizeBound(String function, String field) {
    final match = RegExp(r'\.' + field + r'\.size\(\)\s*<=\s*(\d+)')
        .firstMatch(ruleBody(function));
    expect(match, isNotNull,
        reason: 'no `$field.size() <= N` bound left in $function()');
    return int.parse(match!.group(1)!);
  }

  test('the name length cap matches the rules', () {
    expect(
      PublicProfileService.maxNameLength,
      sizeBound('isValidProfileName', 'name'),
      reason: 'PublicProfileService clamps names to a different length than '
          'firestore.rules accepts. Below it and a legal name is silently '
          'truncated; above it and the write is denied.',
    );
  });

  test('the avatar URL length cap matches the rules', () {
    expect(
      PublicProfileService.maxPhotoUrlLength,
      sizeBound('isValidProfilePhotoUrl', 'photoUrl'),
    );
  });

  test('the shared TypeScript module exists where the script requires it', () {
    expect(
      shared.existsSync(),
      isTrue,
      reason: 'functions/scripts/backfill_public_photo_urls.js requires '
          '../lib/publicProfilePhoto, built from functions/src/'
          'publicProfilePhoto.ts. Moving it silently reverts the backfill to '
          'its own independent copy of the allow-list — which the Admin SDK '
          'does not check against the rules.',
    );
  });

  test('the TypeScript length cap matches the rules', () {
    final match = RegExp(r'MAX_PHOTO_URL_LENGTH\s*=\s*(\d+)')
        .firstMatch(shared.readAsStringSync());
    expect(match, isNotNull, reason: 'MAX_PHOTO_URL_LENGTH is gone');
    expect(
      int.parse(match!.group(1)!),
      sizeBound('isValidProfilePhotoUrl', 'photoUrl'),
    );
  });

  test('both copies allow-list the same two hosts as the rules', () {
    // Not a string comparison of the patterns — the three dialects escape
    // differently. The property that matters is that the same two hosts, and
    // no third one, appear in each.
    final ruleText = ruleBody('isValidProfilePhotoUrl');
    final tsText = shared.readAsStringSync();

    for (final host in ['firebasestorage', 'googleusercontent']) {
      expect(ruleText, contains(host));
      expect(tsText, contains(host));
    }

    // The Google branch must accept any lh<n>, not just lh3: Google has served
    // account photos from lh3 through lh6 and older accounts still carry the
    // earlier hosts. Pinning the digit denies those avatars forever, and the
    // denial is invisible — the mirror only debugPrints.
    expect(ruleText, contains('lh[0-9]+'));
    expect(tsText, contains('lh[0-9]+'));

    // The Storage branch stays pinned to the caller's own uid, so an avatar URL
    // cannot pass off somebody else's picture as yours.
    expect(ruleText, contains('profile_photos%2F'));
    expect(ruleText, contains('+ userId +'));
    expect(tsText, contains('uid +'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The write-avoidance cache behind `AuthService.mirrorPhotoUrl`.
///
/// `mirrorPhotoUrl` runs on every launch and every sign-in, so what it decides
/// to skip is what decides whether the app writes to Firestore on every boot —
/// and, in one direction, whether an avatar is ever published at all.
///
/// The Firestore write itself needs an emulator; these are the decisions taken
/// before it, which are the ones that went wrong.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPreferencesService();
    await prefs.initialize();
  });

  const uid = 'user-1';
  const url = 'https://lh3.googleusercontent.com/a/ACg8ocKq1w=s96-c';

  test('an unmirrored account is not considered mirrored', () {
    expect(prefs.isPhotoMirroredFor(uid, url), isFalse);
    expect(prefs.mirroredPhotoUrlFor(uid), isNull);
  });

  test('a mirrored URL is skipped, a changed one is not', () async {
    await prefs.setPhotoMirrored(uid, url);
    expect(prefs.isPhotoMirroredFor(uid, url), isTrue);
    expect(prefs.isPhotoMirroredFor(uid, '$url&v=2'), isFalse);
  });

  test('the cache is per account', () async {
    await prefs.setPhotoMirrored(uid, url);
    expect(prefs.isPhotoMirroredFor('someone-else', url), isFalse);
  });

  // Null and '' are different answers and the difference is load-bearing:
  // null means "we have never published this account's avatar", '' means "we
  // have published that it has none". Only the second justifies a delete, and
  // collapsing them makes every account without an avatar issue one on every
  // fresh install.
  test('never-mirrored and mirrored-as-absent are distinguishable', () async {
    expect(prefs.mirroredPhotoUrlFor(uid), isNull);
    await prefs.setPhotoMirrored(uid, '');
    expect(prefs.mirroredPhotoUrlFor(uid), '');
    expect(prefs.isPhotoMirroredFor(uid, ''), isTrue);
  });

  // The regression this file was written for. `updatePhotoURL` does not
  // refresh the in-memory `User`, so the upload path used to hand
  // `mirrorProviderPhoto` a user whose `photoURL` was still null — publishing
  // "this account has no avatar" over an avatar that had just been uploaded,
  // and caching that verdict so no later launch would correct it. Passing the
  // URL rather than the user is what makes that unrepresentable; this pins the
  // cache half of it.
  test('a real URL is never masked by a cached empty one', () async {
    await prefs.setPhotoMirrored(uid, '');
    expect(prefs.isPhotoMirroredFor(uid, url), isFalse,
        reason: 'the upload must still publish, even after an empty mirror');
  });
}

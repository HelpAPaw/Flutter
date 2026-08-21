import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/src/services/app_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The write-avoidance cache behind `AuthService.syncTestMode` (#72).
///
/// `syncTestMode` runs on every launch, every sign-in and every mode toggle, so
/// the only thing keeping it from costing a Firestore write per launch is this
/// pair of keys. Every case below is one where a *missed* write puts the account
/// back in the state the bug describes: no recorded mode, silently dropped from
/// the fan-out. So the cache is required to fail towards writing.
void main() {
  late AppPreferencesService prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPreferencesService();
    await prefs.initialize();
  });

  test('an account never synced is not considered synced', () async {
    expect(prefs.isTestModeSyncedFor('uid-a'), isFalse);
  });

  test('the same account in the same mode needs no second write', () async {
    await prefs.setTestMode(true);
    await prefs.setTestModeSynced('uid-a', true);

    expect(prefs.isTestModeSyncedFor('uid-a'), isTrue);
  });

  test('a different account is unsynced even in the same mode', () async {
    await prefs.setTestMode(true);
    await prefs.setTestModeSynced('uid-a', true);

    // Signing out mints a new anonymous uid on a device whose test-mode
    // preference is unchanged — the case that produced #72.
    expect(prefs.isTestModeSyncedFor('uid-b'), isFalse);
  });

  test('toggling the mode invalidates the cache in both directions', () async {
    await prefs.setTestMode(true);
    await prefs.setTestModeSynced('uid-a', true);

    await prefs.setTestMode(false);
    expect(prefs.isTestModeSyncedFor('uid-a'), isFalse);

    await prefs.setTestModeSynced('uid-a', false);
    expect(prefs.isTestModeSyncedFor('uid-a'), isTrue);

    // Back to test mode: the stale `false` must not suppress the write that
    // makes this account visible to test traffic again.
    await prefs.setTestMode(true);
    expect(prefs.isTestModeSyncedFor('uid-a'), isFalse);
  });
}

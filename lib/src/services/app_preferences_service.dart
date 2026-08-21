import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesService {
  static final AppPreferencesService _instance = AppPreferencesService._internal();
  factory AppPreferencesService() => _instance;
  AppPreferencesService._internal();

  SharedPreferences? _prefs;

  // Keys
  static const String _onboardingCompletedKey = 'notification_onboarding_completed';
  static const String _onboardingDismissedKey = 'notification_onboarding_dismissed';
  static const String _testModeKey = 'test_mode_enabled';
  static const String _deferredLinkCheckedKey = 'deferred_link_checked';
  static const String _testModeSyncedUidKey = 'test_mode_synced_uid';
  static const String _testModeSyncedValueKey = 'test_mode_synced_value';

  /// Initialize SharedPreferences - must be called before using any other
  /// methods.
  ///
  /// Idempotent and cheap: `SharedPreferences.getInstance()` caches its own
  /// instance per isolate, so any entrypoint that isn't certain it has run may
  /// simply await this rather than assert about it. That matters because each
  /// isolate gets its own singleton — a headless background isolate starts
  /// uninitialized even while the main isolate is ready — and every getter here
  /// degrades to a *default* rather than throwing. An uninitialized
  /// [isTestMode] silently reports `false`, pointing a background check at the
  /// live `signals` collection while the user believes they are in test mode.
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Whether the one-shot deferred deep-link check has already run.
  ///
  /// The install-referrer / clipboard hand-off is only meaningful on the first
  /// launch after an install. Re-running it would re-open a stale signal, and on
  /// iOS every clipboard read shows the system paste banner.
  bool isDeferredLinkChecked() {
    return _prefs?.getBool(_deferredLinkCheckedKey) ?? false;
  }

  Future<void> setDeferredLinkChecked() async {
    await _prefs?.setBool(_deferredLinkCheckedKey, true);
  }

  /// Check if notification onboarding has been completed
  bool isOnboardingCompleted() {
    return _prefs?.getBool(_onboardingCompletedKey) ?? false;
  }

  /// Mark notification onboarding as completed
  Future<void> setOnboardingCompleted(bool completed) async {
    await _prefs?.setBool(_onboardingCompletedKey, completed);
    if (completed) {
      // Clear dismissed flag when completed
      await _prefs?.remove(_onboardingDismissedKey);
    }
  }

  /// Check if notification onboarding sheet was dismissed
  bool isOnboardingDismissed() {
    return _prefs?.getBool(_onboardingDismissedKey) ?? false;
  }

  /// Mark notification onboarding as dismissed (user tapped "Maybe Later")
  Future<void> setOnboardingDismissed(bool dismissed) async {
    await _prefs?.setBool(_onboardingDismissedKey, dismissed);
  }

  /// Should show the onboarding bottom sheet
  /// Returns true if: not completed AND not dismissed
  bool shouldShowOnboardingSheet() {
    return !isOnboardingCompleted() && !isOnboardingDismissed();
  }

  /// Should show the persistent onboarding button
  /// Returns true if: not completed AND dismissed
  bool shouldShowOnboardingButton() {
    return !isOnboardingCompleted() && isOnboardingDismissed();
  }

  /// Check if test mode is enabled
  bool isTestMode() {
    return _prefs?.getBool(_testModeKey) ?? false;
  }

  /// Enable or disable test mode
  Future<void> setTestMode(bool enabled) async {
    await _prefs?.setBool(_testModeKey, enabled);
  }

  /// Whether `users/{uid}.testMode` on the server is already known to match
  /// [isTestMode] for [uid].
  ///
  /// Purely a write-avoidance cache for [AuthService.syncTestMode], which runs
  /// on every launch and every sign-in. Steady state — same account, same mode
  /// — costs nothing; a mismatch or an unknown account costs one write.
  ///
  /// Safe to lose: cleared prefs (a reinstall) also clear [isTestMode] itself,
  /// so the pair is re-derived rather than stale. It is safe to *keep* because
  /// every in-app flow that deletes a user document — the anonymous merge,
  /// account deletion — also changes the uid, so the entry stops matching.
  ///
  /// The one case it cannot see is a document deleted underneath a live session
  /// (a backend wipe): the uid is unchanged, so the cache still claims the mode
  /// was written. Toggling test mode off and on re-writes it; a reinstall
  /// clears everything.
  bool isTestModeSyncedFor(String uid) {
    return _prefs?.getString(_testModeSyncedUidKey) == uid &&
        _prefs?.getBool(_testModeSyncedValueKey) == isTestMode();
  }

  /// Record that [uid]'s server document now carries [testMode].
  Future<void> setTestModeSynced(String uid, bool testMode) async {
    await _prefs?.setString(_testModeSyncedUidKey, uid);
    await _prefs?.setBool(_testModeSyncedValueKey, testMode);
  }

  /// Returns the Firestore collection name based on test mode state
  String get signalsCollectionName =>
      isTestMode() ? 'signals_test' : 'signals';
}

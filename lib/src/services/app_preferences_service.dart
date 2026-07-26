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

  /// Initialize SharedPreferences - must be called before using any other methods
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

  /// Returns the Firestore collection name based on test mode state
  String get signalsCollectionName =>
      isTestMode() ? 'signals_test' : 'signals';
}

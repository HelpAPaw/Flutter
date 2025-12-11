import 'package:shared_preferences/shared_preferences.dart';

class AppPreferencesService {
  static final AppPreferencesService _instance = AppPreferencesService._internal();
  factory AppPreferencesService() => _instance;
  AppPreferencesService._internal();

  SharedPreferences? _prefs;

  // Keys
  static const String _onboardingCompletedKey = 'notification_onboarding_completed';
  static const String _onboardingDismissedKey = 'notification_onboarding_dismissed';

  /// Initialize SharedPreferences - must be called before using any other methods
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
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
}

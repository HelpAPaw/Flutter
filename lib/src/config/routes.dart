class Routes {
  Routes._();

  static const home = '/home';
  static const signIn = '/sign_in';
  static const verifyEmail = '/verify_email';
  static const completeProfile = '/complete_profile';
  static const profile = '/profile';
  static const mySignals = '/my_signals';
  static const myNotifications = '/my_notifications';
  static const notificationSettings = '/notification-settings';
  static const selectRegion = '/select-region';
  static const faqs = '/faqs';
  static const feedback = '/feedback';
  static const privacyPolicy = '/privacy_policy';
  static const about = '/about';

  static const signalDetailsPath = '/signal_details/:signalId';
  static const editSignalPath = '/edit_signal/:signalId';
  static const clinicDetailsPath = '/clinic_details/:clinicId';

  /// Public, shareable deep-link path (App Links / Universal Links).
  /// Matches the URLs produced by [signalShareUrl] and the hosted fallback
  /// page; redirects to [signalDetailsPath].
  static const signalLinkPath = '/signal/:signalId';

  /// Host serving the shareable links. Must stay in step with the App Link /
  /// Universal Link host declared in AndroidManifest.xml and the iOS
  /// entitlements, and with LINK_HOST in functions/src/index.ts.
  static const linkHost = 'https://link.helpapaw.org';

  /// Public URL for a signal — what gets shared, and what the OS matches
  /// against [signalLinkPath] to open the app.
  static String signalShareUrl(String signalId) => '$linkHost/signal/$signalId';

  /// Prefix of [signalDetailsPath], for testing whether a location is already
  /// on a signal.
  static const signalDetailsPrefix = '/signal_details/';

  static String signalDetails(String signalId) => '$signalDetailsPrefix$signalId';
  static String editSignal(String signalId) => '/edit_signal/$signalId';
  static String clinicDetails(String clinicId) => '/clinic_details/$clinicId';

  /// Routes that the profile-completion flow treats as transient "auth"
  /// screens to pop off the stack on its way back to the origin.
  static const authRoutes = {signIn, verifyEmail, completeProfile};
}

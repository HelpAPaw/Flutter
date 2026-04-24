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

  static String signalDetails(String signalId) => '/signal_details/$signalId';
  static String editSignal(String signalId) => '/edit_signal/$signalId';
  static String clinicDetails(String clinicId) => '/clinic_details/$clinicId';

  /// Routes that the profile-completion flow treats as transient "auth"
  /// screens to pop off the stack on its way back to the origin.
  static const authRoutes = {signIn, verifyEmail, completeProfile};
}

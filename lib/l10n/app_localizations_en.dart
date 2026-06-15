// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get signIn => 'Sign In';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signUp => 'Sign Up';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get retry => 'Retry';

  @override
  String get confirm => 'Confirm';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get unknown => 'Unknown';

  @override
  String get error => 'Error';

  @override
  String get loading => 'Loading...';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get statusNeedsHelp => 'Needs help';

  @override
  String get statusInProgress => 'In progress';

  @override
  String get statusResolved => 'Resolved';

  @override
  String get signalTypeEmergency => 'Emergency';

  @override
  String get signalTypeLostOrFound => 'Lost or Found';

  @override
  String get signalTypeBloodDonation => 'Blood donation';

  @override
  String get signalTypeHomeless => 'Homeless';

  @override
  String get signalTypeUnneuteredAnimals => 'Unneutered animals';

  @override
  String get signalTypeWildAnimals => 'Wild animals';

  @override
  String get signalTypeOther => 'Other';

  @override
  String get filterSignals => 'Filter Signals';

  @override
  String get toggleVetClinics => 'Toggle veterinary clinics';

  @override
  String get selectAll => 'Select All';

  @override
  String get clearAll => 'Clear All';

  @override
  String get deselectAll => 'Deselect All';

  @override
  String get status => 'Status';

  @override
  String get signalType => 'Signal Type';

  @override
  String get timeRange => 'Time Range';

  @override
  String get last24Hours => 'Last 24 hours';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get last30Days => 'Last 30 days';

  @override
  String get allTime => 'All time';

  @override
  String get applyFilters => 'Apply Filters';

  @override
  String get searchThisArea => 'Search this area';

  @override
  String get loadingClinics => 'Loading clinics...';

  @override
  String get title => 'Title';

  @override
  String get description => 'Description';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get submitSignal => 'Submit signal';

  @override
  String get addNewSignal => 'Add new signal';

  @override
  String get pleaseEnterTitle => 'Please enter a title for the signal';

  @override
  String get pleaseEnterDescription =>
      'Please enter a description for the signal';

  @override
  String get signalCreatedPhotoFailed =>
      'Signal created, but photo upload failed. You can try again later.';

  @override
  String get permissionDenied =>
      'Permission denied. Please check your account permissions.';

  @override
  String get authenticationError =>
      'Authentication error. Please sign in again.';

  @override
  String get serviceUnavailable =>
      'Service unavailable. Please try again later.';

  @override
  String get networkError => 'Network error. Please check your connection.';

  @override
  String get failedToCreateSignal =>
      'Failed to create signal. Please try again.';

  @override
  String get requestTimedOut =>
      'Request timed out. Please check your connection and try again.';

  @override
  String get unexpectedError =>
      'An unexpected error occurred. Please try again.';

  @override
  String get noVetClinicsFound => 'No veterinary clinics found in this area';

  @override
  String get failedToLoadVetClinics => 'Failed to load vet clinics';

  @override
  String get tooManySearches =>
      'Too many searches. Please wait a moment and try again.';

  @override
  String get takePhoto => 'Take Photo';

  @override
  String get chooseFromGallery => 'Choose from Gallery';

  @override
  String get removePhoto => 'Remove photo';

  @override
  String errorAccessingCamera(String error) {
    return 'Error accessing camera: $error';
  }

  @override
  String errorAccessingGallery(String error) {
    return 'Error accessing gallery: $error';
  }

  @override
  String get signInSubtitle => 'Sign in to report and help animals in need';

  @override
  String get signInSideMessage => 'Join our community of animal lovers';

  @override
  String get signInRequired => 'Sign in required';

  @override
  String get signInToCreateSignals => 'You need to sign in to create signals';

  @override
  String get signInToComment => 'You need to sign in to comment';

  @override
  String get signalDetails => 'Signal Details';

  @override
  String get uploadingPhoto => 'Uploading photo...';

  @override
  String get addPhoto => 'Add Photo';

  @override
  String get addAnotherPhoto => 'Add Another Photo';

  @override
  String photosCount(int current, int max) {
    return '$current/$max photos';
  }

  @override
  String get failedToLoadImage => 'Failed to load image';

  @override
  String signalTypeLabel(String type) {
    return 'Signal type: $type';
  }

  @override
  String get navigateMe => 'Navigate Me';

  @override
  String get chooseNavigationApp => 'Choose Navigation App';

  @override
  String get cannotNavigate => 'No navigation apps found on this device.';

  @override
  String cannotCall(String phone) {
    return 'Cannot call $phone, please try to connect manually.';
  }

  @override
  String get comments => 'Comments';

  @override
  String get enterYourComment => 'Enter your comment';

  @override
  String changedStatusTo(String name, String status) {
    return '$name changed the status to $status';
  }

  @override
  String get someone => 'Someone';

  @override
  String get deletePhoto => 'Delete photo';

  @override
  String get confirmDeletePhoto =>
      'Are you sure you want to delete this photo?';

  @override
  String get photoAddedSuccessfully => 'Photo added successfully!';

  @override
  String get photoDeletedSuccessfully => 'Photo deleted successfully';

  @override
  String failedToUploadPhoto(String error) {
    return 'Failed to upload photo: $error';
  }

  @override
  String failedToDeletePhoto(String error) {
    return 'Failed to delete photo: $error';
  }

  @override
  String photoOf(int current, int total) {
    return '$current of $total';
  }

  @override
  String get profile => 'Profile';

  @override
  String get pleaseSignInToViewProfile => 'Please sign in to view your profile';

  @override
  String get displayName => 'Display Name';

  @override
  String get noNameSet => 'No name set';

  @override
  String get signals => 'Signals';

  @override
  String get email => 'Email';

  @override
  String get notSet => 'Not set';

  @override
  String get emailVerified => 'Email Verified';

  @override
  String get verify => 'Verify';

  @override
  String get verificationEmailSent => 'Verification email sent';

  @override
  String get memberSince => 'Member Since';

  @override
  String get profileUpdatedSuccessfully => 'Profile updated successfully';

  @override
  String errorUpdatingProfile(String error) {
    return 'Error updating profile: $error';
  }

  @override
  String get photoUpdatedSuccessfully => 'Photo updated successfully';

  @override
  String errorUploadingPhoto(String error) {
    return 'Error uploading photo: $error';
  }

  @override
  String errorLoadingStatistics(String error) {
    return 'Error loading statistics: $error';
  }

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get sendFeedback => 'Send Feedback';

  @override
  String get weLoveToHear => 'We\'d love to hear from you!';

  @override
  String get feedbackHelpsImprove =>
      'Your feedback helps us improve Help a Paw for everyone.';

  @override
  String get feedbackType => 'Feedback Type';

  @override
  String get general => 'General';

  @override
  String get bugReport => 'Bug Report';

  @override
  String get featureRequest => 'Feature Request';

  @override
  String get other => 'Other';

  @override
  String get yourEmailOptional => 'Your Email (optional)';

  @override
  String get emailPlaceholder => 'email@example.com';

  @override
  String get provideEmailForFollowUp =>
      'Provide your email if you\'d like us to follow up';

  @override
  String get yourFeedback => 'Your Feedback';

  @override
  String get bugReportHint => 'Please describe the issue you encountered...';

  @override
  String get featureRequestHint =>
      'Tell us about the feature you\'d like to see...';

  @override
  String get generalFeedbackHint => 'Share your thoughts with us...';

  @override
  String get includeDeviceInfo => 'Include device information';

  @override
  String get helpsUsDiagnose => 'Helps us diagnose issues faster';

  @override
  String get submitFeedback => 'Submit Feedback';

  @override
  String get pleaseEnterFeedback => 'Please enter your feedback';

  @override
  String get thankYouFeedback => 'Thank you for your feedback!';

  @override
  String errorSubmittingFeedback(String error) {
    return 'Error submitting feedback: $error';
  }

  @override
  String get otherWaysToReach => 'Other ways to reach us';

  @override
  String get notificationSettings => 'Notification Settings';

  @override
  String get createAnAccount => 'Create an account';

  @override
  String get signUpToKeepSettings =>
      'Sign up to keep your settings across devices';

  @override
  String get notifications => 'Notifications';

  @override
  String get enableNotifications => 'Enable Notifications';

  @override
  String get receiveNotificationsAboutSignals =>
      'Receive notifications about signals near you';

  @override
  String get locationTracking => 'Location Tracking';

  @override
  String get trackMyLocation => 'Track My Location';

  @override
  String get getNotifiedNearLocation =>
      'Get notified when signals appear near your current location';

  @override
  String notificationRadiusKm(String radius) {
    return 'Notification radius: $radius km';
  }

  @override
  String get regionOfInterest => 'Region of Interest';

  @override
  String get setRegionOnMap => 'Set Region on Map';

  @override
  String radiusKm(String radius) {
    return 'Radius: $radius km';
  }

  @override
  String get tapToSelectArea => 'Tap to select an area on the map';

  @override
  String get clearRegion => 'Clear Region';

  @override
  String get signalTypes => 'Signal Types';

  @override
  String get settingsSaved => 'Settings saved';

  @override
  String get failedToSaveSettings => 'Failed to save settings';

  @override
  String get locationPermissionRequired =>
      'Location permission is required for this feature';

  @override
  String get mySignals => 'My Signals';

  @override
  String get pleaseSignInToViewSignals => 'Please sign in to view your signals';

  @override
  String get noSignalsYet => 'No signals yet';

  @override
  String get submittedSignalsAppearHere =>
      'Your submitted signals will appear here';

  @override
  String get unknownDate => 'Unknown date';

  @override
  String errorWithMessage(String error) {
    return 'Error: $error';
  }

  @override
  String get navigationDrawer => 'Navigation Drawer';

  @override
  String get ourSite => 'Our Site';

  @override
  String get about => 'About';

  @override
  String get share => 'Share';

  @override
  String get faqs => 'FAQs';

  @override
  String get feedback => 'Feedback';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get launchingBrowser => 'Launching Browser';

  @override
  String snapshotError(String error) {
    return 'Snapshot Error: $error';
  }

  @override
  String get faqsTitle => 'FAQs';

  @override
  String get faqSectionGeneral => 'General';

  @override
  String get faqSectionCreatingSignals => 'Creating Signals';

  @override
  String get faqSectionHelpingAnimals => 'Helping Animals';

  @override
  String get faqSectionNotifications => 'Notifications';

  @override
  String get faqSectionPrivacySafety => 'Privacy & Safety';

  @override
  String get faqWhatIsHelpAPaw => 'What is Help a Paw?';

  @override
  String get faqWhatIsHelpAPawAnswer =>
      'Help a Paw is a mobile application that helps connect people who spot animals in distress with volunteers who can provide assistance. By creating signals on the map, you can alert the community about animals that need help.';

  @override
  String get faqNeedAccount => 'Do I need to create an account?';

  @override
  String get faqNeedAccountAnswer =>
      'You can browse signals without an account, but to create new signals or leave comments, you\'ll need to sign in. This helps us maintain the quality of reports and allows you to track your contributions.';

  @override
  String get faqIsFree => 'Is the app free to use?';

  @override
  String get faqIsFreeAnswer =>
      'Yes, Help a Paw is completely free to use. We are a non-profit initiative dedicated to helping animals in need.';

  @override
  String get faqHowCreateSignal => 'How do I create a signal?';

  @override
  String get faqHowCreateSignalAnswer =>
      'Tap the \"+\" button on the map, select the location where you spotted the animal, choose the signal type (Emergency, Lost/Found, etc.), add a description, and optionally include photos. Your signal will be visible to other users in the area.';

  @override
  String get faqWhatTypesSignals => 'What types of signals can I create?';

  @override
  String get faqWhatTypesSignalsAnswer =>
      'You can create signals for: Emergency situations, Lost or Found animals, Blood donation needs, Homeless animals, Unneutered animals, Wild animals, and Other situations.';

  @override
  String get faqCanEditDelete => 'Can I edit or delete my signal?';

  @override
  String get faqCanEditDeleteAnswer =>
      'Yes, you can edit or delete signals that you\'ve created. Go to \"My Signals\" from the menu, select the signal you want to modify, and use the edit or delete options.';

  @override
  String get faqWhatIncludeDescription =>
      'What should I include in a signal description?';

  @override
  String get faqWhatIncludeDescriptionAnswer =>
      'Include details like: the type and condition of the animal, exact location landmarks, any urgent needs (food, medical attention), your availability to help, and a contact number if you\'re comfortable sharing it.';

  @override
  String get faqHowHelp => 'How can I help with a signal?';

  @override
  String get faqHowHelpAnswer =>
      'When you see a signal on the map, tap it to view details. You can leave a comment to coordinate with others, update the signal status if you\'re helping, or contact the person who created the signal.';

  @override
  String get faqWhatStatusesMean => 'What do the signal statuses mean?';

  @override
  String get faqWhatStatusesMeanAnswer =>
      'Red (Needs help): The animal still needs assistance.\nOrange (In progress): Someone is working on helping.\nGreen (Resolved): The animal has received help or the situation is resolved.';

  @override
  String get faqCantHelpDirectly =>
      'I\'m not able to help directly. What can I do?';

  @override
  String get faqCantHelpDirectlyAnswer =>
      'You can share the signal with friends who might be able to help, leave helpful comments with advice or contacts of local animal rescue organizations, or simply spread awareness about the app to grow our community of helpers.';

  @override
  String get faqHowNotificationsWork => 'How do notifications work?';

  @override
  String get faqHowNotificationsWorkAnswer =>
      'You\'ll receive notifications when: a new signal appears in your area, someone comments on your signal, or the status of a signal you\'re following changes. You can customize notification settings in the app.';

  @override
  String get faqChangeNotificationRadius =>
      'How do I change my notification radius?';

  @override
  String get faqChangeNotificationRadiusAnswer =>
      'Go to Notification Settings > Location Tracking > Notification radius and adjust the slider. You can set it from 1km to 50km depending on how far you\'re willing to help.';

  @override
  String get faqPersonalInfoSafe => 'Is my personal information safe?';

  @override
  String get faqPersonalInfoSafeAnswer =>
      'We take privacy seriously. Your email is only used for account management. Phone numbers shared in signals are optional and at your discretion. Location data is only used to show relevant signals.';

  @override
  String get faqReportInappropriate => 'How do I report inappropriate content?';

  @override
  String get faqReportInappropriateAnswer =>
      'If you see a signal that contains inappropriate content, spam, or false information, please use the report function on the signal or contact us through the Feedback option in the menu.';

  @override
  String get stayInformedTitle => 'Stay Informed About Animals in Need';

  @override
  String get stayInformedSubtitle =>
      'Get notified when signals appear near you or in your area of interest.';

  @override
  String get maybeLater => 'Maybe Later';

  @override
  String get enableLocationTitle => 'Enable Location Tracking';

  @override
  String get enableLocationSubtitle =>
      'Get alerts for animals in need within 10km of your location.';

  @override
  String get enableLocation => 'Enable Location';

  @override
  String get skipForNow => 'Skip for Now';

  @override
  String get chooseRegionTitle => 'Choose Your Region of Interest';

  @override
  String get chooseRegionSubtitle =>
      'Select a specific area you care about and get notified of signals there.';

  @override
  String get selectRegion => 'Select Region';

  @override
  String get aboutTitle => 'About';

  @override
  String get helpAPaw => 'Help a Paw';

  @override
  String version(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get appDescription => 'Send emergency signals about animals in need';

  @override
  String get aboutDescription =>
      'Help a Paw is a platform that connects people who spot animals in distress with volunteers who can help. Together, we can make a difference in the lives of animals.';

  @override
  String get connectWithUs => 'Connect with us';

  @override
  String get website => 'Website';

  @override
  String get facebook => 'Facebook';

  @override
  String get gitHub => 'GitHub';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String copyright(int year) {
    return '© $year Help a Paw';
  }

  @override
  String get verifyEmail => 'Verify Email';

  @override
  String get verifyYourEmail => 'Verify Your Email';

  @override
  String get verificationEmailSentTo => 'We sent a verification email to:';

  @override
  String get instructions => 'Instructions:';

  @override
  String get instructionsSteps =>
      '1. Open the email in your inbox\n2. Click the verification link\n3. Return to this app\n4. You\'ll be automatically redirected';

  @override
  String get checkingVerificationStatus => 'Checking verification status...';

  @override
  String get verificationEmailSentCheck =>
      'Verification email sent! Check your inbox.';

  @override
  String get tooManyRequests =>
      'Too many requests. Please try again later or contact support.';

  @override
  String get accountDisabled =>
      'This account has been disabled. Please contact support.';

  @override
  String unexpectedErrorWithMessage(String error) {
    return 'Unexpected error: $error';
  }

  @override
  String errorWithCode(String message) {
    return 'Error: $message';
  }

  @override
  String resendInSeconds(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get resendVerificationEmail => 'Resend Verification Email';

  @override
  String get iveVerifiedMyEmail => 'I\'ve verified my email';

  @override
  String get cancelAndSignOut => 'Cancel and sign out';

  @override
  String get skipDevOnly => 'Skip (Dev Only)';

  @override
  String get myNotifications => 'Notifications';

  @override
  String get pleaseSignInToViewNotifications =>
      'Please sign in to view notifications';

  @override
  String get markAllAsRead => 'Mark all as read';

  @override
  String get clearAllNotifications => 'Clear all';

  @override
  String get noNotifications => 'No notifications';

  @override
  String get notifiedAboutSignalUpdates =>
      'You\'ll be notified about signal updates';

  @override
  String get notification => 'Notification';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int minutes) {
    return '${minutes}m ago';
  }

  @override
  String hoursAgo(int hours) {
    return '${hours}h ago';
  }

  @override
  String daysAgo(int days) {
    return '${days}d ago';
  }

  @override
  String get completeYourProfile => 'Complete Your Profile';

  @override
  String get helpUsPersonalize => 'Help us personalize your experience';

  @override
  String get fullNameRequired => 'Full Name *';

  @override
  String get enterFullName => 'Enter your full name';

  @override
  String get nameIsRequired => 'Name is required';

  @override
  String get nameTooShort => 'Name must be at least 2 characters';

  @override
  String get phoneNumberOptional => 'Phone Number (Optional)';

  @override
  String get enterPhoneNumber => 'Enter your phone number';

  @override
  String get validPhoneNumber => 'Please enter a valid phone number';

  @override
  String get completeProfile => 'Complete Profile';

  @override
  String get skipForNowProfile => 'Skip for now';

  @override
  String errorSavingProfile(String error) {
    return 'Error saving profile: $error';
  }

  @override
  String get clinicDetails => 'Clinic Details';

  @override
  String get clinicNotFound => 'Clinic not found';

  @override
  String get returnToMap => 'Return to Map';

  @override
  String get viewReviews => 'View reviews';

  @override
  String get address => 'Address';

  @override
  String get navigate => 'Navigate';

  @override
  String get phone => 'Phone';

  @override
  String get call => 'Call';

  @override
  String get openingHours => 'Opening Hours';

  @override
  String get viewInGoogleMaps => 'View in Google Maps';

  @override
  String get cannotOpenNavigationApp => 'Cannot open navigation app';

  @override
  String get cannotMakePhoneCalls => 'Cannot make phone calls on this device';

  @override
  String get cannotOpenGoogleMaps => 'Cannot open Google Maps';

  @override
  String get selectRegionTitle => 'Select Region';

  @override
  String get tapToSetCenterPoint =>
      'Please tap on the map to set a center point';

  @override
  String get tapMapInstruction =>
      'Tap on the map to set the center of your region of interest';

  @override
  String get regionRadius => 'Region radius';

  @override
  String get km => 'km';

  @override
  String get dragMarkerToReposition =>
      'Drag the marker to reposition the center';

  @override
  String get shareSignal => 'Share signal';

  @override
  String get sendComment => 'Send comment';

  @override
  String get closePhotoViewer => 'Close photo viewer';

  @override
  String get uploadPhoto => 'Upload photo';

  @override
  String couldNotOpenUrl(String url) {
    return 'Could not open $url';
  }

  @override
  String get completeNotificationSetup => 'Complete notification setup';

  @override
  String get editSignal => 'Edit Signal';

  @override
  String get deleteSignal => 'Delete Signal';

  @override
  String get confirmDeleteSignal =>
      'Are you sure you want to delete this signal? This action cannot be undone.';

  @override
  String get signalUpdatedSuccessfully => 'Signal updated successfully';

  @override
  String get signalDeletedSuccessfully => 'Signal deleted successfully';

  @override
  String get failedToUpdateSignal =>
      'Failed to update signal. Please try again.';

  @override
  String get failedToDeleteSignal =>
      'Failed to delete signal. Please try again.';

  @override
  String get contactPhone => 'Contact Phone';

  @override
  String get errorAddingComment => 'Failed to add comment. Please try again.';

  @override
  String get errorUpdatingStatus =>
      'Failed to update status. Please try again.';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get deleteAccountConfirmTitle => 'Delete account?';

  @override
  String get deleteAccountConfirmBody =>
      'This permanently deletes your account and personal data and cannot be undone. Your past reports will remain but will no longer be linked to you.';

  @override
  String get deleteAccountSuccess => 'Your account has been deleted.';

  @override
  String get deleteAccountError =>
      'Failed to delete account. Please try again.';
}

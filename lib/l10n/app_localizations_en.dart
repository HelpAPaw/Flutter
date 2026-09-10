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
  String get statusNeedsHelp => 'Waiting for help';

  @override
  String get statusInProgress => 'Someone is helping';

  @override
  String get statusResolved => 'Resolved';

  @override
  String get urgency => 'Urgency';

  @override
  String get urgencyGreen => 'Low';

  @override
  String get urgencyGreenDescription =>
      'Not in immediate danger, or the situation is being managed.';

  @override
  String get urgencyAmber => 'Medium';

  @override
  String get urgencyAmberDescription =>
      'Needs help quickly, but is not life-or-death within hours.';

  @override
  String get urgencyRed => 'Critical';

  @override
  String get urgencyRedDescription =>
      'Serious harm, death or disappearance may follow if help does not happen now.';

  @override
  String get pleaseSelectUrgency => 'Please select how urgent this is';

  @override
  String get errorUpdatingUrgency =>
      'Failed to update urgency. Please try again.';

  @override
  String changedUrgencyTo(String name, String urgency) {
    return '$name changed the urgency to $urgency';
  }

  @override
  String get redAlertConfirmTitle => 'Publish as a Red Alert?';

  @override
  String get redAlertConfirmBody =>
      'Red Alert is only for critical cases where the animal may die, disappear, be seriously harmed, or remain in immediate danger if help does not happen now.\n\nMisusing Red Alert reduces trust in the system and may affect your account.';

  @override
  String get redAlertConfirmCheckbox =>
      'I understand and confirm this is an immediate critical case';

  @override
  String get redAlertConfirmAction => 'Confirm Red Alert';

  @override
  String get helpTagRescue => 'Rescue';

  @override
  String get helpTagVetCare => 'Vet care';

  @override
  String get helpTagBloodDonation => 'Blood donation';

  @override
  String get helpTagFoster => 'Fostering';

  @override
  String get helpTagAdoption => 'Adoption';

  @override
  String get helpTagTransport => 'Transport';

  @override
  String get helpTagFood => 'Food & supplies';

  @override
  String get helpTagTrapping => 'Trapping';

  @override
  String get helpTagNeutering => 'Neutering';

  @override
  String get helpTagBabyCare => 'Newborn care';

  @override
  String get helpTagFundraising => 'Fundraising';

  @override
  String get helpTagLostFound => 'Lost / found';

  @override
  String get helpTagDangerWarning => 'Local danger';

  @override
  String get helpTagRescueHelper => 'I can go to an animal in need';

  @override
  String get helpTagVetCareHelper => 'I can help with a vet visit or treatment';

  @override
  String get helpTagBloodDonationHelper =>
      'My pet can donate blood, or I can help arrange a donor';

  @override
  String get helpTagFosterHelper =>
      'I can take an animal into my home for a while';

  @override
  String get helpTagAdoptionHelper =>
      'I am looking to adopt, or can help find a home';

  @override
  String get helpTagTransportHelper => 'I can drive an animal somewhere';

  @override
  String get helpTagFoodHelper => 'I can bring food or supplies';

  @override
  String get helpTagTrappingHelper =>
      'I can trap an animal, or I have a trap or cage';

  @override
  String get helpTagNeuteringHelper =>
      'I can help get animals neutered or spayed';

  @override
  String get helpTagBabyCareHelper => 'I can bottle-feed or care for newborns';

  @override
  String get helpTagFundraisingHelper => 'I can help raise or share funds';

  @override
  String get helpTagLostFoundHelper =>
      'Tell me about lost and found pets near me — I will keep an eye out';

  @override
  String get helpTagDangerWarningHelper =>
      'Tell me about hazards in my area, such as poison bait or traps';

  @override
  String get helpTagRescueNeeded => 'Rescue needed';

  @override
  String get helpTagVetCareNeeded => 'Vet care needed';

  @override
  String get helpTagBloodDonationNeeded => 'Blood donation needed';

  @override
  String get helpTagFosterNeeded => 'Foster needed';

  @override
  String get helpTagAdoptionNeeded => 'Adoption needed';

  @override
  String get helpTagTransportNeeded => 'Transport needed';

  @override
  String get helpTagFoodNeeded => 'Food & supplies needed';

  @override
  String get helpTagTrappingNeeded => 'Trapping needed';

  @override
  String get helpTagNeuteringNeeded => 'Neutering needed';

  @override
  String get helpTagBabyCareNeeded => 'Newborn care needed';

  @override
  String get helpTagFundraisingNeeded => 'Fundraising needed';

  @override
  String get animalTypeCat => 'Cat';

  @override
  String get animalTypeDog => 'Dog';

  @override
  String get animalTypeOther => 'Other animal';

  @override
  String get helpNeeded => 'Help needed';

  @override
  String get animalType => 'Animal';

  @override
  String get animalTypes => 'Animals';

  @override
  String get helperTags => 'How I can help';

  @override
  String get pleaseSelectHelpTag =>
      'Please choose at least one kind of help needed';

  @override
  String get pleaseSelectAnimalType =>
      'Please choose which animal this is about';

  @override
  String helpTagLimitReached(int count) {
    return 'You can choose up to $count kinds of help';
  }

  @override
  String get helperTagsOnboardingTitle => 'How can you help?';

  @override
  String get helperTagsOnboardingIntro =>
      'Pick what you can realistically do, and which animals you can help. We use this to send you the signals you can actually act on — you can change it any time in settings.';

  @override
  String get helperTagsOnboardingHelpSection => 'What can you help with?';

  @override
  String get helperTagsOnboardingAnimalSection => 'Which animals can you help?';

  @override
  String get helperTagsOnboardingContinue => 'Continue';

  @override
  String get helperTagsSaveFailed =>
      'Could not save your choices. Please try again.';

  @override
  String get settingsLoadFailed =>
      'Your settings could not be loaded. Check your connection and try again — nothing has been changed.';

  @override
  String get selectAtLeastOneAnimalType =>
      'Choose at least one animal, or turn notifications off';

  @override
  String get selectAtLeastOneHelperTag =>
      'Choose at least one way you can help';

  @override
  String get filterSignals => 'Filter Signals';

  @override
  String get toggleVetClinics => 'Toggle veterinary clinics';

  @override
  String get selectAll => 'Select All';

  @override
  String get clearAll => 'Clear All';

  @override
  String get status => 'Status';

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
  String get next => 'Next';

  @override
  String get back => 'Back';

  @override
  String get skip => 'Skip';

  @override
  String get change => 'Change';

  @override
  String newSignalStepCounter(int current, int total) {
    return 'Step $current of $total';
  }

  @override
  String get newSignalStepLocation => 'Location';

  @override
  String get newSignalStepPhoto => 'Photo';

  @override
  String get newSignalStepDetails => 'Details';

  @override
  String get newSignalStepAnimal => 'Animal';

  @override
  String get newSignalStepUrgency => 'Urgency';

  @override
  String get newSignalStepHelp => 'Help needed';

  @override
  String get newSignalStepReview => 'Review';

  @override
  String get newSignalQuestionLocation => 'Where is the animal?';

  @override
  String get newSignalQuestionPhoto => 'Can you add a photo?';

  @override
  String get newSignalQuestionDetails => 'What is happening?';

  @override
  String get newSignalQuestionAnimal => 'What animal is it?';

  @override
  String get newSignalQuestionUrgency => 'How urgent is it?';

  @override
  String get newSignalQuestionHelp => 'What does it need?';

  @override
  String get newSignalQuestionReview => 'Ready to send?';

  @override
  String get newSignalHintLocation =>
      'Move the map so the pin sits where the animal is.';

  @override
  String get newSignalHintPhoto =>
      'A photo helps volunteers recognise the animal. You can skip this.';

  @override
  String get newSignalHintDetails =>
      'A short title and a few sentences are enough.';

  @override
  String get newSignalHintUrgency =>
      'A red alert notifies every volunteer nearby, so keep it for real emergencies.';

  @override
  String get newSignalHintReview => 'Check everything, then send it.';

  @override
  String newSignalHintHelp(int count) {
    return 'Choose up to $count, most important first.';
  }

  @override
  String get newSignalAddPhoto => 'Add a photo';

  @override
  String get newSignalNoPhoto => 'No photo';

  @override
  String get newSignalNotProvided => 'Not provided';

  @override
  String get newSignalPinPlaced => 'Pin placed';

  @override
  String get newSignalDiscardTitle => 'Discard this report?';

  @override
  String get newSignalDiscardMessage =>
      'Everything you have entered will be lost.';

  @override
  String get newSignalDiscardConfirm => 'Discard';

  @override
  String get newSignalDiscardKeep => 'Keep editing';

  @override
  String get pleaseSelectLocation => 'Please place the pin where the animal is';

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
  String get notAllowedError =>
      'You are not allowed to do that. Signing in again may help.';

  @override
  String get serverBusyError =>
      'The server is busy right now. Please try again in a moment.';

  @override
  String get cameraPermissionDenied =>
      'Help a Paw needs camera access. You can allow it in Settings.';

  @override
  String get photosPermissionDenied =>
      'Help a Paw needs access to your photos. You can allow it in Settings.';

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
  String get removePhoto => 'Remove Photo';

  @override
  String get errorAccessingCamera =>
      'Could not open the camera. Please try again.';

  @override
  String get errorAccessingGallery =>
      'Could not open your photos. Please try again.';

  @override
  String get signInSubtitle => 'Sign in to report and help animals in need';

  @override
  String get signInSideMessage => 'Join our community of animal lovers';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get googleSignInFailed => 'Google sign-in failed. Please try again.';

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
  String get signalHistory => 'Signal history';

  @override
  String get historyPartiallyUnavailable =>
      'Part of this history could not be loaded.';

  @override
  String get historyFilterAll => 'All';

  @override
  String get historyFilterEvents => 'Events';

  @override
  String reportedThisSignal(String name) {
    return '$name reported this signal';
  }

  @override
  String get updateNoteTitle => 'What changed?';

  @override
  String get nothingWasSaved => 'Nothing was saved.';

  @override
  String updateNoteChangingTo(String level) {
    return 'Changing to: $level';
  }

  @override
  String get updateNoteTakingSignal => 'Taking responsibility for this signal';

  @override
  String updateNoteTakingSignalAndChangingTo(String level) {
    return 'Taking responsibility, and changing to: $level';
  }

  @override
  String get updateNoteSteppingDown => 'Stepping down from this signal';

  @override
  String get updateNoteHandingOver => 'Handing this signal over';

  @override
  String get updateNoteDecliningOffer => 'Declining this offer';

  @override
  String get updateNoteOfferingTakeover => 'Offering to take this signal on';

  @override
  String get updateNoteHint => 'Add a short note for the signal history';

  @override
  String get updateNoteRequired =>
      'Please say what changed — everyone following this signal sees it.';

  @override
  String changedStatusTo(String name, String status) {
    return '$name changed the status to $status';
  }

  @override
  String get someone => 'Someone';

  @override
  String get signalOwner => 'Responsible';

  @override
  String get signalOwnerNobody => 'Nobody has taken this signal on yet';

  @override
  String get signalOwnerIsYou => 'You are responsible for this signal';

  @override
  String get signalOwnerTakeResponsibility => 'Take responsibility';

  @override
  String get signalOwnerRequestTakeover => 'Offer to take over';

  @override
  String get signalOwnerRequestPending => 'You have offered to take this over';

  @override
  String get signalOwnerWithdrawRequest => 'Withdraw offer';

  @override
  String get signalOwnerRelease => 'I can no longer do this';

  @override
  String get signalOwnerHandOver => 'Hand over';

  @override
  String get signalOwnerDecline => 'Decline';

  @override
  String get signalOwnerOffers => 'Offers to take over';

  @override
  String get signalOwnerStale => 'Nobody has updated this signal in a while.';

  @override
  String get takeoverConfirmTitle => 'Take responsibility for this signal?';

  @override
  String get takeoverConfirmBody =>
      'You become the person coordinating this signal. You can change its status and urgency, and hand it on or step down at any time.';

  @override
  String get takeoverConfirmAction => 'Take it on';

  @override
  String get handOverConfirmTitle => 'Hand this signal over?';

  @override
  String get handOverConfirmBody =>
      'They become the person coordinating this signal. You stay subscribed to it and can offer to take it back later.';

  @override
  String get declineConfirmBody =>
      'They are told you are keeping the signal. They can offer again after a day.';

  @override
  String get releaseConfirmTitle => 'Step down from this signal?';

  @override
  String get releaseConfirmBody =>
      'The signal stays open and anyone can take it on. Everyone following it is told.';

  @override
  String get takeoverNoteHint => 'Say what you plan to do';

  @override
  String get takeoverAlreadyOwned =>
      'Someone else is responsible for this signal. You can offer to take it over.';

  @override
  String get takeoverRequestSent =>
      'Your offer was sent to the person responsible.';

  @override
  String get takeoverAlreadyAsked =>
      'You have already offered to take this over.';

  @override
  String takeoverAskAgainAfter(String when) {
    return 'You can offer again after $when.';
  }

  @override
  String get errorChangingSignalOwner => 'Could not change who is responsible.';

  @override
  String tookResponsibility(String name) {
    return '$name took responsibility for this signal';
  }

  @override
  String handedSignalTo(String name, String other) {
    return '$name handed this signal to $other';
  }

  @override
  String get reportedThisSignalShort => 'Reported this signal';

  @override
  String statusSetTo(String status) {
    return 'Status set to $status';
  }

  @override
  String urgencySetTo(String urgency) {
    return 'Urgency set to $urgency';
  }

  @override
  String get releasedSignalShort => 'Stepped down from this signal';

  @override
  String get tookResponsibilityShort => 'Took responsibility for this signal';

  @override
  String handedSignalToShort(String other) {
    return 'Handed this signal to $other';
  }

  @override
  String releasedSignal(String name) {
    return '$name stepped down from this signal';
  }

  @override
  String get notificationOwnershipChangeTitle => 'Someone took responsibility';

  @override
  String get notificationOwnershipReleasedTitle => 'This signal needs someone';

  @override
  String notificationOwnershipChangeBody(String name) {
    return '$name is now responsible';
  }

  @override
  String get notificationOwnershipReleasedBody =>
      'Nobody is responsible for this signal now';

  @override
  String get notificationTakeoverRequestTitle => 'Someone offered to take over';

  @override
  String notificationTakeoverRequestBody(String name) {
    return '$name asked to take responsibility';
  }

  @override
  String get notificationTakeoverApprovedTitle =>
      'You are now responsible for a signal';

  @override
  String get notificationTakeoverApprovedBody => 'The signal is yours';

  @override
  String get notificationTakeoverDeclinedTitle => 'Your offer was declined';

  @override
  String get notificationTakeoverDeclinedBody =>
      'The current owner is keeping this signal';

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
  String get failedToUploadPhoto =>
      'Could not upload the photo. Please try again.';

  @override
  String get failedToDeletePhoto =>
      'Could not delete the photo. Please try again.';

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
  String get errorUpdatingProfile =>
      'Could not save your profile. Please try again.';

  @override
  String get photoUpdatedSuccessfully => 'Photo updated successfully';

  @override
  String get errorUploadingPhoto =>
      'Could not upload your photo. Please try again.';

  @override
  String get errorLoadingStatistics => 'Could not load your statistics.';

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
  String get pleaseEnterValidEmail => 'Please enter a valid email address';

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
  String get errorSubmittingFeedback =>
      'Could not send your feedback. Please try again.';

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
  String get settingsSaved => 'Settings saved';

  @override
  String get failedToSaveSettings => 'Failed to save settings';

  @override
  String get locationBackgroundInactiveTitle =>
      'Only updating while the app is open';

  @override
  String get locationBackgroundInactiveBody =>
      'Location access is not set to \"Allow all the time\", so we cannot check for nearby signals once you close the app.';

  @override
  String get openSettings => 'Open settings';

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
      'Waiting for help: Nobody has taken this on yet.\nSomeone is helping: Someone is working on helping.\nResolved: The animal has received help or the situation is resolved.\n\nStatus is about how far along the response is. It is separate from urgency, which is what the pin colour shows.';

  @override
  String get faqWhatUrgencyMeans => 'What do the pin colours mean?';

  @override
  String get faqWhatUrgencyMeansAnswer =>
      'Pin colour shows urgency — how serious things are if nobody acts:\n\nLow (green pin): The animal is not in immediate danger, or the situation is being managed.\nMedium (amber pin): Help is needed quickly, but it is not life-or-death within hours.\nCritical (red pin): The animal may die, disappear or be seriously harmed if help does not happen now.\n\nOnly the person who created a signal can change its urgency. Please keep Critical for genuine emergencies — if it is overused it stops meaning anything and help gets pulled away from animals truly at risk.';

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
      '1. Open the email in your inbox (or SPAM)\n2. Click the verification link\n3. Return to this app\n4. You\'ll be automatically redirected';

  @override
  String get checkingVerificationStatus => 'Checking verification status...';

  @override
  String get verificationEmailSentCheck =>
      'Verification email sent! Check your inbox (or SPAM).';

  @override
  String get tooManyRequests =>
      'Too many requests. Please try again later or contact support.';

  @override
  String get accountDisabled =>
      'This account has been disabled. Please contact support.';

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
  String get notificationNewSignalTitle => 'New signal nearby';

  @override
  String get notificationNewRedAlertTitle => 'Red Alert nearby';

  @override
  String notificationNewSignalBody(String headline, String signalTitle) {
    return '$headline — $signalTitle';
  }

  @override
  String notificationNewSignalBodyUrgent(String headline, String signalTitle) {
    return 'Urgent · $headline — $signalTitle';
  }

  @override
  String get notificationStatusChangeTitle => 'Signal status updated';

  @override
  String notificationStatusChangeBody(String signalTitle, String status) {
    return '$signalTitle: $status';
  }

  @override
  String get notificationUrgencyChangeTitle => 'Signal urgency raised';

  @override
  String get notificationRedAlertTitle => 'Escalated to Red Alert';

  @override
  String notificationUrgencyChangeBody(String signalTitle, String urgency) {
    return '$signalTitle: $urgency';
  }

  @override
  String notificationNewCommentTitle(String signalTitle) {
    return 'New comment on: $signalTitle';
  }

  @override
  String notificationMentionTitle(String name, String signalTitle) {
    return '$name mentioned you on: $signalTitle';
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
  String get errorSavingProfile =>
      'Could not save your profile. Please try again.';

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
  String get signalUpdatedSuccessfully => 'Signal updated successfully';

  @override
  String get signalNoLongerAvailable => 'This signal is no longer available';

  @override
  String get signalNoLongerAvailableHint =>
      'It may have been deleted by the person who reported it.';

  @override
  String get backToMap => 'Back to map';

  @override
  String get failedToUpdateSignal =>
      'Failed to update signal. Please try again.';

  @override
  String get removeSignal => 'Remove signal';

  @override
  String get removeSignalOpenTitle => 'Is this signal resolved?';

  @override
  String get removeSignalOpenBody =>
      'If the animal has been helped, mark the signal Resolved instead. Your report and its history stay on the map for others to learn from, and it still counts towards your profile.';

  @override
  String get markAsResolved => 'Mark as resolved';

  @override
  String get removeAnyway => 'Remove anyway';

  @override
  String confirmRemoveSignal(int days) {
    return 'This signal will be taken off the map. You can restore it from My Signals for the next $days days, after which it is deleted permanently.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get signalRemovedSuccessfully => 'Signal removed';

  @override
  String get failedToRemoveSignal =>
      'Failed to remove signal. Please try again.';

  @override
  String get signalUnderReview =>
      'This signal is being reviewed and cannot be removed right now.';

  @override
  String get activeSignals => 'Active';

  @override
  String get removedSignals => 'Removed';

  @override
  String get noRemovedSignals =>
      'Nothing here. Signals you remove can be restored from this list.';

  @override
  String get restoreSignalAction => 'Restore';

  @override
  String get signalRestored => 'Signal restored';

  @override
  String get failedToRestoreSignal =>
      'Failed to restore signal. Please try again.';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get confirmDeletePermanently =>
      'Delete this signal and its photos, comments and history for good? This cannot be undone.';

  @override
  String get signalDeletedPermanently => 'Signal deleted permanently';

  @override
  String restorableUntil(String date) {
    return 'Deleted permanently on $date';
  }

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

  @override
  String get signalNearbyNotificationTitle => 'An animal needs help nearby';

  @override
  String get locationAlwaysPermissionRequired =>
      'To be notified while the app is closed, allow location access \"Always\" in Settings. With \"While Using the App\" we can only check when the app is open.';

  @override
  String get reportSignal => 'Report this signal';

  @override
  String get commentOptions => 'Comment options';

  @override
  String get reportComment => 'Report this comment';

  @override
  String get reportTitle => 'Report';

  @override
  String get reportReasonPrompt => 'What is wrong with this?';

  @override
  String get reportDetailsLabel => 'Anything else we should know? (optional)';

  @override
  String get reportSubmit => 'Send report';

  @override
  String get reportSubmitted => 'Thank you. A moderator will review this.';

  @override
  String get reportAlreadySubmitted => 'You have already reported this.';

  @override
  String get reportFailed => 'Could not send the report. Please try again.';

  @override
  String get reportSignInRequired => 'Please sign in to report content.';

  @override
  String get reportReasonFraud => 'Fraud or scam';

  @override
  String get reportReasonAbuse => 'Animal abuse or neglect';

  @override
  String get reportReasonHarassment => 'Harassment';

  @override
  String get reportReasonFalseInformation => 'False information';

  @override
  String get reportReasonDangerousAdvice => 'Dangerous advice';

  @override
  String get reportReasonAnimalEndangerment => 'Puts an animal in danger';

  @override
  String get reportReasonGraphicContent => 'Graphic or distressing content';

  @override
  String get reportReasonSpam => 'Spam';

  @override
  String get reportReasonDoxxing => 'Shares private details';

  @override
  String get reportReasonDefamationRisk => 'Public accusation about a person';

  @override
  String get reportReasonDuplicateSignal => 'Duplicate of another signal';

  @override
  String get reportReasonOther => 'Something else';

  @override
  String get moderation => 'Moderation';

  @override
  String get moderationQueue => 'Reports';

  @override
  String get moderationQueueEmpty => 'No open reports.';

  @override
  String get moderationNotAModerator => 'You do not have moderator access.';

  @override
  String moderationReportedBy(int count) {
    return 'Reported $count times';
  }

  @override
  String get moderationOpenTarget => 'Open';

  @override
  String get moderationNoteLabel => 'Why are you doing this? (required)';

  @override
  String get moderationNoteRequired => 'A note is required.';

  @override
  String get moderationActionApplied => 'Done.';

  @override
  String get moderationActionFailed => 'That did not work. Please try again.';

  @override
  String get moderationPermissionDenied =>
      'You no longer have moderator access.';

  @override
  String get moderationSelfBlocked => 'You cannot moderate your own content.';

  @override
  String get moderationActionsLabel => 'Moderation actions';

  @override
  String get moderationCommentChooserTitle => 'This comment';

  @override
  String get moderationHideSignal => 'Hide signal';

  @override
  String get moderationRestoreSignal => 'Restore signal';

  @override
  String get moderationLockComments => 'Lock comments';

  @override
  String get moderationUnlockComments => 'Unlock comments';

  @override
  String get moderationSetUrgency => 'Correct urgency';

  @override
  String get moderationDeleteComment => 'Delete comment';

  @override
  String get moderationSetLabel => 'Add warning label';

  @override
  String get moderationClearLabel => 'Remove warning label';

  @override
  String get moderationDismissReport => 'Dismiss report';

  @override
  String get moderationAddNote => 'Add internal note';

  @override
  String get moderationLabelUnverified => 'Unverified';

  @override
  String get moderationLabelDuplicate => 'Possible duplicate';

  @override
  String get moderationLabelDisputed => 'Disputed';

  @override
  String get moderationCommentsLocked =>
      'A moderator has locked comments on this signal.';

  @override
  String get moderationBadge => 'Moderator';

  @override
  String get moderationTabReports => 'Reports';

  @override
  String get moderationTabHidden => 'Hidden';

  @override
  String get moderationHiddenEmpty => 'No hidden signals.';

  @override
  String moderationHiddenBy(String name) {
    return 'Hidden by $name';
  }

  @override
  String get moderationRestoreTitle => 'Restore this signal?';

  @override
  String get moderationRestoreBody =>
      'It goes back on the map for everyone. Its comments and history are still there.';

  @override
  String get moderationRestore => 'Restore';

  @override
  String clusterSignalsHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count signals here',
      one: '1 signal here',
    );
    return '$_temp0';
  }

  @override
  String clusterClinicsHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vet clinics here',
      one: '1 vet clinic here',
    );
    return '$_temp0';
  }

  @override
  String get mapLegend => 'What the pins mean';

  @override
  String get mapLegendUrgencyNote =>
      'Pin colour shows urgency — how serious it gets if nobody acts. Signals close together are grouped into a bubble, which takes the colour of the most urgent one inside it. Tap a bubble to zoom in, or to list what is in it when they are too close to separate.';

  @override
  String get mapLegendCluster => 'Several signals; the number is how many';

  @override
  String get mapLegendClinicCluster =>
      'Several vet clinics; the number is how many';

  @override
  String get mapLegendVetClinic => 'Vet clinic';

  @override
  String get done => 'Done';

  @override
  String get signOutFailed => 'Could not sign out. Please try again.';

  @override
  String couldNotOpenEmail(String address) {
    return 'No email app is set up on this device. Write to $address from anywhere.';
  }

  @override
  String get feedbackEmailSubject => 'Help a Paw — feedback';

  @override
  String get couldNotLoadSignals => 'Couldn\'t load your signals';

  @override
  String get couldNotLoadSignalsHint => 'Check your connection and try again.';

  @override
  String get couldNotLoadNotifications => 'Couldn\'t load your notifications';

  @override
  String get couldNotLoadPrivacyPolicy => 'Couldn\'t load the privacy policy';

  @override
  String get couldNotLoadPrivacyPolicyHint =>
      'Check your connection and try again, or read it at helpapaw.org/privacypolicy.';

  @override
  String get notificationDeleted => 'Notification deleted';

  @override
  String get undo => 'Undo';

  @override
  String get discardChanges => 'Discard changes?';

  @override
  String get discardChangesHint => 'Your edits to this profile will be lost.';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get close => 'Close';

  @override
  String get editProfile => 'Edit profile';

  @override
  String get changeProfilePhoto => 'Change profile photo';

  @override
  String get locationPermissionDeniedForever =>
      'Location permission is blocked for this app. Allow it in Settings to use this feature.';

  @override
  String get locationServicesDisabled =>
      'Location is turned off on this device. Turn it on to use this feature.';

  @override
  String get notificationPermissionRequired =>
      'Notifications are turned off for this app. Allow them in Settings to hear about nearby signals.';
}

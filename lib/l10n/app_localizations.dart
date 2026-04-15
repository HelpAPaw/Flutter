import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bg.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bg'),
    Locale('en')
  ];

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @statusHelpNeeded.
  ///
  /// In en, this message translates to:
  /// **'Help needed'**
  String get statusHelpNeeded;

  /// No description provided for @statusSomebodyOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'Somebody on the way'**
  String get statusSomebodyOnTheWay;

  /// No description provided for @statusSolved.
  ///
  /// In en, this message translates to:
  /// **'Solved'**
  String get statusSolved;

  /// No description provided for @statusNeedsHelp.
  ///
  /// In en, this message translates to:
  /// **'Needs Help'**
  String get statusNeedsHelp;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get statusInProgress;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @statusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get statusUnknown;

  /// No description provided for @signalTypeEmergency.
  ///
  /// In en, this message translates to:
  /// **'Emergency'**
  String get signalTypeEmergency;

  /// No description provided for @signalTypeLostOrFound.
  ///
  /// In en, this message translates to:
  /// **'Lost or Found'**
  String get signalTypeLostOrFound;

  /// No description provided for @signalTypeBloodDonation.
  ///
  /// In en, this message translates to:
  /// **'Blood donation'**
  String get signalTypeBloodDonation;

  /// No description provided for @signalTypeHomeless.
  ///
  /// In en, this message translates to:
  /// **'Homeless'**
  String get signalTypeHomeless;

  /// No description provided for @signalTypeUnneuteredAnimals.
  ///
  /// In en, this message translates to:
  /// **'Unneutered animals'**
  String get signalTypeUnneuteredAnimals;

  /// No description provided for @signalTypeWildAnimals.
  ///
  /// In en, this message translates to:
  /// **'Wild animals'**
  String get signalTypeWildAnimals;

  /// No description provided for @signalTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get signalTypeOther;

  /// No description provided for @filterSignals.
  ///
  /// In en, this message translates to:
  /// **'Filter Signals'**
  String get filterSignals;

  /// No description provided for @toggleVetClinics.
  ///
  /// In en, this message translates to:
  /// **'Toggle veterinary clinics'**
  String get toggleVetClinics;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @signalType.
  ///
  /// In en, this message translates to:
  /// **'Signal Type'**
  String get signalType;

  /// No description provided for @timeRange.
  ///
  /// In en, this message translates to:
  /// **'Time Range'**
  String get timeRange;

  /// No description provided for @last24Hours.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get last24Hours;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @last30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get applyFilters;

  /// No description provided for @searchThisArea.
  ///
  /// In en, this message translates to:
  /// **'Search this area'**
  String get searchThisArea;

  /// No description provided for @loadingClinics.
  ///
  /// In en, this message translates to:
  /// **'Loading clinics...'**
  String get loadingClinics;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @submitSignal.
  ///
  /// In en, this message translates to:
  /// **'Submit signal'**
  String get submitSignal;

  /// No description provided for @addNewSignal.
  ///
  /// In en, this message translates to:
  /// **'Add new signal'**
  String get addNewSignal;

  /// No description provided for @pleaseEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title for the signal'**
  String get pleaseEnterTitle;

  /// No description provided for @pleaseEnterDescription.
  ///
  /// In en, this message translates to:
  /// **'Please enter a description for the signal'**
  String get pleaseEnterDescription;

  /// No description provided for @signalCreatedPhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'Signal created, but photo upload failed. You can try again later.'**
  String get signalCreatedPhotoFailed;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied. Please check your account permissions.'**
  String get permissionDenied;

  /// No description provided for @authenticationError.
  ///
  /// In en, this message translates to:
  /// **'Authentication error. Please sign in again.'**
  String get authenticationError;

  /// No description provided for @serviceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Service unavailable. Please try again later.'**
  String get serviceUnavailable;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your connection.'**
  String get networkError;

  /// No description provided for @failedToCreateSignal.
  ///
  /// In en, this message translates to:
  /// **'Failed to create signal. Please try again.'**
  String get failedToCreateSignal;

  /// No description provided for @requestTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Request timed out. Please check your connection and try again.'**
  String get requestTimedOut;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get unexpectedError;

  /// No description provided for @noVetClinicsFound.
  ///
  /// In en, this message translates to:
  /// **'No veterinary clinics found in this area'**
  String get noVetClinicsFound;

  /// No description provided for @failedToLoadVetClinics.
  ///
  /// In en, this message translates to:
  /// **'Failed to load vet clinics'**
  String get failedToLoadVetClinics;

  /// No description provided for @tooManySearches.
  ///
  /// In en, this message translates to:
  /// **'Too many searches. Please wait a moment and try again.'**
  String get tooManySearches;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get chooseFromGallery;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @errorAccessingCamera.
  ///
  /// In en, this message translates to:
  /// **'Error accessing camera: {error}'**
  String errorAccessingCamera(String error);

  /// No description provided for @errorAccessingGallery.
  ///
  /// In en, this message translates to:
  /// **'Error accessing gallery: {error}'**
  String errorAccessingGallery(String error);

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to report and help animals in need'**
  String get signInSubtitle;

  /// No description provided for @signInSideMessage.
  ///
  /// In en, this message translates to:
  /// **'Join our community of animal lovers'**
  String get signInSideMessage;

  /// No description provided for @signInRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in required'**
  String get signInRequired;

  /// No description provided for @signInToCreateSignals.
  ///
  /// In en, this message translates to:
  /// **'You need to sign in to create signals'**
  String get signInToCreateSignals;

  /// No description provided for @signInToComment.
  ///
  /// In en, this message translates to:
  /// **'You need to sign in to comment'**
  String get signInToComment;

  /// No description provided for @signalDetails.
  ///
  /// In en, this message translates to:
  /// **'Signal Details'**
  String get signalDetails;

  /// No description provided for @uploadingPhoto.
  ///
  /// In en, this message translates to:
  /// **'Uploading photo...'**
  String get uploadingPhoto;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get addPhoto;

  /// No description provided for @addAnotherPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Another Photo'**
  String get addAnotherPhoto;

  /// No description provided for @photosCount.
  ///
  /// In en, this message translates to:
  /// **'{current}/{max} photos'**
  String photosCount(int current, int max);

  /// No description provided for @failedToLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image'**
  String get failedToLoadImage;

  /// No description provided for @signalTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Signal type: {type}'**
  String signalTypeLabel(String type);

  /// No description provided for @navigateMe.
  ///
  /// In en, this message translates to:
  /// **'Navigate Me'**
  String get navigateMe;

  /// No description provided for @cannotNavigate.
  ///
  /// In en, this message translates to:
  /// **'Cannot navigate to signal location, please try to do so manually.'**
  String get cannotNavigate;

  /// No description provided for @cannotCall.
  ///
  /// In en, this message translates to:
  /// **'Cannot call {phone}, please try to connect manually.'**
  String cannotCall(String phone);

  /// No description provided for @comments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get comments;

  /// No description provided for @enterYourComment.
  ///
  /// In en, this message translates to:
  /// **'Enter your comment'**
  String get enterYourComment;

  /// No description provided for @changedStatusTo.
  ///
  /// In en, this message translates to:
  /// **'{name} changed the status to {status}'**
  String changedStatusTo(String name, String status);

  /// No description provided for @someone.
  ///
  /// In en, this message translates to:
  /// **'Someone'**
  String get someone;

  /// No description provided for @deletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Delete photo'**
  String get deletePhoto;

  /// No description provided for @confirmDeletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this photo?'**
  String get confirmDeletePhoto;

  /// No description provided for @photoAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Photo added successfully!'**
  String get photoAddedSuccessfully;

  /// No description provided for @photoDeletedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Photo deleted successfully'**
  String get photoDeletedSuccessfully;

  /// No description provided for @failedToUploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload photo: {error}'**
  String failedToUploadPhoto(String error);

  /// No description provided for @failedToDeletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete photo: {error}'**
  String failedToDeletePhoto(String error);

  /// No description provided for @photoOf.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String photoOf(int current, int total);

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @pleaseSignInToViewProfile.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to view your profile'**
  String get pleaseSignInToViewProfile;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayName;

  /// No description provided for @noNameSet.
  ///
  /// In en, this message translates to:
  /// **'No name set'**
  String get noNameSet;

  /// No description provided for @signals.
  ///
  /// In en, this message translates to:
  /// **'Signals'**
  String get signals;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @emailVerified.
  ///
  /// In en, this message translates to:
  /// **'Email Verified'**
  String get emailVerified;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @verificationEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent'**
  String get verificationEmailSent;

  /// No description provided for @memberSince.
  ///
  /// In en, this message translates to:
  /// **'Member Since'**
  String get memberSince;

  /// No description provided for @profileUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdatedSuccessfully;

  /// No description provided for @errorUpdatingProfile.
  ///
  /// In en, this message translates to:
  /// **'Error updating profile: {error}'**
  String errorUpdatingProfile(String error);

  /// No description provided for @photoUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Photo updated successfully'**
  String get photoUpdatedSuccessfully;

  /// No description provided for @errorUploadingPhoto.
  ///
  /// In en, this message translates to:
  /// **'Error uploading photo: {error}'**
  String errorUploadingPhoto(String error);

  /// No description provided for @errorLoadingStatistics.
  ///
  /// In en, this message translates to:
  /// **'Error loading statistics: {error}'**
  String errorLoadingStatistics(String error);

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @sendFeedback.
  ///
  /// In en, this message translates to:
  /// **'Send Feedback'**
  String get sendFeedback;

  /// No description provided for @weLoveToHear.
  ///
  /// In en, this message translates to:
  /// **'We\'d love to hear from you!'**
  String get weLoveToHear;

  /// No description provided for @feedbackHelpsImprove.
  ///
  /// In en, this message translates to:
  /// **'Your feedback helps us improve Help a Paw for everyone.'**
  String get feedbackHelpsImprove;

  /// No description provided for @feedbackType.
  ///
  /// In en, this message translates to:
  /// **'Feedback Type'**
  String get feedbackType;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @bugReport.
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get bugReport;

  /// No description provided for @featureRequest.
  ///
  /// In en, this message translates to:
  /// **'Feature Request'**
  String get featureRequest;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @yourEmailOptional.
  ///
  /// In en, this message translates to:
  /// **'Your Email (optional)'**
  String get yourEmailOptional;

  /// No description provided for @emailPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'email@example.com'**
  String get emailPlaceholder;

  /// No description provided for @provideEmailForFollowUp.
  ///
  /// In en, this message translates to:
  /// **'Provide your email if you\'d like us to follow up'**
  String get provideEmailForFollowUp;

  /// No description provided for @yourFeedback.
  ///
  /// In en, this message translates to:
  /// **'Your Feedback'**
  String get yourFeedback;

  /// No description provided for @bugReportHint.
  ///
  /// In en, this message translates to:
  /// **'Please describe the issue you encountered...'**
  String get bugReportHint;

  /// No description provided for @featureRequestHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us about the feature you\'d like to see...'**
  String get featureRequestHint;

  /// No description provided for @generalFeedbackHint.
  ///
  /// In en, this message translates to:
  /// **'Share your thoughts with us...'**
  String get generalFeedbackHint;

  /// No description provided for @includeDeviceInfo.
  ///
  /// In en, this message translates to:
  /// **'Include device information'**
  String get includeDeviceInfo;

  /// No description provided for @helpsUsDiagnose.
  ///
  /// In en, this message translates to:
  /// **'Helps us diagnose issues faster'**
  String get helpsUsDiagnose;

  /// No description provided for @submitFeedback.
  ///
  /// In en, this message translates to:
  /// **'Submit Feedback'**
  String get submitFeedback;

  /// No description provided for @pleaseEnterFeedback.
  ///
  /// In en, this message translates to:
  /// **'Please enter your feedback'**
  String get pleaseEnterFeedback;

  /// No description provided for @thankYouFeedback.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your feedback!'**
  String get thankYouFeedback;

  /// No description provided for @errorSubmittingFeedback.
  ///
  /// In en, this message translates to:
  /// **'Error submitting feedback: {error}'**
  String errorSubmittingFeedback(String error);

  /// No description provided for @otherWaysToReach.
  ///
  /// In en, this message translates to:
  /// **'Other ways to reach us'**
  String get otherWaysToReach;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification Settings'**
  String get notificationSettings;

  /// No description provided for @createAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Create an account'**
  String get createAnAccount;

  /// No description provided for @signUpToKeepSettings.
  ///
  /// In en, this message translates to:
  /// **'Sign up to keep your settings across devices'**
  String get signUpToKeepSettings;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications'**
  String get enableNotifications;

  /// No description provided for @receiveNotificationsAboutSignals.
  ///
  /// In en, this message translates to:
  /// **'Receive notifications about signals near you'**
  String get receiveNotificationsAboutSignals;

  /// No description provided for @locationTracking.
  ///
  /// In en, this message translates to:
  /// **'Location Tracking'**
  String get locationTracking;

  /// No description provided for @trackMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Track My Location'**
  String get trackMyLocation;

  /// No description provided for @getNotifiedNearLocation.
  ///
  /// In en, this message translates to:
  /// **'Get notified when signals appear near your current location'**
  String get getNotifiedNearLocation;

  /// No description provided for @notificationRadiusKm.
  ///
  /// In en, this message translates to:
  /// **'Notification radius: {radius} km'**
  String notificationRadiusKm(String radius);

  /// No description provided for @regionOfInterest.
  ///
  /// In en, this message translates to:
  /// **'Region of Interest'**
  String get regionOfInterest;

  /// No description provided for @setRegionOnMap.
  ///
  /// In en, this message translates to:
  /// **'Set Region on Map'**
  String get setRegionOnMap;

  /// No description provided for @radiusKm.
  ///
  /// In en, this message translates to:
  /// **'Radius: {radius} km'**
  String radiusKm(String radius);

  /// No description provided for @tapToSelectArea.
  ///
  /// In en, this message translates to:
  /// **'Tap to select an area on the map'**
  String get tapToSelectArea;

  /// No description provided for @clearRegion.
  ///
  /// In en, this message translates to:
  /// **'Clear Region'**
  String get clearRegion;

  /// No description provided for @signalTypes.
  ///
  /// In en, this message translates to:
  /// **'Signal Types'**
  String get signalTypes;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @failedToSaveSettings.
  ///
  /// In en, this message translates to:
  /// **'Failed to save settings'**
  String get failedToSaveSettings;

  /// No description provided for @locationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required for this feature'**
  String get locationPermissionRequired;

  /// No description provided for @mySignals.
  ///
  /// In en, this message translates to:
  /// **'My Signals'**
  String get mySignals;

  /// No description provided for @pleaseSignInToViewSignals.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to view your signals'**
  String get pleaseSignInToViewSignals;

  /// No description provided for @noSignalsYet.
  ///
  /// In en, this message translates to:
  /// **'No signals yet'**
  String get noSignalsYet;

  /// No description provided for @submittedSignalsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Your submitted signals will appear here'**
  String get submittedSignalsAppearHere;

  /// No description provided for @unknownDate.
  ///
  /// In en, this message translates to:
  /// **'Unknown date'**
  String get unknownDate;

  /// No description provided for @errorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithMessage(String error);

  /// No description provided for @navigationDrawer.
  ///
  /// In en, this message translates to:
  /// **'Navigation Drawer'**
  String get navigationDrawer;

  /// No description provided for @ourSite.
  ///
  /// In en, this message translates to:
  /// **'Our Site'**
  String get ourSite;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @faqs.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get faqs;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @launchingBrowser.
  ///
  /// In en, this message translates to:
  /// **'Launching Browser'**
  String get launchingBrowser;

  /// No description provided for @snapshotError.
  ///
  /// In en, this message translates to:
  /// **'Snapshot Error: {error}'**
  String snapshotError(String error);

  /// No description provided for @faqsTitle.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get faqsTitle;

  /// No description provided for @faqSectionGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get faqSectionGeneral;

  /// No description provided for @faqSectionCreatingSignals.
  ///
  /// In en, this message translates to:
  /// **'Creating Signals'**
  String get faqSectionCreatingSignals;

  /// No description provided for @faqSectionHelpingAnimals.
  ///
  /// In en, this message translates to:
  /// **'Helping Animals'**
  String get faqSectionHelpingAnimals;

  /// No description provided for @faqSectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get faqSectionNotifications;

  /// No description provided for @faqSectionPrivacySafety.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Safety'**
  String get faqSectionPrivacySafety;

  /// No description provided for @faqWhatIsHelpAPaw.
  ///
  /// In en, this message translates to:
  /// **'What is Help a Paw?'**
  String get faqWhatIsHelpAPaw;

  /// No description provided for @faqWhatIsHelpAPawAnswer.
  ///
  /// In en, this message translates to:
  /// **'Help a Paw is a mobile application that helps connect people who spot animals in distress with volunteers who can provide assistance. By creating signals on the map, you can alert the community about animals that need help.'**
  String get faqWhatIsHelpAPawAnswer;

  /// No description provided for @faqNeedAccount.
  ///
  /// In en, this message translates to:
  /// **'Do I need to create an account?'**
  String get faqNeedAccount;

  /// No description provided for @faqNeedAccountAnswer.
  ///
  /// In en, this message translates to:
  /// **'You can browse signals without an account, but to create new signals or leave comments, you\'ll need to sign in. This helps us maintain the quality of reports and allows you to track your contributions.'**
  String get faqNeedAccountAnswer;

  /// No description provided for @faqIsFree.
  ///
  /// In en, this message translates to:
  /// **'Is the app free to use?'**
  String get faqIsFree;

  /// No description provided for @faqIsFreeAnswer.
  ///
  /// In en, this message translates to:
  /// **'Yes, Help a Paw is completely free to use. We are a non-profit initiative dedicated to helping animals in need.'**
  String get faqIsFreeAnswer;

  /// No description provided for @faqHowCreateSignal.
  ///
  /// In en, this message translates to:
  /// **'How do I create a signal?'**
  String get faqHowCreateSignal;

  /// No description provided for @faqHowCreateSignalAnswer.
  ///
  /// In en, this message translates to:
  /// **'Tap the \"+\" button on the map, select the location where you spotted the animal, choose the signal type (Emergency, Lost/Found, etc.), add a description, and optionally include photos. Your signal will be visible to other users in the area.'**
  String get faqHowCreateSignalAnswer;

  /// No description provided for @faqWhatTypesSignals.
  ///
  /// In en, this message translates to:
  /// **'What types of signals can I create?'**
  String get faqWhatTypesSignals;

  /// No description provided for @faqWhatTypesSignalsAnswer.
  ///
  /// In en, this message translates to:
  /// **'You can create signals for: Emergency situations, Lost or Found animals, Blood donation needs, Homeless animals, Unneutered animals, Wild animals, and Other situations.'**
  String get faqWhatTypesSignalsAnswer;

  /// No description provided for @faqCanEditDelete.
  ///
  /// In en, this message translates to:
  /// **'Can I edit or delete my signal?'**
  String get faqCanEditDelete;

  /// No description provided for @faqCanEditDeleteAnswer.
  ///
  /// In en, this message translates to:
  /// **'Yes, you can edit or delete signals that you\'ve created. Go to \"My Signals\" from the menu, select the signal you want to modify, and use the edit or delete options.'**
  String get faqCanEditDeleteAnswer;

  /// No description provided for @faqWhatIncludeDescription.
  ///
  /// In en, this message translates to:
  /// **'What should I include in a signal description?'**
  String get faqWhatIncludeDescription;

  /// No description provided for @faqWhatIncludeDescriptionAnswer.
  ///
  /// In en, this message translates to:
  /// **'Include details like: the type and condition of the animal, exact location landmarks, any urgent needs (food, medical attention), your availability to help, and a contact number if you\'re comfortable sharing it.'**
  String get faqWhatIncludeDescriptionAnswer;

  /// No description provided for @faqHowHelp.
  ///
  /// In en, this message translates to:
  /// **'How can I help with a signal?'**
  String get faqHowHelp;

  /// No description provided for @faqHowHelpAnswer.
  ///
  /// In en, this message translates to:
  /// **'When you see a signal on the map, tap it to view details. You can leave a comment to coordinate with others, update the signal status if you\'re helping, or contact the person who created the signal.'**
  String get faqHowHelpAnswer;

  /// No description provided for @faqWhatStatusesMean.
  ///
  /// In en, this message translates to:
  /// **'What do the signal statuses mean?'**
  String get faqWhatStatusesMean;

  /// No description provided for @faqWhatStatusesMeanAnswer.
  ///
  /// In en, this message translates to:
  /// **'Red (Needs Help): The animal still needs assistance.\nOrange (In Progress): Someone is working on helping.\nGreen (Resolved): The animal has received help or the situation is resolved.'**
  String get faqWhatStatusesMeanAnswer;

  /// No description provided for @faqCantHelpDirectly.
  ///
  /// In en, this message translates to:
  /// **'I\'m not able to help directly. What can I do?'**
  String get faqCantHelpDirectly;

  /// No description provided for @faqCantHelpDirectlyAnswer.
  ///
  /// In en, this message translates to:
  /// **'You can share the signal with friends who might be able to help, leave helpful comments with advice or contacts of local animal rescue organizations, or simply spread awareness about the app to grow our community of helpers.'**
  String get faqCantHelpDirectlyAnswer;

  /// No description provided for @faqHowNotificationsWork.
  ///
  /// In en, this message translates to:
  /// **'How do notifications work?'**
  String get faqHowNotificationsWork;

  /// No description provided for @faqHowNotificationsWorkAnswer.
  ///
  /// In en, this message translates to:
  /// **'You\'ll receive notifications when: a new signal appears in your area, someone comments on your signal, or the status of a signal you\'re following changes. You can customize notification settings in the app.'**
  String get faqHowNotificationsWorkAnswer;

  /// No description provided for @faqChangeNotificationRadius.
  ///
  /// In en, this message translates to:
  /// **'How do I change my notification radius?'**
  String get faqChangeNotificationRadius;

  /// No description provided for @faqChangeNotificationRadiusAnswer.
  ///
  /// In en, this message translates to:
  /// **'Go to Notification Settings > Location Tracking > Notification radius and adjust the slider. You can set it from 1km to 50km depending on how far you\'re willing to help.'**
  String get faqChangeNotificationRadiusAnswer;

  /// No description provided for @faqPersonalInfoSafe.
  ///
  /// In en, this message translates to:
  /// **'Is my personal information safe?'**
  String get faqPersonalInfoSafe;

  /// No description provided for @faqPersonalInfoSafeAnswer.
  ///
  /// In en, this message translates to:
  /// **'We take privacy seriously. Your email is only used for account management. Phone numbers shared in signals are optional and at your discretion. Location data is only used to show relevant signals.'**
  String get faqPersonalInfoSafeAnswer;

  /// No description provided for @faqReportInappropriate.
  ///
  /// In en, this message translates to:
  /// **'How do I report inappropriate content?'**
  String get faqReportInappropriate;

  /// No description provided for @faqReportInappropriateAnswer.
  ///
  /// In en, this message translates to:
  /// **'If you see a signal that contains inappropriate content, spam, or false information, please use the report function on the signal or contact us through the Feedback option in the menu.'**
  String get faqReportInappropriateAnswer;

  /// No description provided for @stayInformedTitle.
  ///
  /// In en, this message translates to:
  /// **'Stay Informed About Animals in Need'**
  String get stayInformedTitle;

  /// No description provided for @stayInformedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get notified when signals appear near you or in your area of interest.'**
  String get stayInformedSubtitle;

  /// No description provided for @maybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe Later'**
  String get maybeLater;

  /// No description provided for @enableLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Location Tracking'**
  String get enableLocationTitle;

  /// No description provided for @enableLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get alerts for animals in need within 10km of your location.'**
  String get enableLocationSubtitle;

  /// No description provided for @enableLocation.
  ///
  /// In en, this message translates to:
  /// **'Enable Location'**
  String get enableLocation;

  /// No description provided for @skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for Now'**
  String get skipForNow;

  /// No description provided for @chooseRegionTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Your Region of Interest'**
  String get chooseRegionTitle;

  /// No description provided for @chooseRegionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a specific area you care about and get notified of signals there.'**
  String get chooseRegionSubtitle;

  /// No description provided for @selectRegion.
  ///
  /// In en, this message translates to:
  /// **'Select Region'**
  String get selectRegion;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @helpAPaw.
  ///
  /// In en, this message translates to:
  /// **'Help a Paw'**
  String get helpAPaw;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String version(String version, String build);

  /// No description provided for @appDescription.
  ///
  /// In en, this message translates to:
  /// **'Send emergency signals about animals in need'**
  String get appDescription;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'Help a Paw is a platform that connects people who spot animals in distress with volunteers who can help. Together, we can make a difference in the lives of animals.'**
  String get aboutDescription;

  /// No description provided for @connectWithUs.
  ///
  /// In en, this message translates to:
  /// **'Connect with us'**
  String get connectWithUs;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @facebook.
  ///
  /// In en, this message translates to:
  /// **'Facebook'**
  String get facebook;

  /// No description provided for @gitHub.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get gitHub;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get openSourceLicenses;

  /// No description provided for @copyright.
  ///
  /// In en, this message translates to:
  /// **'© {year} Help a Paw'**
  String copyright(int year);

  /// No description provided for @verifyEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify Email'**
  String get verifyEmail;

  /// No description provided for @verifyYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify Your Email'**
  String get verifyYourEmail;

  /// No description provided for @verificationEmailSentTo.
  ///
  /// In en, this message translates to:
  /// **'We sent a verification email to:'**
  String get verificationEmailSentTo;

  /// No description provided for @instructions.
  ///
  /// In en, this message translates to:
  /// **'Instructions:'**
  String get instructions;

  /// No description provided for @instructionsSteps.
  ///
  /// In en, this message translates to:
  /// **'1. Open the email in your inbox\n2. Click the verification link\n3. Return to this app\n4. You\'ll be automatically redirected'**
  String get instructionsSteps;

  /// No description provided for @checkingVerificationStatus.
  ///
  /// In en, this message translates to:
  /// **'Checking verification status...'**
  String get checkingVerificationStatus;

  /// No description provided for @verificationEmailSentCheck.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent! Check your inbox.'**
  String get verificationEmailSentCheck;

  /// No description provided for @tooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later or contact support.'**
  String get tooManyRequests;

  /// No description provided for @accountDisabled.
  ///
  /// In en, this message translates to:
  /// **'This account has been disabled. Please contact support.'**
  String get accountDisabled;

  /// No description provided for @unexpectedErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error: {error}'**
  String unexpectedErrorWithMessage(String error);

  /// No description provided for @errorWithCode.
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String errorWithCode(String message);

  /// No description provided for @resendInSeconds.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resendInSeconds(int seconds);

  /// No description provided for @resendVerificationEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend Verification Email'**
  String get resendVerificationEmail;

  /// No description provided for @iveVerifiedMyEmail.
  ///
  /// In en, this message translates to:
  /// **'I\'ve verified my email'**
  String get iveVerifiedMyEmail;

  /// No description provided for @cancelAndSignOut.
  ///
  /// In en, this message translates to:
  /// **'Cancel and sign out'**
  String get cancelAndSignOut;

  /// No description provided for @skipDevOnly.
  ///
  /// In en, this message translates to:
  /// **'Skip (Dev Only)'**
  String get skipDevOnly;

  /// No description provided for @myNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get myNotifications;

  /// No description provided for @pleaseSignInToViewNotifications.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to view notifications'**
  String get pleaseSignInToViewNotifications;

  /// No description provided for @markAllAsRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllAsRead;

  /// No description provided for @clearAllNotifications.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAllNotifications;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @notifiedAboutSignalUpdates.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be notified about signal updates'**
  String get notifiedAboutSignalUpdates;

  /// No description provided for @notification.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get notification;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String minutesAgo(int minutes);

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String hoursAgo(int hours);

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String daysAgo(int days);

  /// No description provided for @completeYourProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete Your Profile'**
  String get completeYourProfile;

  /// No description provided for @helpUsPersonalize.
  ///
  /// In en, this message translates to:
  /// **'Help us personalize your experience'**
  String get helpUsPersonalize;

  /// No description provided for @fullNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Full Name *'**
  String get fullNameRequired;

  /// No description provided for @enterFullName.
  ///
  /// In en, this message translates to:
  /// **'Enter your full name'**
  String get enterFullName;

  /// No description provided for @nameIsRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameIsRequired;

  /// No description provided for @nameTooShort.
  ///
  /// In en, this message translates to:
  /// **'Name must be at least 2 characters'**
  String get nameTooShort;

  /// No description provided for @phoneNumberOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone Number (Optional)'**
  String get phoneNumberOptional;

  /// No description provided for @enterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get enterPhoneNumber;

  /// No description provided for @validPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid phone number'**
  String get validPhoneNumber;

  /// No description provided for @completeProfile.
  ///
  /// In en, this message translates to:
  /// **'Complete Profile'**
  String get completeProfile;

  /// No description provided for @skipForNowProfile.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get skipForNowProfile;

  /// No description provided for @errorSavingProfile.
  ///
  /// In en, this message translates to:
  /// **'Error saving profile: {error}'**
  String errorSavingProfile(String error);

  /// No description provided for @clinicDetails.
  ///
  /// In en, this message translates to:
  /// **'Clinic Details'**
  String get clinicDetails;

  /// No description provided for @clinicNotFound.
  ///
  /// In en, this message translates to:
  /// **'Clinic not found'**
  String get clinicNotFound;

  /// No description provided for @returnToMap.
  ///
  /// In en, this message translates to:
  /// **'Return to Map'**
  String get returnToMap;

  /// No description provided for @viewReviews.
  ///
  /// In en, this message translates to:
  /// **'View reviews'**
  String get viewReviews;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @navigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get navigate;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @openingHours.
  ///
  /// In en, this message translates to:
  /// **'Opening Hours'**
  String get openingHours;

  /// No description provided for @viewInGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'View in Google Maps'**
  String get viewInGoogleMaps;

  /// No description provided for @cannotOpenNavigationApp.
  ///
  /// In en, this message translates to:
  /// **'Cannot open navigation app'**
  String get cannotOpenNavigationApp;

  /// No description provided for @cannotMakePhoneCalls.
  ///
  /// In en, this message translates to:
  /// **'Cannot make phone calls on this device'**
  String get cannotMakePhoneCalls;

  /// No description provided for @cannotOpenGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Cannot open Google Maps'**
  String get cannotOpenGoogleMaps;

  /// No description provided for @selectRegionTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Region'**
  String get selectRegionTitle;

  /// No description provided for @tapToSetCenterPoint.
  ///
  /// In en, this message translates to:
  /// **'Please tap on the map to set a center point'**
  String get tapToSetCenterPoint;

  /// No description provided for @tapMapInstruction.
  ///
  /// In en, this message translates to:
  /// **'Tap on the map to set the center of your region of interest'**
  String get tapMapInstruction;

  /// No description provided for @regionRadius.
  ///
  /// In en, this message translates to:
  /// **'Region radius'**
  String get regionRadius;

  /// No description provided for @km.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get km;

  /// No description provided for @dragMarkerToReposition.
  ///
  /// In en, this message translates to:
  /// **'Drag the marker to reposition the center'**
  String get dragMarkerToReposition;

  /// No description provided for @shareSignal.
  ///
  /// In en, this message translates to:
  /// **'Share signal'**
  String get shareSignal;

  /// No description provided for @sendComment.
  ///
  /// In en, this message translates to:
  /// **'Send comment'**
  String get sendComment;

  /// No description provided for @closePhotoViewer.
  ///
  /// In en, this message translates to:
  /// **'Close photo viewer'**
  String get closePhotoViewer;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload photo'**
  String get uploadPhoto;

  /// No description provided for @couldNotOpenUrl.
  ///
  /// In en, this message translates to:
  /// **'Could not open {url}'**
  String couldNotOpenUrl(String url);

  /// No description provided for @completeNotificationSetup.
  ///
  /// In en, this message translates to:
  /// **'Complete notification setup'**
  String get completeNotificationSetup;

  /// No description provided for @errorAddingComment.
  ///
  /// In en, this message translates to:
  /// **'Failed to add comment. Please try again.'**
  String get errorAddingComment;

  /// No description provided for @errorUpdatingStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed to update status. Please try again.'**
  String get errorUpdatingStatus;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bg', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bg':
      return AppLocalizationsBg();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

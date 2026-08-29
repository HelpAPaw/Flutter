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

  /// No description provided for @statusNeedsHelp.
  ///
  /// In en, this message translates to:
  /// **'Waiting for help'**
  String get statusNeedsHelp;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'Someone is helping'**
  String get statusInProgress;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @urgency.
  ///
  /// In en, this message translates to:
  /// **'Urgency'**
  String get urgency;

  /// No description provided for @urgencyGreen.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get urgencyGreen;

  /// No description provided for @urgencyGreenDescription.
  ///
  /// In en, this message translates to:
  /// **'Not in immediate danger, or the situation is being managed.'**
  String get urgencyGreenDescription;

  /// No description provided for @urgencyAmber.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get urgencyAmber;

  /// No description provided for @urgencyAmberDescription.
  ///
  /// In en, this message translates to:
  /// **'Needs help quickly, but is not life-or-death within hours.'**
  String get urgencyAmberDescription;

  /// No description provided for @urgencyRed.
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get urgencyRed;

  /// No description provided for @urgencyRedDescription.
  ///
  /// In en, this message translates to:
  /// **'Serious harm, death or disappearance may follow if help does not happen now.'**
  String get urgencyRedDescription;

  /// No description provided for @pleaseSelectUrgency.
  ///
  /// In en, this message translates to:
  /// **'Please select how urgent this is'**
  String get pleaseSelectUrgency;

  /// No description provided for @errorUpdatingUrgency.
  ///
  /// In en, this message translates to:
  /// **'Failed to update urgency. Please try again.'**
  String get errorUpdatingUrgency;

  /// No description provided for @changedUrgencyTo.
  ///
  /// In en, this message translates to:
  /// **'{name} changed the urgency to {urgency}'**
  String changedUrgencyTo(String name, String urgency);

  /// No description provided for @redAlertConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Publish as a Red Alert?'**
  String get redAlertConfirmTitle;

  /// No description provided for @redAlertConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Red Alert is only for critical cases where the animal may die, disappear, be seriously harmed, or remain in immediate danger if help does not happen now.\n\nMisusing Red Alert reduces trust in the system and may affect your account.'**
  String get redAlertConfirmBody;

  /// No description provided for @redAlertConfirmCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I understand and confirm this is an immediate critical case'**
  String get redAlertConfirmCheckbox;

  /// No description provided for @redAlertConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Confirm Red Alert'**
  String get redAlertConfirmAction;

  /// No description provided for @helpTagRescue.
  ///
  /// In en, this message translates to:
  /// **'Rescue'**
  String get helpTagRescue;

  /// No description provided for @helpTagVetCare.
  ///
  /// In en, this message translates to:
  /// **'Vet care'**
  String get helpTagVetCare;

  /// No description provided for @helpTagBloodDonation.
  ///
  /// In en, this message translates to:
  /// **'Blood donation'**
  String get helpTagBloodDonation;

  /// No description provided for @helpTagFoster.
  ///
  /// In en, this message translates to:
  /// **'Fostering'**
  String get helpTagFoster;

  /// No description provided for @helpTagAdoption.
  ///
  /// In en, this message translates to:
  /// **'Adoption'**
  String get helpTagAdoption;

  /// No description provided for @helpTagTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get helpTagTransport;

  /// No description provided for @helpTagFood.
  ///
  /// In en, this message translates to:
  /// **'Food & supplies'**
  String get helpTagFood;

  /// No description provided for @helpTagTrapping.
  ///
  /// In en, this message translates to:
  /// **'Trapping'**
  String get helpTagTrapping;

  /// No description provided for @helpTagNeutering.
  ///
  /// In en, this message translates to:
  /// **'Neutering'**
  String get helpTagNeutering;

  /// No description provided for @helpTagBabyCare.
  ///
  /// In en, this message translates to:
  /// **'Newborn care'**
  String get helpTagBabyCare;

  /// No description provided for @helpTagFundraising.
  ///
  /// In en, this message translates to:
  /// **'Fundraising'**
  String get helpTagFundraising;

  /// No description provided for @helpTagLostFound.
  ///
  /// In en, this message translates to:
  /// **'Lost / found'**
  String get helpTagLostFound;

  /// No description provided for @helpTagDangerWarning.
  ///
  /// In en, this message translates to:
  /// **'Local danger'**
  String get helpTagDangerWarning;

  /// No description provided for @helpTagRescueHelper.
  ///
  /// In en, this message translates to:
  /// **'I can go to an animal in need'**
  String get helpTagRescueHelper;

  /// No description provided for @helpTagVetCareHelper.
  ///
  /// In en, this message translates to:
  /// **'I can help with a vet visit or treatment'**
  String get helpTagVetCareHelper;

  /// No description provided for @helpTagBloodDonationHelper.
  ///
  /// In en, this message translates to:
  /// **'My pet can donate blood, or I can help arrange a donor'**
  String get helpTagBloodDonationHelper;

  /// No description provided for @helpTagFosterHelper.
  ///
  /// In en, this message translates to:
  /// **'I can take an animal into my home for a while'**
  String get helpTagFosterHelper;

  /// No description provided for @helpTagAdoptionHelper.
  ///
  /// In en, this message translates to:
  /// **'I am looking to adopt, or can help find a home'**
  String get helpTagAdoptionHelper;

  /// No description provided for @helpTagTransportHelper.
  ///
  /// In en, this message translates to:
  /// **'I can drive an animal somewhere'**
  String get helpTagTransportHelper;

  /// No description provided for @helpTagFoodHelper.
  ///
  /// In en, this message translates to:
  /// **'I can bring food or supplies'**
  String get helpTagFoodHelper;

  /// No description provided for @helpTagTrappingHelper.
  ///
  /// In en, this message translates to:
  /// **'I can trap an animal, or I have a trap or cage'**
  String get helpTagTrappingHelper;

  /// No description provided for @helpTagNeuteringHelper.
  ///
  /// In en, this message translates to:
  /// **'I can help get animals neutered or spayed'**
  String get helpTagNeuteringHelper;

  /// No description provided for @helpTagBabyCareHelper.
  ///
  /// In en, this message translates to:
  /// **'I can bottle-feed or care for newborns'**
  String get helpTagBabyCareHelper;

  /// No description provided for @helpTagFundraisingHelper.
  ///
  /// In en, this message translates to:
  /// **'I can help raise or share funds'**
  String get helpTagFundraisingHelper;

  /// No description provided for @helpTagLostFoundHelper.
  ///
  /// In en, this message translates to:
  /// **'Tell me about lost and found pets near me — I will keep an eye out'**
  String get helpTagLostFoundHelper;

  /// No description provided for @helpTagDangerWarningHelper.
  ///
  /// In en, this message translates to:
  /// **'Tell me about hazards in my area, such as poison bait or traps'**
  String get helpTagDangerWarningHelper;

  /// No description provided for @helpTagRescueNeeded.
  ///
  /// In en, this message translates to:
  /// **'Rescue needed'**
  String get helpTagRescueNeeded;

  /// No description provided for @helpTagVetCareNeeded.
  ///
  /// In en, this message translates to:
  /// **'Vet care needed'**
  String get helpTagVetCareNeeded;

  /// No description provided for @helpTagBloodDonationNeeded.
  ///
  /// In en, this message translates to:
  /// **'Blood donation needed'**
  String get helpTagBloodDonationNeeded;

  /// No description provided for @helpTagFosterNeeded.
  ///
  /// In en, this message translates to:
  /// **'Foster needed'**
  String get helpTagFosterNeeded;

  /// No description provided for @helpTagAdoptionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Adoption needed'**
  String get helpTagAdoptionNeeded;

  /// No description provided for @helpTagTransportNeeded.
  ///
  /// In en, this message translates to:
  /// **'Transport needed'**
  String get helpTagTransportNeeded;

  /// No description provided for @helpTagFoodNeeded.
  ///
  /// In en, this message translates to:
  /// **'Food & supplies needed'**
  String get helpTagFoodNeeded;

  /// No description provided for @helpTagTrappingNeeded.
  ///
  /// In en, this message translates to:
  /// **'Trapping needed'**
  String get helpTagTrappingNeeded;

  /// No description provided for @helpTagNeuteringNeeded.
  ///
  /// In en, this message translates to:
  /// **'Neutering needed'**
  String get helpTagNeuteringNeeded;

  /// No description provided for @helpTagBabyCareNeeded.
  ///
  /// In en, this message translates to:
  /// **'Newborn care needed'**
  String get helpTagBabyCareNeeded;

  /// No description provided for @helpTagFundraisingNeeded.
  ///
  /// In en, this message translates to:
  /// **'Fundraising needed'**
  String get helpTagFundraisingNeeded;

  /// No description provided for @animalTypeCat.
  ///
  /// In en, this message translates to:
  /// **'Cat'**
  String get animalTypeCat;

  /// No description provided for @animalTypeDog.
  ///
  /// In en, this message translates to:
  /// **'Dog'**
  String get animalTypeDog;

  /// No description provided for @animalTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other animal'**
  String get animalTypeOther;

  /// No description provided for @helpNeeded.
  ///
  /// In en, this message translates to:
  /// **'Help needed'**
  String get helpNeeded;

  /// No description provided for @animalType.
  ///
  /// In en, this message translates to:
  /// **'Animal'**
  String get animalType;

  /// No description provided for @animalTypes.
  ///
  /// In en, this message translates to:
  /// **'Animals'**
  String get animalTypes;

  /// No description provided for @helperTags.
  ///
  /// In en, this message translates to:
  /// **'How I can help'**
  String get helperTags;

  /// No description provided for @pleaseSelectHelpTag.
  ///
  /// In en, this message translates to:
  /// **'Please choose at least one kind of help needed'**
  String get pleaseSelectHelpTag;

  /// No description provided for @pleaseSelectAnimalType.
  ///
  /// In en, this message translates to:
  /// **'Please choose which animal this is about'**
  String get pleaseSelectAnimalType;

  /// No description provided for @helpTagLimitReached.
  ///
  /// In en, this message translates to:
  /// **'You can choose up to {count} kinds of help'**
  String helpTagLimitReached(int count);

  /// No description provided for @helperTagsOnboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'How can you help?'**
  String get helperTagsOnboardingTitle;

  /// No description provided for @helperTagsOnboardingIntro.
  ///
  /// In en, this message translates to:
  /// **'Pick what you can realistically do, and which animals you can help. We use this to send you the signals you can actually act on — you can change it any time in settings.'**
  String get helperTagsOnboardingIntro;

  /// No description provided for @helperTagsOnboardingHelpSection.
  ///
  /// In en, this message translates to:
  /// **'What can you help with?'**
  String get helperTagsOnboardingHelpSection;

  /// No description provided for @helperTagsOnboardingAnimalSection.
  ///
  /// In en, this message translates to:
  /// **'Which animals can you help?'**
  String get helperTagsOnboardingAnimalSection;

  /// No description provided for @helperTagsOnboardingContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get helperTagsOnboardingContinue;

  /// No description provided for @helperTagsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save your choices. Please try again.'**
  String get helperTagsSaveFailed;

  /// No description provided for @settingsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Your settings could not be loaded. Check your connection and try again — nothing has been changed.'**
  String get settingsLoadFailed;

  /// No description provided for @selectAtLeastOneAnimalType.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one animal, or turn notifications off'**
  String get selectAtLeastOneAnimalType;

  /// No description provided for @selectAtLeastOneHelperTag.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one way you can help'**
  String get selectAtLeastOneHelperTag;

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

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

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

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @newSignalStepCounter.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String newSignalStepCounter(int current, int total);

  /// No description provided for @newSignalStepLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get newSignalStepLocation;

  /// No description provided for @newSignalStepPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get newSignalStepPhoto;

  /// No description provided for @newSignalStepDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get newSignalStepDetails;

  /// No description provided for @newSignalStepAnimal.
  ///
  /// In en, this message translates to:
  /// **'Animal'**
  String get newSignalStepAnimal;

  /// No description provided for @newSignalStepUrgency.
  ///
  /// In en, this message translates to:
  /// **'Urgency'**
  String get newSignalStepUrgency;

  /// No description provided for @newSignalStepHelp.
  ///
  /// In en, this message translates to:
  /// **'Help needed'**
  String get newSignalStepHelp;

  /// No description provided for @newSignalStepReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get newSignalStepReview;

  /// No description provided for @newSignalQuestionLocation.
  ///
  /// In en, this message translates to:
  /// **'Where is the animal?'**
  String get newSignalQuestionLocation;

  /// No description provided for @newSignalQuestionPhoto.
  ///
  /// In en, this message translates to:
  /// **'Can you add a photo?'**
  String get newSignalQuestionPhoto;

  /// No description provided for @newSignalQuestionDetails.
  ///
  /// In en, this message translates to:
  /// **'What is happening?'**
  String get newSignalQuestionDetails;

  /// No description provided for @newSignalQuestionAnimal.
  ///
  /// In en, this message translates to:
  /// **'What animal is it?'**
  String get newSignalQuestionAnimal;

  /// No description provided for @newSignalQuestionUrgency.
  ///
  /// In en, this message translates to:
  /// **'How urgent is it?'**
  String get newSignalQuestionUrgency;

  /// No description provided for @newSignalQuestionHelp.
  ///
  /// In en, this message translates to:
  /// **'What does it need?'**
  String get newSignalQuestionHelp;

  /// No description provided for @newSignalQuestionReview.
  ///
  /// In en, this message translates to:
  /// **'Ready to send?'**
  String get newSignalQuestionReview;

  /// No description provided for @newSignalHintLocation.
  ///
  /// In en, this message translates to:
  /// **'Move the map so the pin sits where the animal is.'**
  String get newSignalHintLocation;

  /// No description provided for @newSignalHintPhoto.
  ///
  /// In en, this message translates to:
  /// **'A photo helps volunteers recognise the animal. You can skip this.'**
  String get newSignalHintPhoto;

  /// No description provided for @newSignalHintDetails.
  ///
  /// In en, this message translates to:
  /// **'A short title and a few sentences are enough.'**
  String get newSignalHintDetails;

  /// No description provided for @newSignalHintUrgency.
  ///
  /// In en, this message translates to:
  /// **'A red alert notifies every volunteer nearby, so keep it for real emergencies.'**
  String get newSignalHintUrgency;

  /// No description provided for @newSignalHintReview.
  ///
  /// In en, this message translates to:
  /// **'Check everything, then send it.'**
  String get newSignalHintReview;

  /// No description provided for @newSignalHintHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose up to {count}, most important first.'**
  String newSignalHintHelp(int count);

  /// No description provided for @newSignalAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a photo'**
  String get newSignalAddPhoto;

  /// No description provided for @newSignalNoPhoto.
  ///
  /// In en, this message translates to:
  /// **'No photo'**
  String get newSignalNoPhoto;

  /// No description provided for @newSignalNotProvided.
  ///
  /// In en, this message translates to:
  /// **'Not provided'**
  String get newSignalNotProvided;

  /// No description provided for @newSignalPinPlaced.
  ///
  /// In en, this message translates to:
  /// **'Pin placed'**
  String get newSignalPinPlaced;

  /// No description provided for @newSignalDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this report?'**
  String get newSignalDiscardTitle;

  /// No description provided for @newSignalDiscardMessage.
  ///
  /// In en, this message translates to:
  /// **'Everything you have entered will be lost.'**
  String get newSignalDiscardMessage;

  /// No description provided for @newSignalDiscardConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get newSignalDiscardConfirm;

  /// No description provided for @newSignalDiscardKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get newSignalDiscardKeep;

  /// No description provided for @pleaseSelectLocation.
  ///
  /// In en, this message translates to:
  /// **'Please place the pin where the animal is'**
  String get pleaseSelectLocation;

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

  /// No description provided for @notAllowedError.
  ///
  /// In en, this message translates to:
  /// **'You are not allowed to do that. Signing in again may help.'**
  String get notAllowedError;

  /// No description provided for @serverBusyError.
  ///
  /// In en, this message translates to:
  /// **'The server is busy right now. Please try again in a moment.'**
  String get serverBusyError;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Help a Paw needs camera access. You can allow it in Settings.'**
  String get cameraPermissionDenied;

  /// No description provided for @photosPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Help a Paw needs access to your photos. You can allow it in Settings.'**
  String get photosPermissionDenied;

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
  /// **'Remove Photo'**
  String get removePhoto;

  /// No description provided for @errorAccessingCamera.
  ///
  /// In en, this message translates to:
  /// **'Could not open the camera. Please try again.'**
  String get errorAccessingCamera;

  /// No description provided for @errorAccessingGallery.
  ///
  /// In en, this message translates to:
  /// **'Could not open your photos. Please try again.'**
  String get errorAccessingGallery;

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

  /// No description provided for @signInWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Google'**
  String get signInWithGoogle;

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed. Please try again.'**
  String get googleSignInFailed;

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

  /// No description provided for @navigateMe.
  ///
  /// In en, this message translates to:
  /// **'Navigate Me'**
  String get navigateMe;

  /// No description provided for @chooseNavigationApp.
  ///
  /// In en, this message translates to:
  /// **'Choose Navigation App'**
  String get chooseNavigationApp;

  /// No description provided for @cannotNavigate.
  ///
  /// In en, this message translates to:
  /// **'No navigation apps found on this device.'**
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

  /// No description provided for @signalHistory.
  ///
  /// In en, this message translates to:
  /// **'Signal history'**
  String get signalHistory;

  /// No description provided for @historyPartiallyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Part of this history could not be loaded.'**
  String get historyPartiallyUnavailable;

  /// No description provided for @historyFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get historyFilterAll;

  /// No description provided for @historyFilterEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get historyFilterEvents;

  /// No description provided for @reportedThisSignal.
  ///
  /// In en, this message translates to:
  /// **'{name} reported this signal'**
  String reportedThisSignal(String name);

  /// No description provided for @updateNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'What changed?'**
  String get updateNoteTitle;

  /// No description provided for @nothingWasSaved.
  ///
  /// In en, this message translates to:
  /// **'Nothing was saved.'**
  String get nothingWasSaved;

  /// No description provided for @updateNoteChangingTo.
  ///
  /// In en, this message translates to:
  /// **'Changing to: {level}'**
  String updateNoteChangingTo(String level);

  /// No description provided for @updateNoteTakingSignal.
  ///
  /// In en, this message translates to:
  /// **'Taking responsibility for this signal'**
  String get updateNoteTakingSignal;

  /// No description provided for @updateNoteTakingSignalAndChangingTo.
  ///
  /// In en, this message translates to:
  /// **'Taking responsibility, and changing to: {level}'**
  String updateNoteTakingSignalAndChangingTo(String level);

  /// No description provided for @updateNoteSteppingDown.
  ///
  /// In en, this message translates to:
  /// **'Stepping down from this signal'**
  String get updateNoteSteppingDown;

  /// No description provided for @updateNoteHandingOver.
  ///
  /// In en, this message translates to:
  /// **'Handing this signal over'**
  String get updateNoteHandingOver;

  /// No description provided for @updateNoteDecliningOffer.
  ///
  /// In en, this message translates to:
  /// **'Declining this offer'**
  String get updateNoteDecliningOffer;

  /// No description provided for @updateNoteOfferingTakeover.
  ///
  /// In en, this message translates to:
  /// **'Offering to take this signal on'**
  String get updateNoteOfferingTakeover;

  /// No description provided for @updateNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a short note for the signal history'**
  String get updateNoteHint;

  /// No description provided for @updateNoteRequired.
  ///
  /// In en, this message translates to:
  /// **'Please say what changed — everyone following this signal sees it.'**
  String get updateNoteRequired;

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

  /// No description provided for @signalOwner.
  ///
  /// In en, this message translates to:
  /// **'Responsible'**
  String get signalOwner;

  /// No description provided for @signalOwnerNobody.
  ///
  /// In en, this message translates to:
  /// **'Nobody has taken this signal on yet'**
  String get signalOwnerNobody;

  /// No description provided for @signalOwnerIsYou.
  ///
  /// In en, this message translates to:
  /// **'You are responsible for this signal'**
  String get signalOwnerIsYou;

  /// No description provided for @signalOwnerTakeResponsibility.
  ///
  /// In en, this message translates to:
  /// **'Take responsibility'**
  String get signalOwnerTakeResponsibility;

  /// No description provided for @signalOwnerRequestTakeover.
  ///
  /// In en, this message translates to:
  /// **'Offer to take over'**
  String get signalOwnerRequestTakeover;

  /// No description provided for @signalOwnerRequestPending.
  ///
  /// In en, this message translates to:
  /// **'You have offered to take this over'**
  String get signalOwnerRequestPending;

  /// No description provided for @signalOwnerWithdrawRequest.
  ///
  /// In en, this message translates to:
  /// **'Withdraw offer'**
  String get signalOwnerWithdrawRequest;

  /// No description provided for @signalOwnerRelease.
  ///
  /// In en, this message translates to:
  /// **'I can no longer do this'**
  String get signalOwnerRelease;

  /// No description provided for @signalOwnerHandOver.
  ///
  /// In en, this message translates to:
  /// **'Hand over'**
  String get signalOwnerHandOver;

  /// No description provided for @signalOwnerDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get signalOwnerDecline;

  /// No description provided for @signalOwnerOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers to take over'**
  String get signalOwnerOffers;

  /// No description provided for @signalOwnerStale.
  ///
  /// In en, this message translates to:
  /// **'Nobody has updated this signal in a while.'**
  String get signalOwnerStale;

  /// No description provided for @takeoverConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Take responsibility for this signal?'**
  String get takeoverConfirmTitle;

  /// No description provided for @takeoverConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You become the person coordinating this signal. You can change its status and urgency, and hand it on or step down at any time.'**
  String get takeoverConfirmBody;

  /// No description provided for @takeoverConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Take it on'**
  String get takeoverConfirmAction;

  /// No description provided for @handOverConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Hand this signal over?'**
  String get handOverConfirmTitle;

  /// No description provided for @handOverConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They become the person coordinating this signal. You stay subscribed to it and can offer to take it back later.'**
  String get handOverConfirmBody;

  /// No description provided for @declineConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'They are told you are keeping the signal. They can offer again after a day.'**
  String get declineConfirmBody;

  /// No description provided for @releaseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Step down from this signal?'**
  String get releaseConfirmTitle;

  /// No description provided for @releaseConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The signal stays open and anyone can take it on. Everyone following it is told.'**
  String get releaseConfirmBody;

  /// No description provided for @takeoverNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Say what you plan to do'**
  String get takeoverNoteHint;

  /// No description provided for @takeoverAlreadyOwned.
  ///
  /// In en, this message translates to:
  /// **'Someone else is responsible for this signal. You can offer to take it over.'**
  String get takeoverAlreadyOwned;

  /// No description provided for @takeoverRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Your offer was sent to the person responsible.'**
  String get takeoverRequestSent;

  /// No description provided for @takeoverAlreadyAsked.
  ///
  /// In en, this message translates to:
  /// **'You have already offered to take this over.'**
  String get takeoverAlreadyAsked;

  /// No description provided for @takeoverAskAgainAfter.
  ///
  /// In en, this message translates to:
  /// **'You can offer again after {when}.'**
  String takeoverAskAgainAfter(String when);

  /// No description provided for @errorChangingSignalOwner.
  ///
  /// In en, this message translates to:
  /// **'Could not change who is responsible.'**
  String get errorChangingSignalOwner;

  /// No description provided for @tookResponsibility.
  ///
  /// In en, this message translates to:
  /// **'{name} took responsibility for this signal'**
  String tookResponsibility(String name);

  /// No description provided for @handedSignalTo.
  ///
  /// In en, this message translates to:
  /// **'{name} handed this signal to {other}'**
  String handedSignalTo(String name, String other);

  /// No description provided for @reportedThisSignalShort.
  ///
  /// In en, this message translates to:
  /// **'Reported this signal'**
  String get reportedThisSignalShort;

  /// No description provided for @statusSetTo.
  ///
  /// In en, this message translates to:
  /// **'Status set to {status}'**
  String statusSetTo(String status);

  /// No description provided for @urgencySetTo.
  ///
  /// In en, this message translates to:
  /// **'Urgency set to {urgency}'**
  String urgencySetTo(String urgency);

  /// No description provided for @releasedSignalShort.
  ///
  /// In en, this message translates to:
  /// **'Stepped down from this signal'**
  String get releasedSignalShort;

  /// No description provided for @tookResponsibilityShort.
  ///
  /// In en, this message translates to:
  /// **'Took responsibility for this signal'**
  String get tookResponsibilityShort;

  /// No description provided for @handedSignalToShort.
  ///
  /// In en, this message translates to:
  /// **'Handed this signal to {other}'**
  String handedSignalToShort(String other);

  /// No description provided for @releasedSignal.
  ///
  /// In en, this message translates to:
  /// **'{name} stepped down from this signal'**
  String releasedSignal(String name);

  /// No description provided for @notificationOwnershipChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Someone took responsibility'**
  String get notificationOwnershipChangeTitle;

  /// No description provided for @notificationOwnershipReleasedTitle.
  ///
  /// In en, this message translates to:
  /// **'This signal needs someone'**
  String get notificationOwnershipReleasedTitle;

  /// No description provided for @notificationOwnershipChangeBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is now responsible'**
  String notificationOwnershipChangeBody(String name);

  /// No description provided for @notificationOwnershipReleasedBody.
  ///
  /// In en, this message translates to:
  /// **'Nobody is responsible for this signal now'**
  String get notificationOwnershipReleasedBody;

  /// No description provided for @notificationTakeoverRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Someone offered to take over'**
  String get notificationTakeoverRequestTitle;

  /// No description provided for @notificationTakeoverRequestBody.
  ///
  /// In en, this message translates to:
  /// **'{name} asked to take responsibility'**
  String notificationTakeoverRequestBody(String name);

  /// No description provided for @notificationTakeoverApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'You are now responsible for a signal'**
  String get notificationTakeoverApprovedTitle;

  /// No description provided for @notificationTakeoverApprovedBody.
  ///
  /// In en, this message translates to:
  /// **'The signal is yours'**
  String get notificationTakeoverApprovedBody;

  /// No description provided for @notificationTakeoverDeclinedTitle.
  ///
  /// In en, this message translates to:
  /// **'Your offer was declined'**
  String get notificationTakeoverDeclinedTitle;

  /// No description provided for @notificationTakeoverDeclinedBody.
  ///
  /// In en, this message translates to:
  /// **'The current owner is keeping this signal'**
  String get notificationTakeoverDeclinedBody;

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
  /// **'Could not upload the photo. Please try again.'**
  String get failedToUploadPhoto;

  /// No description provided for @failedToDeletePhoto.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the photo. Please try again.'**
  String get failedToDeletePhoto;

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
  /// **'Could not save your profile. Please try again.'**
  String get errorUpdatingProfile;

  /// No description provided for @photoUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Photo updated successfully'**
  String get photoUpdatedSuccessfully;

  /// No description provided for @errorUploadingPhoto.
  ///
  /// In en, this message translates to:
  /// **'Could not upload your photo. Please try again.'**
  String get errorUploadingPhoto;

  /// No description provided for @errorLoadingStatistics.
  ///
  /// In en, this message translates to:
  /// **'Could not load your statistics.'**
  String get errorLoadingStatistics;

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

  /// No description provided for @pleaseEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get pleaseEnterValidEmail;

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
  /// **'Could not send your feedback. Please try again.'**
  String get errorSubmittingFeedback;

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

  /// No description provided for @locationBackgroundInactiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Only updating while the app is open'**
  String get locationBackgroundInactiveTitle;

  /// No description provided for @locationBackgroundInactiveBody.
  ///
  /// In en, this message translates to:
  /// **'Location access is not set to \"Allow all the time\", so we cannot check for nearby signals once you close the app.'**
  String get locationBackgroundInactiveBody;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

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
  /// **'Waiting for help: Nobody has taken this on yet.\nSomeone is helping: Someone is working on helping.\nResolved: The animal has received help or the situation is resolved.\n\nStatus is about how far along the response is. It is separate from urgency, which is what the pin colour shows.'**
  String get faqWhatStatusesMeanAnswer;

  /// No description provided for @faqWhatUrgencyMeans.
  ///
  /// In en, this message translates to:
  /// **'What do the pin colours mean?'**
  String get faqWhatUrgencyMeans;

  /// No description provided for @faqWhatUrgencyMeansAnswer.
  ///
  /// In en, this message translates to:
  /// **'Pin colour shows urgency — how serious things are if nobody acts:\n\nLow (green pin): The animal is not in immediate danger, or the situation is being managed.\nMedium (amber pin): Help is needed quickly, but it is not life-or-death within hours.\nCritical (red pin): The animal may die, disappear or be seriously harmed if help does not happen now.\n\nOnly the person who created a signal can change its urgency. Please keep Critical for genuine emergencies — if it is overused it stops meaning anything and help gets pulled away from animals truly at risk.'**
  String get faqWhatUrgencyMeansAnswer;

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
  /// **'1. Open the email in your inbox (or SPAM)\n2. Click the verification link\n3. Return to this app\n4. You\'ll be automatically redirected'**
  String get instructionsSteps;

  /// No description provided for @checkingVerificationStatus.
  ///
  /// In en, this message translates to:
  /// **'Checking verification status...'**
  String get checkingVerificationStatus;

  /// No description provided for @verificationEmailSentCheck.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent! Check your inbox (or SPAM).'**
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

  /// Inbox row title for a signal reported near the user. The stored push text is English-only, so the inbox row is rendered from these keys instead.
  ///
  /// In en, this message translates to:
  /// **'New signal nearby'**
  String get notificationNewSignalTitle;

  /// No description provided for @notificationNewRedAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Red Alert nearby'**
  String get notificationNewRedAlertTitle;

  /// No description provided for @notificationNewSignalBody.
  ///
  /// In en, this message translates to:
  /// **'{headline} — {signalTitle}'**
  String notificationNewSignalBody(String headline, String signalTitle);

  /// No description provided for @notificationNewSignalBodyUrgent.
  ///
  /// In en, this message translates to:
  /// **'Urgent · {headline} — {signalTitle}'**
  String notificationNewSignalBodyUrgent(String headline, String signalTitle);

  /// No description provided for @notificationStatusChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Signal status updated'**
  String get notificationStatusChangeTitle;

  /// No description provided for @notificationStatusChangeBody.
  ///
  /// In en, this message translates to:
  /// **'{signalTitle}: {status}'**
  String notificationStatusChangeBody(String signalTitle, String status);

  /// No description provided for @notificationUrgencyChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Signal urgency raised'**
  String get notificationUrgencyChangeTitle;

  /// No description provided for @notificationRedAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'Escalated to Red Alert'**
  String get notificationRedAlertTitle;

  /// No description provided for @notificationUrgencyChangeBody.
  ///
  /// In en, this message translates to:
  /// **'{signalTitle}: {urgency}'**
  String notificationUrgencyChangeBody(String signalTitle, String urgency);

  /// No description provided for @notificationNewCommentTitle.
  ///
  /// In en, this message translates to:
  /// **'New comment on: {signalTitle}'**
  String notificationNewCommentTitle(String signalTitle);

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
  /// **'Could not save your profile. Please try again.'**
  String get errorSavingProfile;

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

  /// No description provided for @editSignal.
  ///
  /// In en, this message translates to:
  /// **'Edit Signal'**
  String get editSignal;

  /// No description provided for @signalUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Signal updated successfully'**
  String get signalUpdatedSuccessfully;

  /// No description provided for @signalNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'This signal is no longer available'**
  String get signalNoLongerAvailable;

  /// No description provided for @signalNoLongerAvailableHint.
  ///
  /// In en, this message translates to:
  /// **'It may have been deleted by the person who reported it.'**
  String get signalNoLongerAvailableHint;

  /// No description provided for @backToMap.
  ///
  /// In en, this message translates to:
  /// **'Back to map'**
  String get backToMap;

  /// No description provided for @failedToUpdateSignal.
  ///
  /// In en, this message translates to:
  /// **'Failed to update signal. Please try again.'**
  String get failedToUpdateSignal;

  /// No description provided for @removeSignal.
  ///
  /// In en, this message translates to:
  /// **'Remove signal'**
  String get removeSignal;

  /// No description provided for @removeSignalOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Is this signal resolved?'**
  String get removeSignalOpenTitle;

  /// No description provided for @removeSignalOpenBody.
  ///
  /// In en, this message translates to:
  /// **'If the animal has been helped, mark the signal Resolved instead. Your report and its history stay on the map for others to learn from, and it still counts towards your profile.'**
  String get removeSignalOpenBody;

  /// No description provided for @markAsResolved.
  ///
  /// In en, this message translates to:
  /// **'Mark as resolved'**
  String get markAsResolved;

  /// No description provided for @removeAnyway.
  ///
  /// In en, this message translates to:
  /// **'Remove anyway'**
  String get removeAnyway;

  /// No description provided for @confirmRemoveSignal.
  ///
  /// In en, this message translates to:
  /// **'This signal will be taken off the map. You can restore it from My Signals for the next {days} days, after which it is deleted permanently.'**
  String confirmRemoveSignal(int days);

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @signalRemovedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Signal removed'**
  String get signalRemovedSuccessfully;

  /// No description provided for @failedToRemoveSignal.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove signal. Please try again.'**
  String get failedToRemoveSignal;

  /// No description provided for @signalUnderReview.
  ///
  /// In en, this message translates to:
  /// **'This signal is being reviewed and cannot be removed right now.'**
  String get signalUnderReview;

  /// No description provided for @activeSignals.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeSignals;

  /// No description provided for @removedSignals.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get removedSignals;

  /// No description provided for @noRemovedSignals.
  ///
  /// In en, this message translates to:
  /// **'Nothing here. Signals you remove can be restored from this list.'**
  String get noRemovedSignals;

  /// No description provided for @restoreSignalAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreSignalAction;

  /// No description provided for @signalRestored.
  ///
  /// In en, this message translates to:
  /// **'Signal restored'**
  String get signalRestored;

  /// No description provided for @failedToRestoreSignal.
  ///
  /// In en, this message translates to:
  /// **'Failed to restore signal. Please try again.'**
  String get failedToRestoreSignal;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @confirmDeletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete this signal and its photos, comments and history for good? This cannot be undone.'**
  String get confirmDeletePermanently;

  /// No description provided for @signalDeletedPermanently.
  ///
  /// In en, this message translates to:
  /// **'Signal deleted permanently'**
  String get signalDeletedPermanently;

  /// No description provided for @restorableUntil.
  ///
  /// In en, this message translates to:
  /// **'Deleted permanently on {date}'**
  String restorableUntil(String date);

  /// No description provided for @contactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact Phone'**
  String get contactPhone;

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

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteAccountConfirmTitle;

  /// No description provided for @deleteAccountConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes your account and personal data and cannot be undone. Your past reports will remain but will no longer be linked to you.'**
  String get deleteAccountConfirmBody;

  /// No description provided for @deleteAccountSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get deleteAccountSuccess;

  /// No description provided for @deleteAccountError.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account. Please try again.'**
  String get deleteAccountError;

  /// Title of the local notification shown when the user travels into range of an open signal they were not near when it was reported
  ///
  /// In en, this message translates to:
  /// **'An animal needs help nearby'**
  String get signalNearbyNotificationTitle;

  /// Shown when the user grants only while-in-use location permission but background monitoring needs always-on access
  ///
  /// In en, this message translates to:
  /// **'To be notified while the app is closed, allow location access \"Always\" in Settings. With \"While Using the App\" we can only check when the app is open.'**
  String get locationAlwaysPermissionRequired;

  /// No description provided for @reportSignal.
  ///
  /// In en, this message translates to:
  /// **'Report this signal'**
  String get reportSignal;

  /// No description provided for @reportComment.
  ///
  /// In en, this message translates to:
  /// **'Report this comment'**
  String get reportComment;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportTitle;

  /// No description provided for @reportReasonPrompt.
  ///
  /// In en, this message translates to:
  /// **'What is wrong with this?'**
  String get reportReasonPrompt;

  /// No description provided for @reportDetailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Anything else we should know? (optional)'**
  String get reportDetailsLabel;

  /// No description provided for @reportSubmit.
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get reportSubmit;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Thank you. A moderator will review this.'**
  String get reportSubmitted;

  /// No description provided for @reportAlreadySubmitted.
  ///
  /// In en, this message translates to:
  /// **'You have already reported this.'**
  String get reportAlreadySubmitted;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the report. Please try again.'**
  String get reportFailed;

  /// No description provided for @reportSignInRequired.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to report content.'**
  String get reportSignInRequired;

  /// No description provided for @reportReasonFraud.
  ///
  /// In en, this message translates to:
  /// **'Fraud or scam'**
  String get reportReasonFraud;

  /// No description provided for @reportReasonAbuse.
  ///
  /// In en, this message translates to:
  /// **'Animal abuse or neglect'**
  String get reportReasonAbuse;

  /// No description provided for @reportReasonHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment'**
  String get reportReasonHarassment;

  /// No description provided for @reportReasonFalseInformation.
  ///
  /// In en, this message translates to:
  /// **'False information'**
  String get reportReasonFalseInformation;

  /// No description provided for @reportReasonDangerousAdvice.
  ///
  /// In en, this message translates to:
  /// **'Dangerous advice'**
  String get reportReasonDangerousAdvice;

  /// No description provided for @reportReasonAnimalEndangerment.
  ///
  /// In en, this message translates to:
  /// **'Puts an animal in danger'**
  String get reportReasonAnimalEndangerment;

  /// No description provided for @reportReasonGraphicContent.
  ///
  /// In en, this message translates to:
  /// **'Graphic or distressing content'**
  String get reportReasonGraphicContent;

  /// No description provided for @reportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonDoxxing.
  ///
  /// In en, this message translates to:
  /// **'Shares private details'**
  String get reportReasonDoxxing;

  /// No description provided for @reportReasonDefamationRisk.
  ///
  /// In en, this message translates to:
  /// **'Public accusation about a person'**
  String get reportReasonDefamationRisk;

  /// No description provided for @reportReasonDuplicateSignal.
  ///
  /// In en, this message translates to:
  /// **'Duplicate of another signal'**
  String get reportReasonDuplicateSignal;

  /// No description provided for @reportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get reportReasonOther;

  /// No description provided for @moderation.
  ///
  /// In en, this message translates to:
  /// **'Moderation'**
  String get moderation;

  /// No description provided for @moderationQueue.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get moderationQueue;

  /// No description provided for @moderationQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'No open reports.'**
  String get moderationQueueEmpty;

  /// No description provided for @moderationNotAModerator.
  ///
  /// In en, this message translates to:
  /// **'You do not have moderator access.'**
  String get moderationNotAModerator;

  /// No description provided for @moderationReportedBy.
  ///
  /// In en, this message translates to:
  /// **'Reported {count} times'**
  String moderationReportedBy(int count);

  /// No description provided for @moderationOpenTarget.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get moderationOpenTarget;

  /// No description provided for @moderationNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Why are you doing this? (required)'**
  String get moderationNoteLabel;

  /// No description provided for @moderationNoteRequired.
  ///
  /// In en, this message translates to:
  /// **'A note is required.'**
  String get moderationNoteRequired;

  /// No description provided for @moderationActionApplied.
  ///
  /// In en, this message translates to:
  /// **'Done.'**
  String get moderationActionApplied;

  /// No description provided for @moderationActionFailed.
  ///
  /// In en, this message translates to:
  /// **'That did not work. Please try again.'**
  String get moderationActionFailed;

  /// No description provided for @moderationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You no longer have moderator access.'**
  String get moderationPermissionDenied;

  /// No description provided for @moderationSelfBlocked.
  ///
  /// In en, this message translates to:
  /// **'You cannot moderate your own content.'**
  String get moderationSelfBlocked;

  /// No description provided for @moderationActionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Moderation actions'**
  String get moderationActionsLabel;

  /// No description provided for @moderationCommentChooserTitle.
  ///
  /// In en, this message translates to:
  /// **'This comment'**
  String get moderationCommentChooserTitle;

  /// No description provided for @moderationHideSignal.
  ///
  /// In en, this message translates to:
  /// **'Hide signal'**
  String get moderationHideSignal;

  /// No description provided for @moderationRestoreSignal.
  ///
  /// In en, this message translates to:
  /// **'Restore signal'**
  String get moderationRestoreSignal;

  /// No description provided for @moderationLockComments.
  ///
  /// In en, this message translates to:
  /// **'Lock comments'**
  String get moderationLockComments;

  /// No description provided for @moderationUnlockComments.
  ///
  /// In en, this message translates to:
  /// **'Unlock comments'**
  String get moderationUnlockComments;

  /// No description provided for @moderationSetUrgency.
  ///
  /// In en, this message translates to:
  /// **'Correct urgency'**
  String get moderationSetUrgency;

  /// No description provided for @moderationDeleteComment.
  ///
  /// In en, this message translates to:
  /// **'Delete comment'**
  String get moderationDeleteComment;

  /// No description provided for @moderationSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Add warning label'**
  String get moderationSetLabel;

  /// No description provided for @moderationClearLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove warning label'**
  String get moderationClearLabel;

  /// No description provided for @moderationDismissReport.
  ///
  /// In en, this message translates to:
  /// **'Dismiss report'**
  String get moderationDismissReport;

  /// No description provided for @moderationAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add internal note'**
  String get moderationAddNote;

  /// No description provided for @moderationLabelUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get moderationLabelUnverified;

  /// No description provided for @moderationLabelDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Possible duplicate'**
  String get moderationLabelDuplicate;

  /// No description provided for @moderationLabelDisputed.
  ///
  /// In en, this message translates to:
  /// **'Disputed'**
  String get moderationLabelDisputed;

  /// No description provided for @moderationCommentsLocked.
  ///
  /// In en, this message translates to:
  /// **'A moderator has locked comments on this signal.'**
  String get moderationCommentsLocked;

  /// No description provided for @moderationBadge.
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get moderationBadge;

  /// No description provided for @moderationTabReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get moderationTabReports;

  /// No description provided for @moderationTabHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get moderationTabHidden;

  /// No description provided for @moderationHiddenEmpty.
  ///
  /// In en, this message translates to:
  /// **'No hidden signals.'**
  String get moderationHiddenEmpty;

  /// No description provided for @moderationHiddenBy.
  ///
  /// In en, this message translates to:
  /// **'Hidden by {name}'**
  String moderationHiddenBy(String name);

  /// No description provided for @moderationRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore this signal?'**
  String get moderationRestoreTitle;

  /// No description provided for @moderationRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'It goes back on the map for everyone. Its comments and history are still there.'**
  String get moderationRestoreBody;

  /// No description provided for @moderationRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get moderationRestore;

  /// No description provided for @mapLegend.
  ///
  /// In en, this message translates to:
  /// **'What the pins mean'**
  String get mapLegend;

  /// No description provided for @mapLegendUrgencyNote.
  ///
  /// In en, this message translates to:
  /// **'Pin colour shows urgency — how serious it gets if nobody acts. Critical signals are never grouped into a cluster, so they stay visible at every zoom.'**
  String get mapLegendUrgencyNote;

  /// No description provided for @mapLegendVetClinic.
  ///
  /// In en, this message translates to:
  /// **'Vet clinic'**
  String get mapLegendVetClinic;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @signOutFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sign out. Please try again.'**
  String get signOutFailed;

  /// No description provided for @couldNotOpenEmail.
  ///
  /// In en, this message translates to:
  /// **'No email app is set up on this device. Write to {address} from anywhere.'**
  String couldNotOpenEmail(String address);

  /// No description provided for @feedbackEmailSubject.
  ///
  /// In en, this message translates to:
  /// **'Help a Paw — feedback'**
  String get feedbackEmailSubject;

  /// No description provided for @couldNotLoadSignals.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your signals'**
  String get couldNotLoadSignals;

  /// No description provided for @couldNotLoadSignalsHint.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get couldNotLoadSignalsHint;

  /// No description provided for @couldNotLoadNotifications.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your notifications'**
  String get couldNotLoadNotifications;

  /// No description provided for @couldNotLoadPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the privacy policy'**
  String get couldNotLoadPrivacyPolicy;

  /// No description provided for @couldNotLoadPrivacyPolicyHint.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again, or read it at helpapaw.org/privacypolicy.'**
  String get couldNotLoadPrivacyPolicyHint;

  /// No description provided for @notificationDeleted.
  ///
  /// In en, this message translates to:
  /// **'Notification deleted'**
  String get notificationDeleted;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChanges;

  /// No description provided for @discardChangesHint.
  ///
  /// In en, this message translates to:
  /// **'Your edits to this profile will be lost.'**
  String get discardChangesHint;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @changeProfilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change profile photo'**
  String get changeProfilePhoto;
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

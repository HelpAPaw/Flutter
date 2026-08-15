// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bulgarian (`bg`).
class AppLocalizationsBg extends AppLocalizations {
  AppLocalizationsBg([String locale = 'bg']) : super(locale);

  @override
  String get signIn => 'Вход';

  @override
  String get signOut => 'Изход';

  @override
  String get signUp => 'Регистрация';

  @override
  String get cancel => 'Отказ';

  @override
  String get save => 'Запази';

  @override
  String get delete => 'Изтрий';

  @override
  String get retry => 'Опитай отново';

  @override
  String get confirm => 'Потвърди';

  @override
  String get yes => 'Да';

  @override
  String get no => 'Не';

  @override
  String get unknown => 'Неизвестно';

  @override
  String get error => 'Грешка';

  @override
  String get loading => 'Зареждане...';

  @override
  String get somethingWentWrong => 'Нещо се обърка';

  @override
  String get statusNeedsHelp => 'Нужна е помощ';

  @override
  String get statusInProgress => 'В процес';

  @override
  String get statusResolved => 'Решен';

  @override
  String get urgency => 'Спешност';

  @override
  String get urgencyGreen => 'Зелено — под контрол';

  @override
  String get urgencyGreenDescription =>
      'Животното не е в непосредствена опасност или ситуацията е овладяна.';

  @override
  String get urgencyAmber => 'Оранжево — нужна е помощ скоро';

  @override
  String get urgencyAmberDescription =>
      'Нужна е бърза помощ, но не е въпрос на живот и смърт в рамките на часове.';

  @override
  String get urgencyRed => 'Червено — незабавна критична помощ';

  @override
  String get urgencyRedDescription =>
      'Възможни са тежки наранявания, смърт или изчезване, ако помощта не дойде сега.';

  @override
  String get pleaseSelectUrgency => 'Моля, изберете колко спешен е случаят';

  @override
  String get errorUpdatingUrgency =>
      'Неуспешна промяна на спешността. Моля, опитайте отново.';

  @override
  String changedUrgencyTo(String name, String urgency) {
    return '$name промени спешността на $urgency';
  }

  @override
  String get redAlertConfirmTitle => 'Публикуване като червен сигнал?';

  @override
  String get redAlertConfirmBody =>
      'Червен сигнал се използва само за критични случаи, при които животното може да умре, да изчезне, да бъде сериозно наранено или да остане в непосредствена опасност, ако помощта не дойде сега.\n\nЗлоупотребата с червен сигнал намалява доверието в системата и може да се отрази на профила ви.';

  @override
  String get redAlertConfirmCheckbox =>
      'Разбирам и потвърждавам, че това е незабавен критичен случай';

  @override
  String get redAlertConfirmAction => 'Потвърди червен сигнал';

  @override
  String get signalTypeEmergency => 'Спешен случай';

  @override
  String get signalTypeLostOrFound => 'Изгубено или намерено';

  @override
  String get signalTypeBloodDonation => 'Кръводаряване';

  @override
  String get signalTypeHomeless => 'Бездомно';

  @override
  String get signalTypeUnneuteredAnimals => 'Некастрирани животни';

  @override
  String get signalTypeWildAnimals => 'Диви животни';

  @override
  String get signalTypeOther => 'Друго';

  @override
  String get helpTagRescue => 'Спасяване';

  @override
  String get helpTagFoster => 'Временен дом';

  @override
  String get helpTagTransport => 'Транспорт';

  @override
  String get helpTagVetCare => 'Ветеринарна помощ';

  @override
  String get helpTagFood => 'Храна и материали';

  @override
  String get helpTagTrapping => 'Улавяне';

  @override
  String get helpTagFundraising => 'Набиране на средства';

  @override
  String get helpTagAdoption => 'Осиновяване';

  @override
  String get helpTagBabyCare => 'Грижа за новородени';

  @override
  String get helpTagRescueHelper => 'Мога да отида при животно в нужда';

  @override
  String get helpTagFosterHelper => 'Мога да приютя животно за известно време';

  @override
  String get helpTagTransportHelper => 'Мога да превозя животно';

  @override
  String get helpTagVetCareHelper =>
      'Мога да помогна с ветеринарен преглед или лечение';

  @override
  String get helpTagFoodHelper => 'Мога да донеса храна или материали';

  @override
  String get helpTagTrappingHelper => 'Мога да уловя животно или имам клетка';

  @override
  String get helpTagFundraisingHelper =>
      'Мога да помогна със или да споделя набиране на средства';

  @override
  String get helpTagAdoptionHelper =>
      'Търся да осиновя или мога да помогна с намиране на дом';

  @override
  String get helpTagBabyCareHelper =>
      'Мога да храня с биберон или да се грижа за новородени';

  @override
  String get animalTypeCat => 'Котка';

  @override
  String get animalTypeDog => 'Куче';

  @override
  String get animalTypeOther => 'Друго животно';

  @override
  String get helpNeeded => 'Нужна помощ';

  @override
  String get animalType => 'Животно';

  @override
  String get animalTypes => 'Животни';

  @override
  String get helperTags => 'Как мога да помогна';

  @override
  String get pleaseSelectHelpTag => 'Моля, изберете поне един вид нужна помощ';

  @override
  String get pleaseSelectAnimalType =>
      'Моля, изберете за какво животно се отнася сигналът';

  @override
  String helpTagLimitReached(int count) {
    return 'Можете да изберете до $count вида помощ';
  }

  @override
  String get helperTagsOnboardingTitle => 'Как можете да помогнете?';

  @override
  String get helperTagsOnboardingIntro =>
      'Изберете какво реално можете да направите и на кои животни можете да помогнете. Използваме това, за да ви изпращаме случаите, по които наистина можете да действате — можете да го промените по всяко време в настройките.';

  @override
  String get helperTagsOnboardingHelpSection => 'С какво можете да помогнете?';

  @override
  String get helperTagsOnboardingAnimalSection =>
      'На кои животни можете да помогнете?';

  @override
  String get helperTagsOnboardingContinue => 'Продължи';

  @override
  String get helperTagsSaveFailed =>
      'Изборът не можа да бъде запазен. Моля, опитайте отново.';

  @override
  String get selectAtLeastOneSignalType =>
      'Изберете поне един вид сигнал или изключете известията';

  @override
  String get selectAtLeastOneAnimalType =>
      'Изберете поне едно животно или изключете известията';

  @override
  String get selectAtLeastOneHelperTag =>
      'Изберете поне един начин, по който можете да помогнете';

  @override
  String get filterSignals => 'Филтриране на сигнали';

  @override
  String get toggleVetClinics => 'Покажи/скрий ветеринарни клиники';

  @override
  String get selectAll => 'Избери всички';

  @override
  String get clearAll => 'Изчисти всички';

  @override
  String get status => 'Статус';

  @override
  String get signalType => 'Тип сигнал';

  @override
  String get timeRange => 'Времеви обхват';

  @override
  String get last24Hours => 'Последните 24 часа';

  @override
  String get last7Days => 'Последните 7 дни';

  @override
  String get last30Days => 'Последните 30 дни';

  @override
  String get allTime => 'Всички';

  @override
  String get applyFilters => 'Приложи филтри';

  @override
  String get searchThisArea => 'Търси в тази област';

  @override
  String get loadingClinics => 'Зареждане на клиники...';

  @override
  String get title => 'Заглавие';

  @override
  String get description => 'Описание';

  @override
  String get phoneNumber => 'Телефонен номер';

  @override
  String get submitSignal => 'Изпрати сигнал';

  @override
  String get addNewSignal => 'Добави нов сигнал';

  @override
  String get pleaseEnterTitle => 'Моля, въведете заглавие за сигнала';

  @override
  String get pleaseEnterDescription => 'Моля, въведете описание за сигнала';

  @override
  String get signalCreatedPhotoFailed =>
      'Сигналът е създаден, но качването на снимката се провали. Можете да опитате отново по-късно.';

  @override
  String get permissionDenied =>
      'Достъпът е отказан. Моля, проверете правата на акаунта си.';

  @override
  String get authenticationError =>
      'Грешка при удостоверяване. Моля, влезте отново.';

  @override
  String get serviceUnavailable =>
      'Услугата не е достъпна. Моля, опитайте по-късно.';

  @override
  String get networkError => 'Мрежова грешка. Моля, проверете връзката си.';

  @override
  String get failedToCreateSignal =>
      'Неуспешно създаване на сигнал. Моля, опитайте отново.';

  @override
  String get requestTimedOut =>
      'Времето за заявката изтече. Моля, проверете връзката си и опитайте отново.';

  @override
  String get unexpectedError =>
      'Възникна неочаквана грешка. Моля, опитайте отново.';

  @override
  String get noVetClinicsFound =>
      'Няма намерени ветеринарни клиники в тази област';

  @override
  String get failedToLoadVetClinics =>
      'Неуспешно зареждане на ветеринарни клиники';

  @override
  String get tooManySearches =>
      'Твърде много търсения. Моля, изчакайте и опитайте отново.';

  @override
  String get takePhoto => 'Направи снимка';

  @override
  String get chooseFromGallery => 'Избери от галерията';

  @override
  String get removePhoto => 'Премахни снимка';

  @override
  String errorAccessingCamera(String error) {
    return 'Грешка при достъп до камерата: $error';
  }

  @override
  String errorAccessingGallery(String error) {
    return 'Грешка при достъп до галерията: $error';
  }

  @override
  String get signInSubtitle =>
      'Влезте, за да докладвате и помагате на животни в нужда';

  @override
  String get signInSideMessage =>
      'Присъединете се към нашата общност от любители на животни';

  @override
  String get signInWithGoogle => 'Вход с Google';

  @override
  String get googleSignInFailed =>
      'Входът с Google не бе успешен. Моля, опитайте отново.';

  @override
  String get signInRequired => 'Необходим е вход';

  @override
  String get signInToCreateSignals =>
      'Трябва да влезете, за да създавате сигнали';

  @override
  String get signInToComment => 'Трябва да влезете, за да коментирате';

  @override
  String get signalDetails => 'Детайли за сигнала';

  @override
  String get uploadingPhoto => 'Качване на снимка...';

  @override
  String get addPhoto => 'Добави снимка';

  @override
  String get addAnotherPhoto => 'Добави още снимка';

  @override
  String photosCount(int current, int max) {
    return '$current/$max снимки';
  }

  @override
  String get failedToLoadImage => 'Неуспешно зареждане на изображение';

  @override
  String signalTypeLabel(String type) {
    return 'Тип сигнал: $type';
  }

  @override
  String get navigateMe => 'Навигирай ме';

  @override
  String get chooseNavigationApp => 'Изберете навигационно приложение';

  @override
  String get cannotNavigate =>
      'Не са намерени навигационни приложения на устройството.';

  @override
  String cannotCall(String phone) {
    return 'Не може да се обади на $phone, моля опитайте да се свържете ръчно.';
  }

  @override
  String get comments => 'Коментари';

  @override
  String get enterYourComment => 'Въведете коментар';

  @override
  String get caseHistory => 'История на случая';

  @override
  String get historyFilterAll => 'Всичко';

  @override
  String get historyFilterEvents => 'Събития';

  @override
  String reportedThisCase(String name) {
    return '$name подаде този сигнал';
  }

  @override
  String get updateNoteTitle => 'Какво се промени?';

  @override
  String updateNoteChangingTo(String level) {
    return 'Промяна на: $level';
  }

  @override
  String get updateNoteHint =>
      'Добавете кратка бележка към историята на случая';

  @override
  String get updateNoteRequired =>
      'Моля, опишете какво се промени — всички, които следят сигнала, ще го видят.';

  @override
  String changedStatusTo(String name, String status) {
    return '$name промени статуса на $status';
  }

  @override
  String get someone => 'Някой';

  @override
  String get deletePhoto => 'Изтрий снимка';

  @override
  String get confirmDeletePhoto =>
      'Сигурни ли сте, че искате да изтриете тази снимка?';

  @override
  String get photoAddedSuccessfully => 'Снимката е добавена успешно!';

  @override
  String get photoDeletedSuccessfully => 'Снимката е изтрита успешно';

  @override
  String failedToUploadPhoto(String error) {
    return 'Неуспешно качване на снимка: $error';
  }

  @override
  String failedToDeletePhoto(String error) {
    return 'Неуспешно изтриване на снимка: $error';
  }

  @override
  String photoOf(int current, int total) {
    return '$current от $total';
  }

  @override
  String get profile => 'Профил';

  @override
  String get pleaseSignInToViewProfile =>
      'Моля, влезте, за да видите профила си';

  @override
  String get displayName => 'Име за показване';

  @override
  String get noNameSet => 'Няма зададено име';

  @override
  String get signals => 'Сигнали';

  @override
  String get email => 'Имейл';

  @override
  String get notSet => 'Не е зададено';

  @override
  String get emailVerified => 'Имейл потвърден';

  @override
  String get verify => 'Потвърди';

  @override
  String get verificationEmailSent => 'Имейл за потвърждение е изпратен';

  @override
  String get memberSince => 'Член от';

  @override
  String get profileUpdatedSuccessfully => 'Профилът е обновен успешно';

  @override
  String errorUpdatingProfile(String error) {
    return 'Грешка при обновяване на профила: $error';
  }

  @override
  String get photoUpdatedSuccessfully => 'Снимката е обновена успешно';

  @override
  String errorUploadingPhoto(String error) {
    return 'Грешка при качване на снимка: $error';
  }

  @override
  String errorLoadingStatistics(String error) {
    return 'Грешка при зареждане на статистика: $error';
  }

  @override
  String get saveChanges => 'Запази промените';

  @override
  String get sendFeedback => 'Изпрати отзив';

  @override
  String get weLoveToHear => 'Ще се радваме да чуем от вас!';

  @override
  String get feedbackHelpsImprove =>
      'Вашият отзив ни помага да подобрим Помогни на лапа за всички.';

  @override
  String get feedbackType => 'Тип отзив';

  @override
  String get general => 'Общ';

  @override
  String get bugReport => 'Доклад за грешка';

  @override
  String get featureRequest => 'Заявка за функционалност';

  @override
  String get other => 'Друго';

  @override
  String get yourEmailOptional => 'Вашият имейл (по избор)';

  @override
  String get emailPlaceholder => 'email@example.com';

  @override
  String get provideEmailForFollowUp =>
      'Предоставете имейл, ако желаете да се свържем с вас';

  @override
  String get pleaseEnterValidEmail => 'Моля, въведете валиден имейл адрес';

  @override
  String get yourFeedback => 'Вашият отзив';

  @override
  String get bugReportHint => 'Моля, опишете проблема, който срещнахте...';

  @override
  String get featureRequestHint =>
      'Разкажете ни за функционалността, която бихте искали да видите...';

  @override
  String get generalFeedbackHint => 'Споделете мислите си с нас...';

  @override
  String get includeDeviceInfo => 'Включи информация за устройството';

  @override
  String get helpsUsDiagnose =>
      'Помага ни да диагностицираме проблеми по-бързо';

  @override
  String get submitFeedback => 'Изпрати отзив';

  @override
  String get pleaseEnterFeedback => 'Моля, въведете вашия отзив';

  @override
  String get thankYouFeedback => 'Благодарим ви за отзива!';

  @override
  String errorSubmittingFeedback(String error) {
    return 'Грешка при изпращане на отзив: $error';
  }

  @override
  String get otherWaysToReach => 'Други начини да се свържете с нас';

  @override
  String get notificationSettings => 'Настройки за известия';

  @override
  String get createAnAccount => 'Създайте акаунт';

  @override
  String get signUpToKeepSettings =>
      'Регистрирайте се, за да запазите настройките си между устройствата';

  @override
  String get notifications => 'Известия';

  @override
  String get enableNotifications => 'Включи известия';

  @override
  String get receiveNotificationsAboutSignals =>
      'Получавайте известия за сигнали близо до вас';

  @override
  String get locationTracking => 'Проследяване на местоположение';

  @override
  String get trackMyLocation => 'Проследявай местоположението ми';

  @override
  String get getNotifiedNearLocation =>
      'Получавайте известия, когато се появят сигнали близо до текущото ви местоположение';

  @override
  String notificationRadiusKm(String radius) {
    return 'Радиус за известия: $radius км';
  }

  @override
  String get regionOfInterest => 'Регион на интерес';

  @override
  String get setRegionOnMap => 'Задай регион на картата';

  @override
  String radiusKm(String radius) {
    return 'Радиус: $radius км';
  }

  @override
  String get tapToSelectArea => 'Докоснете, за да изберете област на картата';

  @override
  String get clearRegion => 'Изчисти региона';

  @override
  String get signalTypes => 'Типове сигнали';

  @override
  String get settingsSaved => 'Настройките са запазени';

  @override
  String get failedToSaveSettings => 'Неуспешно запазване на настройките';

  @override
  String get locationPermissionRequired =>
      'За тази функционалност е необходимо разрешение за местоположение';

  @override
  String get mySignals => 'Моите сигнали';

  @override
  String get pleaseSignInToViewSignals =>
      'Моля, влезте, за да видите сигналите си';

  @override
  String get noSignalsYet => 'Все още няма сигнали';

  @override
  String get submittedSignalsAppearHere =>
      'Подадените от вас сигнали ще се появят тук';

  @override
  String get unknownDate => 'Неизвестна дата';

  @override
  String errorWithMessage(String error) {
    return 'Грешка: $error';
  }

  @override
  String get navigationDrawer => 'Навигационно меню';

  @override
  String get ourSite => 'Нашият сайт';

  @override
  String get about => 'За нас';

  @override
  String get share => 'Сподели';

  @override
  String get faqs => 'Често задавани въпроси';

  @override
  String get feedback => 'Отзив';

  @override
  String get privacyPolicy => 'Политика за поверителност';

  @override
  String get launchingBrowser => 'Отваряне на браузър';

  @override
  String snapshotError(String error) {
    return 'Грешка в снимката: $error';
  }

  @override
  String get faqsTitle => 'Често задавани въпроси';

  @override
  String get faqSectionGeneral => 'Общи';

  @override
  String get faqSectionCreatingSignals => 'Създаване на сигнали';

  @override
  String get faqSectionHelpingAnimals => 'Помощ за животни';

  @override
  String get faqSectionNotifications => 'Известия';

  @override
  String get faqSectionPrivacySafety => 'Поверителност и безопасност';

  @override
  String get faqWhatIsHelpAPaw => 'Какво е Помогни на лапа?';

  @override
  String get faqWhatIsHelpAPawAnswer =>
      'Помогни на лапа е мобилно приложение, което помага да се свържат хора, забелязали животни в беда, с доброволци, които могат да помогнат. Като създавате сигнали на картата, можете да предупредите общността за животни, които се нуждаят от помощ.';

  @override
  String get faqNeedAccount => 'Трябва ли да създам акаунт?';

  @override
  String get faqNeedAccountAnswer =>
      'Можете да разглеждате сигнали без акаунт, но за да създавате нови сигнали или да оставяте коментари, ще трябва да влезете. Това ни помага да поддържаме качеството на докладите и ви позволява да проследявате приносите си.';

  @override
  String get faqIsFree => 'Приложението безплатно ли е?';

  @override
  String get faqIsFreeAnswer =>
      'Да, Помогни на лапа е напълно безплатно за използване. Ние сме нестопанска инициатива, посветена на помощта на животни в нужда.';

  @override
  String get faqHowCreateSignal => 'Как да създам сигнал?';

  @override
  String get faqHowCreateSignalAnswer =>
      'Докоснете бутона \"+\" на картата, изберете местоположението, където сте забелязали животното, изберете типа сигнал (Спешен случай, Изгубено/Намерено и др.), добавете описание и по желание включете снимки. Вашият сигнал ще бъде видим за други потребители в района.';

  @override
  String get faqWhatTypesSignals => 'Какви типове сигнали мога да създам?';

  @override
  String get faqWhatTypesSignalsAnswer =>
      'Можете да създавате сигнали за: Спешни случаи, Изгубени или намерени животни, Нужди от кръводаряване, Бездомни животни, Некастрирани животни, Диви животни и Други ситуации.';

  @override
  String get faqCanEditDelete => 'Мога ли да редактирам или изтрия сигнала си?';

  @override
  String get faqCanEditDeleteAnswer =>
      'Да, можете да редактирате или изтривате сигнали, които сте създали. Отидете на \"Моите сигнали\" от менюто, изберете сигнала, който искате да промените, и използвайте опциите за редактиране или изтриване.';

  @override
  String get faqWhatIncludeDescription =>
      'Какво да включа в описанието на сигнала?';

  @override
  String get faqWhatIncludeDescriptionAnswer =>
      'Включете детайли като: вида и състоянието на животното, точни ориентири за местоположението, спешни нужди (храна, медицинска помощ), вашата готовност да помогнете и телефонен номер, ако желаете да го споделите.';

  @override
  String get faqHowHelp => 'Как мога да помогна със сигнал?';

  @override
  String get faqHowHelpAnswer =>
      'Когато видите сигнал на картата, докоснете го, за да видите детайлите. Можете да оставите коментар, за да се координирате с другите, да обновите статуса на сигнала, ако помагате, или да се свържете с човека, създал сигнала.';

  @override
  String get faqWhatStatusesMean => 'Какво означават статусите на сигналите?';

  @override
  String get faqWhatStatusesMeanAnswer =>
      'Нужна е помощ: Все още никой не се е заел със сигнала.\nВ процес: Някой работи по проблема.\nРешен: Животното е получило помощ или ситуацията е разрешена.\n\nСтатусът показва докъде е стигнала реакцията. Той е отделен от спешността, която се вижда по цвета на маркера.';

  @override
  String get faqWhatUrgencyMeans => 'Какво означават цветовете на маркерите?';

  @override
  String get faqWhatUrgencyMeansAnswer =>
      'Цветът на маркера показва спешността — колко сериозно е положението, ако никой не реагира:\n\nЗелено (Под контрол): Животното не е в непосредствена опасност или ситуацията е овладяна.\nОранжево (Нужна е помощ скоро): Помощта е нужна бързо, но не е въпрос на живот и смърт в рамките на часове.\nЧервено (Незабавна критична помощ): Животното може да умре, да изчезне или да бъде сериозно наранено, ако помощта не дойде сега.\n\nСамо създателят на сигнала може да променя спешността. Моля, пазете червеното за истински спешни случаи — при злоупотреба то губи смисъл и помощта се отклонява от животните в реален риск.';

  @override
  String get faqCantHelpDirectly =>
      'Не мога да помогна директно. Какво мога да направя?';

  @override
  String get faqCantHelpDirectlyAnswer =>
      'Можете да споделите сигнала с приятели, които може да могат да помогнат, да оставите полезни коментари със съвети или контакти на местни организации за спасяване на животни, или просто да разпространите информация за приложението, за да разрастваме общността от помощници.';

  @override
  String get faqHowNotificationsWork => 'Как работят известията?';

  @override
  String get faqHowNotificationsWorkAnswer =>
      'Ще получавате известия, когато: нов сигнал се появи във вашия район, някой коментира вашия сигнал или статусът на сигнал, който следите, се промени. Можете да персонализирате настройките за известия в приложението.';

  @override
  String get faqChangeNotificationRadius =>
      'Как да променя радиуса за известия?';

  @override
  String get faqChangeNotificationRadiusAnswer =>
      'Отидете в Настройки за известия > Проследяване на местоположението > Радиус за известия и регулирайте плъзгача. Можете да го зададете от 1 км до 50 км в зависимост от това колко далеч сте готови да помогнете.';

  @override
  String get faqPersonalInfoSafe => 'Личната ми информация защитена ли е?';

  @override
  String get faqPersonalInfoSafeAnswer =>
      'Ние приемаме поверителността сериозно. Вашият имейл се използва само за управление на акаунта. Телефонните номера, споделени в сигналите, са по избор и по ваша преценка. Данните за местоположение се използват само за показване на релевантни сигнали.';

  @override
  String get faqReportInappropriate =>
      'Как да докладвам неподходящо съдържание?';

  @override
  String get faqReportInappropriateAnswer =>
      'Ако видите сигнал, който съдържа неподходящо съдържание, спам или невярна информация, моля използвайте функцията за докладване на сигнала или се свържете с нас чрез опцията за отзив в менюто.';

  @override
  String get stayInformedTitle => 'Бъдете информирани за животни в нужда';

  @override
  String get stayInformedSubtitle =>
      'Получавайте известия, когато се появят сигнали близо до вас или във вашия район на интерес.';

  @override
  String get maybeLater => 'Може би по-късно';

  @override
  String get enableLocationTitle => 'Включи проследяване на местоположение';

  @override
  String get enableLocationSubtitle =>
      'Получавайте известия за животни в нужда в радиус от 10 км от вашето местоположение.';

  @override
  String get enableLocation => 'Включи местоположение';

  @override
  String get skipForNow => 'Пропусни за сега';

  @override
  String get chooseRegionTitle => 'Изберете вашия регион на интерес';

  @override
  String get chooseRegionSubtitle =>
      'Изберете конкретна област, която ви интересува, и получавайте известия за сигнали там.';

  @override
  String get selectRegion => 'Избери регион';

  @override
  String get aboutTitle => 'За нас';

  @override
  String get helpAPaw => 'Помогни на лапа';

  @override
  String version(String version, String build) {
    return 'Версия $version ($build)';
  }

  @override
  String get appDescription => 'Изпращайте спешни сигнали за животни в нужда';

  @override
  String get aboutDescription =>
      'Помогни на лапа е платформа, която свързва хора, забелязали животни в беда, с доброволци, които могат да помогнат. Заедно можем да направим разлика в живота на животните.';

  @override
  String get connectWithUs => 'Свържете се с нас';

  @override
  String get website => 'Уебсайт';

  @override
  String get facebook => 'Facebook';

  @override
  String get gitHub => 'GitHub';

  @override
  String get openSourceLicenses => 'Лицензи с отворен код';

  @override
  String copyright(int year) {
    return '© $year Помогни на лапа';
  }

  @override
  String get verifyEmail => 'Потвърди имейл';

  @override
  String get verifyYourEmail => 'Потвърдете имейла си';

  @override
  String get verificationEmailSentTo => 'Изпратихме имейл за потвърждение на:';

  @override
  String get instructions => 'Инструкции:';

  @override
  String get instructionsSteps =>
      '1. Отворете имейла във входящата си поща (или SPAM)\n2. Кликнете върху линка за потвърждение\n3. Върнете се в това приложение\n4. Ще бъдете автоматично пренасочени';

  @override
  String get checkingVerificationStatus =>
      'Проверка на статуса на потвърждение...';

  @override
  String get verificationEmailSentCheck =>
      'Имейл за потвърждение е изпратен! Проверете входящата си поща (или SPAM).';

  @override
  String get tooManyRequests =>
      'Твърде много заявки. Моля, опитайте по-късно или се свържете с поддръжката.';

  @override
  String get accountDisabled =>
      'Този акаунт е деактивиран. Моля, свържете се с поддръжката.';

  @override
  String unexpectedErrorWithMessage(String error) {
    return 'Неочаквана грешка: $error';
  }

  @override
  String errorWithCode(String message) {
    return 'Грешка: $message';
  }

  @override
  String resendInSeconds(int seconds) {
    return 'Изпрати отново след $secondsс';
  }

  @override
  String get resendVerificationEmail => 'Изпрати отново имейл за потвърждение';

  @override
  String get iveVerifiedMyEmail => 'Потвърдих имейла си';

  @override
  String get cancelAndSignOut => 'Отказ и изход';

  @override
  String get skipDevOnly => 'Пропусни (само за разработка)';

  @override
  String get myNotifications => 'Известия';

  @override
  String get pleaseSignInToViewNotifications =>
      'Моля, влезте, за да видите известията';

  @override
  String get markAllAsRead => 'Маркирай всички като прочетени';

  @override
  String get clearAllNotifications => 'Изчисти всички';

  @override
  String get noNotifications => 'Няма известия';

  @override
  String get notifiedAboutSignalUpdates =>
      'Ще бъдете уведомени за обновления на сигнали';

  @override
  String get notification => 'Известие';

  @override
  String get justNow => 'Току-що';

  @override
  String minutesAgo(int minutes) {
    return 'преди $minutesм';
  }

  @override
  String hoursAgo(int hours) {
    return 'преди $hoursч';
  }

  @override
  String daysAgo(int days) {
    return 'преди $daysд';
  }

  @override
  String get notificationNewSignalTitle => 'Нов сигнал наблизо';

  @override
  String get notificationNewRedAlertTitle => 'Червен сигнал наблизо';

  @override
  String notificationNewSignalBody(String signalType, String signalTitle) {
    return '$signalType: $signalTitle';
  }

  @override
  String get notificationStatusChangeTitle => 'Статусът на сигнал е променен';

  @override
  String notificationStatusChangeBody(String signalTitle, String status) {
    return '$signalTitle: $status';
  }

  @override
  String get notificationUrgencyChangeTitle =>
      'Спешността на сигнал е повишена';

  @override
  String get notificationRedAlertTitle => 'Повишен до червен сигнал';

  @override
  String notificationUrgencyChangeBody(String signalTitle, String urgency) {
    return '$signalTitle: $urgency';
  }

  @override
  String notificationNewCommentTitle(String signalTitle) {
    return 'Нов коментар по: $signalTitle';
  }

  @override
  String notificationNearbySignalBody(String signalType, String signalTitle) {
    return '$signalType · $signalTitle';
  }

  @override
  String get completeYourProfile => 'Попълнете профила си';

  @override
  String get helpUsPersonalize =>
      'Помогнете ни да персонализираме изживяването ви';

  @override
  String get fullNameRequired => 'Пълно име *';

  @override
  String get enterFullName => 'Въведете пълното си име';

  @override
  String get nameIsRequired => 'Името е задължително';

  @override
  String get nameTooShort => 'Името трябва да е поне 2 символа';

  @override
  String get phoneNumberOptional => 'Телефонен номер (по избор)';

  @override
  String get enterPhoneNumber => 'Въведете телефонния си номер';

  @override
  String get validPhoneNumber => 'Моля, въведете валиден телефонен номер';

  @override
  String get completeProfile => 'Попълни профила';

  @override
  String get skipForNowProfile => 'Пропусни за сега';

  @override
  String errorSavingProfile(String error) {
    return 'Грешка при запазване на профила: $error';
  }

  @override
  String get clinicDetails => 'Детайли за клиниката';

  @override
  String get clinicNotFound => 'Клиниката не е намерена';

  @override
  String get returnToMap => 'Обратно към картата';

  @override
  String get viewReviews => 'Виж отзиви';

  @override
  String get address => 'Адрес';

  @override
  String get navigate => 'Навигирай';

  @override
  String get phone => 'Телефон';

  @override
  String get call => 'Обади се';

  @override
  String get openingHours => 'Работно време';

  @override
  String get viewInGoogleMaps => 'Виж в Google Maps';

  @override
  String get cannotOpenNavigationApp =>
      'Не може да се отвори навигационното приложение';

  @override
  String get cannotMakePhoneCalls =>
      'Не може да се правят телефонни обаждания на това устройство';

  @override
  String get cannotOpenGoogleMaps => 'Не може да се отвори Google Maps';

  @override
  String get selectRegionTitle => 'Избери регион';

  @override
  String get tapToSetCenterPoint =>
      'Моля, докоснете картата, за да зададете централна точка';

  @override
  String get tapMapInstruction =>
      'Докоснете картата, за да зададете центъра на вашия регион на интерес';

  @override
  String get regionRadius => 'Радиус на региона';

  @override
  String get km => 'км';

  @override
  String get dragMarkerToReposition =>
      'Плъзнете маркера, за да преместите центъра';

  @override
  String get shareSignal => 'Сподели сигнал';

  @override
  String get sendComment => 'Изпрати коментар';

  @override
  String get closePhotoViewer => 'Затвори снимката';

  @override
  String get uploadPhoto => 'Качи снимка';

  @override
  String couldNotOpenUrl(String url) {
    return 'Не може да се отвори $url';
  }

  @override
  String get completeNotificationSetup => 'Завършете настройката на известията';

  @override
  String get editSignal => 'Редактирай сигнал';

  @override
  String get deleteSignal => 'Изтрий сигнал';

  @override
  String get confirmDeleteSignal =>
      'Сигурни ли сте, че искате да изтриете този сигнал? Това действие не може да бъде отменено.';

  @override
  String get signalUpdatedSuccessfully => 'Сигналът е обновен успешно';

  @override
  String get signalDeletedSuccessfully => 'Сигналът е изтрит успешно';

  @override
  String get signalNoLongerAvailable => 'Този сигнал вече не е наличен';

  @override
  String get signalNoLongerAvailableHint =>
      'Възможно е да е изтрит от човека, който го е подал.';

  @override
  String get backToMap => 'Обратно към картата';

  @override
  String get failedToUpdateSignal =>
      'Неуспешно обновяване на сигнала. Моля, опитайте отново.';

  @override
  String get failedToDeleteSignal =>
      'Неуспешно изтриване на сигнала. Моля, опитайте отново.';

  @override
  String get contactPhone => 'Телефон за връзка';

  @override
  String get errorAddingComment =>
      'Неуспешно добавяне на коментар. Моля, опитайте отново.';

  @override
  String get errorUpdatingStatus =>
      'Неуспешна промяна на статуса. Моля, опитайте отново.';

  @override
  String get errorGeneric => 'Нещо се обърка. Моля, опитайте отново.';

  @override
  String get deleteAccount => 'Изтриване на профила';

  @override
  String get deleteAccountConfirmTitle => 'Изтриване на профила?';

  @override
  String get deleteAccountConfirmBody =>
      'Това изтрива безвъзвратно профила и личните ви данни и не може да бъде отменено. Подадените от вас сигнали ще останат, но вече няма да са свързани с вас.';

  @override
  String get deleteAccountSuccess => 'Профилът ви беше изтрит.';

  @override
  String get deleteAccountError =>
      'Неуспешно изтриване на профила. Моля, опитайте отново.';

  @override
  String get signalNearbyNotificationTitle =>
      'Животно наблизо се нуждае от помощ';

  @override
  String get locationAlwaysPermissionRequired =>
      'За да получавате известия, докато приложението е затворено, разрешете достъп до местоположението „Винаги“ в Настройки. При „Докато използвам приложението“ можем да проверяваме само когато приложението е отворено.';
}

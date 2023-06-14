import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

class LocalizationCubit extends HydratedCubit<Locale> {
  LocalizationCubit(BuildContext context) : super(_getInitialLocale(context)) {
    _loadLocale();
  }

  static Locale _getInitialLocale(BuildContext context) {
    final deviceLocale = Localizations.localeOf(context);
    final supportedLanguages = {
      'en',
      'bg'
    }; // Add more supported languages here
    const defaultLanguage = 'en'; // Set a default language

    final languageCode = supportedLanguages.contains(deviceLocale.languageCode)
        ? deviceLocale.languageCode
        : defaultLanguage;

    return Locale(languageCode);
  }

  void setLocale(Locale locale) async {
    await HydratedBloc.storage.write('locale', locale.languageCode);
    emit(locale);
  }

  Future<void> _loadLocale() async {
    final languageCode = await HydratedBloc.storage.read('locale') as String?;
    if (languageCode != null) {
      emit(Locale(languageCode));
    }
  }

  @override
  Map<String, dynamic>? toJson(Locale state) {
    return {'languageCode': state.languageCode};
  }

  @override
  Locale? fromJson(Map<String, dynamic> json) {
    return Locale(json['languageCode'] as String);
  }
}

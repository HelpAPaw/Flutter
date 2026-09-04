import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:help_a_paw/l10n/app_localizations.dart';

/// Guards the four places that separately assert which languages this app
/// speaks, and which drift apart silently.
///
/// The translations themselves are Dart-side (`lib/l10n/*.arb`), invisible to
/// both platforms' packaging. Each platform therefore needs its own
/// declaration, and none of them fail loudly when they disagree:
///
/// * **`android/app/src/main/res/values-<lang>/`** is what makes Android
///   consider a language "supported" at all. Android picks the activity's
///   locale by matching the device's locale list against the locales the APK
///   has *resources* for, and Flutter's `LocalizationPlugin` then reads that
///   decision — so a language with no resource directory resolves to English
///   no matter what the ARBs contain. This is the mechanism behind the field
///   bug that prompted these tests: Play had not delivered `split_config.bg`,
///   the app had no `bg` resources of its own, and every Bulgarian user got an
///   English UI with nothing logged anywhere.
/// * **`res/xml/locales_config.xml`** backs the Android 13+ per-app Language
///   picker. A language missing here simply never appears as an option.
/// * **`ios/Runner/Info.plist`'s `CFBundleLocalizations`** is what the App
///   Store lists as the app's languages.
///
/// Adding a locale to `l10n.yaml`/the ARBs is the easy half; these are the half
/// that gets forgotten, and the failure is always silent. Hence this test.
void main() {
  final supported = AppLocalizations.supportedLocales
      .map((l) => l.languageCode)
      .toSet();

  test('supportedLocales is not accidentally empty', () {
    // Every assertion below compares against this set, so an empty one would
    // make the whole file pass vacuously.
    expect(supported, isNotEmpty);
    expect(supported, contains('en'));
  });

  test('Android locales_config.xml matches supportedLocales', () {
    final file = File('android/app/src/main/res/xml/locales_config.xml');
    expect(file.existsSync(), isTrue,
        reason: 'locales_config.xml is referenced by AndroidManifest.xml');

    final declared = RegExp(r'android:name="([^"]+)"')
        .allMatches(file.readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();

    expect(declared, supported,
        reason: 'res/xml/locales_config.xml has drifted from '
            'AppLocalizations.supportedLocales; the per-app Language picker '
            'will offer the wrong set of languages.');
  });

  test('every supported locale has Android string resources', () {
    // The default locale lives in plain `values/`, everything else needs its
    // own `values-<lang>/` for Android to treat that language as supported.
    for (final code in supported) {
      final dir = code == 'en'
          ? Directory('android/app/src/main/res/values')
          : Directory('android/app/src/main/res/values-$code');

      expect(File('${dir.path}/strings.xml').existsSync(), isTrue,
          reason: '$code has translations in lib/l10n but no '
              '${dir.path}/strings.xml. Without app-owned resources, whether '
              'Android resolves to $code depends on transitive AndroidX/Play '
              'Services translations happening to include it — and when they '
              'stop, the app silently falls back to English.');
    }
  });

  test('iOS CFBundleLocalizations matches supportedLocales', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final block = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);

    expect(block, isNotNull,
        reason: 'Info.plist has no CFBundleLocalizations, so the App Store '
            'lists the app as English-only.');

    final declared = RegExp(r'<string>([^<]+)</string>')
        .allMatches(block!.group(1)!)
        .map((m) => m.group(1)!)
        .toSet();

    expect(declared, supported,
        reason: 'ios/Runner/Info.plist CFBundleLocalizations has drifted from '
            'AppLocalizations.supportedLocales.');
  });
}

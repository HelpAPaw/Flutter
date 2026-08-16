import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import '../config/routes.dart';

class ShareService {
  static const String _appStoreUrl = 'https://apps.apple.com/app/help-a-paw/id1234893764';
  static const String _playStoreUrl = 'https://play.google.com/store/apps/details?id=org.helpapaw.helpapaw';
  static const String _websiteUrl = 'https://www.helpapaw.org';

  static Future<void> shareApp({Rect? sharePositionOrigin}) async {
    const message = '''Help animals in need with Help a Paw! 🐾

Spot an animal in distress? Report it on the map and connect with nearby volunteers who can help.

Download now:
iOS: $_appStoreUrl
Android: $_playStoreUrl

Or visit: $_websiteUrl''';

    await SharePlus.instance.share(ShareParams(text: message, subject: 'Help a Paw - Help animals in need', sharePositionOrigin: sharePositionOrigin));
  }

  /// Shares a signal.
  ///
  /// [headline] is the already-localized description of what the signal needs —
  /// normally `HelpTag.neededLabel`, e.g. "Rescue needed". Resolved by the
  /// caller, which has the `BuildContext` this service deliberately does not.
  static Future<void> shareSignal({
    required String signalId,
    required String headline,
    required String description,
    double? latitude,
    double? longitude,
    Rect? sharePositionOrigin,
  }) async {
    // Smart link: opens the signal directly in the app when installed,
    // otherwise the hosted page routes to the right store / shows a QR.
    final deepLink = Routes.signalShareUrl(signalId);

    // The signal link must come before any other URL: link-preview scrapers
    // (Facebook's among them) unfurl the *first* URL in the text, so putting the
    // maps link first made shares preview as a Google Maps pin instead of the
    // animal's photo and title.
    var message = '''🐾 Animal needs help!

$headline
$description

View on Help a Paw: $deepLink''';

    if (latitude != null && longitude != null) {
      message += '''

📍 Location: https://maps.google.com/?q=$latitude,$longitude''';
    }

    await SharePlus.instance.share(ShareParams(text: message, subject: 'Help a Paw - Animal needs help', sharePositionOrigin: sharePositionOrigin));
  }
}

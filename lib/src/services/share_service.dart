import 'dart:ui';

import 'package:share_plus/share_plus.dart';

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

  static Future<void> shareSignal({
    required String signalId,
    required String signalType,
    required String description,
    double? latitude,
    double? longitude,
    Rect? sharePositionOrigin,
  }) async {
    // Smart link: opens the signal directly in the app when installed,
    // otherwise the hosted page routes to the right store / shows a QR.
    final deepLink = 'https://link.helpapaw.org/signal/$signalId';

    var message = '''🐾 Animal needs help!

Type: $signalType
$description''';

    if (latitude != null && longitude != null) {
      message += '''

📍 Location: https://maps.google.com/?q=$latitude,$longitude''';
    }

    message += '''

View on Help a Paw: $deepLink''';

    await SharePlus.instance.share(ShareParams(text: message, subject: 'Help a Paw - Animal needs help', sharePositionOrigin: sharePositionOrigin));
  }
}

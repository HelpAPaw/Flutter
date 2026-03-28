import 'package:share_plus/share_plus.dart';

class ShareService {
  static const String _appStoreUrl = 'https://apps.apple.com/app/help-a-paw/id123456789';
  static const String _playStoreUrl = 'https://play.google.com/store/apps/details?id=org.helpapaw.helpapaw';
  static const String _websiteUrl = 'https://www.helpapaw.org';

  static Future<void> shareApp() async {
    const message = '''Help animals in need with Help A Paw! 🐾

Spot an animal in distress? Report it on the map and connect with nearby volunteers who can help.

Download now:
iOS: $_appStoreUrl
Android: $_playStoreUrl

Or visit: $_websiteUrl''';

    await SharePlus.instance.share(ShareParams(text: message, subject: 'Help A Paw - Help animals in need'));
  }

  static Future<void> shareSignal({
    required String signalId,
    required String signalType,
    required String description,
    double? latitude,
    double? longitude,
  }) async {
    final deepLink = 'https://www.helpapaw.org/signal/$signalId';

    var message = '''🐾 Animal needs help!

Type: $signalType
$description''';

    if (latitude != null && longitude != null) {
      message += '''

📍 Location: https://maps.google.com/?q=$latitude,$longitude''';
    }

    message += '''

View on Help A Paw: $deepLink

Don't have the app? Download it:
$_websiteUrl''';

    await SharePlus.instance.share(ShareParams(text: message, subject: 'Help A Paw - Animal needs help'));
  }
}

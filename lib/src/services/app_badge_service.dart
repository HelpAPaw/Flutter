import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sets the app icon badge.
///
/// On iOS the badge normally comes from the APNs payload and is applied by the
/// OS, which makes it sticky — nothing but the app can clear it once a
/// notification has been delivered. Neither `firebase_messaging` nor
/// `flutter_local_notifications` exposes a setter, so this goes through a native
/// channel (`AppDelegate.setUpAppBadgeChannel`).
///
/// Android needs nothing: launchers derive their badge from the notification
/// shade, so the call falls through the `MissingPluginException` branch below
/// and is a no-op.
class AppBadgeService {
  static final AppBadgeService _instance = AppBadgeService._internal();
  factory AppBadgeService() => _instance;
  AppBadgeService._internal();

  static const MethodChannel _channel =
      MethodChannel('org.helpapaw.helpapaw/app_badge');

  Future<void> setBadge(int count) async {
    try {
      await _channel.invokeMethod<void>('setBadge', {
        'count': count < 0 ? 0 : count,
      });
    } on MissingPluginException {
      // Platform with no badge channel (Android, tests).
    } catch (error) {
      debugPrint('AppBadgeService: setBadge failed: $error');
    }
  }

  Future<void> clear() => setBadge(0);
}

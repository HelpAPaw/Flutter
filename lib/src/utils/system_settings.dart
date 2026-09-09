import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

/// The OS settings pages the app can send someone to when a permission can no
/// longer be granted from inside the app.
///
/// Both entries come from geolocator, which is already a dependency and whose
/// `openAppSettings` is not location-specific — it is the plain app-details
/// intent on Android and `UIApplication.openSettingsURLString` on iOS. Kept
/// here rather than on a service so that notification code does not have to
/// reach through [LocationService] (or import geolocator itself) to offer the
/// same button.
abstract final class SystemSettings {
  /// This app's own page: where a refused permission — location, notifications
  /// — is switched back on.
  static Future<bool> openAppPage() => Geolocator.openAppSettings();

  /// Whether [openLocationServices] actually goes anywhere useful.
  ///
  /// False on iOS: `geolocator_apple` routes `openLocationSettings` to the same
  /// `openSettingsURLString` as [openAppPage], landing on the app's own page,
  /// which has no Location Services switch. A button that goes nowhere useful
  /// is worse than no button, so callers ask before offering one.
  static bool get canOpenLocationServices => Platform.isAndroid;

  /// The device-wide location switch — a different page from [openAppPage],
  /// and the only one that helps when location is off for the whole device.
  static Future<bool> openLocationServices() =>
      Geolocator.openLocationSettings();
}

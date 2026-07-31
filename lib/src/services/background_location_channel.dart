import 'dart:async';
import 'dart:ui' show PluginUtilities;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the native background location monitors.
///
/// `geolocator` cannot do background significant-change monitoring on either
/// platform — `geolocator_apple` has no significant-change API at all, and
/// `geolocator_android`'s own docs note its foreground service dies with the
/// activity. So the background path is native:
///
/// * **iOS** — `CLLocationManager.startMonitoringSignificantLocationChanges`,
///   which is low-power and relaunches a terminated app to deliver updates.
/// * **Android** — `FusedLocationProviderClient` updates delivered to a
///   `PendingIntent`, which needs no foreground service (and therefore no
///   permanent notification in the shade).
///
/// Both write `userLocations/{uid}` natively, using the persisted Firebase Auth
/// session for the uid, so a location update needs no Dart engine at all.
/// geolocator is still used for everything in the foreground.
class BackgroundLocationChannel {
  static final BackgroundLocationChannel _instance =
      BackgroundLocationChannel._internal();
  factory BackgroundLocationChannel() => _instance;
  BackgroundLocationChannel._internal();

  /// Fixed channel name — deliberately not derived from the application id,
  /// which carries a `.debug` suffix on debug builds.
  static const MethodChannel _channel =
      MethodChannel('org.helpapaw.helpapaw/background_location');

  /// Invoked when a background location arrives while a Dart engine is alive.
  ///
  /// Only iOS uses this: a significant-change relaunch boots the app, so Dart
  /// is available to run the nearby-signal check in the normal isolate.
  /// Android's process has no engine at that point and instead schedules a
  /// headless task.
  Future<void> Function(double latitude, double longitude)? onLocationUpdate;

  bool _handlerInstalled = false;

  /// Single funnel for outbound calls.
  ///
  /// Every method wants the same handling: a platform without the native
  /// monitor is not an error, anything else is worth a log but never worth
  /// throwing into a background path.
  Future<T?> _invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // Platform without the native monitor (e.g. web/desktop).
      return null;
    } catch (e) {
      debugPrint('BackgroundLocationChannel: $method failed: $e');
      return null;
    }
  }

  /// Installs the inbound handler and drains anything the native side buffered
  /// while the engine was still starting.
  void ensureHandlerInstalled({
    required Future<void> Function(double latitude, double longitude) onUpdate,
  }) {
    onLocationUpdate = onUpdate;
    if (_handlerInstalled) return;
    _handlerInstalled = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onLocationUpdate') return null;

      final args = (call.arguments as Map).cast<String, dynamic>();
      final latitude = (args['latitude'] as num).toDouble();
      final longitude = (args['longitude'] as num).toDouble();

      await onLocationUpdate?.call(latitude, longitude);
      return null;
    });

    // A background relaunch can deliver a location before Dart finishes
    // booting; the native side holds those and replays them on request.
    unawaited(_invoke<void>('drainPendingUpdates'));
  }

  /// Starts native background monitoring.
  ///
  /// Returns false when the platform refuses — most often because only
  /// "while in use" location permission was granted, which is not enough for
  /// background delivery on either platform.
  Future<bool> start() async => await _invoke<bool>('start') ?? false;

  /// Stops native background monitoring.
  Future<void> stop() => _invoke<void>('stop');

  /// Tells the native side which Dart entrypoint to boot for headless checks.
  ///
  /// Only Android needs this — iOS relaunches the whole app, so Dart is already
  /// running — but iOS implements it as a no-op so callers don't have to branch
  /// on platform.
  ///
  /// Re-registered on every launch because the handle is only valid for the
  /// current binary: an app update invalidates it, and a stale handle fails to
  /// resolve at exactly the moment it is needed.
  Future<void> registerHeadlessEntrypoint(Function entrypoint) async {
    final handle = PluginUtilities.getCallbackHandle(entrypoint);
    if (handle == null) {
      debugPrint('BackgroundLocationChannel: could not resolve callback handle');
      return;
    }
    await _invoke<void>(
      'registerHeadlessCallback',
      {'handle': handle.toRawHandle()},
    );
  }
}

import FirebaseCore
import Flutter
import GoogleMaps
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let backgroundLocationChannelName =
    "org.helpapaw.helpapaw/background_location"
  private static let appBadgeChannelName = "org.helpapaw.helpapaw/app_badge"

  private var backgroundLocationChannel: FlutterMethodChannel?
  private var appBadgeChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialize Google Maps
    if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String {
      GMSServices.provideAPIKey(apiKey)
    }

    // Configure Firebase natively, guarded so it stays compatible with the
    // Dart-side Firebase.initializeApp (firebase_core reuses an existing
    // default app). This has to happen here rather than only in Dart: on a
    // significant-change background relaunch the native location write runs
    // before Dart finishes booting, and it needs Auth and Firestore ready.
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    GeneratedPluginRegistrant.register(with: self)

    if launchOptions?[.location] != nil {
      NSLog("BackgroundLocation: relaunched by a significant location change")
    }

    // FlutterAppDelegate builds the window and its root FlutterViewController
    // inside this super call, so the method channel cannot be created before
    // it. Setting it up earlier silently yields "no FlutterViewController" and
    // the native monitor never arms — the app looks fine because geolocator
    // still covers the foreground.
    let didFinishLaunching = super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )

    setUpBackgroundLocationChannel()
    setUpAppBadgeChannel()

    // Re-arm monitoring. Significant-change monitoring does not survive process
    // death on its own — only the wake-up does — so every launch has to restore
    // it, including a background relaunch.
    BackgroundLocationManager.shared.restoreIfEnabled()

    return didFinishLaunching
  }

  /// Lets Dart set the app icon badge.
  ///
  /// Needed because the badge value normally arrives in the APNs payload and is
  /// applied by the OS, so it is sticky: nothing but the app itself can clear it
  /// once a notification has been delivered. Neither `firebase_messaging` nor
  /// `flutter_local_notifications` exposes a setter, hence this channel.
  ///
  /// Android has no counterpart — launchers derive their badge from the
  /// notification shade — and the Dart side treats the resulting
  /// `MissingPluginException` as a no-op.
  private func setUpAppBadgeChannel() {
    guard let messenger = registrar(forPlugin: "HelpAPawAppBadge")?.messenger()
    else {
      NSLog("AppBadge: ERROR no plugin registrar, badge channel unavailable")
      return
    }

    let channel = FlutterMethodChannel(
      name: Self.appBadgeChannelName,
      binaryMessenger: messenger
    )
    appBadgeChannel = channel

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setBadge":
        let arguments = call.arguments as? [String: Any]
        let count = arguments?["count"] as? Int ?? 0
        if #available(iOS 16.0, *) {
          UNUserNotificationCenter.current().setBadgeCount(count) { error in
            if let error = error {
              NSLog("AppBadge: setBadgeCount failed: \(error.localizedDescription)")
            }
          }
        } else {
          UIApplication.shared.applicationIconBadgeNumber = count
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setUpBackgroundLocationChannel() {
    // Take the messenger from the plugin registrar rather than casting
    // window.rootViewController. The cast assumes the root is a bare
    // FlutterViewController, which breaks the moment anything wraps it, and it
    // fails silently — the app keeps working in the foreground via geolocator
    // while background monitoring never arms.
    guard let messenger = registrar(forPlugin: "HelpAPawBackgroundLocation")?.messenger()
    else {
      NSLog("BackgroundLocation: ERROR no plugin registrar, channel unavailable — "
        + "background monitoring will not work")
      return
    }

    let channel = FlutterMethodChannel(
      name: Self.backgroundLocationChannelName,
      binaryMessenger: messenger
    )
    backgroundLocationChannel = channel

    BackgroundLocationManager.shared.onLocationUpdate = { [weak channel] latitude, longitude in
      // Always hop to the main thread: CoreLocation delivers on its own queue,
      // and platform channels must be used from the platform thread.
      DispatchQueue.main.async {
        channel?.invokeMethod(
          "onLocationUpdate",
          arguments: ["latitude": latitude, "longitude": longitude]
        )
      }
    }

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        result(BackgroundLocationManager.shared.start())
      // Whether background delivery is really armed, as opposed to what the
      // user's stored preference claims. The two drift apart whenever
      // authorization is downgraded in Settings.
      case "isBackgroundActive":
        result(BackgroundLocationManager.shared.isBackgroundActive)
      case "stop":
        BackgroundLocationManager.shared.stop()
        result(nil)
      case "drainPendingUpdates":
        BackgroundLocationManager.shared.drainPendingUpdates()
        result(nil)
      case "recordNearbyCheck":
        // Android keeps a native pre-filter gate to decide whether booting a
        // headless engine is worthwhile; iOS has no such gate, because a
        // significant-change relaunch runs the check in the normal isolate
        // where Dart's own gate already applies. Nothing to mirror.
        result(nil)
      case "setTestMode":
        // Android keys its native pre-filter gate by mode and needs the mirror.
        // iOS has no native gate — a significant-change relaunch runs the check
        // in the normal isolate, where the Dart gate is already namespaced — so
        // there is nothing to store. Answered rather than left unimplemented so
        // Dart needn't branch on platform.
        result(nil)
      case "registerHeadlessCallback":
        // Android boots a headless engine per delivery; iOS relaunches the whole
        // app, so Dart is already running and there is no entrypoint to record.
        // Answered rather than left unimplemented so Dart needn't branch here.
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

import FirebaseCore
import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private static let backgroundLocationChannelName =
    "org.helpapaw.helpapaw/background_location"

  private var backgroundLocationChannel: FlutterMethodChannel?

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

    // Re-arm monitoring. Significant-change monitoring does not survive process
    // death on its own — only the wake-up does — so every launch has to restore
    // it, including a background relaunch.
    BackgroundLocationManager.shared.restoreIfEnabled()

    return didFinishLaunching
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
      case "stop":
        BackgroundLocationManager.shared.stop()
        result(nil)
      case "drainPendingUpdates":
        BackgroundLocationManager.shared.drainPendingUpdates()
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

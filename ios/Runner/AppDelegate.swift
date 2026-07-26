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

    setUpBackgroundLocationChannel()

    // Re-arm monitoring. Significant-change monitoring does not survive process
    // death on its own — only the wake-up does — so every launch has to restore
    // it, including the background relaunch signalled by the .location key.
    if launchOptions?[.location] != nil {
      NSLog("BackgroundLocation: relaunched by a significant location change")
    }
    BackgroundLocationManager.shared.restoreIfEnabled()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setUpBackgroundLocationChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("BackgroundLocation: no FlutterViewController, channel unavailable")
      return
    }

    let channel = FlutterMethodChannel(
      name: Self.backgroundLocationChannelName,
      binaryMessenger: controller.binaryMessenger
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
      case "isActive":
        result(BackgroundLocationManager.shared.isActive)
      case "drainPendingUpdates":
        BackgroundLocationManager.shared.drainPendingUpdates()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

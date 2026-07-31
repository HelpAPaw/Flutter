import CoreLocation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Background location monitoring for iOS, built on significant-change updates.
///
/// `geolocator` has no significant-change API, so it can only offer continuous
/// `startUpdatingLocation` — GPS-hungry, and it never relaunches a terminated
/// app. `startMonitoringSignificantLocationChanges` is cell-tower based, costs
/// almost no battery, and crucially iOS *relaunches the app in the background*
/// to deliver an update. That relaunch is what makes tracking survive a user
/// force-quitting or the system reclaiming the process.
///
/// The Firestore write happens here in native code rather than over the method
/// channel, so a location update never depends on the Dart engine being up. The
/// uid comes from the persisted Firebase Auth session, which survives process
/// death.
final class BackgroundLocationManager: NSObject {
  static let shared = BackgroundLocationManager()

  /// Native-owned state, deliberately not read from shared_preferences.
  ///
  /// Dart already calls `start`/`stop` over the method channel, so persisting
  /// the flag here costs nothing and avoids depending on shared_preferences'
  /// storage format — which is an implementation detail that has changed
  /// before, and whose breakage would be silent.
  private static let enabledKey = "org.helpapaw.backgroundLocationEnabled"

  private let locationManager = CLLocationManager()
  private var isMonitoring = false

  /// The most recent location that arrived before Dart was ready to receive it.
  ///
  /// On a background relaunch iOS delivers the update almost immediately, well
  /// before the Flutter engine has finished booting and installed its method
  /// call handler. Dropping it would mean the catch-up check never runs for
  /// exactly the case it exists to handle, so it's held until Dart asks.
  ///
  /// Last-write-wins rather than a queue: only the newest position can matter,
  /// and replaying a backlog would start one independent check per entry.
  private var pendingUpdate: (latitude: Double, longitude: Double)?

  /// Whether Dart has registered its channel handler, set by
  /// [drainPendingUpdates]. Until then updates are buffered rather than sent.
  private var isDartReady = false

  /// Set by AppDelegate once the method channel exists.
  var onLocationUpdate: ((Double, Double) -> Void)?

  private override init() {
    super.init()
    locationManager.delegate = self
    // Significant-change updates are coarse by nature; asking for more accuracy
    // just costs battery without changing which signals are "nearby".
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    locationManager.pausesLocationUpdatesAutomatically = false
  }

  var isEnabledInPreferences: Bool {
    UserDefaults.standard.bool(forKey: Self.enabledKey)
  }

  private func setEnabledInPreferences(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
  }

  /// Starts monitoring. Returns false when authorization is insufficient.
  ///
  /// Significant-change delivery in the background requires *Always*
  /// authorization. With only "When In Use" the API silently delivers nothing
  /// once the app is backgrounded, so this reports failure and lets the Dart
  /// layer explain the difference rather than appearing to work.
  @discardableResult
  func start() -> Bool {
    guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
      NSLog("BackgroundLocation: significant-change monitoring unavailable")
      return false
    }

    guard authorizationStatus == .authorizedAlways else {
      NSLog("BackgroundLocation: needs Always authorization, has \(authorizationStatus.rawValue)")
      return false
    }

    // Recorded only on success, so a failed start can't leave restoreIfEnabled
    // re-arming something that could never work.
    setEnabledInPreferences(true)

    if isMonitoring { return true }

    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.startMonitoringSignificantLocationChanges()
    isMonitoring = true
    NSLog("BackgroundLocation: monitoring started")
    return true
  }

  func stop() {
    // Cleared first so an early return can't leave the flag set and have the
    // next launch resurrect tracking the user just turned off.
    setEnabledInPreferences(false)

    guard isMonitoring else { return }
    locationManager.stopMonitoringSignificantLocationChanges()
    locationManager.allowsBackgroundLocationUpdates = false
    isMonitoring = false
    NSLog("BackgroundLocation: monitoring stopped")
  }

  /// Re-arms monitoring if the user has the feature enabled.
  ///
  /// Called on every launch, including background relaunches, because
  /// monitoring does not persist across process death by itself — only the
  /// *wake-up* does.
  func restoreIfEnabled() {
    guard isEnabledInPreferences else { return }
    start()
  }

  /// Hands Dart whatever was buffered while the engine was starting, and marks
  /// Dart as ready so later updates go straight through.
  ///
  /// Dart calling this *is* the readiness signal — it happens immediately after
  /// `BackgroundLocationChannel.ensureHandlerInstalled` registers the receiving
  /// handler. Before this point an `invokeMethod` would land on a channel with
  /// no listener, where Flutter's implicit buffer holds a single message and
  /// silently discards anything beyond it.
  func drainPendingUpdates() {
    isDartReady = true

    guard let handler = onLocationUpdate, let update = pendingUpdate else { return }
    pendingUpdate = nil
    NSLog("BackgroundLocation: replaying update buffered before Dart was ready")
    handler(update.latitude, update.longitude)
  }

  private var authorizationStatus: CLAuthorizationStatus {
    if #available(iOS 14.0, *) {
      return locationManager.authorizationStatus
    }
    return CLLocationManager.authorizationStatus()
  }

  /// Writes the position to `userLocations/{uid}`.
  ///
  /// Same document shape the Dart path writes, including the precision-9
  /// geohash the fan-out's range query depends on.
  private func writeLocation(_ location: CLLocation) {
    guard FirebaseApp.app() != nil else {
      NSLog("BackgroundLocation: Firebase not configured, skipping write")
      return
    }
    guard let uid = Auth.auth().currentUser?.uid else {
      NSLog("BackgroundLocation: no signed-in user, skipping write")
      return
    }

    let latitude = location.coordinate.latitude
    let longitude = location.coordinate.longitude
    let geohash = Geohash.encode(latitude: latitude, longitude: longitude)

    Firestore.firestore()
      .collection("userLocations")
      .document(uid)
      .setData(
        [
          "geopoint": GeoPoint(latitude: latitude, longitude: longitude),
          "geohash": geohash,
          "updatedAt": FieldValue.serverTimestamp(),
        ],
        merge: true
      ) { error in
        if let error = error {
          NSLog("BackgroundLocation: write failed: \(error.localizedDescription)")
        } else {
          NSLog("BackgroundLocation: wrote location (geohash \(geohash))")
        }
      }
  }
}

extension BackgroundLocationManager: CLLocationManagerDelegate {
  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.last else { return }

    writeLocation(location)

    let latitude = location.coordinate.latitude
    let longitude = location.coordinate.longitude

    // Gate on Dart's readiness, not on this closure. AppDelegate assigns
    // onLocationUpdate unconditionally in didFinishLaunchingWithOptions, so it
    // is never nil by the time a location arrives — testing it made the buffer
    // below dead code and drainPendingUpdates() a permanent no-op, leaving the
    // "delivered before the engine was ready" case to Flutter's implicit
    // one-message channel buffer.
    if isDartReady, let handler = onLocationUpdate {
      handler(latitude, longitude)
    } else {
      // A single slot on purpose: only the newest fix is worth acting on, and
      // replaying superseded positions would just burn the check's gate.
      NSLog("BackgroundLocation: buffering update until Dart is ready")
      pendingUpdate = (latitude: latitude, longitude: longitude)
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    NSLog("BackgroundLocation: location error: \(error.localizedDescription)")
  }

  /// Stops monitoring if the user revokes Always authorization from Settings,
  /// rather than leaving a monitor registered that can never deliver.
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if authorizationStatus != .authorizedAlways && isMonitoring {
      NSLog("BackgroundLocation: lost Always authorization, stopping")
      stop()
    }
  }
}

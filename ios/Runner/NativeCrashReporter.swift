import FirebaseCore
import FirebaseCrashlytics
import Foundation

/// Reports failures from the native background path as Crashlytics non-fatals.
///
/// The iOS twin of `android/.../NativeCrashReporter.kt`, and for the same
/// reason: `main.dart` routes errors to Crashlytics through
/// `FlutterError.onError` and `PlatformDispatcher.onError`, but both are
/// Dart-isolate handlers. The paths reported here either run before Dart has
/// installed its channel handler, or describe a state in which Dart is never
/// told anything at all — so nothing Dart installs can see them, and without
/// this they reach no further than an `NSLog` on a device nobody is reading.
///
/// These failures do not crash. They leave background location quietly not
/// running while the app looks healthy, which is the same class of silent
/// outage `GeohashTest` and `NativeFirestoreGuardTest` exist to prevent — with
/// the added problem that iOS background location has never been
/// device-verified, so its real behaviour is currently unobserved as well as
/// unreported.
///
/// Occurrences are deliberately not deduplicated or rate-limited, matching the
/// Kotlin side: Crashlytics already clusters, and how *often* one of these
/// fires is itself the signal.
enum NativeCrashReporter {

  /// Distinct codes rather than one generic failure, because Crashlytics
  /// clusters recorded `NSError`s by domain and code. Folding these together
  /// would hide a feature that never starts behind whichever one fires most.
  enum Reason: Int {
    case significantChangeUnavailable = 1
    case missingAlwaysAuthorization = 2
    case locationUpdateFailed = 3
    case lostAlwaysAuthorization = 4
  }

  private static let domain = "org.helpapaw.helpapaw.native"

  /// Reports an error that already exists, e.g. from a delegate callback.
  static func report(_ tag: String, _ message: String, error: Error) {
    NSLog("\(tag): \(message)")
    send(tag: tag, message: message, error: error)
  }

  /// For failures that are not themselves errors — a bailout that leaves the
  /// feature silently not running. Synthesises one so the report carries a
  /// stack trace pointing at the bailout.
  static func report(_ tag: String, _ message: String, reason: Reason) {
    NSLog("\(tag): \(message)")
    send(
      tag: tag,
      message: message,
      error: NSError(
        domain: domain,
        code: reason.rawValue,
        userInfo: [NSLocalizedDescriptionKey: message]))
  }

  /// A breadcrumb only. For the informational milestones that are not failures
  /// but are worth having attached to a later report.
  static func breadcrumb(_ tag: String, _ message: String) {
    NSLog("\(tag): \(message)")
    guard isReportingAvailable else { return }
    Crashlytics.crashlytics().log("\(tag): \(message)")
  }

  private static func send(tag: String, message: String, error: Error) {
    // Reporting must never become the thing that breaks location handling —
    // the same precaution the Kotlin version and `error_text.dart` take. Swift
    // cannot catch the `NSException` an unconfigured Firebase raises, so the
    // guard has to come first rather than be wrapped in a `catch`.
    guard isReportingAvailable else {
      NSLog("\(tag): Firebase not configured, dropping report")
      return
    }
    let crashlytics = Crashlytics.crashlytics()
    crashlytics.log("\(tag): \(message)")
    crashlytics.record(error: error)
  }

  private static var isReportingAvailable: Bool {
    FirebaseApp.app() != nil
  }
}

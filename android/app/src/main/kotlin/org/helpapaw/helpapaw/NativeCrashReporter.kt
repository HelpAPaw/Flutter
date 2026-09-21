package org.helpapaw.helpapaw

import android.util.Log
import com.google.firebase.crashlytics.FirebaseCrashlytics

/**
 * Reports failures from the native background path as Crashlytics non-fatals.
 *
 * `main.dart` routes Dart errors to Crashlytics through `FlutterError.onError`
 * and `PlatformDispatcher.onError`, but both are isolate-level handlers. The
 * background location path runs in a process where the Dart isolate does not
 * exist yet — and when this path is what failed, it never will. So nothing Dart
 * installs can see these, and without this they reach no further than a
 * `Log.e` on a device nobody is reading.
 *
 * That matters most for the failures that are *caught*. An uncaught one used to
 * announce itself by killing the process repeatedly; a caught one leaves the
 * arrival catch-up silently dead while the app looks healthy, which is the same
 * class of silent outage `GeohashTest` and `firestore_settings_guard_test.dart`
 * exist to prevent.
 *
 * Occurrences are deliberately not deduplicated or rate-limited here.
 * Crashlytics already clusters by stack trace, and how *often* one of these
 * fires is the signal — the bug that prompted this reported 16 times in a day
 * on one device, and that number was the diagnosis.
 */
object NativeCrashReporter {

    /**
     * Never throws. Reporting sits inside `catch` blocks whose whole purpose is
     * to keep a broadcast alive, so a Crashlytics failure — an uninitialized
     * FirebaseApp in an unusual process, most likely — must not become the
     * thing that kills it. The Dart side takes the same precaution in
     * `error_text.dart`.
     */
    fun report(tag: String, message: String, error: Throwable) {
        Log.e(tag, message, error)
        try {
            FirebaseCrashlytics.getInstance().apply {
                log("$tag: $message")
                recordException(error)
            }
        } catch (e: Throwable) {
            Log.w(tag, "could not report to Crashlytics", e)
        }
    }

    /**
     * For failures that are not themselves throwable — a bailout that leaves
     * the feature silently not running. Synthesises a throwable so the report
     * carries a stack trace pointing at the bailout.
     */
    fun report(tag: String, message: String) {
        report(tag, message, IllegalStateException(message))
    }
}

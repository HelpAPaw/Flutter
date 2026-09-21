package org.helpapaw.helpapaw

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

/**
 * Runs the Dart arrival catch-up check with no Activity attached.
 *
 * Android delivers background location to a receiver in a process that has no
 * Flutter engine, so the check has to boot one. The alternative was to
 * reimplement the whole filter chain — radius, type preferences, age window,
 * own-signal exclusion, dedupe, notification text and its localization — in
 * Kotlin *and* Swift. Booting an engine is the cheaper trade, and it keeps one
 * implementation of that logic.
 *
 * Engines are expensive, so [LocationUpdateReceiver] only calls this once its
 * own displacement/interval pre-filter passes.
 *
 * The entrypoint is a Dart callback registered by the app (see
 * `backgroundLocationCallbackDispatcher` in main.dart) and stored here as a raw
 * handle, which is the same mechanism plugins like workmanager use internally.
 */
object HeadlessNearbyCheck {
    private const val TAG = "BackgroundLocation"
    private const val CALLBACK_HANDLE_KEY = "nearby_check_callback_handle"

    /** Channel the headless isolate uses to receive its arguments. */
    private const val CHANNEL = "org.helpapaw.helpapaw/background_location_headless"

    /**
     * Upper bound on a single check. Firestore queries and notification posting
     * should take well under this; the timeout only exists so a wedged engine
     * can't leak for the life of the process.
     */
    private const val TIMEOUT_MILLIS = 60_000L

    @Volatile
    private var running = false

    fun saveCallbackHandle(context: Context, handle: Long) {
        context.getSharedPreferences(
            BackgroundLocationManager.PREFS_FILE,
            Context.MODE_PRIVATE,
        ).edit().putLong(CALLBACK_HANDLE_KEY, handle).apply()
    }

    private fun callbackHandle(context: Context): Long =
        context.getSharedPreferences(
            BackgroundLocationManager.PREFS_FILE,
            Context.MODE_PRIVATE,
        ).getLong(CALLBACK_HANDLE_KEY, 0L)

    /**
     * Returns whether a check was actually started.
     *
     * The caller uses this to decide whether to record the attempt against its
     * displacement/interval gate. Every `false` below is a bailout where no
     * check ran at all, and recording those would burn the 30-minute window on
     * nothing — suppressing the next genuine opportunity.
     */
    fun run(context: Context, latitude: Double, longitude: Double): Boolean {
        val handle = callbackHandle(context)
        if (handle == 0L) {
            // The app has not run since install/upgrade, so no entrypoint is
            // registered yet. The location write still happened; the check will
            // catch up next time the app is opened.
            Log.w(TAG, "no Dart callback registered, skipping nearby check")
            return false
        }

        // Engines are not cheap and updates can arrive in bursts after Doze.
        if (running) {
            Log.i(TAG, "nearby check already running, skipping")
            return false
        }

        // Loads libflutter.so; in this process nothing else has. Without it
        // the lookup below is an UnsatisfiedLinkError rather than a null
        // result, and it kills the process.
        //
        // Not extra work: FlutterEngine's constructor makes these same two
        // calls, so startEngine would do it anyway — they only have to happen
        // here as well because the lookup needs the library and runs first.
        // Both are idempotent, and both require the main thread onReceive
        // already runs on.
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context.applicationContext)
        loader.ensureInitializationComplete(context.applicationContext, null)

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(handle)
        if (callbackInfo == null) {
            // Distinct from the handle == 0L bailout above, which is the benign
            // "app has not run yet" case. A handle that is present but does not
            // resolve means the catch-up is permanently dead until the app is
            // opened again, with nothing else to show for it.
            NativeCrashReporter.report(TAG, "callback handle $handle no longer resolves")
            return false
        }

        running = true

        // Engine creation and channel use must happen on the main thread.
        Handler(Looper.getMainLooper()).post {
            startEngine(context, callbackInfo, latitude, longitude)
        }
        return true
    }

    private fun startEngine(
        context: Context,
        callbackInfo: FlutterCallbackInformation,
        latitude: Double,
        longitude: Double,
    ) {
        // Throwable for the same reason as the loader calls in run(): engine
        // creation reaches native code, and an Error escaping here would run
        // past this frame's reset and leave `running` stuck true, silently
        // disabling the check for the life of the process.
        val engine = try {
            FlutterEngine(context.applicationContext)
        } catch (e: Throwable) {
            NativeCrashReporter.report(TAG, "failed to create Flutter engine", e)
            running = false
            return
        }

        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)

        var finished = false
        val handler = Handler(Looper.getMainLooper())

        // Single shutdown path for success, failure and timeout, so the engine
        // can't be destroyed twice or leaked.
        val shutdown = {
            if (!finished) {
                finished = true
                handler.removeCallbacksAndMessages(null)
                try {
                    engine.destroy()
                } catch (e: Throwable) {
                    NativeCrashReporter.report(TAG, "error destroying engine", e)
                }
                running = false
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Dart signals it has initialized and is ready for arguments.
                "ready" -> {
                    result.success(mapOf("latitude" to latitude, "longitude" to longitude))
                }
                // Dart signals the check has finished.
                "done" -> {
                    result.success(null)
                    Log.i(TAG, "nearby check finished")
                    shutdown()
                }
                else -> result.notImplemented()
            }
        }

        handler.postDelayed({
            if (!finished) {
                // The engine booted but Dart never called "done", so the
                // check did not complete. Reported for the same reason as the
                // bailouts: nothing else distinguishes it from a check that
                // ran and found nothing nearby.
                NativeCrashReporter.report(TAG, "nearby check timed out after ${TIMEOUT_MILLIS}ms")
                shutdown()
            }
        }, TIMEOUT_MILLIS)

        engine.dartExecutor.executeDartCallback(
            DartExecutor.DartCallback(
                context.assets,
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                callbackInfo,
            ),
        )
    }
}

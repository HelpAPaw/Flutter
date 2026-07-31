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

        val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(handle)
        if (callbackInfo == null) {
            Log.e(TAG, "callback handle $handle no longer resolves")
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
        val engine = try {
            FlutterEngine(context.applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "failed to create Flutter engine", e)
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
                } catch (e: Exception) {
                    Log.e(TAG, "error destroying engine", e)
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
                Log.w(TAG, "nearby check timed out, tearing down engine")
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

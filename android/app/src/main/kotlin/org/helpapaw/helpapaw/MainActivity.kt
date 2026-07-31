package org.helpapaw.helpapaw

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Resolved once, outside the handler. Referencing `applicationContext`
        // from inside the lambda would capture `this` — the Activity — for the
        // lifetime of the engine. Harmless with the default per-activity
        // engine, but it would leak the Activity the moment a cached engine is
        // introduced, which is exactly the kind of change that looks safe.
        val appContext = applicationContext

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_LOCATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" ->
                    result.success(BackgroundLocationManager.start(appContext))

                "stop" -> {
                    BackgroundLocationManager.stop(appContext)
                    result.success(null)
                }

                // Registers the Dart entrypoint the headless check runs. Stored
                // natively so a background receiver can find it with no engine.
                "registerHeadlessCallback" -> {
                    val handle = call.argument<Any>("handle")
                    if (handle is Number) {
                        HeadlessNearbyCheck.saveCallbackHandle(
                            appContext,
                            handle.toLong(),
                        )
                        result.success(null)
                    } else {
                        result.error(
                            "invalid_handle",
                            "registerHeadlessCallback requires a numeric handle",
                            null,
                        )
                    }
                }

                // Mirrors Dart's test-mode flag so LocationUpdateReceiver can
                // key its pre-filter gate by mode. Pushed on every launch and on
                // every flip; native must never read Dart's own preferences.
                "setTestMode" -> {
                    BackgroundLocationManager.setTestMode(
                        appContext,
                        call.argument<Boolean>("enabled") == true,
                    )
                    result.success(null)
                }

                // Dart mirroring its own nearby-check gate down, so the
                // background pre-filter stops booting an engine for movement
                // Dart has already covered. Best-effort: a dropped call just
                // leaves the native gate more permissive.
                "recordNearbyCheck" -> {
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    if (latitude != null && longitude != null) {
                        LocationUpdateReceiver.recordCheck(appContext, latitude, longitude)
                    }
                    result.success(null)
                }

                // iOS buffers updates that arrive before Dart is ready; Android
                // starts a fresh engine per delivery, so there is nothing held.
                "drainPendingUpdates" -> result.success(null)

                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val BACKGROUND_LOCATION_CHANNEL = "org.helpapaw.helpapaw/background_location"
    }
}

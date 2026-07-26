package org.helpapaw.helpapaw

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_LOCATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" ->
                    result.success(BackgroundLocationManager.start(applicationContext))

                "stop" -> {
                    BackgroundLocationManager.stop(applicationContext)
                    result.success(null)
                }

                "isActive" ->
                    result.success(
                        BackgroundLocationManager.isEnabledInPreferences(applicationContext),
                    )

                // Registers the Dart entrypoint the headless check runs. Stored
                // natively so a background receiver can find it with no engine.
                "registerHeadlessCallback" -> {
                    val handle = call.argument<Any>("handle")
                    if (handle is Number) {
                        HeadlessNearbyCheck.saveCallbackHandle(
                            applicationContext,
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

package org.helpapaw.helpapaw

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority

/**
 * Background location monitoring for Android, without a foreground service.
 *
 * `geolocator` is not usable here: its own documentation notes that its
 * foreground service "does not prevent Android from killing the activity" and
 * that surviving activity destruction needs a separate background package.
 *
 * Instead we register location updates against a [PendingIntent] delivered to
 * [LocationUpdateReceiver]. That needs no foreground service and therefore no
 * permanent notification in the shade, and Android's own background location
 * throttling — a few deliveries per hour for background apps, batched around
 * Doze maintenance windows — makes it behave as the platform's equivalent of
 * iOS significant-change monitoring.
 *
 * Known limit: if the user force-stops the app from Settings, nothing is
 * delivered until they open it again. That is unavoidable without a foreground
 * service.
 */
object BackgroundLocationManager {
    private const val TAG = "BackgroundLocation"

    /**
     * Native-owned state, deliberately *not* shared_preferences.
     *
     * Reading Dart's preferences from Kotlin looks convenient but is a trap:
     * shared_preferences encodes doubles as `VGhpcyBpcyB0aGUgcHJlZml4...`-style
     * prefixed strings rather than floats, and newer versions can store values
     * in Jetpack DataStore instead of this XML file at all. Any of that changing
     * would break us silently. Dart already calls [start]/[stop] over the method
     * channel, so persisting the flag here costs nothing and owns its own format.
     */
    internal const val PREFS_FILE = "helpapaw_background_location"
    private const val ENABLED_KEY = "enabled"
    private const val TEST_MODE_KEY = "test_mode"

    private const val REQUEST_CODE = 4021

    /**
     * Matches `LocationService.distanceFilterMeters`. Against a 10km default
     * notification radius there is no value in finer granularity.
     */
    private const val MIN_DISPLACEMENT_METERS = 500f

    /**
     * Desired interval. Android treats this as a hint and throttles hard in the
     * background, which is exactly the behaviour we want.
     */
    private const val INTERVAL_MILLIS = 15 * 60 * 1000L
    private const val MAX_UPDATE_DELAY_MILLIS = 60 * 60 * 1000L

    fun isEnabledInPreferences(context: Context): Boolean =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getBoolean(ENABLED_KEY, false)

    private fun setEnabledInPreferences(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(ENABLED_KEY, enabled)
            .apply()
    }

    /**
     * Whether the app is in test mode, mirrored here by Dart.
     *
     * A mirror rather than a read of Dart's own preference, for the same reason
     * everything else in this file is native-owned: `shared_preferences` stores
     * doubles as prefixed strings and newer versions may not use the XML file
     * at all, so reading it from Kotlin breaks silently. Dart pushes this on
     * every launch and on every flip, so a missed push heals on the next start.
     *
     * Defaults to false, matching an uninitialized `AppPreferencesService`.
     */
    fun isTestMode(context: Context): Boolean =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .getBoolean(TEST_MODE_KEY, false)

    fun setTestMode(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(TEST_MODE_KEY, enabled)
            .apply()
    }

    /**
     * Whether we hold the permissions needed for *background* delivery.
     *
     * From Android 10 onwards, foreground location alone yields nothing once
     * the app is backgrounded, so this must be checked before claiming success.
     */
    private fun hasBackgroundPermission(context: Context): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

        if (!fine && !coarse) return false

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, LocationUpdateReceiver::class.java).apply {
            action = LocationUpdateReceiver.ACTION_LOCATION_UPDATE
        }

        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Location results are delivered as extras, so the intent must stay
            // mutable.
            flags = flags or PendingIntent.FLAG_MUTABLE
        }

        return PendingIntent.getBroadcast(
            context.applicationContext,
            REQUEST_CODE,
            intent,
            flags,
        )
    }

    /**
     * Registers for updates and remembers that the user wants them.
     *
     * Returns false when permissions are insufficient. The preference is only
     * recorded on success, so a failed start doesn't leave [BootReceiver]
     * trying to re-arm something that can never work.
     */
    fun start(context: Context): Boolean {
        if (!hasBackgroundPermission(context)) {
            Log.w(TAG, "background location permission missing, not starting")
            return false
        }

        val request = LocationRequest.Builder(
            Priority.PRIORITY_BALANCED_POWER_ACCURACY,
            INTERVAL_MILLIS,
        )
            .setMinUpdateDistanceMeters(MIN_DISPLACEMENT_METERS)
            // Let the OS batch deliveries so it can align them with times the
            // device is already awake.
            .setMaxUpdateDelayMillis(MAX_UPDATE_DELAY_MILLIS)
            .setWaitForAccurateLocation(false)
            .build()

        return try {
            LocationServices.getFusedLocationProviderClient(context.applicationContext)
                .requestLocationUpdates(request, pendingIntent(context))
            setEnabledInPreferences(context, true)
            LocationReconcileWorker.schedule(context.applicationContext)
            Log.i(TAG, "location updates registered")
            true
        } catch (e: SecurityException) {
            Log.e(TAG, "permission denied registering location updates", e)
            false
        } catch (e: Exception) {
            Log.e(TAG, "failed to register location updates", e)
            false
        }
    }

    fun stop(context: Context) {
        // Recorded before the removal call so a thrown exception can't leave the
        // flag set and have BootReceiver silently resurrect tracking the user
        // just turned off.
        setEnabledInPreferences(context, false)
        LocationReconcileWorker.cancel(context.applicationContext)
        try {
            LocationServices.getFusedLocationProviderClient(context.applicationContext)
                .removeLocationUpdates(pendingIntent(context))
            Log.i(TAG, "location updates removed")
        } catch (e: Exception) {
            Log.e(TAG, "failed to remove location updates", e)
        }
    }

    /**
     * Re-registers if the user has the feature enabled.
     *
     * Registration does not survive a reboot, an app update, or an OEM battery
     * manager deciding to clean it up, so this is called from
     * [BootReceiver] and on every app start.
     */
    fun restoreIfEnabled(context: Context): Boolean {
        if (!isEnabledInPreferences(context)) return false
        return start(context)
    }
}

package org.helpapaw.helpapaw

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationResult
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.GeoPoint
import com.google.firebase.firestore.SetOptions

/**
 * Receives background location updates from [BackgroundLocationManager].
 *
 * Two jobs, deliberately separated by cost:
 *
 *  1. Write `userLocations/{uid}` natively. Cheap, and must always happen — the
 *     notification fan-out reads this to decide who is near a new signal. Doing
 *     it in Kotlin means it does not depend on a Dart engine existing.
 *  2. Run the arrival catch-up check, which needs Dart. Booting a Flutter
 *     engine is expensive, so it only happens when the check would actually do
 *     something (see [shouldRunNearbyCheck]).
 */
class LocationUpdateReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_LOCATION_UPDATE) return

        // FusedLocationProviderClient delivers two kinds of broadcast to the
        // same PendingIntent: location results, and location *availability*
        // changes. Availability broadcasts legitimately carry no location, and
        // on a real device they are frequent — treating them as failures buries
        // the genuine ones in noise.
        val location = LocationResult.extractResult(intent)?.lastLocation
        if (location == null) {
            if (LocationAvailability.hasLocationAvailability(intent)) {
                val available =
                    LocationAvailability.extractLocationAvailability(intent)?.isLocationAvailable
                Log.d(TAG, "location availability changed: available=$available")
            } else {
                Log.w(TAG, "broadcast carried neither a location nor availability")
            }
            return
        }

        // The Firestore write is asynchronous, so hold the broadcast open —
        // otherwise the process can be killed mid-write.
        val pendingResult = goAsync()
        val handler = Handler(Looper.getMainLooper())
        val finished = AtomicBoolean(false)
        val release = {
            if (finished.compareAndSet(false, true)) {
                handler.removeCallbacksAndMessages(null)
                pendingResult.finish()
            }
        }

        // Firestore's set() Task only resolves once the *server* acknowledges
        // the write. Offline the write is already durable in the local cache,
        // but the Task can stay pending indefinitely — and for a background
        // location feature poor connectivity is normal, not an edge case.
        // Holding a broadcast open that long risks an ANR, so cap the wait.
        handler.postDelayed({
            Log.w(TAG, "location write has not been acknowledged; releasing broadcast")
            release()
        }, WRITE_ACK_TIMEOUT_MILLIS)

        // Started independently of the write: offline the write may never be
        // acknowledged, but the catch-up check can still run against Firestore's
        // local cache, so it must not be chained to that completion.
        try {
            maybeRunNearbyCheck(context, location)
        } catch (e: Exception) {
            Log.e(TAG, "nearby check failed to start", e)
        }

        writeLocation(context, location) { release() }
    }

    /**
     * Writes the position in the same document shape the Dart path writes,
     * including the precision-9 geohash the fan-out's range query depends on.
     *
     * The uid comes from the persisted Firebase Auth session, which survives
     * process death. Firebase auto-initializes on Android through its
     * ContentProvider, so this works in a receiver with no Activity.
     */
    private fun writeLocation(context: Context, location: Location, onComplete: () -> Unit) {
        val uid = try {
            FirebaseAuth.getInstance().currentUser?.uid
        } catch (e: Exception) {
            Log.e(TAG, "Firebase Auth unavailable", e)
            null
        }

        if (uid == null) {
            Log.w(TAG, "no signed-in user, skipping write")
            onComplete()
            return
        }

        val geohash = Geohash.encode(location.latitude, location.longitude)

        val data = mapOf(
            "geopoint" to GeoPoint(location.latitude, location.longitude),
            "geohash" to geohash,
            "updatedAt" to FieldValue.serverTimestamp(),
        )

        FirebaseFirestore.getInstance()
            .collection("userLocations")
            .document(uid)
            .set(data, SetOptions.merge())
            .addOnSuccessListener { Log.i(TAG, "wrote location (geohash $geohash)") }
            .addOnFailureListener { e -> Log.e(TAG, "location write failed", e) }
            .addOnCompleteListener { onComplete() }
    }

    /**
     * Applies the pre-filter and, if it passes, starts the check.
     *
     * The attempt is recorded only once [HeadlessNearbyCheck.run] confirms it
     * actually started one. Recording unconditionally would mean a bailout —
     * no Dart entrypoint registered yet, or a check already in flight — spent
     * the 30-minute window on a check that never happened, so the next real
     * opportunity would be rejected by a gate advanced on nothing.
     */
    private fun maybeRunNearbyCheck(context: Context, location: Location) {
        val prefs = context.getSharedPreferences(
            BackgroundLocationManager.PREFS_FILE,
            Context.MODE_PRIVATE,
        )

        // Namespaced per mode, matching the Dart gate and NotifiedSignalsStore.
        // Without this a flip into test mode kept the pre-flip timestamp here,
        // so no engine was booted for up to 30 minutes and test signals looked
        // like they produced no catch-up notification at all — while the Dart
        // gate, being namespaced, had already reset. Flipping back now restores
        // the real gate instead of destroying it.
        val suffix = if (BackgroundLocationManager.isTestMode(context)) "_test" else ""

        if (!gateAllows(prefs, location, suffix)) return

        if (HeadlessNearbyCheck.run(context, location.latitude, location.longitude)) {
            recordCheck(prefs, location, suffix)
        }
    }

    /**
     * Cheap pre-filter mirroring the Dart gate, so we don't boot a Flutter
     * engine for movement that would be rejected anyway.
     *
     * This tracks its own state rather than reading the Dart gate's values.
     * shared_preferences encodes doubles as prefixed *strings* and newer
     * versions may not use the XML file at all, so reading them from Kotlin
     * would be a silent-breakage risk for a saving of a few lines. Dart applies
     * the real gate again on the other side and stays authoritative; this only
     * decides whether the expensive path is worth entering.
     */
    private fun gateAllows(
        prefs: android.content.SharedPreferences,
        location: Location,
        suffix: String,
    ): Boolean {
        val lastAt = prefs.getLong(LAST_CHECK_AT_KEY + suffix, 0L)
        val lastLat = prefs.getFloat(LAST_CHECK_LAT_KEY + suffix, Float.NaN).toDouble()
        val lastLon = prefs.getFloat(LAST_CHECK_LON_KEY + suffix, Float.NaN).toDouble()

        // No usable previous check (first run, or a partially written record):
        // fall through and let it run.
        if (lastAt == 0L || lastLat.isNaN() || lastLon.isNaN()) return true

        val elapsedMinutes = (System.currentTimeMillis() - lastAt) / 60_000.0
        if (elapsedMinutes < MIN_INTERVAL_MINUTES) return false

        return distanceKm(lastLat, lastLon, location.latitude, location.longitude) >=
            MIN_DISPLACEMENT_KM
    }

    /**
     * Records the attempt as the check starts, so a failure partway through
     * can't let the next update immediately retry and boot another engine.
     *
     * Float is plenty here: this only feeds a 3km threshold comparison.
     */
    private fun recordCheck(
        prefs: android.content.SharedPreferences,
        location: Location,
        suffix: String,
    ) {
        prefs.edit()
            .putFloat(LAST_CHECK_LAT_KEY + suffix, location.latitude.toFloat())
            .putFloat(LAST_CHECK_LON_KEY + suffix, location.longitude.toFloat())
            .putLong(LAST_CHECK_AT_KEY + suffix, System.currentTimeMillis())
            .apply()
    }

    /**
     * Uses the platform's WGS84 implementation rather than a hand-rolled
     * spherical haversine, so this agrees with the Dart gate near the threshold
     * and there is no trigonometry here to keep correct.
     */
    private fun distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val results = FloatArray(1)
        Location.distanceBetween(lat1, lon1, lat2, lon2, results)
        return results[0] / 1000.0
    }

    companion object {
        private const val TAG = "BackgroundLocation"

        const val ACTION_LOCATION_UPDATE = "org.helpapaw.helpapaw.LOCATION_UPDATE"

        // Native-owned mirror of the Dart gate; see shouldRunNearbyCheck.
        private const val LAST_CHECK_LAT_KEY = "last_check_lat"
        private const val LAST_CHECK_LON_KEY = "last_check_lon"
        private const val LAST_CHECK_AT_KEY = "last_check_at"

        private const val MIN_DISPLACEMENT_KM = 3.0
        private const val MIN_INTERVAL_MINUTES = 30.0

        /**
         * Cap on holding the broadcast open. Comfortably under the ~10s the
         * system allows a foreground broadcast before it counts as an ANR.
         */
        private const val WRITE_ACK_TIMEOUT_MILLIS = 8_000L
    }
}

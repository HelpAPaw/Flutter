package org.helpapaw.helpapaw

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.util.Log
import com.google.android.gms.location.LocationResult
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.GeoPoint
import com.google.firebase.firestore.SetOptions
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

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

        val location = LocationResult.extractResult(intent)?.lastLocation
        if (location == null) {
            Log.w(TAG, "broadcast carried no location")
            return
        }

        // The Firestore write and any engine work are asynchronous, so hold the
        // broadcast open — otherwise the process can be killed mid-write.
        val pendingResult = goAsync()

        writeLocation(context, location) {
            try {
                if (shouldRunNearbyCheck(context, location)) {
                    HeadlessNearbyCheck.run(context, location.latitude, location.longitude)
                }
            } catch (e: Exception) {
                Log.e(TAG, "nearby check failed to start", e)
            } finally {
                pendingResult.finish()
            }
        }
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
    private fun shouldRunNearbyCheck(context: Context, location: Location): Boolean {
        val prefs = context.getSharedPreferences(
            BackgroundLocationManager.PREFS_FILE,
            Context.MODE_PRIVATE,
        )

        if (!prefs.contains(LAST_CHECK_AT_KEY)) {
            recordCheck(prefs, location)
            return true
        }

        val lastAt = prefs.getLong(LAST_CHECK_AT_KEY, 0L)
        val elapsedMinutes = (System.currentTimeMillis() - lastAt) / 60_000.0
        if (elapsedMinutes < MIN_INTERVAL_MINUTES) return false

        val lastLat = prefs.getFloat(LAST_CHECK_LAT_KEY, Float.NaN).toDouble()
        val lastLon = prefs.getFloat(LAST_CHECK_LON_KEY, Float.NaN).toDouble()
        if (lastLat.isNaN() || lastLon.isNaN()) {
            recordCheck(prefs, location)
            return true
        }

        val movedKm = distanceKm(lastLat, lastLon, location.latitude, location.longitude)
        if (movedKm < MIN_DISPLACEMENT_KM) return false

        recordCheck(prefs, location)
        return true
    }

    /**
     * Records the attempt before the check runs, so a failure partway through
     * can't let the next update immediately retry and boot another engine.
     *
     * Float is plenty here: this only feeds a 3km threshold comparison.
     */
    private fun recordCheck(prefs: android.content.SharedPreferences, location: Location) {
        prefs.edit()
            .putFloat(LAST_CHECK_LAT_KEY, location.latitude.toFloat())
            .putFloat(LAST_CHECK_LON_KEY, location.longitude.toFloat())
            .putLong(LAST_CHECK_AT_KEY, System.currentTimeMillis())
            .apply()
    }

    private fun distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadiusKm = 6371.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
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
    }
}

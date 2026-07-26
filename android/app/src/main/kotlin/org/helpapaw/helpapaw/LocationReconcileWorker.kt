package org.helpapaw.helpapaw

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Periodically re-registers background location updates.
 *
 * [BootReceiver] covers reboots and app updates, and `LocationService.initialize`
 * covers app launches, but none of that helps a user who enables tracking and
 * then never opens the app again. Registrations can still be dropped underneath
 * us — most often by an OEM battery manager, which Xiaomi, Huawei and Samsung
 * are all prone to.
 *
 * `requestLocationUpdates` is idempotent for a given PendingIntent, so re-arming
 * an already-live registration is harmless. That makes a blind periodic re-arm
 * the simplest thing that works.
 *
 * This is a safety net, not the delivery mechanism. WorkManager's minimum period
 * is 15 minutes and it is heavily suppressed in Doze, which is exactly why the
 * PendingIntent path carries the actual location updates.
 */
class LocationReconcileWorker(
    context: Context,
    params: WorkerParameters,
) : Worker(context, params) {

    override fun doWork(): Result {
        if (!BackgroundLocationManager.isEnabledInPreferences(applicationContext)) {
            // The user turned tracking off; stop rescheduling ourselves.
            cancel(applicationContext)
            return Result.success()
        }

        val restored = BackgroundLocationManager.start(applicationContext)
        Log.i(TAG, if (restored) "reconciled location updates" else "reconcile skipped")

        // Failing here would trigger WorkManager's backoff for something that is
        // only ever best-effort, so a failed re-arm is still reported as success.
        return Result.success()
    }

    companion object {
        private const val TAG = "BackgroundLocation"
        private const val WORK_NAME = "helpapaw_location_reconcile"

        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<LocationReconcileWorker>(
                6,
                TimeUnit.HOURS,
            )
                .setConstraints(
                    Constraints.Builder()
                        // No network or power requirements: re-arming is local
                        // and cheap, and waiting for ideal conditions would
                        // defeat the point of a safety net.
                        .setRequiresBatteryNotLow(false)
                        .build(),
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                // KEEP, so re-scheduling on every launch doesn't reset the
                // interval and effectively never run.
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}

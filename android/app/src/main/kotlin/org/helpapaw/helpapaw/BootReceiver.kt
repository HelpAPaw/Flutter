package org.helpapaw.helpapaw

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Re-arms background location monitoring after a reboot.
 *
 * Location update registrations do not survive a restart, and nothing else
 * would re-create them until the user next opened the app — which for a
 * notification feature could be days. The `RECEIVE_BOOT_COMPLETED` permission
 * was already declared in the manifest but unused before this.
 *
 * Runs with no Flutter engine, which is why [BackgroundLocationManager] keeps
 * its enabled flag in native storage rather than reading Dart's preferences.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }

        val restored = BackgroundLocationManager.restoreIfEnabled(context)
        Log.i(
            TAG,
            if (restored) {
                "re-armed location updates after $action"
            } else {
                "not re-arming after $action (disabled or permission missing)"
            },
        )
    }

    private companion object {
        const val TAG = "BackgroundLocation"
    }
}

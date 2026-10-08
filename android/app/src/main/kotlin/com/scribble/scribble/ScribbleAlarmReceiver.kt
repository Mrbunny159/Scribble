package com.scribble.scribble

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

class ScribbleAlarmReceiver : BroadcastReceiver() {
    private val TAG = "ScribbleAlarmReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val wakeLock = powerManager?.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "Scribble:AlarmReceiverWakeLock"
        )
        wakeLock?.acquire(15000L) // Hold wake lock for up to 15 seconds for sync to complete

        try {
            Log.d(TAG, "Doze-breaker alarm pulse received, triggering sync pulse")
            ScribbleSyncService.triggerSyncPulse(context)
        } catch (e: Exception) {
            Log.e(TAG, "Error handling sync alarm pulse: ${e.message}")
        } finally {
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock.release()
                }
            } catch (_: Exception) {}
        }
    }
}

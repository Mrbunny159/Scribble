package com.scribble.scribble

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    private val TAG = "BootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.i(TAG, "Received system broadcast: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == "android.intent.action.QUICKBOOT_POWERON") {

            val prefs = context.getSharedPreferences("ScribbleSyncPrefs", Context.MODE_PRIVATE)
            val connectionId = prefs.getString("connectionId", null)
            val projectId = prefs.getString("projectId", "scribble-6d33a") ?: "scribble-6d33a"
            val myUserId = prefs.getString("myUserId", "") ?: ""

            if (!connectionId.isNullOrEmpty()) {
                Log.i(TAG, "Resuming ScribbleSyncService on device boot for connection: $connectionId")
                ScribbleSyncService.startService(context, projectId, connectionId, myUserId)
            }
        }
    }
}

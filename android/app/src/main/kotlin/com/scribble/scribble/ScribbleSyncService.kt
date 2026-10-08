package com.scribble.scribble

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

class ScribbleSyncService : Service() {
    private val TAG = "ScribbleSyncService"
    private val CHANNEL_ID = "scribble_sync_foreground_channel"
    private val NOTIF_ID = 2001

    private var executor: ScheduledExecutorService? = null
    private var isRunning = false
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        const val ACTION_START = "com.scribble.app.START_SYNC"
        const val ACTION_STOP = "com.scribble.app.STOP_SYNC"
        const val ACTION_PULSE = "com.scribble.app.SYNC_PULSE"

        private var instance: ScribbleSyncService? = null

        fun startService(context: Context, projectId: String, connectionId: String, myUserId: String, partnerName: String = "Partner") {
            val intent = Intent(context, ScribbleSyncService::class.java).apply {
                action = ACTION_START
                putExtra("projectId", projectId)
                putExtra("connectionId", connectionId)
                putExtra("myUserId", myUserId)
                putExtra("partnerName", partnerName)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e("ScribbleSyncService", "Failed to start foreground service: ${e.message}")
            }
        }

        fun stopService(context: Context) {
            cancelAlarmPulse(context)
            val intent = Intent(context, ScribbleSyncService::class.java).apply {
                action = ACTION_STOP
            }
            try {
                context.stopService(intent)
            } catch (e: Exception) {
                Log.e("ScribbleSyncService", "Failed to stop foreground service: ${e.message}")
            }
        }

        fun triggerSyncPulse(context: Context) {
            if (instance != null && instance?.isRunning == true) {
                instance?.pollForNewScribbleAsync()
            } else {
                val intent = Intent(context, ScribbleSyncService::class.java).apply {
                    action = ACTION_PULSE
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (e: Exception) {
                    Log.e("ScribbleSyncService", "Error triggering pulse: ${e.message}")
                }
            }
        }

        private fun scheduleAlarmPulse(context: Context, delayMillis: Long = 15000L) {
            try {
                val intent = Intent(context, ScribbleAlarmReceiver::class.java).apply {
                    action = ACTION_PULSE
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context, 2004, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
                val triggerAtMillis = SystemClock.elapsedRealtime() + delayMillis

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAtMillis, pendingIntent)
                } else {
                    alarmManager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAtMillis, pendingIntent)
                }
            } catch (e: Exception) {
                Log.e("ScribbleSyncService", "Failed to schedule alarm pulse: ${e.message}")
            }
        }

        private fun cancelAlarmPulse(context: Context) {
            try {
                val intent = Intent(context, ScribbleAlarmReceiver::class.java).apply {
                    action = ACTION_PULSE
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context, 2004, intent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )
                if (pendingIntent != null) {
                    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
                    alarmManager?.cancel(pendingIntent)
                    pendingIntent.cancel()
                }
            } catch (_: Exception) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
        acquireServiceWakeLock()
    }

    private fun acquireServiceWakeLock() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
            wakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Scribble:SyncServiceWakeLock")
            wakeLock?.setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        val action = intent?.action ?: ACTION_START

        if (action == ACTION_STOP) {
            stopPolling()
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        val prefs = getSharedPreferences("ScribbleSyncPrefs", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        intent?.getStringExtra("projectId")?.let { editor.putString("projectId", it) }
        intent?.getStringExtra("connectionId")?.let { editor.putString("connectionId", it) }
        intent?.getStringExtra("myUserId")?.let { editor.putString("myUserId", it) }
        intent?.getStringExtra("partnerName")?.let { editor.putString("partnerName", it) }
        editor.apply()

        startForegroundNotification()
        startPolling()

        if (action == ACTION_PULSE) {
            pollForNewScribbleAsync()
        }

        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Scribble Background Sync",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps scribble lock-screen synchronization active when phone is locked"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        val notification = builder
            .setContentTitle("Scribble Live Active")
            .setContentText("Listening for live notes from your partner")
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)
    }

    private fun startPolling() {
        if (isRunning) return
        isRunning = true
        executor = Executors.newSingleThreadScheduledExecutor()

        // Fast periodic poll every 10 seconds while CPU is active
        executor?.scheduleWithFixedDelay({
            try {
                pollForNewScribble()
            } catch (e: Exception) {
                Log.e(TAG, "Error in background poll: ${e.message}")
            }
        }, 1, 10, TimeUnit.SECONDS)

        // Also schedule Doze-breaker alarm pulse
        scheduleAlarmPulse(applicationContext, 15000L)
    }

    fun pollForNewScribbleAsync() {
        executor?.execute {
            try {
                pollForNewScribble()
            } catch (e: Exception) {
                Log.e(TAG, "Error in async poll: ${e.message}")
            }
        } ?: run {
            Thread {
                try {
                    pollForNewScribble()
                } catch (e: Exception) {
                    Log.e(TAG, "Error in thread poll: ${e.message}")
                }
            }.start()
        }
    }

    private fun stopPolling() {
        isRunning = false
        executor?.shutdownNow()
        executor = null
        cancelAlarmPulse(applicationContext)
    }

    private fun pollForNewScribble() {
        try {
            wakeLock?.acquire(8000L) // Guarantee CPU stays awake during network request
        } catch (_: Exception) {}

        try {
            val prefs = getSharedPreferences("ScribbleSyncPrefs", Context.MODE_PRIVATE)
            val projectId = prefs.getString("projectId", "scribble-6d33a") ?: "scribble-6d33a"
            val connectionId = prefs.getString("connectionId", null) ?: return
            val myUserId = prefs.getString("myUserId", null) ?: ""
            val storedPartnerName = prefs.getString("partnerName", "Partner") ?: "Partner"

            val endpoint = "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents/scribbles/$connectionId"
            val url = URL(endpoint)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "GET"
            conn.setRequestProperty("Accept", "application/json")
            conn.connectTimeout = 8000
            conn.readTimeout = 8000

            if (conn.responseCode == 200) {
                val responseText = conn.inputStream.bufferedReader().use { it.readText() }
                val doc = JSONObject(responseText)
                val fields = doc.optJSONObject("fields")
                if (fields != null) {
                    val senderId = fields.optJSONObject("sender_id")?.optString("stringValue", "") ?: ""
                    val imageUrl = fields.optJSONObject("image_url")?.optString("stringValue", "") ?: ""
                    val updatedAt = fields.optJSONObject("updated_at")?.optString("stringValue", "") ?: doc.optString("updateTime", "")
                    val isCleared = fields.optJSONObject("is_cleared")?.optBoolean("booleanValue", false) ?: false
                    val senderName = fields.optJSONObject("sender_name")?.optString("stringValue", storedPartnerName) ?: storedPartnerName

                    val lastSyncTime = prefs.getString("lastSyncTime", "")

                    // Only update when partner sends an updated scribble
                    if (senderId.isNotEmpty() && senderId != myUserId && updatedAt != lastSyncTime) {
                        Log.i(TAG, "New partner scribble detected! Sender: $senderName, Updated at: $updatedAt")
                        prefs.edit().putString("lastSyncTime", updatedAt).apply()

                        if (isCleared || imageUrl.isEmpty() || imageUrl == "null") {
                            val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                            nm?.cancel(1001)
                            ScribbleWidgetProvider.updateAllWidgets(applicationContext, null, senderName)
                        } else {
                            downloadAndDisplayScribbleOverlay(imageUrl, senderName)
                        }
                    }
                }
            }
            conn.disconnect()
        } catch (e: Exception) {
            Log.e(TAG, "pollForNewScribble error: ${e.message}")
        } finally {
            // Schedule next Doze-breaker alarm pulse
            scheduleAlarmPulse(applicationContext, 15000L)
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
            } catch (_: Exception) {}
        }
    }

    private fun downloadAndDisplayScribbleOverlay(imageUrl: String, senderName: String) {
        try {
            val bitmap: Bitmap? = if (imageUrl.startsWith("data:image")) {
                val pureBase64 = if (imageUrl.contains(",")) imageUrl.substringAfter(",") else imageUrl
                val decodedBytes = Base64.decode(pureBase64, Base64.DEFAULT)
                BitmapFactory.decodeByteArray(decodedBytes, 0, decodedBytes.size)
            } else {
                val url = URL(imageUrl)
                val conn = url.openConnection() as HttpURLConnection
                conn.connectTimeout = 12000
                conn.readTimeout = 12000
                if (conn.responseCode == 200) {
                    val stream = conn.inputStream
                    val b = BitmapFactory.decodeStream(stream)
                    conn.disconnect()
                    b
                } else {
                    conn.disconnect()
                    null
                }
            }

            if (bitmap != null) {
                Log.i(TAG, "Displaying lock screen overlay & widget for $senderName!")

                // 1. Persist latest bitmap to cache
                try {
                    val file = File(cacheDir, "latest_overlay.png")
                    FileOutputStream(file).use { out ->
                        bitmap.compress(Bitmap.CompressFormat.PNG, 95, out)
                    }
                } catch (_: Exception) {}

                // 2. Launch overlay activity (will display over lock screen)
                LockscreenOverlayActivity.showOverlay(applicationContext, bitmap, senderName)

                // 3. Post full-screen notification to wake screen & pop overlay on lock screen
                MainActivity.showScribbleNotification(
                    applicationContext,
                    "New Note from $senderName! 🎨",
                    "$senderName drew a new note for your lock screen.",
                    bitmap,
                    senderName
                )

                // 4. Glow / Wake up the screen
                MainActivity.wakeUpScreen(applicationContext)

                // 5. Update Android Home Screen Widgets immediately!
                ScribbleWidgetProvider.updateAllWidgets(applicationContext, bitmap, senderName)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to display scribble overlay: ${e.message}")
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val prefs = getSharedPreferences("ScribbleSyncPrefs", Context.MODE_PRIVATE)
        val connectionId = prefs.getString("connectionId", null)
        if (!connectionId.isNullOrEmpty()) {
            val restartIntent = Intent(applicationContext, ScribbleSyncService::class.java).apply {
                action = ACTION_START
                putExtra("projectId", prefs.getString("projectId", "scribble-6d33a"))
                putExtra("connectionId", connectionId)
                putExtra("myUserId", prefs.getString("myUserId", ""))
                putExtra("partnerName", prefs.getString("partnerName", "Partner"))
            }
            val pendingIntent = PendingIntent.getService(
                applicationContext, 2002, restartIntent,
                PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as? AlarmManager
            alarmManager?.set(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 1500,
                pendingIntent
            )
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        stopPolling()
        instance = null
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}

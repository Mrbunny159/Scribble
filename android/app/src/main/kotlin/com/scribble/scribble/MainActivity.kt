package com.scribble.scribble

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.WallpaperManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.DisplayMetrics
import android.content.ContentValues
import android.media.MediaScannerConnection
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.scribble.app/lockscreen"

    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "scribble_lockscreen_channel"

        /**
         * Wakes up the screen and turns on the display for 3 seconds so incoming scribbles glow immediately
         */
        fun wakeUpScreen(context: Context) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
                @Suppress("DEPRECATION")
                val wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                    "Scribble:ScreenGlowWakeLock"
                )
                wakeLock.acquire(3000L) // Light up screen for 3 seconds
            } catch (e: Exception) {
                android.util.Log.e("Scribble", "Failed to wake screen: ${e.message}")
            }
        }

        /**
         * Shows a heads-up notification with high priority, BigPictureStyle, and FullScreenIntent
         * to automatically pop the scribble card onto the lock screen even when the phone is locked.
         */
        fun showScribbleNotification(context: Context, title: String, message: String, bitmap: Bitmap? = null, senderName: String = "Partner") {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val channel = NotificationChannel(
                        NOTIFICATION_CHANNEL_ID,
                        "Incoming Scribbles",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Notifies and displays note on the lock screen when a partner sends a scribble"
                        enableVibration(true)
                        setShowBadge(true)
                        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    }
                    notificationManager.createNotificationChannel(channel)
                }

                val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                val pendingIntent = android.app.PendingIntent.getActivity(
                    context, 0, launchIntent,
                    android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                )

                // FULL SCREEN INTENT: Pops LockscreenOverlayActivity directly over the lock screen without opening app!
                val fullScreenIntent = Intent(context, LockscreenOverlayActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                    putExtra("senderName", senderName)
                }
                val fullScreenPendingIntent = android.app.PendingIntent.getActivity(
                    context, 1002, fullScreenIntent,
                    android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT
                )

                val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
                } else {
                    @Suppress("DEPRECATION")
                    Notification.Builder(context)
                }

                notificationBuilder
                    .setContentTitle(title)
                    .setContentText(message)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentIntent(pendingIntent)
                    .setFullScreenIntent(fullScreenPendingIntent, true)
                    .setAutoCancel(true)
                    .setPriority(Notification.PRIORITY_MAX)
                    .setDefaults(Notification.DEFAULT_ALL)
                    .setVisibility(Notification.VISIBILITY_PUBLIC)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    notificationBuilder.setCategory(Notification.CATEGORY_CALL)
                }

                if (bitmap != null) {
                    notificationBuilder.setStyle(
                        Notification.BigPictureStyle().bigPicture(bitmap).setSummaryText(message)
                    )
                }

                notificationManager.notify(1001, notificationBuilder.build())
            } catch (e: Exception) {
                android.util.Log.e("Scribble", "Notification error: ${e.message}")
            }
        }

        /**
         * Composites the scribble image onto a sleek ambient dark background formatted
         * dynamically for the user's specific screen resolution and sets the wallpaper.
         */
        fun applyScribbleToLockscreen(context: Context, scribbleBitmap: Bitmap): Map<String, Any> {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                return mapOf("success" to false, "error" to "Android version below Nougat (API 24)")
            }

            val wallpaperManager = WallpaperManager.getInstance(context)
            if (!wallpaperManager.isSetWallpaperAllowed) {
                return mapOf("success" to false, "error" to "Changing wallpaper is restricted by device policy")
            }

            // Get actual physical display metrics
            val dm = context.resources.displayMetrics
            val screenWidth = dm.widthPixels
            val screenHeight = dm.heightPixels

            // Create target full-resolution lockscreen bitmap matching the device screen
            val lockscreenBitmap = Bitmap.createBitmap(screenWidth, screenHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(lockscreenBitmap)

            // Draw deep ambient dark background (#0C0E14)
            canvas.drawColor(Color.parseColor("#0C0E14"))

            // Position scribble safely in the middle section of the screen
            // leaving space for Android's system clock/date widget at top (24%) and bottom unlock/fingerprint area (14%)
            val topOffset = (screenHeight * 0.24f).toInt()
            val bottomOffset = (screenHeight * 0.14f).toInt()
            val horizontalPadding = (screenWidth * 0.07f).toInt()

            val targetWidth = screenWidth - (horizontalPadding * 2)
            val targetHeight = screenHeight - topOffset - bottomOffset

            val srcWidth = scribbleBitmap.width
            val srcHeight = scribbleBitmap.height

            // Calculate aspect-fit scaling
            val scale = Math.min(
                targetWidth.toFloat() / srcWidth.toFloat(),
                targetHeight.toFloat() / srcHeight.toFloat()
            )

            val drawWidth = (srcWidth * scale).toInt()
            val drawHeight = (srcHeight * scale).toInt()

            val left = (screenWidth - drawWidth) / 2f
            val top = (topOffset + (targetHeight - drawHeight) / 2).toFloat()
            val right = left + drawWidth
            val bottom = top + drawHeight

            val cardRect = RectF(left, top, right, bottom)
            val cornerRadius = 32f

            // Clip rounded rectangle for the scribble card so edges curve softly
            val clipPath = Path().apply {
                addRoundRect(cardRect, cornerRadius, cornerRadius, Path.Direction.CW)
            }

            canvas.save()
            canvas.clipPath(clipPath)

            val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
            val destRect = Rect(left.toInt(), top.toInt(), right.toInt(), bottom.toInt())
            canvas.drawBitmap(scribbleBitmap, null, destRect, paint)

            canvas.restore()

            // Draw subtle outline around the card
            val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                color = Color.parseColor("#33FFFFFF")
                strokeWidth = 2f
            }
            canvas.drawRoundRect(cardRect, cornerRadius, cornerRadius, borderPaint)

            var applied = false
            var appliedFlag = "NONE"

            // Strategy 1: Attempt to set Lock Screen Wallpaper ONLY (FLAG_LOCK)
            try {
                val result = wallpaperManager.setBitmap(lockscreenBitmap, null, true, WallpaperManager.FLAG_LOCK)
                applied = (result > 0 || Build.VERSION.SDK_INT < Build.VERSION_CODES.N)
                appliedFlag = "FLAG_LOCK"
            } catch (e: Exception) {
                android.util.Log.w("Scribble", "FLAG_LOCK failed (${e.message}), attempting fallback to BOTH...")
            }

            // Strategy 2: If FLAG_LOCK alone failed or was rejected by OEM (e.g. Xiaomi, Samsung OneUI, ColorOS)
            if (!applied) {
                try {
                    wallpaperManager.setBitmap(lockscreenBitmap, null, true, WallpaperManager.FLAG_LOCK or WallpaperManager.FLAG_SYSTEM)
                    applied = true
                    appliedFlag = "FLAG_LOCK_AND_SYSTEM"
                } catch (e: Exception) {
                    android.util.Log.e("Scribble", "Failed to apply wallpaper with both flags: ${e.message}")
                    return mapOf("success" to false, "error" to (e.localizedMessage ?: "Failed to set wallpaper"))
                }
            }

            // Clean up memory
            scribbleBitmap.recycle()
            lockscreenBitmap.recycle()

            // Glow / Wake Up screen when scribble is successfully applied!
            wakeUpScreen(context)

            return mapOf(
                "success" to true,
                "appliedFlag" to appliedFlag
            )
        }

        /**
         * Resets lockscreen to a minimal clean ambient dark background
         */
        fun clearLockscreenWallpaper(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                return false
            }

            val wallpaperManager = WallpaperManager.getInstance(context)
            if (!wallpaperManager.isSetWallpaperAllowed) {
                return false
            }

            val dm = context.resources.displayMetrics
            val screenWidth = dm.widthPixels
            val screenHeight = dm.heightPixels

            val cleanBitmap = Bitmap.createBitmap(screenWidth, screenHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(cleanBitmap)
            canvas.drawColor(Color.parseColor("#0C0E14"))

            try {
                wallpaperManager.setBitmap(cleanBitmap, null, true, WallpaperManager.FLAG_LOCK)
            } catch (e: Exception) {
                wallpaperManager.setBitmap(cleanBitmap, null, true, WallpaperManager.FLAG_LOCK or WallpaperManager.FLAG_SYSTEM)
            }
            cleanBitmap.recycle()

            return true
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    val supported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        val wm = WallpaperManager.getInstance(applicationContext)
                        wm.isSetWallpaperAllowed && wm.isWallpaperSupported
                    } else {
                        false
                    }
                    result.success(supported)
                }

                "isIgnoringBatteryOptimizations" -> {
                    val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    val isIgnored = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && pm != null) {
                        pm.isIgnoringBatteryOptimizations(packageName)
                    } else {
                        true
                    }
                    result.success(isIgnored)
                }

                "requestIgnoreBatteryOptimization" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                }

                "openNotificationSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("INTENT_ERROR", e.localizedMessage, null)
                    }
                }

                "wakeUpScreen" -> {
                    wakeUpScreen(applicationContext)
                    result.success(true)
                }

                "getLaunchExtras" -> {
                    val openCanvas = intent?.getBooleanExtra("openCanvas", false) ?: false
                    intent?.removeExtra("openCanvas")
                    result.success(mapOf("openCanvas" to openCanvas))
                }

                "notifyScribble" -> {
                    val senderName = call.argument<String>("senderName") ?: "Partner"
                    showScribbleNotification(
                        applicationContext,
                        "New Note from $senderName! 🎨",
                        "$senderName drew a new note for your lock screen.",
                        null,
                        senderName
                    )
                    wakeUpScreen(applicationContext)
                    result.success(true)
                }

                "startBackgroundSync" -> {
                    val projectId = call.argument<String>("projectId") ?: "scribble-6d33a"
                    val connectionId = call.argument<String>("connectionId") ?: ""
                    val myUserId = call.argument<String>("myUserId") ?: ""
                    val partnerName = call.argument<String>("partnerName") ?: "Partner"

                    ScribbleSyncService.startService(applicationContext, projectId, connectionId, myUserId, partnerName)
                    result.success(true)
                }

                "stopBackgroundSync" -> {
                    ScribbleSyncService.stopService(applicationContext)
                    result.success(true)
                }

                "canDrawOverlays" -> {
                    val canDraw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(applicationContext)
                    } else {
                        true
                    }
                    result.success(canDraw)
                }

                "requestOverlayPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("PERMISSION_ERROR", e.localizedMessage, null)
                    }
                }

                "setLockscreenWallpaper" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val senderName = call.argument<String>("senderName") ?: "Partner"
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "Image bytes cannot be null or empty", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val decodedBitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            if (decodedBitmap == null) {
                                runOnUiThread {
                                    result.error("DECODE_FAILED", "Failed to decode bitmap from bytes", null)
                                }
                                return@Thread
                            }

                            val showPopup = call.argument<Boolean>("showPopup") ?: false

                            // 1. Update Android Home Screen Widgets immediately
                            ScribbleWidgetProvider.updateAllWidgets(applicationContext, decodedBitmap, senderName)

                            // 2. Only pop up overlay card and notification if requested for a brand-new unseen scribble
                            if (showPopup) {
                                LockscreenOverlayActivity.showOverlay(applicationContext, decodedBitmap, senderName)
                                showScribbleNotification(
                                    applicationContext,
                                    "New Note from $senderName! 🎨",
                                    "$senderName drew a note for your lock screen.",
                                    decodedBitmap,
                                    senderName
                                )
                                wakeUpScreen(applicationContext)
                            }

                            runOnUiThread {
                                result.success(mapOf("success" to true, "mode" to "overlay"))
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("OVERLAY_ERROR", e.localizedMessage ?: "Unknown error", null)
                            }
                        }
                    }.start()
                }

                "clearLockscreen" -> {
                    Thread {
                        try {
                            val nm = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                            nm?.cancel(1001)

                            // Clear widget
                            ScribbleWidgetProvider.updateAllWidgets(applicationContext, null, null)

                            // Clear any wallpaper override from earlier tests
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    val wm = WallpaperManager.getInstance(applicationContext)
                                    wm.clear(WallpaperManager.FLAG_LOCK)
                                }
                            } catch (_: Exception) {}

                            runOnUiThread {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("CLEAR_ERROR", e.localizedMessage ?: "Unknown error", null)
                            }
                        }
                    }.start()
                }

                "saveImageToGallery" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val title = call.argument<String>("title") ?: "scribble_${System.currentTimeMillis()}"
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "Image bytes cannot be null or empty", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val resolver = applicationContext.contentResolver
                            val fileName = "$title.png"
                            val contentValues = ContentValues().apply {
                                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Scribble")
                                    put(MediaStore.Images.Media.IS_PENDING, 1)
                                }
                            }

                            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                            if (uri != null) {
                                resolver.openOutputStream(uri)?.use { stream ->
                                    stream.write(bytes)
                                    stream.flush()
                                }

                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    contentValues.clear()
                                    contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
                                    resolver.update(uri, contentValues, null, null)
                                } else {
                                    MediaScannerConnection.scanFile(
                                        applicationContext,
                                        arrayOf(uri.path ?: "/storage/emulated/0/Pictures/$fileName"),
                                        arrayOf("image/png"),
                                        null
                                    )
                                }

                                runOnUiThread {
                                    result.success(mapOf("success" to true, "uri" to uri.toString(), "fileName" to fileName))
                                }
                            } else {
                                runOnUiThread {
                                    result.error("INSERT_FAILED", "Failed to create MediaStore entry", null)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("SAVE_FAILED", e.localizedMessage ?: "Unknown save error", null)
                            }
                        }
                    }.start()
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}

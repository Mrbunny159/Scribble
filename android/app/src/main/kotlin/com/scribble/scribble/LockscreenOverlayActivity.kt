package com.scribble.scribble

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File
import java.io.FileOutputStream

class LockscreenOverlayActivity : Activity() {

    companion object {
        var currentBitmap: Bitmap? = null
        var currentSender: String = "Partner"

        fun showOverlay(context: Context, bitmap: Bitmap, senderName: String = "Partner") {
            try {
                currentBitmap = bitmap
                currentSender = senderName

                // Also persist to cache as backup
                try {
                    val file = File(context.cacheDir, "latest_overlay.png")
                    FileOutputStream(file).use { out ->
                        bitmap.compress(Bitmap.CompressFormat.PNG, 95, out)
                    }
                } catch (_: Exception) {}

                val intent = Intent(context, LockscreenOverlayActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                             Intent.FLAG_ACTIVITY_CLEAR_TOP or
                             Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("senderName", senderName)
                }
                context.startActivity(intent)
                MainActivity.wakeUpScreen(context)
            } catch (e: Exception) {
                android.util.Log.e("LockscreenOverlay", "Failed to launch overlay activity: ${e.message}")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Enable display over lock screen and wake up display
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Retrieve bitmap
        var bitmap = currentBitmap
        if (bitmap == null) {
            try {
                val file = File(cacheDir, "latest_overlay.png")
                if (file.exists()) {
                    bitmap = BitmapFactory.decodeFile(file.absolutePath)
                }
            } catch (_: Exception) {}
        }

        val senderName = intent?.getStringExtra("senderName") ?: currentSender

        // Build the modern UI programmatically
        val rootLayout = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            // Subtle frosted scrim so the original wallpaper is clearly visible behind
            setBackgroundColor(Color.parseColor("#4D000000"))
            // Tap outside the card dismisses the overlay
            setOnClickListener { finish() }
        }

        val dm = resources.displayMetrics
        val screenWidth = dm.widthPixels
        val screenHeight = dm.heightPixels
        val density = dm.density
        fun dp(value: Float): Int = (value * density + 0.5f).toInt()

        val cardWidth = Math.min((screenWidth * 0.90f).toInt(), dp(360f))
        val maxImageHeight = Math.min((screenHeight * 0.42f).toInt(), dp(320f))

        // Scrollable container to handle all screen heights and scales gracefully
        val scrollView = android.widget.ScrollView(this).apply {
            isFillViewport = true
            overScrollMode = View.OVER_SCROLL_IF_CONTENT_SCROLLS
            val slp = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            layoutParams = slp
            // Tap on scrollable backdrop dismisses overlay
            setOnClickListener { finish() }
        }

        // Center card container
        val centerContainer = FrameLayout(this).apply {
            layoutParams = ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            setOnClickListener { finish() }
        }

        // Card Container
        val cardLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val lp = FrameLayout.LayoutParams(
                cardWidth,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER
                setMargins(dp(16f), dp(32f), dp(16f), dp(32f))
            }
            layoutParams = lp

            val cardBg = GradientDrawable().apply {
                cornerRadius = dp(26f).toFloat()
                setColor(Color.parseColor("#F21E1B24")) // 95% opacity dark violet
                setStroke(dp(1.5f), Color.parseColor("#4D9C8EF7")) // subtle glowing purple border
            }
            background = cardBg
            elevation = dp(16f).toFloat()
            setPadding(dp(18f), dp(16f), dp(18f), dp(18f))
            // Prevent taps inside the card from closing it
            setOnClickListener { /* Consume click */ }
        }

        // Header: Badge & Close Button
        val headerLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(12f)
            }
        }

        val titleView = TextView(this).apply {
            text = "🎨 Note from $senderName"
            setTextColor(Color.parseColor("#F5EFF7"))
            textSize = 16f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }

        val closeButton = TextView(this).apply {
            text = "✕"
            setTextColor(Color.parseColor("#B0A7C0"))
            textSize = 18f
            setPadding(dp(8f), dp(4f), dp(8f), dp(4f))
            setOnClickListener { finish() }
        }

        headerLayout.addView(titleView)
        headerLayout.addView(closeButton)
        cardLayout.addView(headerLayout)

        // Scribble Drawing View (Dynamically constrained to prevent overflow)
        val imageView = ImageView(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dp(14f)
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
            adjustViewBounds = true
            maxHeight = maxImageHeight

            val imgBg = GradientDrawable().apply {
                cornerRadius = dp(18f).toFloat()
                setColor(Color.parseColor("#121016"))
                setStroke(dp(1f), Color.parseColor("#2B2735"))
            }
            background = imgBg
            clipToOutline = true
            setPadding(dp(8f), dp(8f), dp(8f), dp(8f))

            if (bitmap != null) {
                setImageBitmap(bitmap)
            }
        }
        cardLayout.addView(imageView)

        // Action Buttons Row
        val actionsLayout = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
            gravity = Gravity.CENTER
        }

        // "Scribble Back" Pill Button
        val replyButton = TextView(this).apply {
            text = "✏️ Scribble Back"
            setTextColor(Color.WHITE)
            textSize = 14f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            val btnBg = GradientDrawable().apply {
                cornerRadius = dp(24f).toFloat()
                setColor(Color.parseColor("#6750A4")) // Primary brand purple
            }
            background = btnBg
            layoutParams = LinearLayout.LayoutParams(0, dp(44f), 1f).apply {
                rightMargin = dp(8f)
            }
            setOnClickListener {
                unlockAndLaunchApp()
            }
        }

        // "Dismiss" Button
        val dismissButton = TextView(this).apply {
            text = "Dismiss"
            setTextColor(Color.parseColor("#D0BCFF"))
            textSize = 14f
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            val btnBg = GradientDrawable().apply {
                cornerRadius = dp(24f).toFloat()
                setColor(Color.parseColor("#2B2735"))
            }
            background = btnBg
            layoutParams = LinearLayout.LayoutParams(dp(84f), dp(44f))
            setOnClickListener {
                finish()
            }
        }

        actionsLayout.addView(replyButton)
        actionsLayout.addView(dismissButton)
        cardLayout.addView(actionsLayout)

        centerContainer.addView(cardLayout)
        scrollView.addView(centerContainer)
        rootLayout.addView(scrollView)
        setContentView(rootLayout)
    }

    private fun unlockAndLaunchApp() {
        try {
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                keyguardManager?.requestDismissKeyguard(this, null)
            }
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(launchIntent)
            }
            finish()
        } catch (e: Exception) {
            finish()
        }
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        recreate()
    }
}

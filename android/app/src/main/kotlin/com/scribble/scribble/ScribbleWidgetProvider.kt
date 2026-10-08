package com.scribble.scribble

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import java.io.File

class ScribbleWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (widgetId in appWidgetIds) {
            updateSingleWidget(context, appWidgetManager, widgetId, null, null)
        }
    }

    companion object {
        fun updateAllWidgets(context: Context, bitmap: Bitmap? = null, partnerName: String? = null) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val thisWidget = ComponentName(context, ScribbleWidgetProvider::class.java)
            val widgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
            if (widgetIds == null || widgetIds.isEmpty()) return

            for (widgetId in widgetIds) {
                updateSingleWidget(context, appWidgetManager, widgetId, bitmap, partnerName)
            }
        }

        private fun updateSingleWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int,
            providedBitmap: Bitmap?,
            providedPartnerName: String?
        ) {
            val views = RemoteViews(context.packageName, R.layout.widget_scribble)

            // Setup launch intent to open Flutter canvas directly on tap
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("openCanvas", true)
            }

            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    widgetId,
                    launchIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
                views.setOnClickPendingIntent(R.id.widget_action_draw, pendingIntent)
            }

            // Set Partner Name
            val prefs = context.getSharedPreferences("ScribbleSyncPrefs", Context.MODE_PRIVATE)
            val name = providedPartnerName ?: prefs.getString("partnerName", "Partner") ?: "Partner"
            views.setTextViewText(R.id.widget_partner_name, "🎨 $name\'s Note")

            // Load Bitmap
            var bitmap = providedBitmap
            if (bitmap == null) {
                try {
                    val file = File(context.cacheDir, "latest_overlay.png")
                    if (file.exists()) {
                        bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    }
                } catch (_: Exception) {}
            }

            if (bitmap != null) {
                views.setImageViewBitmap(R.id.widget_image, bitmap)
                views.setViewVisibility(R.id.widget_image, View.VISIBLE)
                views.setViewVisibility(R.id.widget_empty_text, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_image, View.GONE)
                views.setViewVisibility(R.id.widget_empty_text, View.VISIBLE)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}

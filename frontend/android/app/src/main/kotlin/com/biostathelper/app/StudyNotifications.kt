package com.biostathelper.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build

internal object StudyNotifications {
    fun permitted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return false
        }
        return (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
    }

    fun show(context: Context, title: String, count: Int): Boolean {
        if (count <= 0 || !permitted(context)) return false
        return try {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(NotificationChannel(
                    "study_subscriptions", "学习订阅更新", NotificationManager.IMPORTANCE_DEFAULT,
                ))
            }
            val open = PendingIntent.getActivity(context, 28002,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, "study_subscriptions")
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            manager.notify(28002, builder.setSmallIcon(android.R.drawable.ic_popup_sync)
                .setContentTitle(title.trim().take(200).ifBlank { "学习订阅更新" })
                .setContentText("发现 $count 条订阅更新")
                .setContentIntent(open).setAutoCancel(true).build())
            true
        } catch (_: RuntimeException) {
            false
        }
    }
}

package com.biostathelper.app

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.CalendarContract
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private val channelName = "com.biostathelper.app/device"
    private val reminderPermissionRequest = 4701
    private val notificationPermissionRequest = 4702
    private var videoPlaybackActive = false
    private var deviceChannel: MethodChannel? = null
    private var pendingReminderCall: MethodCall? = null
    private var pendingReminderResult: MethodChannel.Result? = null
    private var pendingNotificationResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        PlaybackBridge.channel = deviceChannel
        deviceChannel?.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestFloatingWindowPermission" -> {
                        result.success(requestFloatingWindowPermission())
                    }
                    "setVideoPlaybackActive" -> {
                        videoPlaybackActive = call.argument<Boolean>("active") ?: false
                        PlaybackBridge.active = videoPlaybackActive
                        if (!videoPlaybackActive) PlaybackBridge.stop(this)
                        result.success(true)
                    }
                    "setAudioOnlyBackground" -> {
                        PlaybackBridge.audioOnly = call.argument<Boolean>("enabled") ?: false
                        result.success(true)
                    }
                    "updateMediaPlaybackState" -> {
                        val state = (call.arguments as? Map<*, *>)?.let {
                            PlaybackSnapshot.fromArguments(it, SystemClock.elapsedRealtime())
                        }
                        result.success(state != null && PlaybackBridge.update(this, state))
                    }
                    "stopMediaPlayback" -> {
                        videoPlaybackActive = false
                        PlaybackBridge.stop(this)
                        result.success(true)
                    }
                    "configureStudyBackground" -> result.success(StudyBackgroundJobService.configure(
                        this, call.argument<Boolean>("enabled") ?: false,
                    ))
                    "completeStudyBackground" -> result.success(false)
                    "showStudyNotification" -> result.success(StudyNotifications.show(
                        this, call.argument<String>("title").orEmpty(),
                        call.argument<Number>("count")?.toInt() ?: 0,
                    ))
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "enterPictureInPicture" -> {
                        result.success(enterPictureInPictureIfPossible())
                    }
                    "getDynamicAccentColor" -> {
                        result.success(getDynamicAccentColor())
                    }
                    "getPlaybackBrightness" -> {
                        result.success(getPlaybackBrightness())
                    }
                    "setPlaybackBrightness" -> {
                        result.success(setPlaybackBrightness(call.argument<Double>("value") ?: 0.5))
                    }
                    "getPlaybackVolume" -> {
                        result.success(getPlaybackVolume())
                    }
                    "setPlaybackVolume" -> {
                        result.success(setPlaybackVolume(call.argument<Double>("value") ?: 0.5))
                    }
                    "syncTodoReminder" -> {
                        syncTodoReminder(call, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (PlaybackBridge.active && !PlaybackBridge.audioOnly) {
            Handler(Looper.getMainLooper()).postDelayed({
                if (PlaybackBridge.active && !PlaybackBridge.audioOnly && !isFinishing && !isDestroyed) {
                    enterPictureInPictureIfPossible()
                }
            }, 80)
        }
    }

    override fun onResume() {
        PlaybackBridge.foreground = true
        StudyBackgroundJobService.stopForForeground()
        super.onResume()
    }

    override fun onPause() {
        super.onPause()
        PlaybackBridge.foreground = false
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: android.content.res.Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        deviceChannel?.invokeMethod(
            "onPictureInPictureModeChanged",
            mapOf("active" to isInPictureInPictureMode),
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationPermissionRequest) {
            val result = pendingNotificationResult
            pendingNotificationResult = null
            result?.success(StudyNotifications.permitted(this))
            return
        }
        if (requestCode != reminderPermissionRequest) return

        val call = pendingReminderCall
        val result = pendingReminderResult
        pendingReminderCall = null
        pendingReminderResult = null

        if (call == null || result == null) return
        if (hasReminderPermissions()) {
            result.success(performSyncTodoReminder(call))
        } else {
            result.success(false)
        }
    }

    private fun requestFloatingWindowPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (Settings.canDrawOverlays(this)) return true

        val intent = Intent(
            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
            Uri.parse("package:$packageName"),
        )
        startActivity(intent)
        return false
    }

    private fun enterPictureInPictureIfPossible(): Boolean {
        if (PlaybackBridge.audioOnly) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            enterPictureInPictureMode(params)
        } catch (_: Exception) {
            false
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (StudyNotifications.permitted(this)) {
            result.success(true)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
            pendingNotificationResult == null) {
            pendingNotificationResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), notificationPermissionRequest)
        } else {
            result.success(false)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (PlaybackBridge.channel === deviceChannel) {
            PlaybackBridge.stop(this)
            PlaybackBridge.channel = null
            PlaybackBridge.foreground = false
        }
        deviceChannel?.setMethodCallHandler(null)
        deviceChannel = null
        pendingNotificationResult?.success(false)
        pendingNotificationResult = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        if (!isChangingConfigurations && PlaybackBridge.channel === deviceChannel) {
            PlaybackBridge.stop(this)
        }
        super.onDestroy()
    }

    private fun getDynamicAccentColor(): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            val accentId = resources.getIdentifier("system_accent1_600", "color", "android")
            if (accentId == 0) null else getColor(accentId)
        } catch (_: Exception) {
            null
        }
    }

    private fun getPlaybackBrightness(): Double {
        val value = window.attributes.screenBrightness
        return if (value >= 0f) value.toDouble() else 0.5
    }

    private fun setPlaybackBrightness(value: Double): Double {
        val cleanValue = value.coerceIn(0.02, 1.0).toFloat()
        val attrs = window.attributes
        attrs.screenBrightness = cleanValue
        window.attributes = attrs
        return cleanValue.toDouble()
    }

    private fun getPlaybackVolume(): Double {
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        return currentVolume.toDouble() / maxVolume.toDouble()
    }

    private fun setPlaybackVolume(value: Double): Double {
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val targetVolume = (value.coerceIn(0.0, 1.0) * maxVolume).roundToInt()
            .coerceIn(0, maxVolume)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        return targetVolume.toDouble() / maxVolume.toDouble()
    }

    private fun syncTodoReminder(call: MethodCall, result: MethodChannel.Result) {
        if (!hasReminderPermissions()) {
            pendingReminderCall = call
            pendingReminderResult = result
            requestPermissions(missingReminderPermissions(), reminderPermissionRequest)
            return
        }
        result.success(performSyncTodoReminder(call))
    }

    private fun hasReminderPermissions(): Boolean {
        return missingReminderPermissions().isEmpty()
    }

    private fun missingReminderPermissions(): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyArray()
        val permissions = mutableListOf(
            Manifest.permission.READ_CALENDAR,
            Manifest.permission.WRITE_CALENDAR,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        return permissions
            .filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
            .toTypedArray()
    }

    private fun performSyncTodoReminder(call: MethodCall): Boolean {
        val todoId = call.argument<Int>("todoId") ?: 0
        val title = call.argument<String>("title")?.takeIf { it.isNotBlank() } ?: "项目待办"
        val description = call.argument<String>("description") ?: ""
        val projectName = call.argument<String>("projectName") ?: "生统项目"
        val dueAtMillis = call.argument<Number>("dueAtMillis")?.toLong() ?: return false

        val calendarSynced = addCalendarTodoEvent(
            title = title,
            description = description,
            projectName = projectName,
            dueAtMillis = dueAtMillis,
        )
        val notificationsScheduled = scheduleSystemTodoReminders(
            todoId = todoId,
            title = title,
            projectName = projectName,
            dueAtMillis = dueAtMillis,
        )
        return calendarSynced || notificationsScheduled
    }

    private fun addCalendarTodoEvent(
        title: String,
        description: String,
        projectName: String,
        dueAtMillis: Long,
    ): Boolean {
        val calendarId = findWritableCalendarId() ?: return false
        val eventValues = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, listOf(projectName, description)
                .filter { it.isNotBlank() }
                .joinToString("\n"))
            put(CalendarContract.Events.DTSTART, dueAtMillis)
            put(CalendarContract.Events.DTEND, dueAtMillis + 30 * 60 * 1000L)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getDefault().id)
            put(CalendarContract.Events.HAS_ALARM, 1)
        }
        val eventUri = contentResolver.insert(CalendarContract.Events.CONTENT_URI, eventValues)
            ?: return false
        val eventId = eventUri.lastPathSegment?.toLongOrNull() ?: return false
        for (minutes in listOf(60, 30, 10)) {
            val reminderValues = ContentValues().apply {
                put(CalendarContract.Reminders.EVENT_ID, eventId)
                put(CalendarContract.Reminders.MINUTES, minutes)
                put(CalendarContract.Reminders.METHOD, CalendarContract.Reminders.METHOD_ALERT)
            }
            contentResolver.insert(CalendarContract.Reminders.CONTENT_URI, reminderValues)
        }
        return true
    }

    private fun findWritableCalendarId(): Long? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
        )
        val selection =
            "${CalendarContract.Calendars.VISIBLE}=1 AND " +
                "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=?"
        val selectionArgs = arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString())
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        }
        return null
    }

    private fun scheduleSystemTodoReminders(
        todoId: Int,
        title: String,
        projectName: String,
        dueAtMillis: Long,
    ): Boolean {
        val alarmManager = getSystemService(ALARM_SERVICE) as AlarmManager
        var scheduled = false
        for (minutes in listOf(60, 30, 10)) {
            val triggerAt = dueAtMillis - minutes * 60 * 1000L
            if (triggerAt <= System.currentTimeMillis()) continue

            val intent = Intent(this, ReminderReceiver::class.java).apply {
                action = ReminderReceiver.actionTodoReminder
                putExtra(ReminderReceiver.extraTitle, title)
                putExtra(ReminderReceiver.extraProjectName, projectName)
                putExtra(ReminderReceiver.extraMinutes, minutes)
                putExtra(ReminderReceiver.extraNotificationId, "$todoId-$minutes".hashCode())
            }
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                "$todoId-$minutes".hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutablePendingIntentFlag(),
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
            }
            scheduled = true
        }
        return scheduled
    }

    private fun immutablePendingIntentFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
    }
}

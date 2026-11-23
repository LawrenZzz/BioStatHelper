package com.biostathelper.app

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.MethodChannel

// Main-looper only. The service keeps no engine, account, URL, or credentials.
internal object PlaybackBridge {
    var channel: MethodChannel? = null
    var foreground = false
    var active = false
    var audioOnly = false
    var snapshot: PlaybackSnapshot? = null
        private set
    var generation = 0L
        private set
    var onUpdate: (() -> Unit)? = null

    fun update(context: Context, next: PlaybackSnapshot): Boolean {
        if (!active || channel == null) return false
        if (snapshot?.mediaId != next.mediaId) generation++
        snapshot = next
        val listener = onUpdate
        if (listener != null) {
            listener()
            return true
        }
        return try {
            val intent = Intent(context, MediaPlaybackService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            true
        } catch (_: RuntimeException) {
            snapshot = null
            false
        }
    }

    fun dispatch(action: String, positionMs: Long? = null): Boolean {
        val current = snapshot ?: return false
        val target = channel ?: return false
        if (!active) return false
        target.invokeMethod("onMediaPlaybackAction", mapOf(
            "action" to action,
            "mediaId" to current.mediaId,
            "positionMs" to positionMs,
        ))
        return true
    }

    fun stop(context: Context) {
        active = false
        audioOnly = false
        snapshot = null
        onUpdate = null
        generation++
        context.stopService(Intent(context, MediaPlaybackService::class.java))
    }
}

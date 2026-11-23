package com.biostathelper.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.KeyEvent

class MediaPlaybackService : Service() {
    private lateinit var session: MediaSession
    private lateinit var audioManager: AudioManager
    private lateinit var notifications: NotificationManager
    private lateinit var wakeLock: PowerManager.WakeLock
    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false
    private var receiverRegistered = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE).build()

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0 && PlaybackBridge.snapshot?.playing == true) {
            PlaybackBridge.dispatch("pause")
        }
        if (change == AudioManager.AUDIOFOCUS_LOSS) hasFocus = false
    }
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY &&
                PlaybackBridge.snapshot?.playing == true) PlaybackBridge.dispatch("pause")
        }
    }

    override fun onCreate() {
        super.onCreate()
        notifications = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:study-media")
            .apply { setReferenceCounted(false) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications.createNotificationChannel(NotificationChannel(
                channelId, "学习播放", NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) })
        }
        session = MediaSession(this, "StudyPlayback").apply {
            setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
            setPlaybackToLocal(attributes)
            setSessionActivity(openAppIntent())
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { PlaybackBridge.dispatch("play") }
                override fun onPause() { PlaybackBridge.dispatch("pause") }
                override fun onStop() { stopFromControl() }
                override fun onSeekTo(pos: Long) { seek(pos) }
                override fun onFastForward() { skip(10_000) }
                override fun onRewind() { skip(-10_000) }
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    @Suppress("DEPRECATION")
                    val key = mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                        ?: return super.onMediaButtonEvent(mediaButtonIntent)
                    if (key.action != KeyEvent.ACTION_DOWN || key.repeatCount != 0) return true
                    return when (key.keyCode) {
                        KeyEvent.KEYCODE_HEADSETHOOK, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                            PlaybackBridge.dispatch(if (PlaybackBridge.snapshot?.playing == true) "pause" else "play")
                            true
                        }
                        KeyEvent.KEYCODE_MEDIA_PLAY -> { onPlay(); true }
                        KeyEvent.KEYCODE_MEDIA_PAUSE -> { onPause(); true }
                        KeyEvent.KEYCODE_MEDIA_STOP -> { onStop(); true }
                        KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> { onFastForward(); true }
                        KeyEvent.KEYCODE_MEDIA_REWIND -> { onRewind(); true }
                        else -> super.onMediaButtonEvent(mediaButtonIntent)
                    }
                }
            }, mainHandler)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
                Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(noisyReceiver, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        }
        receiverRegistered = true
        PlaybackBridge.onUpdate = { publish() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!PlaybackBridge.active || PlaybackBridge.snapshot == null || PlaybackBridge.channel == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        publish()
        if (intent?.action == actionControl &&
            intent.getLongExtra("generation", -1) == PlaybackBridge.generation &&
            intent.getStringExtra("mediaId") == PlaybackBridge.snapshot?.mediaId) {
            when (intent.getStringExtra("command")) {
                "play" -> PlaybackBridge.dispatch("play")
                "pause" -> PlaybackBridge.dispatch("pause")
                "rewind" -> skip(-10_000)
                "forward" -> skip(10_000)
                "stop" -> stopFromControl()
            }
        }
        return START_NOT_STICKY
    }

    private fun seek(position: Long) {
        val state = PlaybackBridge.snapshot ?: return
        if (state.canSeek) PlaybackBridge.dispatch("seekTo", state.clampPosition(position))
    }

    private fun skip(delta: Long) {
        val state = PlaybackBridge.snapshot ?: return
        val now = state.positionAt(SystemClock.elapsedRealtime())
        val position = (now.toDouble() + delta).coerceIn(0.0, Long.MAX_VALUE.toDouble()).toLong()
        seek(position)
    }

    private fun stopFromControl() {
        PlaybackBridge.dispatch("stop")
        PlaybackBridge.stop(this)
        stopSelf()
    }

    private fun publish() {
        val state = PlaybackBridge.snapshot ?: return
        try {
            session.setMetadata(MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_MEDIA_ID, state.mediaId)
                .putString(MediaMetadata.METADATA_KEY_TITLE, state.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, state.artist)
                .putString(MediaMetadata.METADATA_KEY_ALBUM, state.album)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, state.durationMs).build())
            val status = when {
                state.buffering -> PlaybackState.STATE_BUFFERING
                state.playing -> PlaybackState.STATE_PLAYING
                else -> PlaybackState.STATE_PAUSED
            }
            var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP
            if (state.canSeek) actions = actions or PlaybackState.ACTION_SEEK_TO or
                PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND
            session.setPlaybackState(PlaybackState.Builder().setActions(actions)
                .setState(status, state.positionMs, if (state.playing && !state.buffering) state.speed else 0f,
                    state.sampledAt).build())
            session.isActive = true
            val notification = notification(state)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(notificationId, notification)
            }
            updateAudioFocus(state.playing)
            if (state.playing) wakeLock.acquire(10 * 60 * 1000L)
            else if (wakeLock.isHeld) wakeLock.release()
        } catch (_: RuntimeException) {
            PlaybackBridge.dispatch("pause")
            PlaybackBridge.stop(this)
            stopSelf()
        }
    }

    private fun notification(state: PlaybackSnapshot): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val toggle = if (state.playing) "pause" else "play"
        return builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(state.title.ifBlank { "学习播放" })
            .setContentText(state.artist.ifBlank { state.album })
            .setContentIntent(openAppIntent())
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true).setShowWhen(false).setOngoing(state.playing)
            .setDeleteIntent(controlIntent("stop", 3))
            .addAction(action(android.R.drawable.ic_media_rew, "后退10秒", "rewind", 0))
            .addAction(action(if (state.playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (state.playing) "暂停" else "播放", toggle, 1))
            .addAction(action(android.R.drawable.ic_media_ff, "前进10秒", "forward", 2))
            .addAction(action(android.R.drawable.ic_menu_close_clear_cancel, "停止", "stop", 3))
            .setStyle(Notification.MediaStyle().setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1, 2)).build()
    }

    private fun action(icon: Int, title: String, command: String, request: Int): Notification.Action =
        Notification.Action.Builder(icon, title, controlIntent(command, request)).build()

    private fun controlIntent(command: String, request: Int): PendingIntent = PendingIntent.getService(
        this, request, Intent(this, MediaPlaybackService::class.java).apply {
            action = actionControl
            data = Uri.parse("study-playback://control/${PlaybackBridge.generation}/$request")
            putExtra("command", command)
            putExtra("generation", PlaybackBridge.generation)
            putExtra("mediaId", PlaybackBridge.snapshot?.mediaId)
        }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun openAppIntent(): PendingIntent = PendingIntent.getActivity(this, 0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun updateAudioFocus(playing: Boolean) {
        if (!playing) {
            abandonFocus()
        } else if (!hasFocus) {
            val result = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener, mainHandler).build()
                focusRequest = request
                audioManager.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
            }
            hasFocus = result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            if (!hasFocus) PlaybackBridge.dispatch("pause")
        }
    }

    private fun abandonFocus() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            focusRequest = null
        } else if (hasFocus) {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
        hasFocus = false
    }

    override fun onTaskRemoved(rootIntent: Intent?) { stopFromControl() }

    override fun onDestroy() {
        PlaybackBridge.onUpdate = null
        if (receiverRegistered) unregisterReceiver(noisyReceiver)
        abandonFocus()
        if (wakeLock.isHeld) wakeLock.release()
        session.isActive = false
        session.release()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        private const val channelId = "study_playback"
        private const val notificationId = 28001
        private const val actionControl = "com.biostathelper.app.MEDIA_CONTROL"
    }
}

package com.biostathelper.app

internal data class PlaybackSnapshot(
    val mediaId: String,
    val title: String,
    val artist: String,
    val album: String,
    val playing: Boolean,
    val buffering: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val speed: Float,
    val canSeek: Boolean,
    val sampledAt: Long,
) {
    fun positionAt(now: Long): Long {
        val elapsed = if (playing && !buffering) (now - sampledAt).coerceAtLeast(0) else 0
        val position = (positionMs.toDouble() + elapsed * speed.toDouble())
            .coerceIn(0.0, Long.MAX_VALUE.toDouble()).toLong()
        return clampPosition(position)
    }

    fun clampPosition(position: Long): Long =
        position.coerceIn(0, if (durationMs > 0) durationMs else Long.MAX_VALUE)

    companion object {
        fun fromArguments(arguments: Map<*, *>, now: Long): PlaybackSnapshot? {
            val id = arguments["mediaId"] as? String ?: return null
            val title = arguments["title"] as? String ?: return null
            val playing = arguments["playing"] as? Boolean ?: return null
            val speed = (arguments["speed"] as? Number)?.toFloat() ?: 1f
            if (id.isBlank() || !speed.isFinite() || speed <= 0 || speed > 16) return null
            val duration = ((arguments["durationMs"] as? Number)?.toLong() ?: 0).coerceAtLeast(0)
            val position = ((arguments["positionMs"] as? Number)?.toLong() ?: 0)
                .coerceIn(0, if (duration > 0) duration else Long.MAX_VALUE)
            return PlaybackSnapshot(
                mediaId = id,
                title = title.take(300),
                artist = (arguments["artist"] as? String).orEmpty().take(200),
                album = (arguments["album"] as? String).orEmpty().take(200),
                playing = playing,
                buffering = arguments["buffering"] == true,
                positionMs = position,
                durationMs = duration,
                speed = speed,
                canSeek = arguments["canSeek"] != false,
                sampledAt = now,
            )
        }
    }
}

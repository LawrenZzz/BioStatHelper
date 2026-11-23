package com.biostathelper.app

// Dependency-free JVM regression executable; no Android runtime or account.
fun main() {
    var assertions = 0
    fun verify(condition: Boolean) { check(condition); assertions++ }
    val args = mapOf<String, Any>(
        "mediaId" to "study:42:9", "title" to "Lesson", "playing" to true,
        "durationMs" to 60_000L, "positionMs" to 20_000L, "speed" to 1.5,
    )
    val state = checkNotNull(PlaybackSnapshot.fromArguments(args, 1_000))
    verify(state.positionAt(3_000) == 23_000L)
    verify(state.positionAt(500) == 20_000L)
    verify(state.positionAt(100_000) == 60_000L)
    verify(state.copy(playing = false).positionAt(3_000) == 20_000L)
    verify(state.copy(buffering = true).positionAt(3_000) == 20_000L)
    verify(state.clampPosition(-100) == 0L)
    verify(state.clampPosition(70_000) == 60_000L)
    verify(state.copy(durationMs = 0).clampPosition(70_000) == 70_000L)
    verify(PlaybackSnapshot.fromArguments(args + ("mediaId" to " "), 0) == null)
    verify(PlaybackSnapshot.fromArguments(args - "playing", 0) == null)
    for (speed in listOf(Double.NaN, Double.POSITIVE_INFINITY, 0.0, -1.0, 17.0)) {
        verify(PlaybackSnapshot.fromArguments(args + ("speed" to speed), 0) == null)
    }
    val clamped = checkNotNull(PlaybackSnapshot.fromArguments(args + ("positionMs" to 100_000L), 0))
    verify(clamped.positionMs == 60_000L)
    val negative = checkNotNull(PlaybackSnapshot.fromArguments(args + mapOf("positionMs" to -1L, "durationMs" to -1L), 0))
    verify(negative.positionMs == 0L && negative.durationMs == 0L)
    val text = checkNotNull(PlaybackSnapshot.fromArguments(args + ("title" to "x".repeat(1_000)), 0))
    verify(text.title.length == 300)
    println("PlaybackSnapshot: $assertions assertions passed")
}

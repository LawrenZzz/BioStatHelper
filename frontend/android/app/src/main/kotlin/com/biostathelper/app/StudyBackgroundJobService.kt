package com.biostathelper.app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class StudyBackgroundJobService : JobService() {
    private val handler = Handler(Looper.getMainLooper())
    private var parameters: JobParameters? = null
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private val timeout = Runnable { finish() }

    override fun onStartJob(params: JobParameters): Boolean {
        // The UI isolate checks only while resumed. An alive but paused
        // Activity must not prevent background checks; keep credentials in Dart.
        if (PlaybackBridge.foreground || running != null) return false
        parameters = params
        running = this
        handler.postDelayed(timeout, 80_000)
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            val worker = FlutterEngine(applicationContext)
            engine = worker
            channel = MethodChannel(worker.dartExecutor.binaryMessenger, "com.biostathelper.app/device").apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "completeStudyBackground" -> {
                            result.success(true)
                            handler.post { finish() }
                        }
                        "showStudyNotification" -> result.success(StudyNotifications.show(
                            this@StudyBackgroundJobService,
                            call.argument<String>("title").orEmpty(),
                            call.argument<Number>("count")?.toInt() ?: 0,
                        ))
                        "requestNotificationPermission" -> result.success(false)
                        else -> result.notImplemented()
                    }
                }
            }
            worker.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "package:bio_stat_helper/core/services/study_background.dart",
                "studyBackgroundMain",
            ))
            return true
        } catch (_: RuntimeException) {
            // onStartJob has not returned true yet, so no jobFinished callback.
            cleanup()
            return false
        }
    }

    override fun onStopJob(params: JobParameters): Boolean {
        cleanup()
        return false
    }

    private fun finish() {
        val params = parameters ?: return
        cleanup()
        jobFinished(params, false)
    }

    private fun cleanup() {
        handler.removeCallbacks(timeout)
        parameters = null
        channel?.setMethodCallHandler(null)
        channel = null
        val previous = engine
        engine = null
        if (running === this) running = null
        previous?.destroy()
    }

    override fun onDestroy() {
        cleanup()
        super.onDestroy()
    }

    companion object {
        private const val jobId = 28003
        private var running: StudyBackgroundJobService? = null

        fun stopForForeground() { running?.finish() }

        fun configure(context: Context, enabled: Boolean): Boolean {
            val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            return try {
                if (!enabled) {
                    scheduler.cancel(jobId)
                    running?.finish()
                    true
                } else if (scheduler.getPendingJob(jobId) != null) {
                    true
                } else {
                    val job = JobInfo.Builder(jobId, ComponentName(context, StudyBackgroundJobService::class.java))
                        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                        .setPeriodic(60 * 60 * 1000L)
                        .setPersisted(true)
                        .build()
                    scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
                }
            } catch (_: RuntimeException) {
                false
            }
        }
    }
}

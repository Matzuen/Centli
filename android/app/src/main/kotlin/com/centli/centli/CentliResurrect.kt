package com.centli.centli

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log

/**
 * 后台复活（不常驻、无通知）。
 *
 * 设计前提：`NotificationListenerService` 由系统绑定，进程被杀后来通知时系统会重新
 * 绑定它——所以**不需要**自己的前台服务常驻。这里只做"把绑定补回来"：
 *
 * 1. [ensureAlive]：立即向系统请求重绑，并确保周期任务已排上；
 * 2. JobScheduler 15 分钟周期任务（`setPersisted(true)`，跨重启保留）作为心跳；
 * 3. [scheduleRetry]：进程刚被清掉时的一次性补救（非精确闹钟，不需要任何特殊权限）。
 *
 * 前台服务已被移除：Android 要求前台服务必须显示常驻通知，而这里的目标是"保活但
 * 不要通知"，二者不可兼得，因此改用系统绑定 + 周期任务。
 */
object CentliResurrect {
    private const val TAG = "CentliResurrect"

    /** JobScheduler 的任务 id。 */
    private const val JOB_ID = 71101

    /** 一次性补救闹钟的请求码。 */
    private const val RETRY_REQUEST = 71102

    /** JobScheduler 允许的最小周期（15 分钟）。 */
    private const val PERIOD_MS = 15 * 60 * 1000L

    /** 旧版前台服务的通知渠道 / id，升级后清掉，避免留下僵尸渠道。 */
    private const val LEGACY_CHANNEL_ID = "centli_capture_keeper"
    private const val LEGACY_NOTIFICATION_ID = 71001

    /** 打开自动记账、进程启动、任务触发时调用：重绑监听 + 保证心跳已排。 */
    fun ensureAlive(context: Context) {
        if (!CentliNotificationListener.isAutoCaptureEnabled(context)) {
            cancel(context)
            return
        }
        try {
            CentliNotificationListener.recoverBinding(context)
        } catch (e: Exception) {
            Log.w(TAG, "recoverBinding failed", e)
        }
        // 尚未连上时加一次短补救，避免只靠 15 分钟周期。
        if (!CentliNotificationListener.isConnectedNow()) {
            scheduleRetry(context, delayMs = 8_000L)
        }
        schedule(context)
    }

    /** 排上周期任务（幂等）。 */
    fun schedule(context: Context) {
        if (!CentliNotificationListener.isAutoCaptureEnabled(context)) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        val app = context.applicationContext
        val js = app.getSystemService(JobScheduler::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && js.getPendingJob(JOB_ID) != null) {
            return
        }
        val info = JobInfo.Builder(
            JOB_ID,
            ComponentName(app, CentliResurrectJobService::class.java),
        )
            // 跨重启保留：开机后系统会自己把任务排回来（另见 CentliBootReceiver）。
            .setPersisted(true)
            .setPeriodic(PERIOD_MS)
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_NONE)
            .build()
        try {
            js.schedule(info)
            Log.i(TAG, "resurrect job scheduled")
        } catch (e: Exception) {
            Log.w(TAG, "resurrect job schedule failed", e)
        }
    }

    /** 关闭自动记账时撤销心跳。 */
    fun cancel(context: Context) {
        val app = context.applicationContext
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                app.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID)
            }
        } catch (_: Exception) {
        }
        val am = app.getSystemService(AlarmManager::class.java)
        if (am != null) {
            try {
                am.cancel(retryPendingIntent(app))
            } catch (_: Exception) {
            }
        }
        cleanupLegacyNotification(app)
    }

    /**
     * 一次性补救：进程刚被系统清掉时，15 分钟的周期任务太慢，这里补一发。
     *
     * 用非精确闹钟（`setAndAllowWhileIdle`）：不需要 `SCHEDULE_EXACT_ALARM`，
     * 也不会被 Doze 的精确闹钟频率限制卡住。
     */
    fun scheduleRetry(context: Context, delayMs: Long = 60_000L) {
        if (!CentliNotificationListener.isAutoCaptureEnabled(context)) return
        val app = context.applicationContext
        val am = app.getSystemService(AlarmManager::class.java) ?: return
        val at = SystemClock.elapsedRealtime() + delayMs.coerceAtLeast(5_000L)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, retryPendingIntent(app))
            } else {
                @Suppress("DEPRECATION")
                am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, retryPendingIntent(app))
            }
        } catch (e: Exception) {
            Log.w(TAG, "retry alarm failed", e)
        }
    }

    /** 周期任务是否已排上（给设置页自检用）。 */
    fun isScheduled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return false
        val app = context.applicationContext
        val js = app.getSystemService(JobScheduler::class.java) ?: return false
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                js.getPendingJob(JOB_ID) != null
            } else {
                js.allPendingJobs.any { it.id == JOB_ID }
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun retryPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, CentliBootReceiver::class.java)
            .setAction(CentliBootReceiver.ACTION_WATCHDOG)
        return PendingIntent.getBroadcast(
            context,
            RETRY_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 旧版本留下过「正在监听支付通知」的常驻通知与渠道，升级后删掉。 */
    private fun cleanupLegacyNotification(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            nm.cancel(LEGACY_NOTIFICATION_ID)
            if (nm.getNotificationChannel(LEGACY_CHANNEL_ID) != null) {
                nm.deleteNotificationChannel(LEGACY_CHANNEL_ID)
            }
        } catch (_: Exception) {
        }
    }
}

/**
 * 周期复活任务：每次触发只做两件事——重绑通知监听、确认心跳还在。
 *
 * 不做长任务，因此不需要 `jobFinished(params, true)` 重试；失败下次周期再来。
 */
class CentliResurrectJobService : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        val app = applicationContext
        try {
            if (CentliNotificationListener.isAutoCaptureEnabled(app)) {
                CentliNotificationListener.recoverBinding(app)
                MainActivity.flushCaptureQueueNatively(app)
                CentliResurrect.schedule(app)
            }
        } catch (e: Exception) {
            Log.w(TAG, "resurrect job failed", e)
        }
        jobFinished(params, false)
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = false

    companion object {
        private const val TAG = "CentliResurrectJob"
    }
}

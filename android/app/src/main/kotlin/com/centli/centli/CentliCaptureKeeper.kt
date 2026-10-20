package com.centli.centli

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/**
 * Keeps the process (and therefore [CentliNotificationListener]) alive after
 * the UI is swiped away. Native ingest writes pending rows without Flutter.
 */
class CentliCaptureKeeper : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        acquireWakeLock()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!CentliNotificationListener.isAutoCaptureEnabled(this)) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        // Must call startForeground promptly after startForegroundService.
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                )
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: Exception) {
            Log.e(TAG, "startForeground failed", e)
        }
        acquireWakeLock()
        // Soft rebind only when disconnected — never toggle-disable a live NLS.
        CentliNotificationListener.ensureRebind(this)
        scheduleWatchdog(this, delayMs = WATCHDOG_MS)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // User swiped the app from Recents — restart immediately + short alarm.
        if (CentliNotificationListener.isAutoCaptureEnabled(this)) {
            CentliNotificationListener.ensureRebind(this)
            scheduleWatchdog(this, delayMs = 2_000L)
            start(this)
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        releaseWakeLock()
        if (CentliNotificationListener.isAutoCaptureEnabled(this)) {
            // OEM killed the FGS — ask AlarmManager to bring us back soon.
            scheduleWatchdog(this, delayMs = 3_000L)
            try {
                start(applicationContext)
            } catch (_: Exception) {
            }
        }
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        try {
            if (wakeLock?.isHeld == true) return
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "centli:capture_keeper",
            ).also {
                it.setReferenceCounted(false)
                it.acquire(10 * 60 * 1000L)
            }
        } catch (e: Exception) {
            Log.w(TAG, "wakeLock failed", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildNotification(): Notification {
        ensureChannel(this)
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setContentTitle("正在监听支付通知")
            .setContentText("清后台后仍会捕获；点此打开 Centli")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    companion object {
        private const val TAG = "CentliCaptureKeeper"
        private const val NOTIF_ID = 71001
        private const val CHANNEL_ID = "centli_capture_keeper"
        private const val WATCHDOG_REQUEST = 71002
        /** Recurring keep-alive; shorter than typical OEM idle kill windows. */
        private const val WATCHDOG_MS = 2 * 60 * 1000L

        fun start(context: Context) {
            if (!CentliNotificationListener.isAutoCaptureEnabled(context)) {
                stop(context)
                return
            }
            val app = context.applicationContext
            val intent = Intent(app, CentliCaptureKeeper::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    app.startForegroundService(intent)
                } else {
                    app.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "foreground start blocked", e)
                CentliNotificationListener.ensureRebind(app)
                scheduleWatchdog(app, delayMs = 5_000L)
            }
        }

        fun stop(context: Context) {
            val app = context.applicationContext
            try {
                app.stopService(Intent(app, CentliCaptureKeeper::class.java))
            } catch (_: Exception) {
            }
            try {
                app.getSystemService(NotificationManager::class.java).cancel(NOTIF_ID)
            } catch (_: Exception) {
            }
            cancelWatchdog(app)
        }

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java)
            // Recreate if an old MIN channel exists — MIN FGS is killed more often.
            val existing = nm.getNotificationChannel(CHANNEL_ID)
            if (existing != null && existing.importance < NotificationManager.IMPORTANCE_LOW) {
                nm.deleteNotificationChannel(CHANNEL_ID)
            } else if (existing != null) {
                return
            }
            val channel = NotificationChannel(
                CHANNEL_ID,
                "支付通知监听",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "保持通知监听在后台运行（请勿关闭）"
                setShowBadge(false)
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }

        fun scheduleWatchdog(context: Context, delayMs: Long = WATCHDOG_MS) {
            val app = context.applicationContext
            val am = app.getSystemService(AlarmManager::class.java) ?: return
            val intent = Intent(app, CentliBootReceiver::class.java)
                .setAction(CentliBootReceiver.ACTION_WATCHDOG)
            val pi = PendingIntent.getBroadcast(
                app,
                WATCHDOG_REQUEST,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val at = SystemClock.elapsedRealtime() + delayMs.coerceAtLeast(1_000L)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
                } else {
                    @Suppress("DEPRECATION")
                    am.setExact(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
                }
            } catch (e: SecurityException) {
                Log.w(TAG, "exact alarm denied; fallback", e)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
                } else {
                    am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
                }
            } catch (e: Exception) {
                Log.w(TAG, "scheduleWatchdog failed", e)
            }
        }

        private fun cancelWatchdog(context: Context) {
            try {
                val am = context.getSystemService(AlarmManager::class.java) ?: return
                val intent = Intent(context, CentliBootReceiver::class.java)
                    .setAction(CentliBootReceiver.ACTION_WATCHDOG)
                val pi = PendingIntent.getBroadcast(
                    context,
                    WATCHDOG_REQUEST,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                am.cancel(pi)
            } catch (_: Exception) {
            }
        }
    }
}

/** Restarts capture after boot, package replace, and watchdog alarms. */
class CentliBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!CentliNotificationListener.isAutoCaptureEnabled(context)) return
        val pending = goAsync()
        try {
            CentliNotificationListener.ensureRebind(context)
            CentliCaptureKeeper.start(context)
            // Chain the next heartbeat.
            CentliCaptureKeeper.scheduleWatchdog(context)
        } finally {
            pending.finish()
        }
    }

    companion object {
        const val ACTION_WATCHDOG = "com.centli.centli.CAPTURE_WATCHDOG"
    }
}

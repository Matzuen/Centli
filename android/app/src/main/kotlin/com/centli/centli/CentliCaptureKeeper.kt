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
import android.os.SystemClock
import android.util.Log

/**
 * Dual insurance with [CentliNotificationListener] + [NativeCaptureIngest]:
 *
 * 1. NLS receives payment notices → native SQLite write + 「待确认」push
 * 2. This foreground keeper keeps the process (and therefore the bound NLS)
 *    alive after the UI is swiped away. Android requires an ongoing bar for FGS.
 */
class CentliCaptureKeeper : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!CentliNotificationListener.isAutoCaptureEnabled(this)) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }
        if (!CentliNotificationListener.connected) {
            CentliNotificationListener.ensureRebind(this)
        }
        scheduleWatchdog(this)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (CentliNotificationListener.isAutoCaptureEnabled(this)) {
            start(this)
        }
        super.onTaskRemoved(rootIntent)
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
            .setContentText("关闭或清后台后仍会记入待确认")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .build()
    }

    companion object {
        private const val NOTIF_ID = 71001
        private const val CHANNEL_ID = "centli_capture_keeper"
        private const val WATCHDOG_REQUEST = 71002

        fun start(context: Context) {
            if (!CentliNotificationListener.isAutoCaptureEnabled(context)) {
                stop(context)
                return
            }
            val intent = Intent(context, CentliCaptureKeeper::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.w("CentliCaptureKeeper", "foreground start blocked", e)
                if (!CentliNotificationListener.connected) {
                    CentliNotificationListener.ensureRebind(context)
                }
            }
        }

        fun stop(context: Context) {
            try {
                context.stopService(Intent(context, CentliCaptureKeeper::class.java))
            } catch (_: Exception) {
            }
            try {
                context.getSystemService(NotificationManager::class.java).cancel(NOTIF_ID)
            } catch (_: Exception) {
            }
        }

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "支付通知监听",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "保持通知监听在后台运行"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }

        fun scheduleWatchdog(context: Context) {
            val am = context.getSystemService(AlarmManager::class.java)
            val intent = Intent(context, CentliBootReceiver::class.java)
                .setAction(CentliBootReceiver.ACTION_WATCHDOG)
            val pi = PendingIntent.getBroadcast(
                context,
                WATCHDOG_REQUEST,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val at = SystemClock.elapsedRealtime() + 15 * 60 * 1000L
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
            } else {
                am.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
            }
        }
    }
}

/** Restarts capture after boot, package replace, and the 15-minute watchdog. */
class CentliBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!CentliNotificationListener.isAutoCaptureEnabled(context)) return
        CentliCaptureKeeper.start(context)
    }

    companion object {
        const val ACTION_WATCHDOG = "com.centli.centli.CAPTURE_WATCHDOG"
    }
}

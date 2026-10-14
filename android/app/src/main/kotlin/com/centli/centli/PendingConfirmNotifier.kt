package com.centli.centli

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Local push after a payment notification is ingested into pending_captures.
 * Title format: 待确认 ¥xx (optional body: merchant).
 * Tap opens MainActivity with route extra → Flutter /home/pending.
 */
object PendingConfirmNotifier {
    const val CHANNEL_ID = "centli_pending_confirm"
    const val EXTRA_OPEN = "centli_open"
    const val EXTRA_PENDING_ID = "centli_pending_id"

    private const val CHANNEL_NAME = "待确认记账"
    private const val CHANNEL_DESC = "支付通知解析后的待确认提醒"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = CHANNEL_DESC
            enableVibration(true)
        }
        nm.createNotificationChannel(channel)
    }

    fun show(
        context: Context,
        pendingId: String,
        title: String,
        body: String?,
    ) {
        ensureChannel(context)
        val app = context.applicationContext
        val intent = Intent(app, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_OPEN, "/home/pending")
            putExtra(EXTRA_PENDING_ID, pendingId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pi = PendingIntent.getActivity(app, notifId(pendingId), intent, flags)

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(app, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(app)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(title)
            .setContentText(body?.takeIf { it.isNotBlank() })
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)

        if (!body.isNullOrBlank()) {
            builder.setStyle(Notification.BigTextStyle().bigText(body))
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
        }

        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(notifId(pendingId), builder.build())
    }

    fun cancel(context: Context, pendingId: String) {
        val nm = context.applicationContext
            .getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(notifId(pendingId))
    }

    fun cancelAll(context: Context) {
        val nm = context.applicationContext
            .getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancelAll()
    }

    private fun notifId(pendingId: String): Int =
        pendingId.hashCode() and 0x7fffffff
}

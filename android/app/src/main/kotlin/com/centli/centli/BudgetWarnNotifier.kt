package com.centli.centli

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 预算进度约 80% 时的本地预警通知（与待确认通知共用 POST_NOTIFICATIONS）。
 * 点击打开预算页；同一 notifId 覆盖更新，避免刷屏。
 */
object BudgetWarnNotifier {
    const val CHANNEL_ID = "centli_budget_warn"

    private const val CHANNEL_NAME = "预算预警"
    private const val CHANNEL_DESC = "预算使用接近上限时提醒一次"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = CHANNEL_DESC
            enableVibration(false)
            setShowBadge(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }

    fun show(
        context: Context,
        notifId: Int,
        title: String,
        body: String,
    ) {
        ensureChannel(context)
        val app = context.applicationContext

        val open = Intent(app, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(PendingConfirmNotifier.EXTRA_OPEN, "/me/budget")
        }
        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val contentPi = PendingIntent.getActivity(
            app,
            notifId xor 0x6b17,
            open,
            piFlags,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(app, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(app)
        }
        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentPi)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_DEFAULT)
        }

        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(notifId and 0x7fffffff, builder.build())
    }
}

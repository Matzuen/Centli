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
 *
 * Tap / 「确认」 → open MainActivity to review (confirm sheet).
 * 「忽略」 → [PendingActionReceiver] without opening the UI.
 *
 * No RemoteInput「改金额」: OEM shells hide action rows when a text input
 * action is present (often only visible after long-press / expand).
 */
object PendingConfirmNotifier {
    const val CHANNEL_ID = "centli_pending_confirm"
    const val EXTRA_OPEN = "centli_open"
    const val EXTRA_PENDING_ID = "centli_pending_id"
    /** When true, Flutter should open the confirm sheet for [EXTRA_PENDING_ID]. */
    const val EXTRA_REVIEW = "centli_review"

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

        fun openIntent(review: Boolean): Intent =
            Intent(app, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_OPEN, "/home/pending")
                putExtra(EXTRA_PENDING_ID, pendingId)
                if (review) putExtra(EXTRA_REVIEW, true)
            }

        val contentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val contentPi = PendingIntent.getActivity(
            app,
            notifId(pendingId),
            openIntent(review = true),
            contentFlags,
        )

        val confirmPi = PendingIntent.getActivity(
            app,
            PendingActionReceiver.requestCode(pendingId, 0),
            openIntent(review = true),
            contentFlags,
        )

        val ignoreFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val ignorePi = PendingIntent.getBroadcast(
            app,
            PendingActionReceiver.requestCode(pendingId, 2),
            Intent(app, PendingActionReceiver::class.java).apply {
                action = PendingActionReceiver.ACTION_IGNORE
                putExtra(PendingActionReceiver.EXTRA_PENDING_ID, pendingId)
            },
            ignoreFlags,
        )

        val confirmAction = Notification.Action.Builder(
            android.R.drawable.ic_menu_edit,
            "确认",
            confirmPi,
        ).build()

        val ignoreAction = Notification.Action.Builder(
            android.R.drawable.ic_menu_close_clear_cancel,
            "忽略",
            ignorePi,
        ).build()

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(app, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(app)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(title)
            .setContentText(body?.takeIf { it.isNotBlank() } ?: "点「确认」核对后入账")
            .setContentIntent(contentPi)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            // Prefer showing actions without forcing a long-press expand.
            .setStyle(
                Notification.BigTextStyle()
                    .bigText(
                        listOfNotNull(
                            body?.takeIf { it.isNotBlank() },
                            "点「确认」核对金额与分类后入账，或点「忽略」。",
                        ).joinToString("\n"),
                    ),
            )
            .addAction(confirmAction)
            .addAction(ignoreAction)

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

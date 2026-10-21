package com.centli.centli

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews

/**
 * Local push after a payment notification is ingested into pending_captures.
 *
 * - 点整条 / 「确认」→ 直接弹悬浮窗（关闭悬浮窗时回退进 App 确认页）
 * - 「详情」→ 打开 App 内确认弹窗（原实现）
 * - 「忽略」→ 标记忽略，不打开 UI
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
        /** When set, also attach a full-screen intent for LiteNote-style quick UI. */
        overlayLaunch: Intent? = null,
    ) {
        ensureChannel(context)
        val app = context.applicationContext

        fun openDetailIntent(): Intent =
            Intent(app, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(EXTRA_OPEN, "/home/pending")
                putExtra(EXTRA_PENDING_ID, pendingId)
                putExtra(EXTRA_REVIEW, true)
            }

        val piFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

        // 整条 / 确认 → 广播拉起悬浮窗
        val confirmBroadcast = Intent(app, PendingActionReceiver::class.java).apply {
            action = PendingActionReceiver.ACTION_CONFIRM
            putExtra(PendingActionReceiver.EXTRA_PENDING_ID, pendingId)
        }
        val confirmPi = PendingIntent.getBroadcast(
            app,
            PendingActionReceiver.requestCode(pendingId, 0),
            confirmBroadcast,
            piFlags,
        )

        val detailPi = PendingIntent.getActivity(
            app,
            PendingActionReceiver.requestCode(pendingId, 1),
            openDetailIntent(),
            piFlags,
        )

        val ignorePi = PendingIntent.getBroadcast(
            app,
            PendingActionReceiver.requestCode(pendingId, 2),
            Intent(app, PendingActionReceiver::class.java).apply {
                action = PendingActionReceiver.ACTION_IGNORE
                putExtra(PendingActionReceiver.EXTRA_PENDING_ID, pendingId)
            },
            piFlags,
        )

        val shortBody = body?.takeIf { it.isNotBlank() }
            ?: "点「确认」弹窗入账，或「详情」进 App"
        val longBody = listOfNotNull(
            body?.takeIf { it.isNotBlank() },
            "点「确认」直接弹窗核对入账；点「详情」进入 App；点「忽略」跳过。",
        ).joinToString("\n")

        val compact = buildRemoteViews(
            app,
            R.layout.centli_pending_notif,
            title,
            shortBody,
            confirmPi,
            detailPi,
            ignorePi,
        )
        val expanded = buildRemoteViews(
            app,
            R.layout.centli_pending_notif_big,
            title,
            longBody,
            confirmPi,
            detailPi,
            ignorePi,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(app, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(app)
        }
        builder
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(title)
            .setContentText(shortBody)
            // 点整条通知 = 确认（弹悬浮窗）
            .setContentIntent(confirmPi)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setCustomContentView(compact)
            .setCustomBigContentView(expanded)
            .setCustomHeadsUpContentView(compact)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setStyle(Notification.DecoratedCustomViewStyle())
        }
        // 按钮只放在自定义 RemoteViews 里；再 addAction 会在展开态再出一排重复按钮。

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
        }

        // 资产锁开启时不挂全屏 Intent，避免锁屏绕过 PIN 一键入账。
        if (overlayLaunch != null &&
            PaymentOverlayManager.isEnabled(app) &&
            !PaymentOverlayManager.isAppLockEnabled(app)
        ) {
            val fsiFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            val fsi = PendingIntent.getActivity(
                app,
                notifId(pendingId) xor 0x51f0,
                overlayLaunch,
                fsiFlags,
            )
            builder.setFullScreenIntent(fsi, true)
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

    private fun buildRemoteViews(
        context: Context,
        layoutId: Int,
        title: String,
        body: String,
        confirmPi: PendingIntent,
        detailPi: PendingIntent,
        ignorePi: PendingIntent,
    ): RemoteViews {
        return RemoteViews(context.packageName, layoutId).apply {
            setTextViewText(R.id.tv_notif_title, title)
            setTextViewText(R.id.tv_notif_body, body)
            setOnClickPendingIntent(R.id.btn_notif_confirm, confirmPi)
            setOnClickPendingIntent(R.id.btn_notif_detail, detailPi)
            setOnClickPendingIntent(R.id.btn_notif_ignore, ignorePi)
        }
    }

    private fun notifId(pendingId: String): Int =
        pendingId.hashCode() and 0x7fffffff
}

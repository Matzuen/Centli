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
    /**
     * v2：旧 channel 若曾被用户/OEM 降成「静默」，系统不允许再改 importance，
     * 换新 id 才能重新以 HIGH 出现在通知一级页（而不是「更多通知」）。
     */
    const val CHANNEL_ID = "centli_pending_confirm_v2"
    private const val LEGACY_CHANNEL_ID = "centli_pending_confirm"

    const val EXTRA_OPEN = "centli_open"
    const val EXTRA_PENDING_ID = "centli_pending_id"
    /** When true, Flutter should open the confirm sheet for [EXTRA_PENDING_ID]. */
    const val EXTRA_REVIEW = "centli_review"

    private const val CHANNEL_NAME = "待确认记账"
    private const val CHANNEL_DESC = "支付通知解析后的待确认提醒（需保持「紧急/高」才会出现在通知一级页）"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // 清掉已被降权的旧通道，避免继续往「更多通知」里塞。
        try {
            if (nm.getNotificationChannel(LEGACY_CHANNEL_ID) != null) {
                nm.deleteNotificationChannel(LEGACY_CHANNEL_ID)
            }
        } catch (_: Exception) {
        }
        val existing = nm.getNotificationChannel(CHANNEL_ID)
        if (existing != null) {
            // 仍被降到 DEFAULT 以下时重建（多数机型只能删了再建）。
            if (existing.importance >= NotificationManager.IMPORTANCE_DEFAULT) return
            try {
                nm.deleteNotificationChannel(CHANNEL_ID)
            } catch (_: Exception) {
                return
            }
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = CHANNEL_DESC
            enableVibration(true)
            setShowBadge(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
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

        // 展开态自定义按钮区；折叠态不用 customContentView，减少被 OEM 丢进「更多通知」。
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
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(shortBody)
            .setStyle(Notification.BigTextStyle().bigText(longBody))
            // 点整条通知 = 确认（弹悬浮窗）
            .setContentIntent(confirmPi)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_STATUS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            // 仅展开用自定义按钮；不 setCustomContentView / 不 addAction，避免重复按钮且利于一级展示。
            .setCustomBigContentView(expanded)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_HIGH)
            @Suppress("DEPRECATION")
            builder.setDefaults(Notification.DEFAULT_ALL)
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

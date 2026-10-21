package com.centli.centli

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager

/**
 * LiteNote-style quick bookkeeping as a translucent Activity.
 * Used when WindowManager overlay is blocked (common on OEM ROMs even after
 * 「显示在其他应用上层」 is toggled).
 */
class PaymentOverlayActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val pendingId = intent.getStringExtra(EXTRA_PENDING_ID)
        if (pendingId.isNullOrBlank()) {
            finish()
            return
        }
        // 资产锁开启：不展示金额悬浮窗，改走 App 内确认（会过锁）。
        if (PaymentOverlayManager.isAppLockEnabled(this)) {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(PendingConfirmNotifier.EXTRA_OPEN, "/home/pending")
                    putExtra(PendingConfirmNotifier.EXTRA_PENDING_ID, pendingId)
                    putExtra(PendingConfirmNotifier.EXTRA_REVIEW, true)
                },
            )
            finish()
            return
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val view = layoutInflater.inflate(R.layout.centli_payment_overlay, null)
        setContentView(view)
        val amountMinor = if (intent.hasExtra(EXTRA_AMOUNT_MINOR)) {
            intent.getIntExtra(EXTRA_AMOUNT_MINOR, 0)
        } else {
            null
        }
        PaymentOverlayManager.bindActivityHost(
            this,
            view,
            pendingId = pendingId,
            amountMinor = amountMinor,
            currency = intent.getStringExtra(EXTRA_CURRENCY) ?: "CNY",
            sourcePkg = intent.getStringExtra(EXTRA_SOURCE_PKG).orEmpty(),
            merchant = intent.getStringExtra(EXTRA_MERCHANT),
            direction = intent.getStringExtra(EXTRA_DIRECTION),
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        PaymentOverlayManager.dismiss()
        @Suppress("DEPRECATION")
        super.onBackPressed()
    }

    companion object {
        const val EXTRA_PENDING_ID = "pending_id"
        const val EXTRA_AMOUNT_MINOR = "amount_minor"
        const val EXTRA_CURRENCY = "currency"
        const val EXTRA_SOURCE_PKG = "source_pkg"
        const val EXTRA_MERCHANT = "merchant"
        const val EXTRA_DIRECTION = "direction"

        fun launchIntent(
            context: Context,
            pendingId: String,
            amountMinor: Int?,
            currency: String,
            sourcePkg: String,
            merchant: String?,
            direction: String?,
        ): Intent =
            Intent(context, PaymentOverlayActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
                        Intent.FLAG_ACTIVITY_NO_USER_ACTION,
                )
                putExtra(EXTRA_PENDING_ID, pendingId)
                if (amountMinor != null) {
                    putExtra(EXTRA_AMOUNT_MINOR, amountMinor)
                }
                putExtra(EXTRA_CURRENCY, currency)
                putExtra(EXTRA_SOURCE_PKG, sourcePkg)
                putExtra(EXTRA_MERCHANT, merchant)
                putExtra(EXTRA_DIRECTION, direction)
            }

        fun start(
            context: Context,
            pendingId: String,
            amountMinor: Int?,
            currency: String,
            sourcePkg: String,
            merchant: String?,
            direction: String?,
        ) {
            context.startActivity(
                launchIntent(
                    context,
                    pendingId = pendingId,
                    amountMinor = amountMinor,
                    currency = currency,
                    sourcePkg = sourcePkg,
                    merchant = merchant,
                    direction = direction,
                ),
            )
        }
    }
}

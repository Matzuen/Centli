package com.centli.centli

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用更新 / 一次性补救闹钟触发时，把通知监听的绑定补回来。
 *
 * 注意：这里**不再**拉起前台服务——保活由 [CentliResurrect] 的周期任务负责。
 */
class CentliBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (!CentliNotificationListener.isAutoCaptureEnabled(context)) return
        val pending = goAsync()
        try {
            CentliNotificationListener.ensureRebind(context)
            MainActivity.flushCaptureQueueNatively(context)
            CentliResurrect.schedule(context)
        } catch (e: Exception) {
            Log.w(TAG, "boot revive failed", e)
        } finally {
            pending.finish()
        }
    }

    companion object {
        private const val TAG = "CentliBootReceiver"
        const val ACTION_WATCHDOG = "com.centli.centli.CAPTURE_WATCHDOG"
    }
}

package com.centli.centli

import android.app.Application
import android.util.Log

/**
 * Soft-revive notification listening as soon as the process is born
 * (NLS bind, boot, JobScheduler) — not only when [MainActivity] opens.
 */
class CentliApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        try {
            if (CentliNotificationListener.isAutoCaptureEnabled(this)) {
                CentliResurrect.ensureAlive(this)
                // 划掉后台后进程再起：软绑不够时 escalate 到硬重绑（等同磁贴关开）。
                CentliNotificationListener.recoverBinding(this)
                // 进程刚起来（可能由 NLS / Job 拉起）：先把积压通知用 native 落库。
                MainActivity.flushCaptureQueueNatively(this)
            }
        } catch (e: Exception) {
            Log.w(TAG, "early capture start failed", e)
        }
    }

    companion object {
        private const val TAG = "CentliApplication"
    }
}

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
                CentliNotificationListener.ensureRebind(this)
            }
        } catch (e: Exception) {
            Log.w(TAG, "early capture start failed", e)
        }
    }

    companion object {
        private const val TAG = "CentliApplication"
    }
}

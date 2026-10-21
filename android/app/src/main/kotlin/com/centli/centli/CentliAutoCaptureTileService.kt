package com.centli.centli

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import android.widget.Toast

/**
 * 控制中心快捷开关：一键开/关自动账单监听（对齐 NekoBox / v2rayNG 式 QS Tile）。
 *
 * - 未授予通知使用权时点开：跳转系统授权页，不偷偷打开开关。
 * - 开关状态与 SharedPreferences + app_settings 双向同步。
 */
class CentliAutoCaptureTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val app = applicationContext
        val currentlyOn = CentliNotificationListener.isAutoCaptureEnabled(app)
        if (!currentlyOn) {
            if (!CentliNotificationListener.isNotificationAccessGranted(app)) {
                openNotificationAccessSettings()
                Toast.makeText(
                    app,
                    R.string.qs_tile_need_notification_access,
                    Toast.LENGTH_LONG,
                ).show()
                refreshTile()
                return
            }
            CentliNotificationListener.applyAutoCaptureEnabled(app, true)
            Toast.makeText(app, R.string.qs_tile_turned_on, Toast.LENGTH_SHORT).show()
        } else {
            CentliNotificationListener.applyAutoCaptureEnabled(app, false)
            Toast.makeText(app, R.string.qs_tile_turned_off, Toast.LENGTH_SHORT).show()
        }
        refreshTile()
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val app = applicationContext
        val enabled = CentliNotificationListener.isAutoCaptureEnabled(app)
        val granted = CentliNotificationListener.isNotificationAccessGranted(app)
        tile.label = getString(R.string.qs_tile_auto_capture_label)
        tile.contentDescription = getString(R.string.qs_tile_auto_capture_label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = when {
                !granted -> getString(R.string.qs_tile_subtitle_need_access)
                enabled -> getString(R.string.qs_tile_subtitle_on)
                else -> getString(R.string.qs_tile_subtitle_off)
            }
        }
        tile.state = when {
            !granted -> Tile.STATE_INACTIVE
            enabled -> Tile.STATE_ACTIVE
            else -> Tile.STATE_INACTIVE
        }
        tile.updateTile()
    }

    private fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val launch = Runnable {
            try {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(intent)
            } catch (e: Exception) {
                Log.w(TAG, "startActivityAndCollapse failed", e)
                try {
                    startActivity(intent)
                } catch (_: Exception) {
                }
            }
        }
        try {
            unlockAndRun(launch)
        } catch (_: Exception) {
            launch.run()
        }
    }

    companion object {
        private const val TAG = "CentliQsTile"

        fun requestRefresh(context: Context) {
            try {
                val cn = ComponentName(context, CentliAutoCaptureTileService::class.java)
                requestListeningState(context.applicationContext, cn)
            } catch (e: Exception) {
                Log.w(TAG, "requestListeningState failed", e)
            }
        }
    }
}

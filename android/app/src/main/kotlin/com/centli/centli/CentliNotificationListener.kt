package com.centli.centli

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * Captures payment-style notifications and forwards them to Flutter via
 * [MainActivity] MethodChannel. When the Flutter engine is not ready,
 * payloads are queued in SharedPreferences and flushed on next attach.
 */
class CentliNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        connected = true
        Log.i(TAG, "onListenerConnected")
    }

    override fun onListenerDisconnected() {
        connected = false
        Log.w(TAG, "onListenerDisconnected — requesting rebind")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                requestRebind(ComponentName(this, CentliNotificationListener::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "requestRebind failed", e)
            }
        }
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!isAutoCaptureEnabled(this)) return

        val pkg = sbn.packageName ?: return
        if (pkg !in WATCHED_PACKAGES) return

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val textParts = listOfNotNull(
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
        ).filter { it.isNotBlank() }.distinct()
        val text = textParts.joinToString("\n")

        if (title.isBlank() && text.isBlank()) return

        val whenMs = sbn.notification?.`when`?.takeIf { it > 0 }
            ?: System.currentTimeMillis()
        val channelId = sbn.notification?.channelId

        val payload = hashMapOf<String, Any?>(
            "pkg" to pkg,
            "title" to title,
            "text" to text,
            "when" to whenMs,
            "key" to sbn.key,
            "channelId" to channelId,
        )

        // Native SQLite path first — survives process kill / no Flutter engine.
        try {
            NativeCaptureIngest.ingestAndNotify(this, payload)
        } catch (e: Exception) {
            Log.e(TAG, "native ingest error", e)
            enqueue(this, payload)
        }
        // Flutter path for live UI (Dart dedupes if native already wrote).
        MainActivity.emitNotificationCapture(this, payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // no-op
    }

    companion object {
        private const val TAG = "CentliNotiListener"
        private const val PREFS = "centli_notification_capture"
        private const val KEY_AUTO = "auto_capture_enabled"
        private const val KEY_QUEUE = "pending_queue"

        @Volatile
        var connected: Boolean = false
            private set

        /** Packages mirrored from assets/noti_templates.json */
        val WATCHED_PACKAGES = setOf(
            "com.eg.android.AlipayGphone",
            "com.tencent.mm",
        )

        fun prefs(context: Context): SharedPreferences =
            context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun isAutoCaptureEnabled(context: Context): Boolean =
            prefs(context).getBoolean(KEY_AUTO, true)

        fun setAutoCaptureEnabled(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(KEY_AUTO, enabled).apply()
        }

        fun enqueue(context: Context, payload: Map<String, Any?>) {
            val p = prefs(context)
            val arr = try {
                JSONArray(p.getString(KEY_QUEUE, "[]"))
            } catch (_: Exception) {
                JSONArray()
            }
            arr.put(JSONObject(payload.filterValues { it != null }))
            // Cap queue to avoid unbounded growth if Flutter never attaches
            while (arr.length() > 50) {
                arr.remove(0)
            }
            p.edit().putString(KEY_QUEUE, arr.toString()).apply()
        }

        fun drainQueue(context: Context): List<Map<String, Any?>> {
            val p = prefs(context)
            val raw = p.getString(KEY_QUEUE, "[]") ?: "[]"
            p.edit().remove(KEY_QUEUE).apply()
            return try {
                val arr = JSONArray(raw)
                buildList {
                    for (i in 0 until arr.length()) {
                        val obj = arr.getJSONObject(i)
                        val map = HashMap<String, Any?>()
                        val keys = obj.keys()
                        while (keys.hasNext()) {
                            val k = keys.next()
                            map[k] = obj.opt(k)
                        }
                        add(map)
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        fun ensureRebind(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            val cn = ComponentName(context, CentliNotificationListener::class.java)
            try {
                val pm = context.packageManager
                pm.setComponentEnabledSetting(
                    cn,
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                    PackageManager.DONT_KILL_APP,
                )
                pm.setComponentEnabledSetting(
                    cn,
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                    PackageManager.DONT_KILL_APP,
                )
                requestRebind(cn)
                Log.i(TAG, "ensureRebind requested for $cn")
            } catch (e: Exception) {
                Log.e(TAG, "ensureRebind failed", e)
            }
        }

    }
}
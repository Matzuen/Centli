package com.centli.centli

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * Captures payment-style notifications and forwards them to Flutter via
 * [MainActivity] MethodChannel. When the Flutter engine is not ready,
 * payloads are queued in SharedPreferences and flushed on next attach.
 */
class CentliNotificationListener : NotificationListenerService() {

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

        MainActivity.emitNotificationCapture(this, payload)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // no-op
    }

    companion object {
        private const val PREFS = "centli_notification_capture"
        private const val KEY_AUTO = "auto_capture_enabled"
        private const val KEY_QUEUE = "pending_queue"

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
    }
}
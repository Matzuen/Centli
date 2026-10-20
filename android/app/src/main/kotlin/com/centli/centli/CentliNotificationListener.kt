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

    override fun onCreate() {
        super.onCreate()
        // Process may start from NLS bind with no Activity — keep FGS up.
        if (isAutoCaptureEnabled(this)) {
            CentliResurrect.ensureAlive(this)
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        connected = true
        Log.i(TAG, "onListenerConnected")
        if (isAutoCaptureEnabled(this)) {
            CentliResurrect.ensureAlive(this)
        }
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
        // Ask AlarmManager / FGS to revive the process soon.
        if (isAutoCaptureEnabled(this)) {
            CentliResurrect.scheduleRetry(this, delayMs = 30_000L)
            CentliResurrect.ensureAlive(this)
        }
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val pkg = sbn.packageName ?: return
        val extras = sbn.notification?.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""

        if (!isAutoCaptureEnabled(this)) {
            recordDrop(this, pkg, title, "disabled")
            return
        }
        if (!isWatchedPackage(this, pkg)) {
            recordDrop(this, pkg, title, "not_watched")
            return
        }

        if (extras == null) return
        val textParts = listOfNotNull(
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
        ).filter { it.isNotBlank() }.distinct()
        val text = textParts.joinToString("\n")

        if (title.isBlank() && text.isBlank()) {
            recordDrop(this, pkg, title, "blank")
            return
        }

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

        // Single writer inside emitNotificationCapture: Flutter when bridge is
        // ready, otherwise native SQLite + push (no dual insert).
        CentliResurrect.ensureAlive(this)
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

        /** Builtin packages mirrored from assets/noti_templates.json */
        val WATCHED_PACKAGES = setOf(
            "com.eg.android.AlipayGphone",
            "com.tencent.mm",
        )

        private const val KEY_WATCHED = "watched_packages"
        private const val KEY_RULES = "rules_json"

        fun prefs(context: Context): SharedPreferences =
            context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        fun isAutoCaptureEnabled(context: Context): Boolean =
            prefs(context).getBoolean(KEY_AUTO, false)

        fun setAutoCaptureEnabled(context: Context, enabled: Boolean) {
            prefs(context).edit().putBoolean(KEY_AUTO, enabled).apply()
        }

        /** Union of builtin + Flutter-synced extra packages (JSON string array). */
        fun watchedPackages(context: Context): Set<String> {
            val extras = try {
                val raw = prefs(context).getString(KEY_WATCHED, null) ?: return WATCHED_PACKAGES
                val arr = JSONArray(raw)
                buildSet {
                    addAll(WATCHED_PACKAGES)
                    for (i in 0 until arr.length()) {
                        val p = arr.optString(i)
                        if (p.isNotBlank()) add(p)
                    }
                }
            } catch (_: Exception) {
                WATCHED_PACKAGES
            }
            return extras
        }

        fun isWatchedPackage(context: Context, pkg: String): Boolean =
            pkg in watchedPackages(context)

        fun setWatchedPackages(context: Context, packages: List<String>) {
            val arr = JSONArray()
            for (p in packages) {
                if (p.isNotBlank()) arr.put(p)
            }
            prefs(context).edit().putString(KEY_WATCHED, arr.toString()).apply()
        }

        fun setRulesJson(context: Context, raw: String) {
            prefs(context).edit().putString(KEY_RULES, raw).apply()
        }

        fun rulesJson(context: Context): String? =
            prefs(context).getString(KEY_RULES, null)

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

        fun peekQueue(context: Context): List<Map<String, Any?>> {
            val p = prefs(context)
            val raw = p.getString(KEY_QUEUE, "[]") ?: "[]"
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

        fun clearQueue(context: Context) {
            prefs(context).edit().remove(KEY_QUEUE).apply()
        }

        /** Peek then clear. Prefer [peekQueue]+[clearQueue] after successful deliver. */
        fun drainQueue(context: Context): List<Map<String, Any?>> {
            val items = peekQueue(context)
            if (items.isNotEmpty()) clearQueue(context)
            return items
        }

        private const val KEY_DROPS = "drops"
        private const val MAX_DROPS = 20

        /** Ring buffer of recently dropped notifications (no body text). */
        fun recordDrop(context: Context, pkg: String, title: String, reason: String) {
            try {
                val p = prefs(context)
                val arr = try {
                    JSONArray(p.getString(KEY_DROPS, "[]"))
                } catch (_: Exception) {
                    JSONArray()
                }
                val truncated = title.take(80)
                // Dedupe by pkg+title: remove older same key, keep newest.
                val kept = JSONArray()
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    if (o.optString("pkg") == pkg && o.optString("title") == truncated) {
                        continue
                    }
                    kept.put(o)
                }
                val entry = JSONObject()
                entry.put("pkg", pkg)
                entry.put("title", truncated)
                entry.put("when", System.currentTimeMillis())
                entry.put("reason", reason)
                kept.put(entry)
                while (kept.length() > MAX_DROPS) {
                    kept.remove(0)
                }
                p.edit().putString(KEY_DROPS, kept.toString()).apply()
            } catch (e: Exception) {
                Log.w(TAG, "recordDrop failed", e)
            }
        }

        fun getDroppedNotifications(context: Context): List<Map<String, Any?>> {
            val raw = prefs(context).getString(KEY_DROPS, "[]") ?: "[]"
            return try {
                val arr = JSONArray(raw)
                buildList {
                    for (i in arr.length() - 1 downTo 0) { // newest first
                        val o = arr.optJSONObject(i) ?: continue
                        add(
                            hashMapOf(
                                "pkg" to o.optString("pkg"),
                                "title" to o.optString("title").take(80),
                                "when" to o.optLong("when"),
                                "reason" to o.optString("reason"),
                            ),
                        )
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        fun clearDroppedNotifications(context: Context) {
            prefs(context).edit().remove(KEY_DROPS).apply()
        }

        /**
         * Soft rebind: if already connected, do nothing (toggling the component
         * would drop live notifications). Otherwise ask the system to bind again.
         */
        fun ensureRebind(context: Context) {
            if (connected) return
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            val cn = ComponentName(context, CentliNotificationListener::class.java)
            try {
                // Ensure component is enabled (may have been left disabled by an
                // older force-rebind path).
                val pm = context.packageManager
                val state = pm.getComponentEnabledSetting(cn)
                if (state == PackageManager.COMPONENT_ENABLED_STATE_DISABLED) {
                    pm.setComponentEnabledSetting(
                        cn,
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP,
                    )
                }
                requestRebind(cn)
                Log.i(TAG, "ensureRebind (soft) for $cn")
            } catch (e: Exception) {
                Log.e(TAG, "ensureRebind failed", e)
            }
        }

        /**
         * Hard rebind for the settings UI "重新连接" button — disable/enable the
         * component. Do **not** call this on a timer.
         */
        fun forceRebind(context: Context) {
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
                Log.i(TAG, "forceRebind for $cn")
            } catch (e: Exception) {
                Log.e(TAG, "forceRebind failed", e)
            }
        }

    }
}
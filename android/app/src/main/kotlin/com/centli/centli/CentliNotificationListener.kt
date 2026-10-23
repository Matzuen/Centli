package com.centli.centli

import android.app.Notification
import android.content.Context
import android.content.SharedPreferences
import android.database.sqlite.SQLiteDatabase
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Captures payment-style notifications and forwards them to Flutter via
 * [MainActivity] MethodChannel. When the Flutter engine is not ready,
 * payloads are queued in SharedPreferences and flushed on next attach.
 */
class CentliNotificationListener : NotificationListenerService() {

    override fun onCreate() {
        super.onCreate()
        // Process may start from NLS bind with no Activity — schedule heartbeat.
        if (isAutoCaptureEnabled(this)) {
            CentliResurrect.ensureAlive(this)
        }
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        connected = true
        cancelRebindRetries()
        Log.i(TAG, "onListenerConnected")
        if (isAutoCaptureEnabled(this)) {
            CentliResurrect.ensureAlive(this)
        }
        // 进程被杀后重绑：队列里可能还有 Flutter 未处理的通知，用 native 立刻落库。
        try {
            MainActivity.flushCaptureQueueNatively(this)
        } catch (e: Exception) {
            Log.w(TAG, "flush queue on connect failed", e)
        }
        // 刚退出 App / 断绑窗口内来的支付通知可能已错过 onNotificationPosted；
        // 重连后扫一遍状态栏里最近的监听包通知做补漏（入库侧有 dedupe）。
        try {
            catchUpRecentNotifications()
        } catch (e: Exception) {
            Log.w(TAG, "catch-up failed", e)
        }
    }

    override fun onListenerDisconnected() {
        connected = false
        instance = null
        Log.w(TAG, "onListenerDisconnected — requesting rebind")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                requestRebind(ComponentName(this, CentliNotificationListener::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "requestRebind failed", e)
            }
        }
        // 退出 App 后立刻来通知：补绑要快，不要干等 8s / 15min Job。
        if (isAutoCaptureEnabled(this)) {
            CentliResurrect.scheduleRetry(this, delayMs = 2_000L)
            CentliResurrect.ensureAlive(this)
            recoverBinding(applicationContext)
        }
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        if (instance === this) {
            instance = null
            connected = false
        }
        // 服务被拆时再排一次短补救（划掉后台常见）。
        if (isAutoCaptureEnabled(applicationContext)) {
            CentliResurrect.scheduleRetry(applicationContext, delayMs = 2_000L)
        }
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        handlePosted(sbn, fromCatchUp = false)
    }

    /**
     * 重连后补漏：状态栏里仍在的、近 [CATCH_UP_WINDOW_MS] 内、属于监听包的通知。
     * 断绑窗口内来的支付通知往往只存在于 active 列表，不会再走 posted 回调。
     */
    private fun catchUpRecentNotifications() {
        if (!isAutoCaptureEnabled(this)) return
        val cutoff = System.currentTimeMillis() - CATCH_UP_WINDOW_MS
        val active = try {
            activeNotifications ?: return
        } catch (e: Exception) {
            Log.w(TAG, "activeNotifications unavailable", e)
            return
        }
        var n = 0
        for (sbn in active) {
            val pkg = sbn.packageName ?: continue
            if (!isWatchedPackage(this, pkg)) continue
            val whenMs = sbn.notification?.`when`?.takeIf { it > 0 }
                ?: sbn.postTime.takeIf { it > 0 }
                ?: 0L
            if (whenMs > 0 && whenMs < cutoff) continue
            handlePosted(sbn, fromCatchUp = true)
            n++
        }
        if (n > 0) Log.i(TAG, "catch-up processed $n active notification(s)")
    }

    private fun handlePosted(sbn: StatusBarNotification, fromCatchUp: Boolean) {
        val pkg = sbn.packageName ?: return
        // 对齐 LiteNote / AutoBookKeeping：尽量抽全通知字段，避免金额只在
        // bigText / textLines / ticker 里时漏抓。
        val notification = sbn.notification
        val extras = notification?.extras
        val title = listOfNotNull(
            extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            extras?.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString(),
        ).firstOrNull { it.isNotBlank() } ?: ""

        if (!isAutoCaptureEnabled(this)) {
            if (!fromCatchUp) recordDrop(this, pkg, title, "disabled")
            return
        }
        if (!isWatchedPackage(this, pkg)) {
            if (!fromCatchUp) recordDrop(this, pkg, title, "not_watched")
            return
        }

        if (extras == null) return
        val lineParts = ArrayList<String>()
        val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
        if (textLines != null) {
            for (line in textLines) {
                val s = line?.toString()?.trim().orEmpty()
                if (s.isNotEmpty()) lineParts.add(s)
            }
        }
        val textParts = listOfNotNull(
            extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_SUMMARY_TEXT)?.toString(),
            extras.getCharSequence(Notification.EXTRA_INFO_TEXT)?.toString(),
            notification?.tickerText?.toString(),
        ).filter { it.isNotBlank() } + lineParts
        val text = textParts.distinct().joinToString("\n")

        if (title.isBlank() && text.isBlank()) {
            if (!fromCatchUp) recordDrop(this, pkg, title, "blank")
            return
        }

        // 对齐 AutoBookKeeping：短时内容去重，避免同一支付刷多次 posted。
        // 补漏路径也走同一套，防止重连重复入库。
        if (isRecentContentDuplicate(pkg, title, text)) {
            if (!fromCatchUp) recordDrop(this, pkg, title, "dup_content")
            return
        }

        val whenMs = notification?.`when`?.takeIf { it > 0 }
            ?: sbn.postTime.takeIf { it > 0 }
            ?: System.currentTimeMillis()
        val channelId = notification?.channelId

        val payload = hashMapOf<String, Any?>(
            "pkg" to pkg,
            "title" to title,
            "text" to text,
            "when" to whenMs,
            "key" to sbn.key,
            "channelId" to channelId,
            "catchUp" to fromCatchUp,
        )

        // Do NOT call ensureAlive/ensureRebind here — thrashing requestRebind
        // on every post can make OEMs drop the binding.
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

        @Volatile
        private var instance: CentliNotificationListener? = null

        private val rebindHandler = Handler(Looper.getMainLooper())
        private val rebindRetryRunnables = mutableListOf<Runnable>()

        /** 内容去重窗口（对齐 AutoBookKeeping 5 分钟）。 */
        private const val CONTENT_DEDUP_WINDOW_MS = 5 * 60 * 1000L
        /** 重连补漏：只扫近 3 分钟内仍挂在状态栏的支付通知。 */
        private const val CATCH_UP_WINDOW_MS = 3 * 60 * 1000L
        private val recentContentDedup = LinkedHashMap<String, Long>()

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
            // Native ingest 读 Drift app_settings；与 prefs 保持一致。
            syncAutoCaptureSettingToDb(context, enabled)
            CentliAutoCaptureTileService.requestRefresh(context)
        }

        /**
         * 开关自动监听：写 prefs+DB、重绑 NLS / 启停复活任务。
         *
         * [hardRebind] 仅磁贴等「用户刚打开开关、进程可能冷着」时用；
         * App 内日常同步请保持 false，避免每次进前台硬掐监听。
         */
        fun applyAutoCaptureEnabled(
            context: Context,
            enabled: Boolean,
            hardRebind: Boolean = false,
        ) {
            val app = context.applicationContext
            setAutoCaptureEnabled(app, enabled)
            if (enabled && isNotificationAccessGranted(app)) {
                if (hardRebind) {
                    forceRebind(app)
                    MainActivity.flushCaptureQueueNatively(app)
                } else {
                    ensureRebind(app)
                }
                CentliResurrect.ensureAlive(app)
            } else if (!enabled) {
                CentliResurrect.cancel(app)
            }
        }

        private fun syncAutoCaptureSettingToDb(context: Context, enabled: Boolean) {
            val dbFile = File(
                context.applicationContext.getDir("flutter", Context.MODE_PRIVATE),
                "centli.sqlite",
            )
            if (!dbFile.exists()) return
            var db: SQLiteDatabase? = null
            try {
                db = SQLiteDatabase.openDatabase(
                    dbFile.absolutePath,
                    null,
                    SQLiteDatabase.OPEN_READWRITE,
                )
                val value = if (enabled) "true" else "false"
                db.execSQL(
                    """
                    INSERT INTO app_settings(key, value) VALUES(?, ?)
                    ON CONFLICT(key) DO UPDATE SET value=excluded.value
                    """.trimIndent(),
                    arrayOf(KEY_AUTO, value),
                )
            } catch (e: Exception) {
                Log.w(TAG, "sync auto_capture_enabled to DB failed", e)
            } finally {
                try {
                    db?.close()
                } catch (_: Exception) {
                }
            }
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

        /** 覆盖整队列（flush 时逐条成功后再缩短，避免中途崩溃丢未处理项）。 */
        fun replaceQueue(context: Context, items: List<Map<String, Any?>>) {
            if (items.isEmpty()) {
                clearQueue(context)
                return
            }
            val arr = JSONArray()
            for (payload in items) {
                arr.put(JSONObject(payload.filterValues { it != null }))
            }
            prefs(context).edit().putString(KEY_QUEUE, arr.toString()).apply()
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

        @Synchronized
        private fun isRecentContentDuplicate(pkg: String, title: String, text: String): Boolean {
            val amountHint = Regex(
                """(?:¥|￥|\$|€)?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*元?""",
            ).find("$title\n$text")?.groupValues?.getOrNull(1) ?: ""
            val key = ("$pkg|$title|$text|$amountHint").replace(Regex("\\s+"), "")
            val now = System.currentTimeMillis()
            val it = recentContentDedup.entries.iterator()
            while (it.hasNext()) {
                if (now - it.next().value >= CONTENT_DEDUP_WINDOW_MS) it.remove()
            }
            val last = recentContentDedup[key]
            if (last != null && now - last < CONTENT_DEDUP_WINDOW_MS) return true
            recentContentDedup[key] = now
            // Bound memory.
            while (recentContentDedup.size > 80) {
                val first = recentContentDedup.keys.firstOrNull() ?: break
                recentContentDedup.remove(first)
            }
            return false
        }

        /**
         * True only when the service is bound and can read the notification shade.
         * Static [connected] alone is a false negative right after process start.
         */
        fun isConnectedNow(): Boolean {
            val svc = instance
            if (svc == null) {
                connected = false
                return false
            }
            return try {
                // Throws if the listener is not currently bound to the system.
                @Suppress("UNUSED_VARIABLE")
                val probe = svc.activeNotifications
                connected = true
                true
            } catch (_: Exception) {
                connected = false
                false
            }
        }

        fun isNotificationAccessGranted(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            if (TextUtils.isEmpty(flat)) return false
            val cn = ComponentName(context, CentliNotificationListener::class.java)
            val full = cn.flattenToString()
            val shortName = ComponentName(cn.packageName, cn.shortClassName).flattenToString()
            return flat.split(':').any {
                it.equals(full, ignoreCase = true) ||
                    it.equals(shortName, ignoreCase = true) ||
                    it.contains(cn.className, ignoreCase = true)
            }
        }

        /** 硬重绑节流：划掉后台后 OEM 常卡在僵尸绑定，但频繁 disable/enable 会丢通知。 */
        private const val FORCE_REBIND_MIN_INTERVAL_MS = 45_000L

        @Volatile
        private var lastForceRebindAtMs: Long = 0L

        /**
         * Soft rebind: if already connected, do nothing (toggling the component
         * would drop live notifications). Otherwise ask the system to bind again,
         * and retry a few times — cold start often needs 0.5–3s before connected.
         */
        fun ensureRebind(context: Context) {
            if (isConnectedNow()) return
            val app = context.applicationContext
            if (!isNotificationAccessGranted(app)) return
            requestSoftRebind(app)
            scheduleRebindRetries(app)
        }

        /**
         * 进程被划掉后：prefs/磁贴仍显示「开着」，但系统 NLS 绑定已死。
         * 软 [requestRebind] 常常无效，需在短暂重试后升级为 [forceRebind]
         *（与磁贴关开一次等价）。
         */
        fun recoverBinding(context: Context) {
            val app = context.applicationContext
            if (!isAutoCaptureEnabled(app)) return
            if (!isNotificationAccessGranted(app)) return
            if (isConnectedNow()) return
            requestSoftRebind(app)
            scheduleRebindRetries(app, escalateToForce = true)
            CentliResurrect.scheduleRetry(app, delayMs = 2_000L)
        }

        private fun requestSoftRebind(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            if (isConnectedNow()) return
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

        private fun scheduleRebindRetries(
            context: Context,
            escalateToForce: Boolean = false,
        ) {
            cancelRebindRetries()
            val app = context.applicationContext
            // 冷启动 / 刚退出 App：尽快软绑；约 2s 起升级硬重绑（划掉后台后软绑常无效）。
            val delays = longArrayOf(300L, 1_000L, 2_000L, 4_000L, 8_000L)
            for (delay in delays) {
                val useForce = escalateToForce && delay >= 2_000L
                val r = Runnable {
                    if (isConnectedNow()) return@Runnable
                    if (!isNotificationAccessGranted(app)) return@Runnable
                    if (!isAutoCaptureEnabled(app)) return@Runnable
                    if (useForce) {
                        forceRebindThrottled(app)
                    } else {
                        requestSoftRebind(app)
                    }
                }
                rebindRetryRunnables.add(r)
                rebindHandler.postDelayed(r, delay)
            }
        }

        private fun forceRebindThrottled(context: Context) {
            if (isConnectedNow()) return
            val now = System.currentTimeMillis()
            if (now - lastForceRebindAtMs < FORCE_REBIND_MIN_INTERVAL_MS) {
                Log.i(TAG, "forceRebind throttled")
                requestSoftRebind(context)
                return
            }
            lastForceRebindAtMs = now
            forceRebind(context)
        }

        private fun cancelRebindRetries() {
            for (r in rebindRetryRunnables) {
                rebindHandler.removeCallbacks(r)
            }
            rebindRetryRunnables.clear()
        }

        /**
         * Hard rebind for the settings UI "重新连接" button — disable/enable the
         * component. Do **not** call this on a timer.
         */
        fun forceRebind(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
            val app = context.applicationContext
            val cn = ComponentName(app, CentliNotificationListener::class.java)
            try {
                connected = false
                instance = null
                lastForceRebindAtMs = System.currentTimeMillis()
                val pm = app.packageManager
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
                // 硬重绑后只做软重试，避免 disable/enable 连环触发。
                scheduleRebindRetries(app, escalateToForce = false)
                Log.i(TAG, "forceRebind for $cn")
            } catch (e: Exception) {
                Log.e(TAG, "forceRebind failed", e)
            }
        }

    }
}
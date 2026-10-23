package com.centli.centli

import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPostNotifResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        )
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPermissionGranted" -> {
                    result.success(isNotificationAccessGranted())
                }
                "isPostNotificationsGranted" -> {
                    result.success(isPostNotificationsGranted())
                }
                "requestPostNotificationsPermission" -> {
                    requestPostNotificationsPermission(result)
                }
                "isListenerConnected" -> {
                    // Probe the live bind — static flag alone is false on cold start.
                    result.success(CentliNotificationListener.isConnectedNow())
                }
                "ensureListenerRebind" -> {
                    try {
                        // Soft: no-op when already connected. Safe for page reload /
                        // app resume — hard toggle would drop live notifications.
                        CentliNotificationListener.ensureRebind(this)
                        CentliResurrect.ensureAlive(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("rebind_failed", e.message, null)
                    }
                }
                "forceListenerRebind" -> {
                    try {
                        // Hard disable/enable — only for explicit「重新连接」.
                        CentliNotificationListener.forceRebind(this)
                        CentliResurrect.ensureAlive(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("rebind_failed", e.message, null)
                    }
                }
                "openPermissionSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("open_failed", e.message, null)
                    }
                }
                "setAutoCaptureEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: true
                    CentliNotificationListener.applyAutoCaptureEnabled(this, enabled)
                    result.success(null)
                }
                "setWatchedPackages" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? List<*> ?: emptyList<Any?>()
                    val packages = args.mapNotNull { it as? String }.filter { it.isNotBlank() }
                    CentliNotificationListener.setWatchedPackages(this, packages)
                    result.success(null)
                }
                "setRulesJson" -> {
                    val raw = call.arguments as? String ?: "[]"
                    CentliNotificationListener.setRulesJson(this, raw)
                    result.success(null)
                }
                "isAutoCaptureEnabled" -> {
                    result.success(CentliNotificationListener.isAutoCaptureEnabled(this))
                }
                "showPendingConfirm" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val pendingId = args["pendingId"] as? String
                    val title = args["title"] as? String
                    if (pendingId.isNullOrBlank() || title.isNullOrBlank()) {
                        result.error("bad_args", "pendingId and title required", null)
                        return@setMethodCallHandler
                    }
                    val body = args["body"] as? String
                    ensurePostNotificationsPermission()
                    PendingConfirmNotifier.show(this, pendingId, title, body)
                    PaymentOverlayManager.showFromPendingId(this, pendingId)
                    result.success(null)
                }
                "isOverlayPermissionGranted" -> {
                    result.success(PaymentOverlayManager.hasPermission(this))
                }
                "isOverlayEnabled" -> {
                    result.success(PaymentOverlayManager.isEnabled(this))
                }
                "setOverlayEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: true
                    PaymentOverlayManager.setEnabled(this, enabled)
                    result.success(null)
                }
                "openOverlayPermissionSettings" -> {
                    try {
                        PaymentOverlayManager.openPermissionSettings(this)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("open_failed", e.message, null)
                    }
                }
                "cancelPendingConfirm" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val pendingId = args["pendingId"] as? String
                    if (pendingId.isNullOrBlank()) {
                        result.error("bad_args", "pendingId required", null)
                        return@setMethodCallHandler
                    }
                    PendingConfirmNotifier.cancel(this, pendingId)
                    result.success(null)
                }
                "cancelAllPendingConfirm" -> {
                    PendingConfirmNotifier.cancelAll(this)
                    result.success(null)
                }
                "nativeIngestCapture" -> {
                    // Dart 处理失败（异常/DB 不可用）时的兜底：由 native 自己写库 + 推送。
                    @Suppress("UNCHECKED_CAST")
                    val payload = (call.arguments as? Map<*, *>)?.entries
                        ?.associate { it.key.toString() to it.value } as? Map<String, Any?>
                    if (payload == null) {
                        result.success(null)
                    } else {
                        result.success(NativeCaptureIngest.ingestAndNotify(this, payload))
                    }
                }
                "isResurrectScheduled" -> {
                    result.success(CentliResurrect.isScheduled(this))
                }
                "isBatteryOptimizationIgnored" -> {
                    result.success(isBatteryOptimizationIgnored())
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        openBatteryOptimizationSettings()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("open_failed", e.message, null)
                    }
                }
                "bridgeReady" -> {
                    dartBridgeReadyGlobal = true
                    flushQueuedCaptures()
                    flushQueuedPendingIntake()
                    flushQueuedOpenRoute()
                    result.success(null)
                }
                "getDroppedNotifications" -> {
                    result.success(CentliNotificationListener.getDroppedNotifications(this))
                }
                "clearDroppedNotifications" -> {
                    CentliNotificationListener.clearDroppedNotifications(this)
                    result.success(null)
                }
                "recordDroppedNotification" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val pkg = args["pkg"] as? String ?: ""
                    val title = args["title"] as? String ?: ""
                    val reason = args["reason"] as? String ?: "weak"
                    if (pkg.isNotBlank()) {
                        CentliNotificationListener.recordDrop(this, pkg, title, reason)
                    }
                    result.success(null)
                }
                "listLaunchableApps" -> {
                    result.success(listLaunchableApps())
                }
                else -> result.notImplemented()
            }
        }

        // Do not flush capture queues here — Dart calls bridgeReady after handler bind (#10).
        mainHandler.post {
            deliverOpenRoute(intent)
            deliverPendingIntake(intent)
            if (isNotificationAccessGranted() &&
                CentliNotificationListener.isAutoCaptureEnabled(this)
            ) {
                // 回前台补绑：划掉后台后可能需硬重绑才能恢复监听。
                CentliResurrect.ensureAlive(this)
                CentliNotificationListener.recoverBinding(this)
            } else if (isNotificationAccessGranted() &&
                !CentliNotificationListener.isConnectedNow()
            ) {
                CentliNotificationListener.ensureRebind(this)
            } else if (!CentliNotificationListener.isAutoCaptureEnabled(this)) {
                CentliResurrect.cancel(this)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        appInForeground = true
        // 每次回前台都尽量把监听补上（已连接则 no-op；断开则 soft→force）。
        if (isNotificationAccessGranted()) {
            if (CentliNotificationListener.isAutoCaptureEnabled(this)) {
                CentliNotificationListener.recoverBinding(this)
                CentliResurrect.ensureAlive(this)
            } else {
                CentliNotificationListener.ensureRebind(this)
            }
        }
    }

    override fun onPause() {
        // 退到后台后 Flutter isolate 可能被挂起，通知改走 native 写库。
        appInForeground = false
        super.onPause()
    }

    override fun onStop() {
        super.onStop()
        // 刚退出 / 划到后台后立刻来支付通知：提前排短补救，缩短断绑空窗。
        if (isNotificationAccessGranted() &&
            CentliNotificationListener.isAutoCaptureEnabled(this)
        ) {
            CentliResurrect.scheduleRetry(this, delayMs = 2_000L)
            CentliNotificationListener.ensureRebind(this)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverOpenRoute(intent)
        deliverPendingIntake(intent)
    }

    override fun onDestroy() {
        appInForeground = false
        dartBridgeReadyGlobal = false
        if (methodChannel != null) {
            methodChannel = null
        }
        super.onDestroy()
    }

    private fun isPostNotificationsGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun ensurePostNotificationsPermission() {
        if (isPostNotificationsGranted()) return
        requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            REQ_POST_NOTIFICATIONS,
        )
    }

    /** Installed launchable apps for 「其它」规则包名选择（无需 QUERY_ALL_PACKAGES）。 */
    private fun listLaunchableApps(): List<Map<String, String>> {
        return try {
            val pm = packageManager
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val resolves = pm.queryIntentActivities(intent, 0)
            val out = ArrayList<Map<String, String>>(resolves.size)
            val seen = HashSet<String>()
            for (ri in resolves) {
                val pkg = ri.activityInfo?.packageName?.trim().orEmpty()
                if (pkg.isEmpty() || !seen.add(pkg)) continue
                val label = try {
                    ri.loadLabel(pm)?.toString()?.trim().orEmpty()
                } catch (_: Exception) {
                    ""
                }
                out.add(
                    mapOf(
                        "packageName" to pkg,
                        "label" to label.ifEmpty { pkg },
                    ),
                )
            }
            out.sortBy { it["label"]?.lowercase() ?: it["packageName"] ?: "" }
            out
        } catch (e: Exception) {
            Log.w("CentliMain", "listLaunchableApps failed", e)
            emptyList()
        }
    }

    /** System dialog for POST_NOTIFICATIONS (Android 13+). Completes [result]. */
    private fun requestPostNotificationsPermission(result: MethodChannel.Result) {
        if (isPostNotificationsGranted()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        // Drop previous waiter if any (should be rare).
        pendingPostNotifResult?.success(false)
        pendingPostNotifResult = result
        requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            REQ_POST_NOTIFICATIONS,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_POST_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val pending = pendingPostNotifResult
        pendingPostNotifResult = null
        pending?.success(granted)
    }

    private fun isNotificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        if (TextUtils.isEmpty(flat)) return false
        val cn = ComponentName(this, CentliNotificationListener::class.java)
        val full = cn.flattenToString()
        val shortName = ComponentName(cn.packageName, cn.shortClassName).flattenToString()
        return flat.split(':').any {
            it.equals(full, ignoreCase = true) ||
                it.equals(shortName, ignoreCase = true) ||
                it.contains(cn.className, ignoreCase = true)
        }
    }

    private fun flushQueuedCaptures() {
        if (!dartBridgeReadyGlobal) return
        val queued = CentliNotificationListener.peekQueue(this)
        if (queued.isEmpty()) return
        val ch = methodChannel ?: return
        // 等 Dart 处理完再清队列；失败则保留未完成项（见 notification_capture_flush）。
        try {
            ch.invokeMethod(
                "notification_capture_flush",
                queued,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        when (result) {
                            is List<*> -> {
                                val keep = result.mapNotNull { item ->
                                    @Suppress("UNCHECKED_CAST")
                                    (item as? Map<*, *>)?.entries
                                        ?.associate { it.key.toString() to it.value }
                                        as? Map<String, Any?>
                                }
                                CentliNotificationListener.replaceQueue(
                                    this@MainActivity,
                                    keep,
                                )
                                Log.i(
                                    "CentliMain",
                                    "flush ack: kept ${keep.size}/${queued.size}",
                                )
                            }
                            else -> {
                                CentliNotificationListener.clearQueue(this@MainActivity)
                                Log.i(
                                    "CentliMain",
                                    "flush ack: cleared ${queued.size}",
                                )
                            }
                        }
                    }

                    override fun error(
                        errorCode: String,
                        errorMessage: String?,
                        errorDetails: Any?,
                    ) {
                        Log.w(
                            "CentliMain",
                            "flushQueuedCaptures error $errorCode: $errorMessage; keeping queue",
                        )
                    }

                    override fun notImplemented() {
                        // 旧 Dart：退回逐条 fire-and-forget，但不再提前清空。
                        Log.w("CentliMain", "notification_capture_flush missing; legacy path")
                        for (payload in queued) {
                            try {
                                ch.invokeMethod("notification_capture", payload)
                            } catch (e: Exception) {
                                Log.w("CentliMain", "legacy flush item failed", e)
                            }
                        }
                        // 给 Dart 一点时间；不清空，靠下次 bridgeReady / 去重消化。
                    }
                },
            )
        } catch (e: Exception) {
            Log.w("CentliMain", "flushQueuedCaptures failed; keeping queue", e)
        }
    }

    private fun deliverOpenRoute(intent: Intent?) {
        if (intent == null) return
        val route = intent.getStringExtra(PendingConfirmNotifier.EXTRA_OPEN) ?: return
        val pendingId = intent.getStringExtra(PendingConfirmNotifier.EXTRA_PENDING_ID)
        val review = intent.getBooleanExtra(PendingConfirmNotifier.EXTRA_REVIEW, false)
        // Consume so rotation / recreate does not re-navigate.
        intent.removeExtra(PendingConfirmNotifier.EXTRA_OPEN)
        intent.removeExtra(PendingConfirmNotifier.EXTRA_PENDING_ID)
        intent.removeExtra(PendingConfirmNotifier.EXTRA_REVIEW)
        val payload = hashMapOf<String, Any?>(
            "route" to route,
            "pendingId" to pendingId,
            "review" to review,
        )
        // Cold start often delivers the intent before Dart binds the channel.
        if (!dartBridgeReadyGlobal || methodChannel == null) {
            queuedOpenRoute = payload
            return
        }
        invokeOpenRoute(payload)
    }

    private fun flushQueuedOpenRoute() {
        val payload = queuedOpenRoute ?: return
        queuedOpenRoute = null
        invokeOpenRoute(payload)
    }

    private fun invokeOpenRoute(payload: Map<String, Any?>) {
        val ch = methodChannel ?: run {
            queuedOpenRoute = payload
            return
        }
        mainHandler.post {
            try {
                ch.invokeMethod("open_route", payload)
            } catch (_: Exception) {
                queuedOpenRoute = payload
            }
        }
    }



    private fun deliverPendingIntake(intent: Intent?) {
        val payload = PendingIntakeIntents.fromIntent(this, intent) ?: return
        intent?.action = Intent.ACTION_MAIN
        intent?.data = null
        intent?.removeExtra(Intent.EXTRA_TEXT)
        intent?.removeExtra(Intent.EXTRA_STREAM)
        intent?.removeExtra(Intent.EXTRA_SUBJECT)
        val ch = methodChannel
        if (ch == null) {
            PendingIntakeIntents.enqueue(this, payload)
            return
        }
        mainHandler.post {
            try {
                ch.invokeMethod("pending_intake", payload.toMap())
            } catch (_: Exception) {
                PendingIntakeIntents.enqueue(this, payload)
            }
        }
    }

    private fun flushQueuedPendingIntake() {
        if (!dartBridgeReadyGlobal) return
        val payload = PendingIntakeIntents.drain(this) ?: return
        val ch = methodChannel ?: run {
            PendingIntakeIntents.enqueue(this, payload)
            return
        }
        mainHandler.post {
            try {
                ch.invokeMethod("pending_intake", payload.toMap())
            } catch (_: Exception) {
                PendingIntakeIntents.enqueue(this, payload)
            }
        }
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    private fun openBatteryOptimizationSettings() {
        // Prefer app-specific request; fall back to list.
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            return
        } catch (_: Exception) {
            // Fall through.
        }
        try {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
        }
    }

    companion object {
        const val CHANNEL_NAME = "centli/notification_capture"
        private const val REQ_POST_NOTIFICATIONS = 4201

        @Volatile
        private var methodChannel: MethodChannel? = null

        @Volatile
        private var dartBridgeReadyGlobal = false

        /** True only while [MainActivity] is resumed (UI visible). */
        @Volatile
        private var appInForeground = false

        @Volatile
        private var queuedOpenRoute: Map<String, Any?>? = null

        @JvmStatic
        fun isDartBridgeReady(): Boolean = dartBridgeReadyGlobal

        /** Native SQLite wrote pending/txn — refresh Drift watchers when Flutter is up. */
        @JvmStatic
        fun notifyPendingDbChanged() {
            val ch = methodChannel
            if (ch == null || !dartBridgeReadyGlobal) {
                Log.d("CentliMain", "pending_db_changed deferred (bridge not ready)")
                return
            }
            Handler(Looper.getMainLooper()).post {
                try {
                    ch.invokeMethod("pending_db_changed", null)
                } catch (e: Exception) {
                    Log.w("CentliMain", "pending_db_changed failed", e)
                }
            }
        }

        /**
         * Called from [CentliNotificationListener].
         *
         * 对齐 LiteNote / AutoBookKeeping：**始终由 native 解析并写待确认**，
         * 不依赖 Flutter 是否在前台。前台时额外通知 Dart 做 AI 反写
         * （二次入库会被 dedupe 挡掉）。
         */
        @JvmStatic
        fun emitNotificationCapture(context: android.content.Context, payload: Map<String, Any?>) {
            ingestViaNative(context, payload)
            val outcome = NativeCaptureIngest.takeLastOutcome()

            val ch = methodChannel
            if (ch != null && dartBridgeReadyGlobal && appInForeground) {
                Handler(Looper.getMainLooper()).post {
                    try {
                        val enriched = HashMap(payload)
                        when (outcome) {
                            NativeCaptureIngest.OUTCOME_INSERTED -> {
                                // Dart 侧主要用于 AI 蒸馏；入库已由 native 完成。
                                enriched["nativeIngested"] = true
                                ch.invokeMethod("notification_capture", enriched)
                            }
                            NativeCaptureIngest.OUTCOME_SOFT_ALLOW,
                            NativeCaptureIngest.OUTCOME_QUEUED,
                            -> {
                                // 仅加入监听、尚无硬规则：native 未落库，交给 Dart 精炼入库。
                                enriched["nativeIngested"] = false
                                ch.invokeMethod("notification_capture", enriched)
                            }
                            else -> {
                                // dropped — 不打扰 Dart
                            }
                        }
                    } catch (e: Exception) {
                        Log.w("CentliMain", "notify dart after native ingest failed", e)
                    }
                }
            } else {
                Log.d(
                    "CentliMain",
                    "native-only outcome=$outcome (fg=$appInForeground bridge=$dartBridgeReadyGlobal)",
                )
            }
        }

        @JvmStatic
        fun ingestViaNative(context: android.content.Context, payload: Map<String, Any?>) {
            try {
                NativeCaptureIngest.ingestAndNotify(context, payload)
            } catch (e: Exception) {
                Log.e("CentliMain", "native ingest failed", e)
                CentliNotificationListener.enqueue(context, payload)
            }
        }

        /**
         * Drain SharedPreferences queue through native ingest (no Flutter needed).
         * softAllow / 需重试项留在队列给 Dart；已入库或确定丢弃的从队列移除。
         */
        @JvmStatic
        fun flushCaptureQueueNatively(context: android.content.Context) {
            val remaining = CentliNotificationListener.peekQueue(context)
            if (remaining.isEmpty()) return
            val total = remaining.size
            var done = 0
            val keep = ArrayList<Map<String, Any?>>()
            for (head in remaining) {
                try {
                    val tagged = HashMap(head)
                    tagged["__centliFlush"] = true
                    val id = NativeCaptureIngest.ingestAndNotify(context, tagged)
                    val outcome = NativeCaptureIngest.takeLastOutcome()
                    when {
                        id != null || outcome == NativeCaptureIngest.OUTCOME_INSERTED -> done++
                        outcome == NativeCaptureIngest.OUTCOME_SOFT_ALLOW ||
                            outcome == NativeCaptureIngest.OUTCOME_QUEUED -> keep.add(head)
                        else -> {
                            // dropped（非支付 / 去重 / 关开关）— 不再占队列
                        }
                    }
                } catch (e: Exception) {
                    Log.e("CentliMain", "flush item failed; keep in queue", e)
                    keep.add(head)
                }
            }
            CentliNotificationListener.replaceQueue(context, keep)
            Log.i(
                "CentliMain",
                "native flush: inserted=$done keep=${keep.size} total=$total",
            )
        }
    }
}

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
                // Soft rebind NLS + schedule resurrect heartbeat (no FGS).
                CentliResurrect.ensureAlive(this)
                CentliNotificationListener.ensureRebind(this)
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
        // 每次回前台都尽量把监听补上（软重绑；已连接则 no-op）。
        if (isNotificationAccessGranted()) {
            CentliNotificationListener.ensureRebind(this)
            if (CentliNotificationListener.isAutoCaptureEnabled(this)) {
                CentliResurrect.ensureAlive(this)
            }
        }
    }

    override fun onPause() {
        // 退到后台后 Flutter isolate 可能被挂起，通知改走 native 写库。
        appInForeground = false
        super.onPause()
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
        try {
            for (payload in queued) {
                ch.invokeMethod("notification_capture", payload)
            }
            CentliNotificationListener.clearQueue(this)
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

            val ch = methodChannel
            if (ch != null && dartBridgeReadyGlobal && appInForeground) {
                Handler(Looper.getMainLooper()).post {
                    try {
                        // Dart 侧主要用于 AI 蒸馏；入库已由 native 完成。
                        val enriched = HashMap(payload)
                        enriched["nativeIngested"] = true
                        ch.invokeMethod("notification_capture", enriched)
                    } catch (e: Exception) {
                        Log.w("CentliMain", "notify dart after native ingest failed", e)
                    }
                }
            } else {
                Log.d(
                    "CentliMain",
                    "native-only (fg=$appInForeground bridge=$dartBridgeReadyGlobal)",
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

        /** Drain SharedPreferences queue through native ingest (no Flutter needed). */
        @JvmStatic
        fun flushCaptureQueueNatively(context: android.content.Context) {
            val queued = CentliNotificationListener.peekQueue(context)
            if (queued.isEmpty()) return
            CentliNotificationListener.clearQueue(context)
            for (payload in queued) {
                ingestViaNative(context, payload)
            }
            Log.i("CentliMain", "flushed ${queued.size} queued captures via native")
        }
    }
}

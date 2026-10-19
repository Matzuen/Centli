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

    @Volatile
    private var dartBridgeReady = false

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
                "isListenerConnected" -> {
                    result.success(CentliNotificationListener.connected)
                }
                "ensureListenerRebind" -> {
                    try {
                        CentliNotificationListener.ensureRebind(this)
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
                    CentliNotificationListener.setAutoCaptureEnabled(this, enabled)
                    if (enabled && isNotificationAccessGranted()) {
                        CentliNotificationListener.ensureRebind(this)
                        CentliCaptureKeeper.start(this)
                    } else if (!enabled) {
                        CentliCaptureKeeper.stop(this)
                    }
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
                    result.success(null)
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
                    dartBridgeReady = true
                    flushQueuedCaptures()
                    flushQueuedPendingIntake()
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
                CentliCaptureKeeper.start(this)
                if (!CentliNotificationListener.connected) {
                    CentliNotificationListener.ensureRebind(this)
                }
            } else if (isNotificationAccessGranted() &&
                !CentliNotificationListener.connected
            ) {
                CentliNotificationListener.ensureRebind(this)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (isNotificationAccessGranted() && !CentliNotificationListener.connected) {
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
        if (methodChannel != null) {
            methodChannel = null
        }
        super.onDestroy()
    }

    private fun ensurePostNotificationsPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                REQ_POST_NOTIFICATIONS,
            )
        }
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
        if (!dartBridgeReady) return
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
        // Consume so rotation / recreate does not re-navigate.
        intent.removeExtra(PendingConfirmNotifier.EXTRA_OPEN)
        intent.removeExtra(PendingConfirmNotifier.EXTRA_PENDING_ID)
        val ch = methodChannel ?: return
        val payload = hashMapOf<String, Any?>(
            "route" to route,
            "pendingId" to pendingId,
        )
        mainHandler.post {
            try {
                ch.invokeMethod("open_route", payload)
            } catch (_: Exception) {
                // Engine may be tearing down.
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
        if (!dartBridgeReady) return
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

        /**
         * Called from [CentliNotificationListener]. Delivers to Flutter when
         * the engine is attached; otherwise enqueues for later flush.
         */
        @JvmStatic
        fun emitNotificationCapture(context: android.content.Context, payload: Map<String, Any?>) {
            val ch = methodChannel
            if (ch != null) {
                Handler(Looper.getMainLooper()).post {
                    try {
                        ch.invokeMethod("notification_capture", payload)
                    } catch (e: Exception) {
                        Log.w("CentliMain", "invoke notification_capture failed", e)
                        // Native ingest already attempted; keep queue as backup.
                        CentliNotificationListener.enqueue(context, payload)
                    }
                }
            } else {
                Log.d("CentliMain", "Flutter channel null; native path owns ingest")
            }
        }
    }
}

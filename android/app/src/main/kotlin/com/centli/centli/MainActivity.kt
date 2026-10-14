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
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val mainHandler = Handler(Looper.getMainLooper())

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
                else -> result.notImplemented()
            }
        }

        // Flush any captures queued while Flutter was not running.
        mainHandler.post {
            flushQueuedCaptures()
            deliverOpenRoute(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        deliverOpenRoute(intent)
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
        val expected = cn.flattenToString()
        return flat.split(':').any { it.equals(expected, ignoreCase = true) }
    }

    private fun flushQueuedCaptures() {
        val queued = CentliNotificationListener.drainQueue(this)
        val ch = methodChannel ?: return
        for (payload in queued) {
            ch.invokeMethod("notification_capture", payload)
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
                    } catch (_: Exception) {
                        CentliNotificationListener.enqueue(context, payload)
                    }
                }
            } else {
                CentliNotificationListener.enqueue(context, payload)
            }
        }
    }
}

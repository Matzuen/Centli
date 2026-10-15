# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\MainActivity.kt")
t = p.read_text(encoding="utf-8")

if "import android.util.Log" not in t:
    t = t.replace("import android.text.TextUtils\n", "import android.text.TextUtils\nimport android.util.Log\n", 1)

# Add channel methods after isPermissionGranted
if "isListenerConnected" not in t:
    old = '''                "isPermissionGranted" -> {
                    result.success(isNotificationAccessGranted())
                }
                "openPermissionSettings" -> {'''
    new = '''                "isPermissionGranted" -> {
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
                "openPermissionSettings" -> {'''
    if old not in t:
        raise SystemExit("isPermissionGranted block missing")
    t = t.replace(old, new, 1)

# setAutoCaptureEnabled: rebind when enabling
old_set = '''                "setAutoCaptureEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: true
                    CentliNotificationListener.setAutoCaptureEnabled(this, enabled)
                    result.success(null)
                }'''
new_set = '''                "setAutoCaptureEnabled" -> {
                    val enabled = call.arguments as? Boolean ?: true
                    CentliNotificationListener.setAutoCaptureEnabled(this, enabled)
                    if (enabled && isNotificationAccessGranted()) {
                        CentliNotificationListener.ensureRebind(this)
                    }
                    result.success(null)
                }'''
if "enabled && isNotificationAccessGranted()" not in t:
    if old_set not in t:
        raise SystemExit("setAutoCaptureEnabled missing")
    t = t.replace(old_set, new_set, 1)

# After configureFlutterEngine flush, also rebind if needed
old_post = '''        mainHandler.post {
            flushQueuedCaptures()
            deliverOpenRoute(intent)
        }'''
new_post = '''        mainHandler.post {
            flushQueuedCaptures()
            deliverOpenRoute(intent)
            if (isNotificationAccessGranted() && !CentliNotificationListener.connected) {
                CentliNotificationListener.ensureRebind(this)
            }
        }'''
if "ensureRebind(this)" not in t.split("mainHandler.post")[1][:400]:
    if old_post not in t:
        raise SystemExit("mainHandler.post block missing")
    t = t.replace(old_post, new_post, 1)

# Add onResume
if "override fun onResume()" not in t:
    old_newintent = "    override fun onNewIntent(intent: Intent) {"
    new_resume = '''    override fun onResume() {
        super.onResume()
        if (isNotificationAccessGranted() && !CentliNotificationListener.connected) {
            CentliNotificationListener.ensureRebind(this)
        }
    }

    override fun onNewIntent(intent: Intent) {'''
    if old_newintent not in t:
        raise SystemExit("onNewIntent missing")
    t = t.replace(old_newintent, new_resume, 1)

# Fix isNotificationAccessGranted to accept short component names
old_grant = '''    private fun isNotificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        if (TextUtils.isEmpty(flat)) return false
        val cn = ComponentName(this, CentliNotificationListener::class.java)
        val expected = cn.flattenToString()
        return flat.split(':').any { it.equals(expected, ignoreCase = true) }
    }'''
new_grant = '''    private fun isNotificationAccessGranted(): Boolean {
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
    }'''
if "shortClassName" not in t:
    if old_grant not in t:
        raise SystemExit("isNotificationAccessGranted missing")
    t = t.replace(old_grant, new_grant, 1)

# Soften emit when channel null (native already wrote)
old_emit = '''        @JvmStatic
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
        }'''
new_emit = '''        @JvmStatic
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
        }'''
if 'Flutter channel null' not in t:
    if old_emit not in t:
        raise SystemExit("emitNotificationCapture missing")
    t = t.replace(old_emit, new_emit, 1)

p.write_text(t, encoding="utf-8", newline="\n")
print("MainActivity patched")
for k in ["isListenerConnected", "ensureListenerRebind", "onResume", "shortClassName", "Flutter channel null"]:
    print(k, k in t)

# -*- coding: utf-8 -*-
from pathlib import Path

listener = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\CentliNotificationListener.kt")
t = listener.read_text(encoding="utf-8")

# Add imports if missing
if "import android.util.Log" not in t:
    t = t.replace(
        "import android.service.notification.StatusBarNotification\n",
        "import android.service.notification.StatusBarNotification\n"
        "import android.content.ComponentName\n"
        "import android.content.pm.PackageManager\n"
        "import android.os.Build\n"
        "import android.util.Log\n",
        1,
    )

# Insert onListenerConnected/Disconnected before onNotificationPosted
if "onListenerConnected" not in t:
    old = "    override fun onNotificationPosted(sbn: StatusBarNotification?) {"
    new = '''    override fun onListenerConnected() {
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

    override fun onNotificationPosted(sbn: StatusBarNotification?) {'''
    if old not in t:
        raise SystemExit("onNotificationPosted not found")
    t = t.replace(old, new, 1)

# Replace MainActivity.emit only with native-first path
old_emit = "        MainActivity.emitNotificationCapture(this, payload)"
new_emit = '''        // Native SQLite path first — survives process kill / no Flutter engine.
        try {
            NativeCaptureIngest.ingestAndNotify(this, payload)
        } catch (e: Exception) {
            Log.e(TAG, "native ingest error", e)
            enqueue(this, payload)
        }
        // Flutter path for live UI (Dart dedupes if native already wrote).
        MainActivity.emitNotificationCapture(this, payload)'''
if "NativeCaptureIngest.ingestAndNotify" not in t:
    if old_emit not in t:
        raise SystemExit("emit call not found")
    t = t.replace(old_emit, new_emit, 1)

# Add companion TAG, connected, ensureRebind
if "var connected" not in t:
    old_c = '''    companion object {
        private const val PREFS = "centli_notification_capture"
        private const val KEY_AUTO = "auto_capture_enabled"
        private const val KEY_QUEUE = "pending_queue"'''
    new_c = '''    companion object {
        private const val TAG = "CentliNotiListener"
        private const val PREFS = "centli_notification_capture"
        private const val KEY_AUTO = "auto_capture_enabled"
        private const val KEY_QUEUE = "pending_queue"

        @Volatile
        var connected: Boolean = false
            private set'''
    if old_c not in t:
        raise SystemExit("companion start not found")
    t = t.replace(old_c, new_c, 1)

if "fun ensureRebind" not in t:
    # before closing of companion - find drainQueue end
    marker = "            } catch (_: Exception) {\n                emptyList()\n            }\n        }\n    }\n}"
    # More reliably append before last companion closing
    idx = t.rfind("        fun drainQueue")
    if idx < 0:
        raise SystemExit("drainQueue not found")
    # find end of drainQueue function then insert ensureRebind
    end = t.find("        }\n    }\n}", idx)
    if end < 0:
        raise SystemExit("companion end not found")
    insert = '''

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
'''
    # end points at "        }\n    }\n}" which is end of drainQueue + companion + class
    # Insert before "    }\n}" (companion close)
    companion_close = t.rfind("\n    }\n}")
    t = t[:companion_close] + insert + t[companion_close:]

listener.write_text(t, encoding="utf-8", newline="\n")
print("listener patched", listener.stat().st_size)
print("connected" in t, "ensureRebind" in t, "NativeCaptureIngest" in t)

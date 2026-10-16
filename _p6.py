from pathlib import Path
import re
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

# ===== MainActivity #10 bridgeReady =====
mp = ROOT / "android/app/src/main/kotlin/com/centli/centli/MainActivity.kt"
m = mp.read_text(encoding="utf-8")

# Add dartBridgeReady flag and bridgeReady handler
if "dartBridgeReady" not in m:
    m = m.replace(
        "    private val mainHandler = Handler(Looper.getMainLooper())\n",
        "    private val mainHandler = Handler(Looper.getMainLooper())\n\n"
        "    @Volatile\n"
        "    private var dartBridgeReady = false\n",
        1,
    )

# Insert bridgeReady case before else
if '"bridgeReady"' not in m:
    m = m.replace(
        "                else -> result.notImplemented()\n",
        '                "bridgeReady" -> {\n'
        "                    dartBridgeReady = true\n"
        "                    flushQueuedCaptures()\n"
        "                    flushQueuedPendingIntake()\n"
        "                    result.success(null)\n"
        "                }\n"
        "                else -> result.notImplemented()\n",
        1,
    )

# Remove early flush of queues from configureFlutterEngine post
# Keep deliverOpenRoute / deliverPendingIntake / rebind
old_post = """        // Flush any captures queued while Flutter was not running.
        mainHandler.post {
            flushQueuedCaptures()
            deliverOpenRoute(intent)
            deliverPendingIntake(intent)
            flushQueuedPendingIntake()
            if (isNotificationAccessGranted() && !CentliNotificationListener.connected) {
                CentliNotificationListener.ensureRebind(this)
            }
        }"""

new_post = """        // Do not flush capture queues here — Dart calls bridgeReady after handler bind (#10).
        mainHandler.post {
            deliverOpenRoute(intent)
            deliverPendingIntake(intent)
            if (isNotificationAccessGranted() && !CentliNotificationListener.connected) {
                CentliNotificationListener.ensureRebind(this)
            }
        }"""

if old_post not in m:
    raise SystemExit("post block missing")
m = m.replace(old_post, new_post, 1)

# flushQueuedCaptures: peek, deliver, clear only if ready
old_flush = """    private fun flushQueuedCaptures() {
        val queued = CentliNotificationListener.drainQueue(this)
        val ch = methodChannel ?: return
        for (payload in queued) {
            ch.invokeMethod("notification_capture", payload)
        }
    }"""

new_flush = """    private fun flushQueuedCaptures() {
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
    }"""

if old_flush not in m:
    raise SystemExit("flushQueuedCaptures missing")
m = m.replace(old_flush, new_flush, 1)

# flushQueuedPendingIntake gate on dartBridgeReady
old_fp = """    private fun flushQueuedPendingIntake() {
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
    }"""

new_fp = """    private fun flushQueuedPendingIntake() {
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
    }"""

if old_fp not in m:
    raise SystemExit("flushQueuedPendingIntake missing")
m = m.replace(old_fp, new_fp, 1)

mp.write_text(m, encoding="utf-8", newline="\n")
print("patched MainActivity")

# ===== #12 permission_explain_page =====
pep = ROOT / "lib/features/settings/permission_explain_page.dart"
pe = pep.read_text(encoding="utf-8")
old_pe = """    if (granted) {
      // Keep preference in sync once the user has granted access.
      final db = ref.read(databaseProvider);
      await db.setSetting('auto_capture_enabled', 'true');
      await NotificationCaptureStub.setAutoCaptureEnabled(true);
      // Binding often stays dead until an explicit rebind after toggle.
      await NotificationCaptureStub.ensureListenerRebind();
    }"""
new_pe = """    if (granted) {
      // Do NOT force auto_capture_enabled=true — permission != user opt-in (#12).
      // Only rebind so an already-enabled preference can take effect.
      await NotificationCaptureStub.ensureListenerRebind();
    }"""
if old_pe not in pe:
    raise SystemExit("permission auto-enable block missing")
pep.write_text(pe.replace(old_pe, new_pe, 1), encoding="utf-8", newline="\n")
print("patched permission_explain_page")

# ===== #20 pending categories in+out =====
pp = ROOT / "lib/features/pending/pending_page.dart"
pt = pp.read_text(encoding="utf-8")
old_cat = """              FutureBuilder<List<Category>>(
                future: ref
                    .read(databaseProvider)
                    .loadCategories(widget.ledgerId, 'out'),
                builder: (context, snap) {
                  final cats = snap.data ?? const <Category>[];"""
new_cat = """              FutureBuilder<List<Category>>(
                future: () async {
                  final db = ref.read(databaseProvider);
                  final out = await db.loadCategories(widget.ledgerId, 'out');
                  final inn = await db.loadCategories(widget.ledgerId, 'in');
                  return [...out, ...inn];
                }(),
                builder: (context, snap) {
                  final cats = snap.data ?? const <Category>[];"""
if old_cat not in pt:
    raise SystemExit("pending categories missing")
pt = pt.replace(old_cat, new_cat, 1)

# ===== #23 wrap seed button in kDebugMode =====
if "kDebugMode" not in pt:
    # add import
    if "package:flutter/foundation.dart" not in pt:
        pt = pt.replace(
            "import 'package:flutter/material.dart';",
            "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';",
            1,
        )
# Wrap the science IconButton
# Find IconButton with science_outlined
m = re.search(
    r"IconButton\(\n            tooltip: '[^']*',\n            icon: const Icon\(Icons\.science_outlined\),",
    pt,
)
if not m:
    # tooltip may be garbled
    m = re.search(
        r"IconButton\(\n            tooltip: .*?,\n            icon: const Icon\(Icons\.science_outlined\),",
        pt,
    )
if not m:
    raise SystemExit("seed IconButton missing")
# Find the whole IconButton including closing
start = m.start()
# find matching close - look for onPressed block end
end = pt.find("          ),\n        ],\n      ),\n      body:", start)
if end < 0:
    raise SystemExit("seed button end missing")
end = pt.find("\n", end)  # stay before ],
# Actually end should be right after the IconButton's closing `),`
btn_end = pt.find("          ),\n", start)
# The seed button closes with `          ),` then maybe more actions
# Find from start the first `          ),` that closes IconButton - after onPressed
depth_line = pt[start:start+800]
# simpler: wrap from IconButton( to its closing),
close = pt.find("            },\n          ),", start)
if close < 0:
    raise SystemExit("seed close missing")
close_end = close + len("            },\n          ),")
btn = pt[start:close_end]
wrapped = "if (kDebugMode)\n          " + btn
pt = pt[:start] + wrapped + pt[close_end:]
pp.write_text(pt, encoding="utf-8", newline="\n")
print("patched pending_page #20 #23")

# ===== #14 PIN lockout =====
asp = ROOT / "lib/features/security/app_lock_service.dart"
a = asp.read_text(encoding="utf-8")
if "lockout" not in a.lower() and "failedAttempts" not in a:
    # Add lockout fields and logic
    a = a.replace(
        "  static const _keySalt = 'centli_pin_salt';\n  static const _keyHash = 'centli_pin_hash';\n",
        "  static const _keySalt = 'centli_pin_salt';\n"
        "  static const _keyHash = 'centli_pin_hash';\n"
        "  static const _keyFailCount = 'centli_pin_fail_count';\n"
        "  static const _keyLockUntil = 'centli_pin_lock_until_ms';\n"
        "  static const _maxFails = 5;\n"
        "  static const _lockoutMs = 60 * 1000; // 1 minute\n",
        1,
    )
    old_verify = """  Future<bool> verifyPin(String pin) async {
    if (!_looksLikePin(pin)) return false;
    final salt = await _storage.read(key: _keySalt);
    final expected = await _storage.read(key: _keyHash);
    if (salt == null || expected == null) return false;
    return _hashPin(pin, salt) == expected;
  }"""
    new_verify = """  Future<Duration?> lockoutRemaining() async {
    final untilRaw = await _storage.read(key: _keyLockUntil);
    final until = int.tryParse(untilRaw ?? '');
    if (until == null) return null;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) {
      await _storage.delete(key: _keyLockUntil);
      return null;
    }
    return Duration(milliseconds: left);
  }

  Future<bool> verifyPin(String pin) async {
    if (!_looksLikePin(pin)) return false;
    final remaining = await lockoutRemaining();
    if (remaining != null) return false;
    final salt = await _storage.read(key: _keySalt);
    final expected = await _storage.read(key: _keyHash);
    if (salt == null || expected == null) return false;
    final ok = _hashPin(pin, salt) == expected;
    if (ok) {
      await _storage.delete(key: _keyFailCount);
      await _storage.delete(key: _keyLockUntil);
      return true;
    }
    final prev = int.tryParse(await _storage.read(key: _keyFailCount) ?? '0') ?? 0;
    final next = prev + 1;
    await _storage.write(key: _keyFailCount, value: '$next');
    if (next >= _maxFails) {
      final until = DateTime.now().millisecondsSinceEpoch + _lockoutMs;
      await _storage.write(key: _keyLockUntil, value: '$until');
      await _storage.write(key: _keyFailCount, value: '0');
    }
    return false;
  }"""
    if old_verify not in a:
        raise SystemExit("verifyPin missing")
    a = a.replace(old_verify, new_verify, 1)
    # clear lockout on clearPin
    a = a.replace(
        """  Future<void> clearPin() async {
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyHash);
  }""",
        """  Future<void> clearPin() async {
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyHash);
    await _storage.delete(key: _keyFailCount);
    await _storage.delete(key: _keyLockUntil);
  }""",
        1,
    )
    asp.write_text(a, encoding="utf-8", newline="\n")
    print("patched app_lock_service lockout")
else:
    print("lockout already present")

# Update app_lock_page to show lockout message if easy
alp = ROOT / "lib/features/security/app_lock_page.dart"
al = alp.read_text(encoding="utf-8")
if "lockoutRemaining" not in al and "verifyPin(v)" in al:
    al = al.replace(
        "final ok = await ref.read(appLockServiceProvider).verifyPin(v);",
        "final svc = ref.read(appLockServiceProvider);\n"
        "      final locked = await svc.lockoutRemaining();\n"
        "      if (locked != null) {\n"
        "        if (mounted) {\n"
        "          ScaffoldMessenger.of(context).showSnackBar(\n"
        "            SnackBar(content: Text('Try again in ${locked.inSeconds + 1}s')),\n"
        "          );\n"
        "        }\n"
        "        return;\n"
        "      }\n"
        "      final ok = await svc.verifyPin(v);",
        1,
    )
    alp.write_text(al, encoding="utf-8", newline="\n")
    print("patched app_lock_page")

print("p6 done")

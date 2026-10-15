# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

# --- IO ---
io_path = ROOT / "lib/platform/notifications/notification_listener_io.dart"
io = io_path.read_text(encoding="utf-8")
if "isListenerConnected" not in io:
    needle = """  static Future<bool> isPermissionGranted() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isPermissionGranted');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }"""
    insert = needle + """

  /// Whether NotificationListenerService.onListenerConnected has fired.
  /// Permission can be ON while this is false (OEM dropped the binding).
  static Future<bool> isListenerConnected() async {
    if (!supported) return false;
    try {
      final v = await _channel.invokeMethod<bool>('isListenerConnected');
      return v ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Ask the system to re-bind the notification listener service.
  static Future<void> ensureListenerRebind() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('ensureListenerRebind');
    } on MissingPluginException {
      // no-op
    } on PlatformException {
      // no-op
    }
  }"""
    if needle not in io:
        raise SystemExit("io needle missing")
    io_path.write_text(io.replace(needle, insert, 1), encoding="utf-8", newline="\n")
    print("io patched")
else:
    print("io ok")

# --- stub ---
stub_path = ROOT / "lib/platform/notifications/notification_listener_stub_impl.dart"
stub = stub_path.read_text(encoding="utf-8")
if "isListenerConnected" not in stub:
    stub = stub.replace(
        "  static Future<bool> isPermissionGranted() async => false;\n",
        "  static Future<bool> isPermissionGranted() async => false;\n\n"
        "  static Future<bool> isListenerConnected() async => false;\n\n"
        "  static Future<void> ensureListenerRebind() async {}\n",
        1,
    )
    stub_path.write_text(stub, encoding="utf-8", newline="\n")
    print("stub patched")
else:
    print("stub ok")

# --- bridge catch ---
bridge_path = ROOT / "lib/platform/notifications/notification_ingest_bridge.dart"
bridge = bridge_path.read_text(encoding="utf-8")
if "Native path may have inserted" not in bridge:
    old = """    final currency = parsed.currency ?? 'CNY';
    final id = await db.ingestParsedNotification(
      ledgerId: ledgerId,
      sourcePkg: notification.pkg,
      rawTitle: notification.title,
      rawText: notification.text,
      dedupeKey: key,
      amountMinor: parsed.amountMinor,
      currency: currency,
      merchant: parsed.merchant,
      happenAt: parsed.happenAt?.millisecondsSinceEpoch ?? notification.whenMs,
      parseOk: parsed.ok,
      accountHint: parsed.accountHint,
    );

    if (id != null) {
      await _showLocalPendingPush(
        pendingId: id,
        amountMinor: parsed.amountMinor,
        currency: currency,
        merchant: parsed.merchant,
      );
    }
    return id;"""
    new = """    final currency = parsed.currency ?? 'CNY';
    String? id;
    try {
      id = await db.ingestParsedNotification(
        ledgerId: ledgerId,
        sourcePkg: notification.pkg,
        rawTitle: notification.title,
        rawText: notification.text,
        dedupeKey: key,
        amountMinor: parsed.amountMinor,
        currency: currency,
        merchant: parsed.merchant,
        happenAt: parsed.happenAt?.millisecondsSinceEpoch ?? notification.whenMs,
        parseOk: parsed.ok,
        accountHint: parsed.accountHint,
      );
    } catch (e) {
      // Native path may have inserted the same dedupe_key already.
      return null;
    }

    if (id != null) {
      await _showLocalPendingPush(
        pendingId: id,
        amountMinor: parsed.amountMinor,
        currency: currency,
        merchant: parsed.merchant,
      );
    }
    return id;"""
    if old not in bridge:
        raise SystemExit("bridge block missing")
    bridge_path.write_text(bridge.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("bridge patched")
else:
    print("bridge ok")

# --- permission explain ---
perm_path = ROOT / "lib/features/settings/permission_explain_page.dart"
perm = perm_path.read_text(encoding="utf-8")
if "ensureListenerRebind" not in perm:
    old = """    if (granted) {
      // Keep preference in sync once the user has granted access.
      final db = ref.read(databaseProvider);
      await db.setSetting('auto_capture_enabled', 'true');
      await NotificationCaptureStub.setAutoCaptureEnabled(true);
    }"""
    new = """    if (granted) {
      // Keep preference in sync once the user has granted access.
      final db = ref.read(databaseProvider);
      await db.setSetting('auto_capture_enabled', 'true');
      await NotificationCaptureStub.setAutoCaptureEnabled(true);
      // Binding often stays dead until an explicit rebind after toggle.
      await NotificationCaptureStub.ensureListenerRebind();
    }"""
    if old not in perm:
        raise SystemExit("perm block missing")
    perm_path.write_text(perm.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("perm patched")
else:
    print("perm ok")

# --- auto_capture ---
auto_path = ROOT / "lib/features/settings/auto_capture_page.dart"
auto = auto_path.read_text(encoding="utf-8")
if "ensureListenerRebind" not in auto:
    if "bool _listenerConnected" not in auto:
        auto = auto.replace(
            "bool _granted = false;",
            "bool _granted = false;\n  bool _listenerConnected = false;",
            1,
        )
    old = """    final granted = await NotificationCaptureStub.isPermissionGranted();
    final batteryIgnored =
        await NotificationCaptureStub.isBatteryOptimizationIgnored();"""
    new = """    final granted = await NotificationCaptureStub.isPermissionGranted();
    if (granted) {
      await NotificationCaptureStub.ensureListenerRebind();
    }
    final connected = await NotificationCaptureStub.isListenerConnected();
    final batteryIgnored =
        await NotificationCaptureStub.isBatteryOptimizationIgnored();"""
    if old not in auto:
        raise SystemExit("auto reload missing")
    auto = auto.replace(old, new, 1)
    auto = auto.replace(
        "      _granted = granted;\n",
        "      _granted = granted;\n      _listenerConnected = connected;\n",
        1,
    )
    auto_path.write_text(auto, encoding="utf-8", newline="\n")
    print("auto patched")
else:
    print("auto ok")

# --- bookkeeping sheet ---
sheet = ROOT / "lib/features/ledger/bookkeeping_sheet.dart"
st = sheet.read_text(encoding="utf-8")
if "final detail = _speech.lastError" not in st:
    old_catch = (
        "    } catch (e) {\n"
        "      if (!mounted) return;\n"
        "      setState(() => _speechListening = false);\n"
        "      ScaffoldMessenger.of(context).showSnackBar(\n"
        "        SnackBar(content: Text('\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e')),\n"
        "      );\n"
        "    }"
    )
    new_catch = (
        "    } catch (e) {\n"
        "      if (!mounted) return;\n"
        "      setState(() => _speechListening = false);\n"
        "      final detail = _speech.lastError;\n"
        "      final msg = detail == null || detail.isEmpty\n"
        "          ? '\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e'\n"
        "          : '\\u8bed\\u97f3\\u8bc6\\u522b\\u5931\\u8d25: $e\\n$detail';\n"
        "      ScaffoldMessenger.of(context).showSnackBar(\n"
        "        SnackBar(content: Text(msg)),\n"
        "      );\n"
        "    }"
    )
    if old_catch not in st:
        print("WARN sheet catch not found; trying alt")
        # find catch near _toggleVoiceFill
        i = st.find("_toggleVoiceFill")
        j = st.find("} catch (e) {", i)
        print(repr(st[j:j+280]))
    else:
        sheet.write_text(st.replace(old_catch, new_catch, 1), encoding="utf-8", newline="\n")
        print("sheet patched")
else:
    print("sheet ok")

print("ALL DART DONE")

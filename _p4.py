from pathlib import Path
import re
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

pp = ROOT / "lib/platform/notifications/notification_parse.dart"
p = pp.read_text(encoding="utf-8")

m = re.search(r"const kAmountRegex =\n    r'([^']+)';", p)
if not m:
    raise SystemExit("kAmountRegex missing")
new_regex = (
    r"(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\s*|(?:\u00a5|\uffe5|\$|\u20ac))\s*"
    r"([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"
)
p = p[:m.start()] + "const kAmountRegex =\n    r'" + new_regex + "';" + p[m.end():]

old_ext = """_ExtractedAmount? _extractAmount(
  String body,
  String amountRegex,
  String defaultCcy,
) {
  final m = RegExp(amountRegex).firstMatch(body);
  if (m == null) return null;
  final raw = (m.group(1) ?? '').replaceAll(',', '');
  final major = double.tryParse(raw);
  if (major == null) return null;
  final ccy = detectCurrencyNearMatch(body, m, defaultCcy);
  return _ExtractedAmount(minor: toMinor(ccy, major), currency: ccy);
}"""

new_ext = """_ExtractedAmount? _extractAmount(
  String body,
  String amountRegex,
  String defaultCcy,
) {
  final re = RegExp(amountRegex);
  for (final m in re.allMatches(body)) {
    // Skip date fragments like 10月 / 15日 even if somehow matched.
    final end = m.end;
    final after = end < body.length ? body.substring(end, end + 1) : '';
    if (after.isNotEmpty && RegExp(r'[\u6708\u65e5\u53f7\u65f6\u5206\u79d2]').hasMatch(after)) {
      continue;
    }
    final raw = (m.group(1) ?? '').replaceAll(',', '');
    final major = double.tryParse(raw);
    if (major == null) continue;
    final ccy = detectCurrencyNearMatch(body, m, defaultCcy);
    return _ExtractedAmount(minor: toMinor(ccy, major), currency: ccy);
  }
  return null;
}"""

if old_ext not in p:
    raise SystemExit("_extractAmount missing")
p = p.replace(old_ext, new_ext, 1)
pp.write_text(p, encoding="utf-8", newline="\n")
print("patched notification_parse")

io_p = ROOT / "lib/platform/notifications/notification_listener_io.dart"
io = io_p.read_text(encoding="utf-8")

if "channelSupported" not in io:
    io = io.replace(
        "  static bool get supported => !kIsWeb && Platform.isAndroid;\n",
        "  static bool get supported => !kIsWeb && Platform.isAndroid;\n\n"
        "  /// MethodChannel available for share / deeplink on Android + iOS.\n"
        "  static bool get channelSupported =>\n"
        "      !kIsWeb && (Platform.isAndroid || Platform.isIOS);\n",
        1,
    )

bind_start = io.find("  /// Listen for native to Dart")
bind_pending_end = io.find("  static void unbind()")
if bind_start < 0 or bind_pending_end < 0:
    raise SystemExit("bind region missing %s %s" % (bind_start, bind_pending_end))

new_bind_region = '''  /// Listen for native to Dart `notification_capture` / `open_route` /
  /// `pending_intake` invokes.
  static Future<void> bind({
    required Future<void> Function(Map<String, dynamic> raw) onCapture,
  }) async {
    _onCapture = onCapture;
    await _ensureChannelHandler();
  }

  /// Register handler for native share / deep-link (`pending_intake`).
  /// Binds on Android and iOS (not gated by [supported] notification listener).
  static Future<void> bindPendingIntake(
    void Function(Map<String, dynamic> payload) onIntake,
  ) async {
    onPendingIntake = onIntake;
    await _ensureChannelHandler();
  }

  static Future<void> _ensureChannelHandler() async {
    if (!channelSupported) return;
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler(_onMethodCall);
    // Ask native to flush queues only after Dart handler is bound (#10).
    try {
      await _channel.invokeMethod<void>('bridgeReady');
    } on MissingPluginException {
      // iOS / older builds may not implement yet.
    } on PlatformException {
      // ignore
    }
  }

  static Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'notification_capture') {
      final args = call.arguments;
      if (args is Map) {
        final raw = Map<String, dynamic>.from(args);
        final handler = _onCapture;
        if (handler != null) {
          await handler(raw);
        }
      }
      return null;
    }
    if (call.method == 'open_route') {
      final args = call.arguments;
      if (args is Map) {
        final map = Map<String, dynamic>.from(args);
        final route = map['route'] as String?;
        final pendingId = map['pendingId'] as String?;
        if (route != null && route.isNotEmpty) {
          onOpenRoute?.call(route, pendingId);
        }
      }
      return null;
    }
    if (call.method == 'pending_intake') {
      final args = call.arguments;
      if (args is Map) {
        onPendingIntake?.call(Map<String, dynamic>.from(args));
      }
      return null;
    }
    throw MissingPluginException(
      'No handler for method ${call.method} on $channelName',
    );
  }

'''

io = io[:bind_start] + new_bind_region + io[bind_pending_end:]

old_unbind = """  static void unbind() {
    _onCapture = null;
    if (_bound && supported) {
      _channel.setMethodCallHandler(null);
      _bound = false;
    }
  }"""
new_unbind = """  static void unbind() {
    _onCapture = null;
    onPendingIntake = null;
    if (_bound && channelSupported) {
      _channel.setMethodCallHandler(null);
      _bound = false;
    }
  }"""
if old_unbind not in io:
    # maybe already partially changed
    if "channelSupported" in io[io.find("static void unbind"):io.find("static void unbind")+200]:
        print("unbind already patched")
    else:
        raise SystemExit("unbind missing")
else:
    io = io.replace(old_unbind, new_unbind, 1)

io_p.write_text(io, encoding="utf-8", newline="\n")
print("patched notification_listener_io")

stub = ROOT / "lib/platform/notifications/notification_listener_stub_impl.dart"
st = stub.read_text(encoding="utf-8")
if "channelSupported" not in st:
    st = st.replace(
        "  static const bool supported = false;",
        "  static const bool supported = false;\n  static const bool channelSupported = false;",
        1,
    )
    stub.write_text(st, encoding="utf-8", newline="\n")
    print("patched stub_impl")

print("p4 done")

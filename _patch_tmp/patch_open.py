# -*- coding: utf-8 -*-
from pathlib import Path
auto_path = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\settings\auto_capture_page.dart")
auto = auto_path.read_text(encoding="utf-8")
old = """  Future<void> _openPermission() async {
    final result = await context.push<bool>(
      _granted ? '/me/permission' : '/me/permission?open=1',
    );
    if (!mounted) return;
    final granted = result == true
        ? true
        : await NotificationCaptureStub.isPermissionGranted();
    setState(() => _granted = granted);
    await _reload(soft: true);
  }"""
new = """  Future<void> _openPermission() async {
    if (_granted && !_listenerConnected) {
      await NotificationCaptureStub.ensureListenerRebind();
      final connected = await NotificationCaptureStub.isListenerConnected();
      if (!mounted) return;
      setState(() => _listenerConnected = connected);
      if (connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已请求重新连接通知监听')),
        );
        return;
      }
    }
    final result = await context.push<bool>(
      _granted ? '/me/permission' : '/me/permission?open=1',
    );
    if (!mounted) return;
    final granted = result == true
        ? true
        : await NotificationCaptureStub.isPermissionGranted();
    setState(() => _granted = granted);
    await _reload(soft: true);
  }"""
if old not in auto:
    raise SystemExit('openPermission missing')
auto_path.write_text(auto.replace(old, new, 1), encoding="utf-8", newline="\n")
print("openPermission patched")

# Fix NativeCaptureIngest AMOUNT if still broken
native = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
nt = native.read_text(encoding="utf-8")
# Show AMOUNT
import re
m = re.search(r'private val AMOUNT[\s\S]*?\n    \)', nt)
print("AMOUNT:\n", m.group(0) if m else "MISSING")

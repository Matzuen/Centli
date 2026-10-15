# -*- coding: utf-8 -*-
from pathlib import Path

# Show listener structure around companion / ensureRebind
t = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\CentliNotificationListener.kt").read_text(encoding="utf-8")
print("=== last 80 lines ===")
print("\n".join(t.splitlines()[-80:]))

# Use _listenerConnected in auto_capture UI near permission tile
auto_path = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\settings\auto_capture_page.dart")
auto = auto_path.read_text(encoding="utf-8")
if "_listenerConnected" in auto and "监听未连接" not in auto and "\\u76d1\\u542c" not in auto:
    # Find permission ListTile / status text patterns
    # Soft: add a small banner after loading check if granted but not connected
    needle = "      body: _loading"
    # Look for something we can hang a banner on - Card about permission
    idx = auto.find("_granted")
    print("auto has _listenerConnected; searching UI hooks")
    # Find Text that mentions permission status
    for line in auto.splitlines():
        if "通知" in line or "permission" in line.lower() or "权限" in line or "\\u901a\\u77e5" in line:
            if "Text(" in line or "title:" in line or "subtitle:" in line:
                print(" UI:", line.strip()[:120])

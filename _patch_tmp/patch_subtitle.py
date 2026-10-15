# -*- coding: utf-8 -*-
from pathlib import Path
auto_path = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\settings\auto_capture_page.dart")
auto = auto_path.read_text(encoding="utf-8")
old = """                    subtitle: Text(
                      !supported
                          ? '仅 Android 可申请'
                          : (_granted ? '已开启' : '未开启 · 去开启'),
                    ),"""
new = """                    subtitle: Text(
                      !supported
                          ? '仅 Android 可申请'
                          : (!_granted
                              ? '未开启 · 去开启'
                              : (_listenerConnected
                                  ? '已开启 · 监听已连接'
                                  : '已开启 · 监听未连接（请点此重连或开关一次通知使用权）')),
                    ),"""
if old not in auto:
    raise SystemExit('subtitle block not found')
auto_path.write_text(auto.replace(old, new, 1), encoding="utf-8", newline="\n")
print("subtitle updated")

# Also call rebind when tapping permission if already granted
# Check _openPermission

# -*- coding: utf-8 -*-
from pathlib import Path
auto_path = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\settings\auto_capture_page.dart")
auto = auto_path.read_text(encoding="utf-8")
# Find notification permission ListTile block
i = auto.find("title: const Text('\u901a\u77e5\u6743\u9650')")
if i < 0:
    i = auto.find("title: const Text('通知权限')")
print("idx", i)
print(repr(auto[i-200:i+500]))

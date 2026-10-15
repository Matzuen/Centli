# -*- coding: utf-8 -*-
from pathlib import Path
native = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
t = native.read_text(encoding="utf-8")
old = 'val dbFile = File(context.applicationContext.filesDir, DB_NAME)'
new = 'val dbFile = File(context.applicationContext.getDir("flutter", Context.MODE_PRIVATE), DB_NAME)'
if old not in t:
    raise SystemExit('dbFile line not found: ' + repr([line for line in t.splitlines() if 'dbFile' in line][:3]))
t = t.replace(old, new, 1)
# Update comment
t = t.replace(
    "Path: context.filesDir / centli.sqlite (path_provider documents dir on Android).",
    "Path: context.getDir(\"flutter\") / centli.sqlite (path_provider getApplicationDocumentsDirectory).",
)
native.write_text(t, encoding="utf-8", newline="\n")
print("db path fixed to app_flutter")
print([line for line in native.read_text(encoding='utf-8').splitlines() if 'dbFile' in line or 'getDir' in line])

# -*- coding: utf-8 -*-
from pathlib import Path
files = [
r"lib\features\ledger\local_speech.dart",
r"lib\features\ledger\bookkeeping_sheet.dart",
r"lib\platform\notifications\notification_parse.dart",
r"lib\platform\notifications\notification_listener_io.dart",
r"lib\platform\notifications\notification_listener_stub_impl.dart",
r"lib\platform\notifications\notification_ingest_bridge.dart",
r"lib\features\settings\permission_explain_page.dart",
r"lib\features\settings\auto_capture_page.dart",
r"android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt",
r"android\app\src\main\kotlin\com\centli\centli\CentliNotificationListener.kt",
r"android\app\src\main\kotlin\com\centli\centli\MainActivity.kt",
]
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
for f in files:
    p = root/f
    print(f"{'OK' if p.exists() else 'MISS'} {f} ({p.stat().st_size if p.exists() else 0})")
# quick sanity
listener = (root/"android/app/src/main/kotlin/com/centli/centli/CentliNotificationListener.kt").read_text(encoding="utf-8")
assert "NativeCaptureIngest.ingestAndNotify" in listener
assert "onListenerDisconnected" in listener
assert "ensureRebind" in listener
main = (root/"android/app/src/main/kotlin/com/centli/centli/MainActivity.kt").read_text(encoding="utf-8")
assert "isListenerConnected" in main
assert "onResume" in main
native = (root/"android/app/src/main/kotlin/com/centli/centli/NativeCaptureIngest.kt").read_text(encoding="utf-8")
assert 'getDir("flutter"' in native
speech = (root/"lib/features/ledger/local_speech.dart").read_text(encoding="utf-8")
assert "onDevice: false" in speech
print("SANITY OK")

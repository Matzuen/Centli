# -*- coding: utf-8 -*-
from pathlib import Path
# Verify Drift table names in generated code if present
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
gens = list((root/"lib").rglob("*database*.g.dart")) + list((root/"lib").rglob("*.g.dart"))
print("generated", [str(g.relative_to(root)) for g in gens[:20]])
for g in gens:
    t = g.read_text(encoding="utf-8", errors="replace")
    if "pending_captures" in t or "CREATE TABLE" in t:
        if "pending_captures" in t:
            print("found pending_captures in", g.name)
        if "app_settings" in t:
            print("found app_settings in", g.name)
# path_provider
import os
pp = Path(os.environ["LOCALAPPDATA"]) / "Pub" / "Cache" / "hosted" / "pub.dev"
hits = list(pp.glob("path_provider_android-*/android/**/*.kt")) + list(pp.glob("path_provider_android-*/android/**/*.java"))
print("pp android files", hits[:5])
for h in hits:
    txt = h.read_text(encoding="utf-8", errors="replace")
    if "getApplicationDocumentsPath" in txt or "filesDir" in txt or "Documents" in txt:
        for line in txt.splitlines():
            if "Document" in line or "filesDir" in line or "getPath" in line:
                print(h.name, ":", line.strip())

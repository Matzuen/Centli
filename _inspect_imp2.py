from pathlib import Path
t = Path("lib/data/export/import_service.dart").read_text(encoding="utf-8")
i = t.find("final schemaVersion = _asInt")
print(repr(t[i:i+220]))
needle = "final accounts = _asMapList(map['accounts'], 'accounts')"
print("needle in file", needle in t)
print("repr needle section", repr(t[t.find("final accounts"):t.find("final accounts")+80]))

from pathlib import Path
import re
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
# Find DB path, pendingCaptures schema, existsDedupeKey
db = (root / "lib/data/db/centli_database.dart").read_text(encoding="utf-8")
for needle in ["LazyDatabase", "getApplicationDocumentsDirectory", "centli.sqlite", "openConnection", "NativeDatabase", "existsDedupeKey", "pendingCaptures", "class PendingCaptures", "auto_capture"]:
    print(needle, "->", db.find(needle))

i = db.find("existsDedupeKey")
print("==== existsDedupeKey ====")
print(db[i:i+500])

# schema file
for p in (root/"lib").rglob("*"):
    if p.is_file() and ("schema" in p.name.lower() or "table" in p.name.lower() or p.name.endswith(".drift") or "pending" in p.name.lower()):
        print("FILE", p)

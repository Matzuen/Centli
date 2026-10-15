from pathlib import Path
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
db = (root / "lib/data/db/centli_database.dart").read_text(encoding="utf-8")
print(db[66380:66750])
print("==== TABLE ====")
print((root/"lib/data/db/tables/pending_captures.dart").read_text(encoding="utf-8"))
# settings table / current ledger
for needle in ["currentLedgerId", "getSetting", "settings", "app_documents", "flutter."]:
    pass
print("==== currentLedgerId ====")
i = db.find("currentLedgerId")
print(db[i:i+400])
print("==== settings table ====")
for p in (root/"lib/data/db/tables").glob("*.dart"):
    print(p.name)
    if "setting" in p.name.lower():
        print(p.read_text(encoding="utf-8")[:800])

from pathlib import Path
import re
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
p = root / "lib/platform/notifications/notification_parse.dart"
raw = p.read_bytes()
idx = raw.find(b"mustContainRegex")
print("BYTES:", raw[idx:idx+180])
t = p.read_text(encoding="utf-8")
for m in re.finditer(r"mustContainRegex: '([^']+)'", t):
    s = m.group(1)
    print("mustContain:", repr(s))
    print("codepoints:", [hex(ord(c)) for c in s])
db = (root / "lib/data/db/centli_database.dart").read_text(encoding="utf-8")
i = db.find("ingestParsedNotification")
print("==== INGEST ====")
print(db[i:i+3500])

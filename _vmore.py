from pathlib import Path
import re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# callers of insert/updateManualTransaction
root = Path(".")
for p in root.rglob("*.dart"):
    if p.name.endswith(".g.dart"): continue
    t = p.read_text(encoding="utf-8", errors="replace")
    if "insertManualTransaction" in t or "updateManualTransaction" in t:
        print(p)

# Native AMOUNT line
n = Path("android/app/src/main/kotlin/com/centli/centli/NativeCaptureIngest.kt").read_text(encoding="utf-8")
m = re.search(r"private val AMOUNT.*?\n.*?\)", n, re.S)
print("AMOUNT:\n", m.group(0) if m else "MISSING")

# Dart kAmountRegex
d = Path("lib/platform/notifications/notification_parse.dart").read_text(encoding="utf-8")
m = re.search(r"const kAmountRegex =.*?;", d, re.S)
print("kAmountRegex:\n", m.group(0) if m else "MISSING")

# bracket balance bookkeeping
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
print("parens", b.count("(")-b.count(")"), "braces", b.count("{")-b.count("}"), "brackets", b.count("[")-b.count("]"))

# notification tests
tp = Path("test/notification_parse_test.dart")
if tp.exists():
    tt = tp.read_text(encoding="utf-8")
    print("test mentions 月", "月" in tt)
    print("test file lines", tt.count("\n"))

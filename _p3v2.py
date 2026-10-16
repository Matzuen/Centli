from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
# Check unicode labels
import re
for m in re.finditer(r"Text\('([^']{1,20})'", b[b.find("if (_type == 'transfer')"):b.find("if (_type == 'transfer')")+5000]):
    s=m.group(1)
    print(repr(s), [hex(ord(c)) for c in s])
k = b.find("key: ValueKey('dd-acc-")
print("--- after acc ---")
print(b[k:k+700])
print("placeholder?", "KEY_TRANSFER" in b)

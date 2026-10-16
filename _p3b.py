from pathlib import Path
import re
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
print("merchant field", "String? _merchant;" in b)
print("replaceFx load archived", "getAccount(id)" in b)
print("finally dispose", "finally {\n      toCtrl.dispose();" in b)
print("merchant save", "merchant: merchant," in b)
print("merchantText", "_merchant =" in b and "merchantText" in b)
print("ValueKeys:")
for m in re.finditer(r"ValueKey\('dd[^']*'\)", b):
    print(" ", m.group())
print("old key left", b.count("dd-$_fieldEpoch-${_accountId}"))
# third dropdown may use different quote style
for m in re.finditer(r"DropdownButtonFormField[\s\S]{0,200}ValueKey\([^\)]+\)", b):
    print("DD:", m.group()[:120].replace("\n"," "))

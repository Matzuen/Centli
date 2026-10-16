from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
i = b.find("if (_type == 'transfer')")
# find the transfer UI block start near dropdowns
j = b.find("if (_type == 'transfer') ...[")
print("j", j)
print(b[j:j+2500])

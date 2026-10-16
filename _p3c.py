from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
idx = 0
while True:
    i = b.find("DropdownButtonFormField", idx)
    if i < 0: break
    print("---", i)
    print(b[i:i+350])
    idx = i + 1

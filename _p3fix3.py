from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
j = b.find("if (_type == 'transfer') ...[")
# find end of else account dropdown - look for next section after account dropdown
k = b.find("] else\n                  Padding(", j)
print("else at", k)
# find after the else dropdown closes - look for category section or similar
rest = b[k:k+1200]
print(rest)

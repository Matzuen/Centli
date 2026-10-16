from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
start = b.find("if (_type == 'transfer') ...[")
chunk = b[start:start+5600]
i = chunk.find("dd-acc-")
print(repr(chunk[i+700:i+1000]))

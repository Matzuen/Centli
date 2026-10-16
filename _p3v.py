from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
j = b.find("if (_type == 'transfer') ...[")
print(b[j:j+2800])
print("====AFTER====")
# show 200 chars after the else padding
k = b.find("key: ValueKey('dd-acc-")
print(b[k:k+600])

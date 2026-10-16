from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
# Show corrupted region
i = b.find("KEY_TRANSFER_FROM_PLACEHOLDER")
print("placeholder at", i)
print(repr(b[i-400:i+800]))

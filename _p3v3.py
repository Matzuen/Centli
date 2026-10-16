from pathlib import Path
b = Path("lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
start = b.find("if (_type == 'transfer') ...[")
chunk = b[start:start+5500]
# find labels near transfer
assert "\u8f6c\u51fa" in chunk, "zhuanchu missing"
assert "\u8f6c\u5165" in chunk, "zhuanru missing"
assert "\u8d26\u6237" in chunk, "zhanghu missing"
assert "dd-from-" in chunk and "dd-to-" in chunk and "dd-acc-" in chunk
# show tail after dd-acc decoration
i = chunk.find("dd-acc-")
print(chunk[i:i+900])
# rough paren balance in chunk until we hit next sibling at same indent
print("OK labels and keys")

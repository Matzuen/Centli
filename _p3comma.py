from pathlib import Path
p = Path("lib/features/ledger/bookkeeping_sheet.dart")
b = p.read_text(encoding="utf-8")
old = """                      ],
                    ),
                  )
                Padding(
                  padding: const EdgeInsets"""
new = """                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets"""
if old not in b:
    raise SystemExit("comma site missing")
p.write_text(b.replace(old, new, 1), encoding="utf-8", newline="\n")
print("added trailing comma after else Padding")

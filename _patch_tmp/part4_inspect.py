# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

# export_page
p = ROOT / "lib/features/settings/export_page.dart"
t = p.read_text(encoding="utf-8")
old = "summary / accounts / categories / transactions / pending / merchant_rules"
new = "summary / accounts / categories / transactions / pending / merchant_rules / budgets"
if "merchant_rules / budgets" not in t:
    if old not in t:
        raise SystemExit("export subtitle not found")
    t = t.replace(old, new, 1)
    p.write_text(t, encoding="utf-8")
print("export_page OK")

# import_page - inspect snackbar and preview encoding
p = ROOT / "lib/features/settings/import_page.dart"
t = p.read_text(encoding="utf-8")
# find snippets
idx = t.find("result.categories")
print("snack snippet:", repr(t[idx-120:idx+80]))
idx2 = t.find("fxRates.length")
print("preview snippet:", repr(t[idx2-80:idx2+120]))

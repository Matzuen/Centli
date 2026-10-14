# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\features\settings\import_page.dart")
t = p.read_text(encoding="utf-8")

old_snack = (
    "'${result.categories} \\u5206\\u7c7b',\n"
)
new_snack = (
    "'${result.categories} \\u5206\\u7c7b / '\n"
    "            '${result.budgets} \\u9884\\u7b97',\n"
)
if "result.budgets" not in t:
    if old_snack not in t:
        raise SystemExit("snack not found: " + repr(old_snack))
    t = t.replace(old_snack, new_snack, 1)

old_prev = (
    "'\\u6c47\\u7387 ${preview.bundle.fxRates.length} \\u00b7 '\n"
    "                '\\u8bbe\\u7f6e\\u952e ${preview.bundle.settings.length}',\n"
)
new_prev = (
    "'\\u6c47\\u7387 ${preview.bundle.fxRates.length} \\u00b7 '\n"
    "                '\\u9884\\u7b97 ${preview.bundle.budgets.length} \\u00b7 '\n"
    "                '\\u8bbe\\u7f6e\\u952e ${preview.bundle.settings.length}',\n"
)
if "bundle.budgets.length" not in t:
    if old_prev not in t:
        raise SystemExit("preview not found")
    t = t.replace(old_prev, new_prev, 1)

p.write_text(t, encoding="utf-8")
print("import_page OK")

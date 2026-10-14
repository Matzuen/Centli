# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")
checks = {
  "db loadBudgetsForExport": "loadBudgetsForExport",
  "db budgetMaps": "budgetMaps",
  "db budget insert": "for (final b in budgetRows)",
  "db stats budgets": "budgets: budgetRows.length",
  "export budgets key": "'budgets': budgetRows",
  "export schema 2": "'schema_version': 2",
  "export excel sheet": "excel['budgets']",
  "import bundle budgets": "final List<Map<String, dynamic>> budgets;",
  "import normalize": "_normalizeBudget",
  "import Budget.fromJson": "Budget.fromJson(b)",
  "import budgetMaps call": "budgetMaps: bundle.budgets",
  "export page": "merchant_rules / budgets",
  "import preview": "bundle.budgets.length",
  "import snack": "result.budgets",
}
files = {
  "db loadBudgetsForExport": ROOT/"lib/data/db/centli_database.dart",
  "db budgetMaps": ROOT/"lib/data/db/centli_database.dart",
  "db budget insert": ROOT/"lib/data/db/centli_database.dart",
  "db stats budgets": ROOT/"lib/data/db/centli_database.dart",
  "export budgets key": ROOT/"lib/data/export/export_service.dart",
  "export schema 2": ROOT/"lib/data/export/export_service.dart",
  "export excel sheet": ROOT/"lib/data/export/export_service.dart",
  "import bundle budgets": ROOT/"lib/data/export/import_service.dart",
  "import normalize": ROOT/"lib/data/export/import_service.dart",
  "import Budget.fromJson": ROOT/"lib/data/export/import_service.dart",
  "import budgetMaps call": ROOT/"lib/data/export/import_service.dart",
  "export page": ROOT/"lib/features/settings/export_page.dart",
  "import preview": ROOT/"lib/features/settings/import_page.dart",
  "import snack": ROOT/"lib/features/settings/import_page.dart",
}
ok=True
for k,v in checks.items():
  text = files[k].read_text(encoding="utf-8")
  found = v in text
  print(("OK" if found else "MISS"), k)
  ok = ok and found
# other callers of restoreFromImportBundle
import re
hits=[]
for f in ROOT.joinpath("lib").rglob("*.dart"):
  s=f.read_text(encoding="utf-8", errors="ignore")
  if "restoreFromImportBundle" in s:
    hits.append(str(f))
print("restore callers:", hits)
raise SystemExit(0 if ok else 1)

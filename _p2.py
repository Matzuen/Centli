from pathlib import Path
import re

ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")
imp_p = ROOT / "lib/data/export/import_service.dart"
imp = imp_p.read_text(encoding="utf-8")

imp2, n = re.subn(
    r"(if \(schemaVersion < 1 \|\| schemaVersion > )2(\))",
    r"\g<1>3\2",
    imp,
    count=1,
)
print("schema replacements", n)
imp = imp2

needle = "final accounts = _asMapList(map['accounts'], 'accounts')"
print("needle found", needle in imp)
if needle not in imp:
    raise SystemExit("accounts needle missing")

req = (
    "// Missing required arrays must fail before wipe (null != empty).\n"
    "    for (final key in ['accounts', 'categories', 'transactions']) {\n"
    "      if (!map.containsKey(key)) {\n"
    "        throw StateError('missing required field: $key');\n"
    "      }\n"
    "    }\n"
    "\n"
    "    final accounts = _asMapList(map['accounts'], 'accounts')"
)
imp = imp.replace(needle, req, 1)

# null -> throw
old_null = "    if (v == null) return [];"
new_null = (
    "    if (v == null) {\n"
    "      throw StateError('$field cannot be null');\n"
    "    }"
)
if old_null not in imp:
    raise SystemExit("null branch missing")
imp = imp.replace(old_null, new_null, 1)

# optional lists: pass empty list when key absent
for opt in ["merchant_rules", "pending_captures", "fx_rates", "budgets"]:
    old = "_asMapList(map['%s'], '%s')" % (opt, opt)
    new = "_asMapList(map['%s'] ?? const <dynamic>[], '%s')" % (opt, opt)
    if old not in imp:
        raise SystemExit("optional missing: " + opt)
    imp = imp.replace(old, new, 1)

old_restore = "  Future<ImportResult> restore(ImportBundle bundle) async {\n    final stats = await db.restoreFromImportBundle(\n      ledgerMap: bundle.ledger,\n      accountMaps: bundle.accounts,\n      categoryMaps: bundle.categories,\n      transactionMaps: bundle.transactions,\n      merchantRuleMaps: bundle.merchantRules,\n      pendingCaptureMaps: bundle.pendingCaptures,\n      fxRateMaps: bundle.fxRates,\n      budgetMaps: bundle.budgets,\n      settingsMap: bundle.settings,\n      settingsSkipKeys: _settingsSkipKeys,\n    );"

new_restore = "  Future<ImportResult> restore(\n    ImportBundle bundle, {\n    bool replaceFxRates = true,\n  }) async {\n    final stats = await db.restoreFromImportBundle(\n      ledgerMap: bundle.ledger,\n      accountMaps: bundle.accounts,\n      categoryMaps: bundle.categories,\n      transactionMaps: bundle.transactions,\n      merchantRuleMaps: bundle.merchantRules,\n      pendingCaptureMaps: bundle.pendingCaptures,\n      fxRateMaps: bundle.fxRates,\n      budgetMaps: bundle.budgets,\n      settingsMap: bundle.settings,\n      settingsSkipKeys: _settingsSkipKeys,\n      replaceFxRates: replaceFxRates,\n    );"

if old_restore not in imp:
    raise SystemExit("restore block missing")
imp = imp.replace(old_restore, new_restore, 1)

# Excel limitations: replace first line only via regex if present
imp_p.write_text(imp, encoding="utf-8", newline="\n")
print("wrote import_service")

# import_page
ip = ROOT / "lib/features/settings/import_page.dart"
ipt = ip.read_text(encoding="utf-8")
old = "await svc.restore(b);"
new = "await svc.restore(\n        b,\n        replaceFxRates: preview.sourceKind != 'excel',\n      );"
if old not in ipt:
    raise SystemExit("import_page restore missing")
ip.write_text(ipt.replace(old, new, 1), encoding="utf-8", newline="\n")
print("wrote import_page")

# export version
exp = ROOT / "lib/data/export/export_service.dart"
et = exp.read_text(encoding="utf-8")
et = et.replace("static const appVersion = '1.0.0+1';", "static const appVersion = '1.0.1+2';")
et = et.replace("'schema_version': 2,", "'schema_version': 3,")
exp.write_text(et, encoding="utf-8", newline="\n")
print("wrote export_service")

# -*- coding: utf-8 -*-
from pathlib import Path

ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

def read(p): return p.read_text(encoding="utf-8")
def write(p, s): p.write_text(s, encoding="utf-8", newline="\n"); print("ok", p.name)

# ---------- import_service #3 #4 #24 ----------
imp_p = ROOT / "lib/data/export/import_service.dart"
imp = read(imp_p)

# #3 require transactions key
old_as = """  static List<Map<String, dynamic>> _asMapList(Object? v, String field) {
    if (v == null) return [];
    if (v is! List) {
      throw StateError('$field 必须是数组');
    }
    return [
      for (final e in v)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }"""

# Encoding may have garbled Chinese - match by structure
import re
m = re.search(
    r"static List<Map<String, dynamic>> _asMapList\(Object\? v, String field\) \{.*?\n  \}",
    imp,
    re.S,
)
if not m:
    raise SystemExit("_asMapList not found")
# Keep Chinese error messages as-is from file; just change null handling for required fields via callers

# Replace parseJsonString validation for schema and missing transactions
old_schema = """    final schemaVersion = _asInt(map['schema_version'], 'schema_version');
    if (schemaVersion < 1 || schemaVersion > 2) {
      throw StateError('不支持的数据版本 schema_version=$schemaVersion');
    }"""

# Try flexible match for garbled Chinese
m2 = re.search(
    r"final schemaVersion = _asInt\(map\['schema_version'\], 'schema_version'\);\n"
    r"    if \(schemaVersion < 1 \|\| schemaVersion > 2\) \{\n"
    r"      throw StateError\('([^']*)'\);\n"
    r"    \}",
    imp,
)
if not m2:
    raise SystemExit("schema check not found")
err_msg = m2.group(1)
# Keep similar message but allow schema 3
imp = imp[:m2.start()] + (
    "final schemaVersion = _asInt(map['schema_version'], 'schema_version');\n"
    "    if (schemaVersion < 1 || schemaVersion > 3) {\n"
    f"      throw StateError('{err_msg}');\n"
    "    }"
) + imp[m2.end()]

# Require transactions / accounts / categories keys before _asMapList
marker = "final accounts = _asMapList(map['accounts'], 'accounts')"
if marker not in imp:
    raise SystemExit("accounts marker not found")
require_block = """    // Missing required arrays must fail before wipe (null ≠ empty).
    for (final key in ['accounts', 'categories', 'transactions']) {
      if (!map.containsKey(key)) {
        throw StateError('缺少必填字段: $key');
      }
    }

    final accounts = _asMapList(map['accounts'], 'accounts')"""
imp = imp.replace(marker, require_block, 1)

# Change _asMapList null → throw for clarity when key present but null
m3 = re.search(
    r"static List<Map<String, dynamic>> _asMapList\(Object\? v, String field\) \{\n"
    r"    if \(v == null\) return \[\];\n",
    imp,
)
if not m3:
    raise SystemExit("_asMapList null branch not found")
imp = (
    imp[: m3.start()]
    + "static List<Map<String, dynamic>> _asMapList(Object? v, String field) {\n"
    "    if (v == null) {\n"
    "      throw StateError('$field 不能为 null');\n"
    "    }\n"
    + imp[m3.end() :]
)

# Optional lists: merchant_rules / pending / fx / budgets may be absent → use empty
# Fix callers for optional keys
for opt in ['merchant_rules', 'pending_captures', 'fx_rates', 'budgets']:
    old = f"_asMapList(map['{opt}'], '{opt}')"
    new = f"_asMapList(map['{opt}'] ?? const <dynamic>[], '{opt}')"
    if old not in imp:
        raise SystemExit(f"optional {opt} not found")
    imp = imp.replace(old, new, 1)

# restore() pass replaceFxRates
old_restore = """  Future<ImportResult> restore(ImportBundle bundle) async {
    final stats = await db.restoreFromImportBundle(
      ledgerMap: bundle.ledger,
      accountMaps: bundle.accounts,
      categoryMaps: bundle.categories,
      transactionMaps: bundle.transactions,
      merchantRuleMaps: bundle.merchantRules,
      pendingCaptureMaps: bundle.pendingCaptures,
      fxRateMaps: bundle.fxRates,
      budgetMaps: bundle.budgets,
      settingsMap: bundle.settings,
      settingsSkipKeys: _settingsSkipKeys,
    );"""

new_restore = """  Future<ImportResult> restore(
    ImportBundle bundle, {
    bool replaceFxRates = true,
  }) async {
    final stats = await db.restoreFromImportBundle(
      ledgerMap: bundle.ledger,
      accountMaps: bundle.accounts,
      categoryMaps: bundle.categories,
      transactionMaps: bundle.transactions,
      merchantRuleMaps: bundle.merchantRules,
      pendingCaptureMaps: bundle.pendingCaptures,
      fxRateMaps: bundle.fxRates,
      budgetMaps: bundle.budgets,
      settingsMap: bundle.settings,
      settingsSkipKeys: _settingsSkipKeys,
      replaceFxRates: replaceFxRates,
    );"""

if old_restore not in imp:
    raise SystemExit("restore method not found")
imp = imp.replace(old_restore, new_restore)

# Update excelRestoreLimitations warning text (keep bilingual safe ASCII+)
# Find excelRestoreLimitations
m4 = re.search(
    r"static const excelRestoreLimitations = <String>\[\n(.*?)\n  \];",
    imp,
    re.S,
)
if m4:
    imp = (
        imp[: m4.start()]
        + "static const excelRestoreLimitations = <String>[\n"
        "    'Excel 为尽力而为还原：不会清空或覆盖本机 fx_rates / settings；完整备份请用 JSON。',\n"
        "    '缺少的时间戳 / ledgerId / includeInBudget 等字段会用默认值填入。',\n"
        "    '重要数据备份请使用 JSON（format: centli-export）。',\n"
        "  ];"
        + imp[m4.end() :]
    )

write(imp_p, imp)

# ---------- import_page: Excel restore skip FX ----------
ip = ROOT / "lib/features/settings/import_page.dart"
ip_t = read(ip)
if "await svc.restore(b);" in ip_t:
    ip_t = ip_t.replace(
        "await svc.restore(b);",
        "await svc.restore(\n"
        "        b,\n"
        "        replaceFxRates: preview.sourceKind != 'excel',\n"
        "      );",
        1,
    )
    write(ip, ip_t)
else:
    raise SystemExit("import_page restore call not found")

# ---------- export_service #24 #43 ----------
exp = ROOT / "lib/data/export/export_service.dart"
et = read(exp)
et = et.replace("static const appVersion = '1.0.0+1';", "static const appVersion = '1.0.1+2';")
et = et.replace("'schema_version': 2,", "'schema_version': 3,")
write(exp, et)

print("import/export done")

# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

def must_replace(text, old, new, label):
    if old not in text:
        raise SystemExit(f"NOT FOUND: {label}\n---OLD START---\n{old[:200]}")
    return text.replace(old, new, 1)

p = ROOT / "lib/data/export/export_service.dart"
t = p.read_text(encoding="utf-8")

if "loadBudgetsForExport" not in t:
    t = must_replace(t, """    final fx = await db.loadAllFxRates();
    final settings = await db.loadAllSettings();
    final pending = options.includePending
""", """    final fx = await db.loadAllFxRates();
    final settings = await db.loadAllSettings();
    final budgetRows = await db.loadBudgetsForExport(ledgerId);
    final pending = options.includePending
""", "load budgets")

if "'budgets':" not in t:
    t = must_replace(t, """      'schema_version': 1,
""", """      'schema_version': 2,
""", "schema_version")
    t = must_replace(t, """      'fx_rates': fx.map((e) => e.toJson()).toList(),
      'settings': settings,
""", """      'fx_rates': fx.map((e) => e.toJson()).toList(),
      'budgets': budgetRows.map((e) => e.toJson()).toList(),
      'settings': settings,
""", "budgets in bundle")

if "final budgetList" not in t:
    t = must_replace(t, """    final rules = (bundle['merchant_rules'] as List).cast<Map>();

    void row(Sheet sheet, List<CellValue> cells) {
""", """    final rules = (bundle['merchant_rules'] as List).cast<Map>();
    final budgetList = (bundle['budgets'] as List? ?? const []).cast<Map>();

    void row(Sheet sheet, List<CellValue> cells) {
""", "budgetList var")

if "TextCellValue('budgets')" not in t:
    t = must_replace(t, """    row(summary, [
      TextCellValue('merchant_rules'),
      IntCellValue(rules.length),
    ]);

    final accountName = <String, String>{
""", """    row(summary, [
      TextCellValue('merchant_rules'),
      IntCellValue(rules.length),
    ]);
    row(summary, [
      TextCellValue('budgets'),
      IntCellValue(budgetList.length),
    ]);

    final accountName = <String, String>{
""", "summary budgets count")

if "excel['budgets']" not in t:
    sheet = r"""
    // budgets
    final baseCcy = '${ledger['baseCurrency'] ?? 'CNY'}';
    final budgetSheet = excel['budgets'];
    row(budgetSheet, [
      TextCellValue('id'),
      TextCellValue('ledger_id'),
      TextCellValue('year_month'),
      TextCellValue('category_id'),
      TextCellValue('category_name'),
      TextCellValue('amount_minor'),
      TextCellValue('amount'),
      TextCellValue('created_at'),
      TextCellValue('updated_at'),
    ]);
    for (final b in budgetList) {
      final categoryId = '${b['categoryId'] ?? ''}';
      final minor = b['amountMinor'] as int? ?? 0;
      final catLabel = categoryId.isEmpty
          ? '\u603b\u989d'
          : (categoryName[categoryId] ?? '');
      row(budgetSheet, [
        TextCellValue('${b['id']}'),
        TextCellValue('${b['ledgerId']}'),
        TextCellValue('${b['yearMonth']}'),
        TextCellValue(categoryId),
        TextCellValue(catLabel),
        IntCellValue(minor),
        DoubleCellValue(fromMinor(baseCcy, minor)),
        IntCellValue(b['createdAt'] as int? ?? 0),
        IntCellValue(b['updatedAt'] as int? ?? 0),
      ]);
    }

"""
    t = must_replace(t, """    final saved = excel.save();
""", sheet + """    final saved = excel.save();
""", "budgets excel sheet")

p.write_text(t, encoding="utf-8")
print("EXPORT OK")

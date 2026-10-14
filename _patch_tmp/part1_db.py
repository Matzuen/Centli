# -*- coding: utf-8 -*-
from pathlib import Path
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

def must_replace(text, old, new, label):
    if old not in text:
        raise SystemExit(f"NOT FOUND: {label}")
    return text.replace(old, new, 1)

# ---- DB ----
p = ROOT / "lib/data/db/centli_database.dart"
t = p.read_text(encoding="utf-8")
if "loadBudgetsForExport" not in t:
    t = must_replace(t, """  Future<List<Budget>> loadBudgetsForMonth(
    String ledgerId,
    String yearMonth,
  ) {
    return (select(budgets)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.yearMonth.equals(yearMonth),
          ))
        .get();
  }
""", """  Future<List<Budget>> loadBudgetsForMonth(
    String ledgerId,
    String yearMonth,
  ) {
    return (select(budgets)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.yearMonth.equals(yearMonth),
          ))
        .get();
  }

  /// All budgets for a ledger (export / backup).
  Future<List<Budget>> loadBudgetsForExport(String ledgerId) {
    return (select(budgets)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.yearMonth),
            (t) => OrderingTerm.asc(t.categoryId),
          ]))
        .get();
  }
""", "loadBudgetsForMonth")

if "required List<Map<String, dynamic>> budgetMaps," not in t:
    t = must_replace(t, """    required List<Map<String, dynamic>> fxRateMaps,
    required Map<String, String> settingsMap,
""", """    required List<Map<String, dynamic>> fxRateMaps,
    required List<Map<String, dynamic>> budgetMaps,
    required Map<String, String> settingsMap,
""", "budgetMaps param")

if "final budgetRows = [for (final m in budgetMaps) Budget.fromJson(m)];" not in t:
    t = must_replace(t, """    final fxRows = [for (final m in fxRateMaps) FxRate.fromJson(m)];

    var settingsWritten = 0;
""", """    final fxRows = [for (final m in fxRateMaps) FxRate.fromJson(m)];
    final budgetRows = [for (final m in budgetMaps) Budget.fromJson(m)];

    var settingsWritten = 0;
""", "budgetRows parse")

if "for (final b in budgetRows)" not in t:
    t = must_replace(t, """      for (final c in categoryRows) {
        await into(categories).insert(c.toCompanion(true));
      }
      for (final t in txnRows) {
""", """      for (final c in categoryRows) {
        await into(categories).insert(c.toCompanion(true));
      }
      for (final b in budgetRows) {
        await into(budgets).insert(b.toCompanion(true));
      }
      for (final t in txnRows) {
""", "budget insert")

if "budgets: budgetRows.length," not in t:
    t = must_replace(t, """      fxRates: fxRows.length,
      settingsWritten: settingsWritten,
""", """      fxRates: fxRows.length,
      budgets: budgetRows.length,
      settingsWritten: settingsWritten,
""", "stats return budgets")

if "required this.budgets," not in t.split("class RestoreImportStats")[1][:500]:
    t = must_replace(t, """class RestoreImportStats {
  const RestoreImportStats({
    required this.ledgerId,
    required this.ledgerName,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.merchantRules,
    required this.pendingCaptures,
    required this.fxRates,
    required this.settingsWritten,
  });

  final String ledgerId;
  final String ledgerName;
  final int accounts;
  final int categories;
  final int transactions;
  final int merchantRules;
  final int pendingCaptures;
  final int fxRates;
  final int settingsWritten;
}
""", """class RestoreImportStats {
  const RestoreImportStats({
    required this.ledgerId,
    required this.ledgerName,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.merchantRules,
    required this.pendingCaptures,
    required this.fxRates,
    required this.budgets,
    required this.settingsWritten,
  });

  final String ledgerId;
  final String ledgerName;
  final int accounts;
  final int categories;
  final int transactions;
  final int merchantRules;
  final int pendingCaptures;
  final int fxRates;
  final int budgets;
  final int settingsWritten;
}
""", "RestoreImportStats class")

p.write_text(t, encoding="utf-8")
print("DB OK")

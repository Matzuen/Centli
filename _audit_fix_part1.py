# -*- coding: utf-8 -*-
"""Centli audit checklist fixes #1-#13, #20, #22-#24, #43, #47, #5/#51, #7-#11."""
from pathlib import Path
import re
import shutil

ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")
changed = []

def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")

def write(p: Path, s: str):
    p.write_text(s, encoding="utf-8", newline="\n")
    changed.append(str(p.relative_to(ROOT)))

# ---------- #1 + #4: scoped restore + optional FX wipe ----------
dbp = ROOT / "lib/data/db/centli_database.dart"
db = read(dbp)

old_restore_sig = """  /// Wipe all ledger-scoped rows (+ FX + budgets), insert backup maps, merge settings.
  /// [settingsSkipKeys] are left unchanged (e.g. app_lock*). Always sets current_ledger_id.
  Future<RestoreImportStats> restoreFromImportBundle({
    required Map<String, dynamic> ledgerMap,
    required List<Map<String, dynamic>> accountMaps,
    required List<Map<String, dynamic>> categoryMaps,
    required List<Map<String, dynamic>> transactionMaps,
    required List<Map<String, dynamic>> merchantRuleMaps,
    required List<Map<String, dynamic>> pendingCaptureMaps,
    required List<Map<String, dynamic>> fxRateMaps,
    required List<Map<String, dynamic>> budgetMaps,
    required Map<String, String> settingsMap,
    required Set<String> settingsSkipKeys,
  }) async {"""

new_restore_sig = """  /// Replace one ledger's rows (+ optional FX + budgets), insert backup maps, merge settings.
  /// Other ledgers are left intact. [replaceFxRates] false keeps existing FX (Excel path).
  /// [settingsSkipKeys] are left unchanged (e.g. app_lock*). Always sets current_ledger_id.
  Future<RestoreImportStats> restoreFromImportBundle({
    required Map<String, dynamic> ledgerMap,
    required List<Map<String, dynamic>> accountMaps,
    required List<Map<String, dynamic>> categoryMaps,
    required List<Map<String, dynamic>> transactionMaps,
    required List<Map<String, dynamic>> merchantRuleMaps,
    required List<Map<String, dynamic>> pendingCaptureMaps,
    required List<Map<String, dynamic>> fxRateMaps,
    required List<Map<String, dynamic>> budgetMaps,
    required Map<String, String> settingsMap,
    required Set<String> settingsSkipKeys,
    bool replaceFxRates = true,
  }) async {"""

if old_restore_sig not in db:
    raise SystemExit("restore signature not found")
db = db.replace(old_restore_sig, new_restore_sig)

old_wipe = """    await transaction(() async {
      await delete(transactions).go();
      await delete(pendingCaptures).go();
      await delete(merchantRules).go();
      await delete(budgets).go();
      await delete(categories).go();
      await delete(accounts).go();
      await delete(ledgers).go();
      await delete(fxRates).go();

      await into(ledgers).insert(ledgerRow.toCompanion(true));
      for (final a in accountRows) {
        await into(accounts).insert(a.toCompanion(true));
      }
      for (final c in categoryRows) {
        await into(categories).insert(c.toCompanion(true));
      }
      for (final b in budgetRows) {
        await into(budgets).insert(b.toCompanion(true));
      }
      for (final t in txnRows) {
        await into(transactions).insert(t.toCompanion(true));
      }
      for (final r in ruleRows) {
        await into(merchantRules).insert(r.toCompanion(true));
      }
      for (final p in pendingRows) {
        await into(pendingCaptures).insert(p.toCompanion(true));
      }
      for (final f in fxRows) {
        await into(fxRates).insert(f.toCompanion(true));
      }"""

new_wipe = """    final lid = ledgerRow.id;

    await transaction(() async {
      // Scoped wipe: only the ledger being restored (export is single-ledger).
      await (delete(transactions)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(pendingCaptures)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(merchantRules)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(budgets)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(categories)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(accounts)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(ledgers)..where((t) => t.id.equals(lid))).go();
      if (replaceFxRates) {
        await delete(fxRates).go();
      }

      await into(ledgers).insert(ledgerRow.toCompanion(true));
      for (final a in accountRows) {
        await into(accounts).insert(a.toCompanion(true));
      }
      for (final c in categoryRows) {
        await into(categories).insert(c.toCompanion(true));
      }
      for (final b in budgetRows) {
        await into(budgets).insert(b.toCompanion(true));
      }
      for (final t in txnRows) {
        await into(transactions).insert(t.toCompanion(true));
      }
      for (final r in ruleRows) {
        await into(merchantRules).insert(r.toCompanion(true));
      }
      for (final p in pendingRows) {
        await into(pendingCaptures).insert(p.toCompanion(true));
      }
      if (replaceFxRates) {
        for (final f in fxRows) {
          await into(fxRates).insert(f.toCompanion(true));
        }
      }"""

if old_wipe not in db:
    raise SystemExit("wipe block not found")
db = db.replace(old_wipe, new_wipe)

# Fix fxRates count in return when not replaced
db = db.replace(
    "      fxRates: fxRows.length,",
    "      fxRates: replaceFxRates ? fxRows.length : 0,",
)

# #2 merchant params
old_ins = """  Future<void> insertManualTransaction({
    required String ledgerId,
    required String type,
    required int amountMinor,
    required String currency,
    required String accountId,
    String? toAccountId,
    String? categoryId,
    String? note,
    DateTime? happenAt,
    double? fxRate,
    int? toAmountMinor,
    int includeInStat = 1,
    int includeInBudget = 1,
  }) async {
    final ts = nowMs();
    final happen = happenAt?.toUtc().millisecondsSinceEpoch ?? ts;
    await into(transactions).insert(
      TransactionsCompanion.insert(
        id: newId(),
        ledgerId: ledgerId,
        type: type,
        amountMinor: amountMinor,
        currency: currency,
        accountId: accountId,
        toAccountId: Value(toAccountId),
        categoryId: Value(categoryId),
        note: Value(note),
        happenAt: happen,
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        includeInStat: Value(includeInStat),
        includeInBudget: Value(includeInBudget),
        createdAt: ts,
        updatedAt: ts,
      ),
    );
  }"""

new_ins = """  Future<void> insertManualTransaction({
    required String ledgerId,
    required String type,
    required int amountMinor,
    required String currency,
    required String accountId,
    String? toAccountId,
    String? categoryId,
    String? merchant,
    String? note,
    DateTime? happenAt,
    double? fxRate,
    int? toAmountMinor,
    int includeInStat = 1,
    int includeInBudget = 1,
  }) async {
    final ts = nowMs();
    final happen = happenAt?.toUtc().millisecondsSinceEpoch ?? ts;
    await into(transactions).insert(
      TransactionsCompanion.insert(
        id: newId(),
        ledgerId: ledgerId,
        type: type,
        amountMinor: amountMinor,
        currency: currency,
        accountId: accountId,
        toAccountId: Value(toAccountId),
        categoryId: Value(categoryId),
        merchant: Value(merchant),
        note: Value(note),
        happenAt: happen,
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        includeInStat: Value(includeInStat),
        includeInBudget: Value(includeInBudget),
        createdAt: ts,
        updatedAt: ts,
      ),
    );
  }"""

if old_ins not in db:
    raise SystemExit("insertManualTransaction not found")
db = db.replace(old_ins, new_ins)

old_upd = """  Future<void> updateManualTransaction({
    required String id,
    required String type,
    required int amountMinor,
    required String currency,
    required String accountId,
    String? toAccountId,
    String? categoryId,
    String? note,
    DateTime? happenAt,
    double? fxRate,
    int? toAmountMinor,
  }) async {
    final ts = nowMs();
    final happen = happenAt?.toUtc().millisecondsSinceEpoch;
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        type: Value(type),
        amountMinor: Value(amountMinor),
        currency: Value(currency),
        accountId: Value(accountId),
        toAccountId: Value(toAccountId),
        categoryId: Value(categoryId),
        note: Value(note),
        happenAt: happen != null ? Value(happen) : const Value.absent(),
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        updatedAt: Value(ts),
      ),
    );
  }"""

new_upd = """  Future<void> updateManualTransaction({
    required String id,
    required String type,
    required int amountMinor,
    required String currency,
    required String accountId,
    String? toAccountId,
    String? categoryId,
    String? merchant,
    String? note,
    DateTime? happenAt,
    double? fxRate,
    int? toAmountMinor,
  }) async {
    final ts = nowMs();
    final happen = happenAt?.toUtc().millisecondsSinceEpoch;
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        type: Value(type),
        amountMinor: Value(amountMinor),
        currency: Value(currency),
        accountId: Value(accountId),
        toAccountId: Value(toAccountId),
        categoryId: Value(categoryId),
        merchant: Value(merchant),
        note: Value(note),
        happenAt: happen != null ? Value(happen) : const Value.absent(),
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        updatedAt: Value(ts),
      ),
    );
  }"""

if old_upd not in db:
    raise SystemExit("updateManualTransaction not found")
db = db.replace(old_upd, new_upd)

# #22 PRAGMA foreign_keys
old_mig = """  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedDefaults();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(budgets);
          }
          if (from < 3) {
            await m.addColumn(accounts, accounts.icon);
            await backfillDefaultIcons();
          }
        },
      );"""

new_mig = """  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await seedDefaults();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(budgets);
          }
          if (from < 3) {
            await m.addColumn(accounts, accounts.icon);
            await backfillDefaultIcons();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );"""

if old_mig not in db:
    raise SystemExit("migration block not found")
db = db.replace(old_mig, new_mig)

write(dbp, db)
print("patched centli_database.dart")

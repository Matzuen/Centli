**Status: IMPLEMENTED** (2026-10-14) — JSON/Excel export + import restore include `budgets`.

﻿# Analysis: Include budgets in JSON/Excel export and restore on import

**Date:** 2026-10-14 (Asia/Shanghai)  
**Repo:** `D:\Resource\Codebase\studyProject\Centli`  
**Scope:** Analyze only (no code changes applied)

---

## Verdict

**Budgets are a first-class DB feature (schema v2 / P3 MVP) but are completely absent from export and import.**  
Worse: restore already **wipes** the `budgets` table and never re-inserts rows, so a full restore **destroys** any local budgets even when the backup never contained them.

---

## What exists today

### Data model (`lib/data/db/tables/budgets.dart`)

| Column | Notes |
|--------|--------|
| `id` | PK |
| `ledger_id` | FK → ledgers |
| `year_month` | `yyyy-MM` local |
| `category_id` | `''` = monthly total expense budget; else `categories.id` (text, not Drift FK) |
| `amount_minor` | Limit in **ledger base currency** minor units |
| `created_at` / `updated_at` | epoch ms |

Unique: `(ledger_id, year_month, category_id)`.

Drift already generates `Budget.toJson` / `Budget.fromJson` (camelCase keys: `ledgerId`, `yearMonth`, `categoryId`, `amountMinor`, …).

DB APIs: `watchBudgetsForMonth`, `loadBudgetsForMonth`, `upsertBudget`, `deleteBudget*`, `monthBudgetProgress`.  
**There is no `loadBudgetsForExport` / load-all-for-ledger helper.**

`CentliDatabase.schemaVersion == 2` (budgets table created on upgrade from 1). Docs: `docs/Centli_schema.md` §2.9.

### Export (`lib/data/export/export_service.dart`)

`buildBundle` writes:

- `format: centli-export`, `export_version: 1`, **`schema_version: 1` (hardcoded)**  
- `ledger`, `accounts`, `categories`, `transactions`, `merchant_rules`, `pending_captures`, `fx_rates`, `settings`

**No `budgets` key.**

Excel sheets: `summary`, `accounts`, `categories`, `transactions`, `pending`, `merchant_rules`.  
**No `budgets` sheet.** Summary row counts omit budgets.

UI (`export_page.dart`) Excel subtitle lists those sheets only — no budgets.

### Import (`lib/data/export/import_service.dart`)

- JSON-only restore (Excel is view-only; import UI says so).
- `ImportBundle` / `ImportResult` have no budgets field.
- `parseJsonString` never reads `budgets`; dry-run does not call `Budget.fromJson`.
- `restore()` → `db.restoreFromImportBundle(...)` with no budget maps.
- Accepts `schema_version` 1–2 already (good for bumping export schema to 2).

### Restore wipe path (`centli_database.dart` ~1800+)

Inside the transaction:

```dart
await delete(budgets).go();  // yes — wiped
// ... insert ledger, accounts, categories, txns, rules, pending, fx
// NO budget inserts
```

`RestoreImportStats` has no `budgets` count.

### UI impact

Import preview counts: accounts / categories / transactions / pending / rules / fx / settings — **no budgets**. Success snackbar same omission.

---

## Gap summary

| Layer | Status |
|-------|--------|
| Table + CRUD + Budget page | Done |
| `Budget` JSON serde (Drift) | Done |
| Export JSON `budgets` array | **Missing** |
| Export Excel `budgets` sheet + summary count | **Missing** |
| `loadBudgets*` for full ledger export | **Missing** (only by month) |
| Import parse + normalize + dry-run | **Missing** |
| Restore re-insert after wipe | **Missing** (wipe only → data loss) |
| Preview / ImportResult / RestoreImportStats counts | **Missing** |
| Export `schema_version` vs DB | Export still emits `1`; DB is `2` |

---

## Recommended implementation (when implementing)

### 1. Database

Add something like:

```dart
Future<List<Budget>> loadBudgetsForExport(String ledgerId) {
  return (select(budgets)
        ..where((t) => t.ledgerId.equals(ledgerId))
        ..orderBy([
          (t) => OrderingTerm.asc(t.yearMonth),
          (t) => OrderingTerm.asc(t.categoryId),
        ]))
      .get();
}
```

Extend `restoreFromImportBundle` with `List<Map<String, dynamic>> budgetMaps`:

- Parse with `Budget.fromJson`.
- Insert **after** categories (and ledger), **before** or with other ledger children — order after categories is safest for referential integrity even without Drift FK on `category_id`.
- Return `budgets: budgetRows.length` from `RestoreImportStats`.

### 2. ExportService

In `buildBundle`:

```dart
final budgets = await db.loadBudgetsForExport(ledgerId);
// ...
'budgets': budgets.map((e) => e.toJson()).toList(),
'schema_version': 2,  // align with DB; import already allows 1..2
```

In `_buildExcel`:

- Summary rows: add `budgets` count.
- New sheet `budgets` columns e.g.:  
  `id`, `ledger_id`, `year_month`, `category_id`, `category_name`, `amount_minor`, `amount` (major via `fromMinor(baseCurrency, …)`), `created_at`, `updated_at`.  
  Resolve `category_name` from categories map; empty `category_id` → label like “总额” / leave blank.
- Optionally list `budgets` in Excel subtitle on `export_page.dart`.

`export_version` can stay `1` if you treat budgets as additive under `schema_version: 2`, or bump `export_version` if you want a hard gate — current import rejects unknown `export_version`, so **prefer keeping `export_version: 1` and setting `schema_version: 2`** for backward-compatible parsers.

### 3. ImportService

- Add `budgets` to `ImportBundle` / `ImportResult`.
- `_asMapList(map['budgets'], 'budgets')` → empty if absent (old backups).
- `_normalizeBudget`: `putIfAbsent` for `categoryId` → `''`, timestamps if needed.
- Dry-run `Budget.fromJson`.
- Pass `budgetMaps` into `restoreFromImportBundle`.

### 4. UI

- Import preview line: include `预算 N`.
- Success message: include budgets count.
- Export Excel subtitle: add `budgets`.

### 5. Tests (suggested)

- Round-trip: upsert budgets → `buildBundle` → `parseJsonString` → `restore` → `loadBudgetsForMonth` / load-all equals.
- Old JSON without `budgets` still imports; post-restore budgets table empty (and wipe of prior local budgets documented).
- Excel sheet present when `wantExcel` (optional smoke).

---

## Behavioral notes / edge cases

1. **Destructive restore already deletes budgets** — fixing insert is required, not optional, once budgets matter to users.
2. **Old exports** lack `budgets` → restore correctly yields zero budgets; users who had local budgets lose them (same as today). Document in import copy if desired.
3. **Category budgets** reference category ids that must exist in the same bundle; export always includes all categories for the ledger, so OK if we export all budgets for that ledger.
4. **Excel is not imported** — budgets sheet is for humans / spreadsheets only, matching accounts/txns.
5. **`include_in_budget` on transactions** is already exported/imported via txn JSON; only the **limits** in `budgets` are missing.
6. FX rates are global (not ledger-scoped) and already wiped/restored; budgets are ledger-scoped like accounts — export is per-ledger today, so export only that ledger’s budgets (consistent).

---

## Files to touch (implementation checklist)

1. `lib/data/db/centli_database.dart` — load + restore insert + `RestoreImportStats`
2. `lib/data/export/export_service.dart` — JSON + Excel
3. `lib/data/export/import_service.dart` — parse / normalize / result
4. `lib/features/settings/export_page.dart` — Excel subtitle
5. `lib/features/settings/import_page.dart` — preview + snackbar counts
6. `test/` — new or extend export/import/budget tests
7. Optionally `docs/Centli_schema.md` — note export payload includes `budgets` at schema_version 2

---

## Conclusion

Feature request is valid and narrowly scoped. Infrastructure (table, Drift JSON, wipe-on-restore) is already in place; the hole is wiring budgets through `ExportService` / `ImportService` / restore insert / UI counts. Highest-priority fix is **re-insert on restore**, because wipe-without-restore is active data loss today.

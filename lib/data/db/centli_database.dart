import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils/note_compose.dart';

import '../../core/utils/id_gen.dart';
import '../../core/icons/centli_icon_defaults.dart';
import '../../core/utils/fx.dart';
import 'tables/accounts.dart';
import 'tables/asset_types.dart';
import 'tables/app_settings.dart';
import 'tables/categories.dart';
import 'tables/fx_rates.dart';
import 'tables/ledgers.dart';
import 'tables/merchant_rules.dart';
import 'tables/pending_captures.dart';
import 'tables/budgets.dart';
import 'tables/recurring_rules.dart';
import 'tables/sub_transaction_types.dart';
import 'tables/transactions.dart';
import 'txn_tags.dart';

part 'centli_database.g.dart';

@DriftDatabase(
  tables: [
    Ledgers,
    Accounts,
    AssetTypes,
    Categories,
    Transactions,
    PendingCaptures,
    MerchantRules,
    FxRates,
    Budgets,
    AppSettings,
    RecurringRules,
    SubTransactionTypes,
  ],
)
class CentliDatabase extends _$CentliDatabase {
  CentliDatabase() : super(_openConnection());

  CentliDatabase.forTesting(super.e);

  /// Reused by the burst of home/stats aggregates that follow one write.
  FxBook? _fxBookCache;

  void _dropFxBookCache() => _fxBookCache = null;

  /// Native（悬浮窗 / 通知栏）直接改 SQLite 时调用：让已订阅的 Drift
  /// stream 重新 SELECT，否则前台 UI 会一直看到旧快照。
  void notifyExternalMutation() {
    _dropFxBookCache();
    notifyUpdates({
      const TableUpdate('transactions'),
      const TableUpdate('pending_captures'),
      const TableUpdate('accounts'),
    });
  }

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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
          if (from < 4) {
            await m.addColumn(transactions, transactions.tags);
          }
          if (from < 5) {
            // Historical v5 column; kept as raw SQL so v11 can drop it after merge.
            await customStatement(
              'ALTER TABLE transactions ADD COLUMN member TEXT',
            );
          }
          if (from < 6) {
            await m.createTable(recurringRules);
            await m.addColumn(pendingCaptures, pendingCaptures.direction);
            await m.addColumn(transactions, transactions.occurrenceKey);
          }
          if (from < 7) {
            await customStatement("""
CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT NOT NULL PRIMARY KEY,
  ledger_id TEXT NOT NULL,
  name TEXT NOT NULL,
  icon TEXT,
  category_id TEXT,
  price_minor INTEGER NOT NULL,
  currency TEXT NOT NULL,
  period_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  next_due_at INTEGER,
  remind_days_before INTEGER NOT NULL DEFAULT 3,
  note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
""");
          }
          if (from < 8) {
            await customStatement('''
UPDATE transactions SET note = CASE
  WHEN merchant IS NOT NULL AND length(trim(merchant)) > 0
       AND note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(merchant) || ' · ' || trim(note)
  WHEN merchant IS NOT NULL AND length(trim(merchant)) > 0
    THEN trim(merchant)
  WHEN note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(note)
  ELSE NULL
END
''');
            await m.addColumn(pendingCaptures, pendingCaptures.note);
            await customStatement('''
UPDATE pending_captures SET note = CASE
  WHEN merchant IS NOT NULL AND length(trim(merchant)) > 0
       AND note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(merchant) || ' · ' || trim(note)
  WHEN merchant IS NOT NULL AND length(trim(merchant)) > 0
    THEN trim(merchant)
  WHEN note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(note)
  ELSE NULL
END
''');
            // Jumping across versions with current schema would drop member
            // without merging — fold into note first when the column exists.
            if (await _hasTableColumn('transactions', 'member')) {
              await customStatement('''
UPDATE transactions SET note = CASE
  WHEN member IS NOT NULL AND length(trim(member)) > 0
       AND note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(note) || ' · ' || trim(member)
  WHEN member IS NOT NULL AND length(trim(member)) > 0
    THEN trim(member)
  WHEN note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(note)
  ELSE NULL
END
WHERE member IS NOT NULL AND length(trim(member)) > 0
''');
            }
            await _alterTransactionsSafe(m);
            await m.alterTable(TableMigration(pendingCaptures));
          }
          if (from < 9) {
            await m.deleteTable('subscriptions');
            await customStatement(
              "DELETE FROM app_settings WHERE key LIKE 'subscription_%'",
            );
          }
          if (from < 10) {
            await m.createTable(assetTypes);
            await _migrateAccountsToAssetTypes();
          }
          if (from < 11) {
            // Merge non-empty member into note (note · member), then drop column.
            if (await _hasTableColumn('transactions', 'member')) {
              await customStatement('''
UPDATE transactions SET note = CASE
  WHEN member IS NOT NULL AND length(trim(member)) > 0
       AND note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(note) || ' · ' || trim(member)
  WHEN member IS NOT NULL AND length(trim(member)) > 0
    THEN trim(member)
  WHEN note IS NOT NULL AND length(trim(note)) > 0
    THEN trim(note)
  ELSE NULL
END
WHERE member IS NOT NULL AND length(trim(member)) > 0
''');
              await _alterTransactionsSafe(m);
            }
          }
          if (from < 12) {
            // Keep one row per pending_id before unique index (prefer oldest).
            await customStatement('''
DELETE FROM transactions
WHERE pending_id IS NOT NULL
  AND rowid NOT IN (
    SELECT MIN(rowid) FROM transactions
    WHERE pending_id IS NOT NULL
    GROUP BY pending_id
  )
''');
          }
          if (from < 13) {
            await ensureTransferCategoriesForAllLedgers();
          }
          if (from < 14) {
            await m.createTable(subTransactionTypes);
            if (!await _hasTableColumn('transactions', 'parent_id')) {
              await m.addColumn(transactions, transactions.parentId);
            }
            if (!await _hasTableColumn('transactions', 'sub_type_id')) {
              await m.addColumn(transactions, transactions.subTypeId);
            }
            await seedDefaultSubTransactionTypes();
          }
          await _ensureQueryIndexes();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _ensureQueryIndexes();
        },
      );


  Future<bool> _hasTableColumn(String table, String column) async {
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((r) => r.read<String>('name') == column);
  }


  /// Rebuild [transactions] while Drift's current table already has columns
  /// added in later migrations (e.g. parent_id @ v14). Without [newColumns],
  /// alterTable would SELECT those names from the old table → "no such column".
  Future<void> _alterTransactionsSafe(Migrator m) async {
    final newCols = <GeneratedColumn>[];
    if (!await _hasTableColumn('transactions', 'parent_id')) {
      newCols.add(transactions.parentId);
    }
    if (!await _hasTableColumn('transactions', 'sub_type_id')) {
      newCols.add(transactions.subTypeId);
    }
    await m.alterTable(
      TableMigration(transactions, newColumns: newCols),
    );
  }


  /// Hot-path indexes (idempotent). Called from onUpgrade + beforeOpen.
  Future<void> _ensureQueryIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_txn_ledger_happen '
      'ON transactions(ledger_id, happen_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_txn_account_happen '
      'ON transactions(account_id, happen_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_accounts_ledger_archived '
      'ON accounts(ledger_id, archived)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_categories_ledger_kind_archived '
      'ON categories(ledger_id, kind, archived)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pending_status_created '
      'ON pending_captures(status, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_txn_occurrence_key '
      'ON transactions(occurrence_key)',
    );
    // Live rows are what home / stats / balances actually scan.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_txn_ledger_live_happen '
      'ON transactions(ledger_id, happen_at) WHERE deleted_at IS NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_txn_parent '
      'ON transactions(parent_id) WHERE parent_id IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_pending_ledger_status '
      'ON pending_captures(ledger_id, status)',
    );
    // One confirmed txn per pending capture (blocks Native/Dart double-confirm).
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_pending_id '
      'ON transactions(pending_id) WHERE pending_id IS NOT NULL',
    );
  }


  static const kDefaultAssetTypeNames = <String>[
    '现金',
    '银行卡',
    '电子钱包',
    '信用卡',
    '其他',
  ];

  static const _legacyTypeToName = <String, String>{
    'cash': '现金',
    'bank': '银行卡',
    'ewallet': '电子钱包',
    'credit': '信用卡',
    'other': '其他',
  };

  /// Seed five default asset types for [ledgerId]; returns name → id.
  /// Idempotent: existing names are reused (no duplicate rows).
  Future<Map<String, String>> seedDefaultAssetTypes(String ledgerId) async {
    final existing = await (select(assetTypes)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .get();
    final byName = {for (final r in existing) r.name: r.id};
    final ts = nowMs();
    for (var i = 0; i < kDefaultAssetTypeNames.length; i++) {
      final name = kDefaultAssetTypeNames[i];
      if (byName.containsKey(name)) continue;
      final id = newId();
      await into(assetTypes).insert(
        AssetTypesCompanion.insert(
          id: id,
          ledgerId: ledgerId,
          name: name,
          sortOrder: Value(i),
          createdAt: ts,
          updatedAt: ts,
        ),
      );
      byName[name] = id;
    }
    return byName;
  }

  Future<void> _migrateAccountsToAssetTypes() async {
    final ledgerRows = await select(ledgers).get();
    for (final ledger in ledgerRows) {
      final nameToId = await seedDefaultAssetTypes(ledger.id);
      final otherId = nameToId['其他']!;
      final accs = await (select(accounts)
            ..where((t) => t.ledgerId.equals(ledger.id)))
          .get();
      for (final a in accs) {
        final raw = a.type.trim();
        // Already an asset_types id?
        if (nameToId.values.contains(raw)) continue;
        final name = _legacyTypeToName[raw] ??
            (raw.isEmpty ? '其他' : (nameToId.containsKey(raw) ? raw : '其他'));
        final newId = nameToId[name] ?? otherId;
        if (newId == a.type) continue;
        await (update(accounts)..where((t) => t.id.equals(a.id))).write(
          AccountsCompanion(type: Value(newId)),
        );
      }
    }
  }

  Future<List<AssetType>> loadAssetTypes(
    String ledgerId, {
    bool includeArchived = false,
  }) {
    final q = select(assetTypes)..where((t) => t.ledgerId.equals(ledgerId));
    if (!includeArchived) {
      q.where((t) => t.archived.equals(0));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.get();
  }

  Stream<List<AssetType>> watchAssetTypes(
    String ledgerId, {
    bool includeArchived = true,
  }) {
    final q = select(assetTypes)..where((t) => t.ledgerId.equals(ledgerId));
    if (!includeArchived) {
      q.where((t) => t.archived.equals(0));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.watch();
  }

  Future<AssetType?> getAssetType(String id) {
    return (select(assetTypes)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<String> resolveAssetTypeId({
    required String ledgerId,
    required String raw,
  }) async {
    final nameToId = await seedDefaultAssetTypes(ledgerId);
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return nameToId['其他']!;
    if (nameToId.values.contains(trimmed)) return trimmed;
    final legacy = _legacyTypeToName[trimmed];
    if (legacy != null) return nameToId[legacy]!;
    if (nameToId.containsKey(trimmed)) return nameToId[trimmed]!;
    // Look up by id in DB (including archived)
    final byId = await getAssetType(trimmed);
    if (byId != null && byId.ledgerId == ledgerId) return byId.id;
    return nameToId['其他']!;
  }

  Future<String> createAssetType({
    required String ledgerId,
    required String name,
    String? icon,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw StateError('分类名称不能为空');
    }
    final existing = await (select(assetTypes)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.name.equals(trimmed)))
        .get();
    if (existing.isNotEmpty) {
      throw StateError('同记账本已有同名分类');
    }
    final maxOrder = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM asset_types WHERE ledger_id = ?',
      variables: [Variable.withString(ledgerId)],
      readsFrom: {assetTypes},
    ).getSingle();
    final order = (maxOrder.read<int>('m')) + 1;
    final id = newId();
    final ts = nowMs();
    await into(assetTypes).insert(
      AssetTypesCompanion.insert(
        id: id,
        ledgerId: ledgerId,
        name: trimmed,
        icon: Value(icon),
        sortOrder: Value(order),
        createdAt: ts,
        updatedAt: ts,
      ),
    );
    return id;
  }

  Future<void> renameAssetType({
    required String id,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw StateError('分类名称不能为空');
    final row = await getAssetType(id);
    if (row == null) throw StateError('分类不存在');
    final clash = await (select(assetTypes)
          ..where((t) =>
              t.ledgerId.equals(row.ledgerId) &
              t.name.equals(trimmed) &
              t.id.equals(id).not()))
        .get();
    if (clash.isNotEmpty) throw StateError('同记账本已有同名分类');
    await (update(assetTypes)..where((t) => t.id.equals(id))).write(
      AssetTypesCompanion(name: Value(trimmed), updatedAt: Value(nowMs())),
    );
  }

  Future<void> setAssetTypeArchived(String id, bool archived) async {
    await (update(assetTypes)..where((t) => t.id.equals(id))).write(
      AssetTypesCompanion(
        archived: Value(archived ? 1 : 0),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  Future<void> reorderAssetType(String id, {required bool up}) async {
    final row = await getAssetType(id);
    if (row == null) return;
    final siblings = await (select(assetTypes)
          ..where((t) => t.ledgerId.equals(row.ledgerId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    final idx = siblings.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    final swapWith = up ? idx - 1 : idx + 1;
    if (swapWith < 0 || swapWith >= siblings.length) return;
    final a = siblings[idx];
    final b = siblings[swapWith];
    final ts = nowMs();
    await (update(assetTypes)..where((t) => t.id.equals(a.id))).write(
      AssetTypesCompanion(sortOrder: Value(b.sortOrder), updatedAt: Value(ts)),
    );
    await (update(assetTypes)..where((t) => t.id.equals(b.id))).write(
      AssetTypesCompanion(sortOrder: Value(a.sortOrder), updatedAt: Value(ts)),
    );
  }

  Future<void> deleteAssetType(String id) async {
    final row = await getAssetType(id);
    if (row == null) return;
    final all = await (select(assetTypes)
          ..where((t) => t.ledgerId.equals(row.ledgerId)))
        .get();
    if (all.length <= 1) {
      throw StateError('至少保留一个资产分类');
    }
    final inUse = await (select(accounts)..where((t) => t.type.equals(id))).get();
    if (inUse.isNotEmpty) {
      throw StateError('有 ${inUse.length} 个资产账户在用，无法删除（可先归档）');
    }
    await (delete(assetTypes)..where((t) => t.id.equals(id))).go();
  }

  Future<int> countAccountsForAssetType(String typeId) async {
    final rows = await (select(accounts)..where((t) => t.type.equals(typeId))).get();
    return rows.length;
  }

  Future<void> seedDefaults() async {
    final existing = await (select(ledgers)..limit(1)).get();
    if (existing.isNotEmpty) return;

    final ts = nowMs();
    final ledgerId = newId();

    await into(ledgers).insert(
      LedgersCompanion.insert(
        id: ledgerId,
        name: '\u4e2a\u4eba',
        baseCurrency: 'CNY',
        createdAt: ts,
      ),
    );

    final typeIds = await seedDefaultAssetTypes(ledgerId);
    final accountDefs = <(String name, String legacyType, int order)>[
      ('\u73b0\u91d1', 'cash', 0),
      ('\u652f\u4ed8\u5b9d', 'ewallet', 1),
      ('\u5fae\u4fe1', 'ewallet', 2),
    ];
    for (final a in accountDefs) {
      final typeId = typeIds[_legacyTypeToName[a.$2] ?? '其他'] ?? typeIds['其他']!;
      await into(accounts).insert(
        AccountsCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          name: a.$1,
          currency: 'CNY',
          type: typeId,
          icon: Value(defaultIconKeyForAccount(name: a.$1, type: a.$2)),
          sortOrder: Value(a.$3),
          createdAt: ts,
          updatedAt: ts,
        ),
      );
    }

    final outCats = [
      '\u9910\u996e',
      '\u4ea4\u901a',
      '\u65e5\u7528',
      '\u5c45\u4f4f',
      '\u5a31\u4e50',
      '\u533b\u7597',
      '\u6559\u80b2',
      '\u5176\u4ed6',
    ];
    for (var i = 0; i < outCats.length; i++) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          name: outCats[i],
          icon: Value(defaultIconKeyForCategoryName(outCats[i])),
          kind: 'out',
          sortOrder: Value(i),
          createdAt: ts,
        ),
      );
    }

    final inCats = ['\u5de5\u8d44', '\u7ea2\u5305', '\u7406\u8d22', '\u5176\u4ed6'];
    for (var i = 0; i < inCats.length; i++) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          name: inCats[i],
          icon: Value(defaultIconKeyForCategoryName(inCats[i])),
          kind: 'in',
          sortOrder: Value(i),
          createdAt: ts,
        ),
      );
    }

    await seedDefaultTransferCategory(ledgerId, createdAt: ts);

    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: 'current_ledger_id',
        value: ledgerId,
      ),
    );
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: 'auto_capture_enabled',
        value: 'false',
      ),
    );
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: 'onboarding_done',
        value: 'false',
      ),
    );
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: 'app_lock',
        value: 'false',
      ),
    );
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: 'app_lock_biometric',
        value: 'false',
      ),
    );
    await seedDefaultSubTransactionTypes();
  }

  /// Fill icon keys for built-in categories/accounts that still have null icon.
  Future<void> backfillDefaultIcons() async {
    final cats = await select(categories).get();
    for (final c in cats) {
      if ((c.icon ?? '').trim().isNotEmpty) continue;
      final key = defaultIconKeyForCategoryName(c.name);
      if (key == null) continue;
      await (update(categories)..where((t) => t.id.equals(c.id))).write(
        CategoriesCompanion(icon: Value(key)),
      );
    }
    final accts = await select(accounts).get();
    for (final a in accts) {
      if ((a.icon ?? '').trim().isNotEmpty) continue;
      final key = defaultIconKeyForAccount(name: a.name, type: a.type);
      if (key == null) continue;
      await (update(accounts)..where((t) => t.id.equals(a.id))).write(
        AccountsCompanion(icon: Value(key)),
      );
    }
  }

  Future<String?> currentLedgerId() async {
    final row = await (select(appSettings)
          ..where((t) => t.key.equals('current_ledger_id')))
        .getSingleOrNull();
    return row?.value;
  }

  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  Stream<String?> watchSetting(String key) {
    return (select(appSettings)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }

  Stream<bool> watchAppLockEnabled() {
    return (select(appSettings)..where((t) => t.key.equals('app_lock')))
        .watchSingleOrNull()
        .map((row) => row?.value == 'true');
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    await setSetting('app_lock', enabled ? 'true' : 'false');
  }

  Stream<bool> watchAppLockBiometric() {
    return (select(appSettings)
          ..where((t) => t.key.equals('app_lock_biometric')))
        .watchSingleOrNull()
        .map((row) => row?.value == 'true');
  }

  Future<void> setAppLockBiometric(bool enabled) async {
    await setSetting('app_lock_biometric', enabled ? 'true' : 'false');
  }


  Future<Ledger?> getLedger(String id) {
    return (select(ledgers)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Ledger?> watchLedger(String id) {
    return (select(ledgers)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  Stream<Ledger?> watchCurrentLedger() {
    return (select(appSettings)
          ..where((t) => t.key.equals('current_ledger_id')))
        .watchSingleOrNull()
        .asyncMap((row) async {
      final id = row?.value;
      if (id == null || id.isEmpty) return null;
      return getLedger(id);
    });
  }

  Future<void> updateLedger({
    required String id,
    String? name,
    String? baseCurrency,
  }) async {
    await (update(ledgers)..where((t) => t.id.equals(id))).write(
      LedgersCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        baseCurrency:
            baseCurrency != null ? Value(baseCurrency) : const Value.absent(),
      ),
    );
  }

  Stream<List<Ledger>> watchAllLedgers({bool includeArchived = false}) {
    return (select(ledgers)
          ..where(
            (t) => includeArchived
                ? const Constant(true)
                : t.archived.equals(0),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.archived),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<Ledger>> loadAllLedgers({bool includeArchived = false}) {
    return (select(ledgers)
          ..where(
            (t) => includeArchived
                ? const Constant(true)
                : t.archived.equals(0),
          )
          ..orderBy([
            (t) => OrderingTerm.asc(t.archived),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
  }

  Future<void> setCurrentLedgerId(String ledgerId) async {
    await setSetting('current_ledger_id', ledgerId);
  }

  /// 每个账本默认一条 `kind=transfer`、名为「转账」的一级分类。
  Future<Category> seedDefaultTransferCategory(
    String ledgerId, {
    int? createdAt,
  }) async {
    final ts = createdAt ?? nowMs();
    final id = newId();
    await into(categories).insert(
      CategoriesCompanion.insert(
        id: id,
        ledgerId: ledgerId,
        name: '转账',
        icon: Value(defaultIconKeyForCategoryName('转账')),
        kind: 'transfer',
        sortOrder: const Value(0),
        createdAt: ts,
      ),
    );
    final row = await getCategory(id);
    return row!;
  }

  /// 若账本尚无可用转账分类，则补一条「转账」并返回。
  Future<Category> ensureDefaultTransferCategory(String ledgerId) async {
    final existing = await (select(categories)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.kind.equals('transfer') &
                t.archived.equals(0),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
    Category? named;
    for (final c in existing) {
      if (c.parentId == null && c.name == '转账') {
        named = c;
        break;
      }
    }
    if (named != null) return named;
    if (existing.isNotEmpty) {
      for (final c in existing) {
        if (c.parentId == null) return c;
      }
      return existing.first;
    }
    return seedDefaultTransferCategory(ledgerId);
  }

  /// v13：给已有账本补转账分类，并回填历史转账流水的 category_id。
  Future<void> ensureTransferCategoriesForAllLedgers() async {
    final all = await select(ledgers).get();
    for (final ledger in all) {
      final cat = await ensureDefaultTransferCategory(ledger.id);
      await customStatement(
        'UPDATE transactions SET category_id = ? '
        "WHERE ledger_id = ? AND type = 'transfer' AND category_id IS NULL",
        [cat.id, ledger.id],
      );
    }
  }

  /// Create a new ledger with default accounts + categories (mirrors seedDefaults).
  Future<Ledger> createLedgerWithDefaults({
    required String name,
    String baseCurrency = 'CNY',
    bool switchTo = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('请填写记账本名称');
    }
    final ts = nowMs();
    final ledgerId = newId();
    await into(ledgers).insert(
      LedgersCompanion.insert(
        id: ledgerId,
        name: trimmed,
        baseCurrency: baseCurrency,
        createdAt: ts,
      ),
    );

    final typeIds = await seedDefaultAssetTypes(ledgerId);
    final accountDefs = <(String name, String legacyType, int order)>[
      ('现金', 'cash', 0),
      ('支付宝', 'ewallet', 1),
      ('微信', 'ewallet', 2),
    ];
    for (final a in accountDefs) {
      final typeId = typeIds[_legacyTypeToName[a.$2] ?? '其他'] ?? typeIds['其他']!;
      await into(accounts).insert(
        AccountsCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          name: a.$1,
          currency: baseCurrency,
          type: typeId,
          icon: Value(defaultIconKeyForAccount(name: a.$1, type: a.$2)),
          sortOrder: Value(a.$3),
          createdAt: ts,
          updatedAt: ts,
        ),
      );
    }

    final outCats = [
      '餐饮',
      '交通',
      '日用',
      '居住',
      '娱乐',
      '医疗',
      '教育',
      '其他',
    ];
    for (var i = 0; i < outCats.length; i++) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          name: outCats[i],
          icon: Value(defaultIconKeyForCategoryName(outCats[i])),
          kind: 'out',
          sortOrder: Value(i),
          createdAt: ts,
        ),
      );
    }

    final inCats = ['工资', '红包', '理财', '其他'];
    for (var i = 0; i < inCats.length; i++) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          name: inCats[i],
          icon: Value(defaultIconKeyForCategoryName(inCats[i])),
          kind: 'in',
          sortOrder: Value(i),
          createdAt: ts,
        ),
      );
    }

    await seedDefaultTransferCategory(ledgerId, createdAt: ts);

    if (switchTo) {
      await setCurrentLedgerId(ledgerId);
    }
    final row = await getLedger(ledgerId);
    return row!;
  }

  Future<void> setLedgerArchived(String id, bool archived) async {
    await (update(ledgers)..where((t) => t.id.equals(id))).write(
      LedgersCompanion(archived: Value(archived ? 1 : 0)),
    );
    if (!archived) return;
    final current = await currentLedgerId();
    if (current != id) return;
    final others = await (select(ledgers)
          ..where((t) => t.archived.equals(0) & t.id.isNotValue(id)))
        .get();
    if (others.isNotEmpty) {
      await setCurrentLedgerId(others.first.id);
    }
  }


  Stream<List<Account>> watchActiveAccounts(String ledgerId) {
    return (select(accounts)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.archived.equals(0))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Stream<List<Transaction>> watchRecentTransactions(
    String ledgerId, {
    int limit = 50,
  }) {
    return (select(transactions)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.deletedAt.isNull() &
                t.parentId.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(limit))
        .watch();
  }

  /// [limit] ≤0：不截断，返回区间内全部流水。
  Stream<List<Transaction>> watchTransactionsInRange(
    String ledgerId,
    int startMs,
    int endMs, {
    int limit = 200,
  }) {
    final q = select(transactions)
      ..where(
        (t) =>
            t.ledgerId.equals(ledgerId) &
            t.deletedAt.isNull() &
            t.parentId.isNull() &
            t.happenAt.isBiggerOrEqualValue(startMs) &
            t.happenAt.isSmallerThanValue(endMs),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.happenAt)]);
    if (limit > 0) {
      q.limit(limit);
    }
    return q.watch();
  }

  /// Bill search: optional keyword (note / merchant / amount) plus filters.
  ///
  /// Keyword may be empty when at least one filter is set (type / category /
  /// account / date range). Account filter matches [accountId] or [toAccountId].
  /// Keywords separated by spaces / full-width spaces are **ORed**: a row
  /// matches if **any** token hits note, tags, category name, account name,
  /// type word or amount.
  Future<List<Transaction>> searchTransactions(
    String ledgerId,
    String query, {
    String? type,
    String? categoryId,
    String? accountId,
    int? startMs,
    int? endMs,
    /// ≤0：不截断，返回全部匹配行（「查看全部账单」）。
    int limit = 200,
    /// 无关键词、无筛选时仍列出该账本全部未删除流水。
    bool listAll = false,
  }) async {
    final q = query.trim();
    final hasFilter = type != null ||
        categoryId != null ||
        accountId != null ||
        startMs != null ||
        endMs != null;
    if (q.isEmpty && !hasFilter && !listAll) return const [];

    // Space (incl. full-width) separates keywords; any token may match (OR).
    final tokens = q
        .split(RegExp(r'[\s\u3000]+'))
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();

    final cats = tokens.isEmpty
        ? const <Category>[]
        : await (select(categories)..where((t) => t.ledgerId.equals(ledgerId)))
            .get();
    final accs = tokens.isEmpty
        ? const <Account>[]
        : await (select(accounts)..where((t) => t.ledgerId.equals(ledgerId)))
            .get();

    // limit≤0：不设 LIMIT；否则多取 1 条供 UI 判断截断。
    final capped = limit > 0;
    final fetchLimit = capped ? limit + 1 : null;

    final qBuilder = select(transactions)
      ..where((t) {
        Expression<bool> pred = t.ledgerId.equals(ledgerId) &
            t.deletedAt.isNull() &
            t.parentId.isNull();

        if (type != null) {
          pred = pred & t.type.equals(type);
        }
        if (categoryId != null) {
          pred = pred & t.categoryId.equals(categoryId);
        }
        if (accountId != null) {
          pred = pred &
              (t.accountId.equals(accountId) |
                  t.toAccountId.equals(accountId));
        }
        if (startMs != null) {
          pred = pred & t.happenAt.isBiggerOrEqualValue(startMs);
        }
        if (endMs != null) {
          pred = pred & t.happenAt.isSmallerThanValue(endMs);
        }

        if (tokens.isNotEmpty) {
          Expression<bool>? anyTok;
          for (final tok in tokens) {
            final pattern = '%$tok%';
            Expression<bool> textHit =
                t.note.lower().like(pattern) | t.tags.lower().like(pattern);
            // 仅当前词匹配的分类 / 账户名，避免把「羽毛球」分类串到「商飞」上。
            final catHits = [
              for (final c in cats)
                if (c.name.toLowerCase() == tok) c.id,
            ];
            if (catHits.isNotEmpty) {
              textHit = textHit | t.categoryId.isIn(catHits);
            }
            final accHits = [
              for (final a in accs)
                if (a.name.toLowerCase() == tok) a.id,
            ];
            if (accHits.isNotEmpty) {
              textHit = textHit |
                  t.accountId.isIn(accHits) |
                  t.toAccountId.isIn(accHits);
            }
            if (tok == '\u8f6c\u8d26') {
              textHit = textHit | t.type.equals('transfer');
            }
            final amountMinors = _amountMinorCandidates(tok);
            final tokHit = amountMinors.isEmpty
                ? textHit
                : (textHit | t.amountMinor.isIn(amountMinors));
            anyTok = anyTok == null ? tokHit : (anyTok | tokHit);
          }
          pred = pred & anyTok!;
        }
        return pred;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.happenAt)]);
    if (fetchLimit != null) {
      qBuilder.limit(fetchLimit);
    }
    return qBuilder.get();
  }

  /// Parse user amount input into possible minor-unit values (0 / 2 decimals).
  static List<int> _amountMinorCandidates(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[¥￥$€£,\s]'), '')
        .trim();
    if (cleaned.isEmpty) return const [];
    final n = double.tryParse(cleaned);
    if (n == null || n < 0 || n.isNaN || n.isInfinite) return const [];
    final out = <int>{};
    for (final decimals in [0, 2]) {
      var factor = 1;
      for (var i = 0; i < decimals; i++) {
        factor *= 10;
      }
      out.add((n * factor).round());
    }
    return out.toList();
  }

  /// Totals for one currency only -- never mix minor units across currencies.
  Future<({int income, int expense})> rangeSummary(
    String ledgerId,
    int startMs,
    int endMs, {
    String? currency,
  }) async {
    final by = await rangeSummaryByCurrency(ledgerId, startMs, endMs);
    if (currency != null) {
      return by[currency] ?? (income: 0, expense: 0);
    }
    // Legacy callers without currency: only safe when a single currency exists.
    if (by.length == 1) return by.values.first;
    if (by.isEmpty) return (income: 0, expense: 0);
    return (income: 0, expense: 0);
  }

  Future<Map<String, ({int income, int expense})>> rangeSummaryByCurrency(
    String ledgerId,
    int startMs,
    int endMs,
  ) async {
    // Include child sub-transactions when include_in_stat=1 (list UIs still
    // filter parent_id IS NULL).
    final rows = await (select(transactions)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.deletedAt.isNull() &
                t.includeInStat.equals(1) &
                t.happenAt.isBiggerOrEqualValue(startMs) &
                t.happenAt.isSmallerThanValue(endMs),
          ))
        .get();

    final map = <String, ({int income, int expense})>{};
    for (final r in rows) {
      if (r.type != 'in' && r.type != 'out') continue;
      final cur = map[r.currency] ?? (income: 0, expense: 0);
      if (r.type == 'in') {
        map[r.currency] =
            (income: cur.income + r.amountMinor, expense: cur.expense);
      } else {
        // out（金额可为负，表示冲减）
        map[r.currency] =
            (income: cur.income, expense: cur.expense + r.amountMinor);
      }
    }
    return map;
  }


  /// Kept for callers that still want calendar-month bounds.
  Future<({int income, int expense})> monthSummary(
    String ledgerId,
    DateTime monthLocal,
  ) async {
    final start = DateTime(monthLocal.year, monthLocal.month, 1).toUtc();
    final end = DateTime(monthLocal.year, monthLocal.month + 1, 1).toUtc();
    return rangeSummary(
      ledgerId,
      start.millisecondsSinceEpoch,
      end.millisecondsSinceEpoch,
    );
  }

  Future<List<({String categoryId, String name, int totalMinor})>>
      categoryBreakdown(
    String ledgerId,
    int startMs,
    int endMs, {
    String kind = 'out',
    String? currency,
  }) async {
    final rows = await (select(transactions)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.deletedAt.isNull() &
                t.includeInStat.equals(1) &
                t.type.equals(kind) &
                t.happenAt.isBiggerOrEqualValue(startMs) &
                t.happenAt.isSmallerThanValue(endMs),
          ))
        .get();

    final cats = await loadCategories(ledgerId, kind);
    final nameById = {for (final c in cats) c.id: c.name};
    final totals = <String, int>{};
    for (final r in rows) {
      if (currency != null && r.currency != currency) continue;
      final cid = r.categoryId ?? '_none';
      totals[cid] = (totals[cid] ?? 0) + r.amountMinor;
    }
    final list = totals.entries
        .map(
          (e) => (
            categoryId: e.key,
            name: nameById[e.key] ?? '\u672a\u5206\u7c7b',
            totalMinor: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
    return list;
  }

  /// balance = opening + in - out - transfer_out + transfer_in
  ///
  /// Aggregated in SQL. Active accounts keep their opening balance; any other
  /// account id that appears on a row is included from zero, matching the
  /// previous in-memory fold.
  Future<Map<String, int>> accountBalances(String ledgerId) async {
    final accs = await loadActiveAccounts(ledgerId);
    final balances = {for (final a in accs) a.id: a.openingBalanceMinor};
    if (balances.isEmpty) return balances;

    // Aggregate by account id (not txn.ledger_id) so cross-ledger transfers
    // update both sides' balances when the single row lives in one ledger.
    final ids = balances.keys.toList();
    final ph = List.filled(ids.length, '?').join(',');
    final vars = [for (final id in ids) Variable<String>(id)];
    final sql = '''
      SELECT id, SUM(delta) AS delta FROM (
        SELECT account_id AS id,
               SUM(CASE
                 WHEN type = 'in' THEN amount_minor
                 WHEN type IN ('out', 'transfer') THEN -amount_minor
                 ELSE 0
               END) AS delta
        FROM transactions
        WHERE deleted_at IS NULL AND account_id IN (__IN__)
        GROUP BY account_id
        UNION ALL
        SELECT to_account_id AS id,
               SUM(COALESCE(to_amount_minor, amount_minor)) AS delta
        FROM transactions
        WHERE deleted_at IS NULL
          AND type = 'transfer' AND to_account_id IN (__IN__)
        GROUP BY to_account_id
      )
      GROUP BY id
      '''.replaceAll('__IN__', ph);

    final deltas = await customSelect(
      sql,
      variables: [...vars, ...vars],
      readsFrom: {transactions},
    ).get();
    for (final r in deltas) {
      final id = r.read<String>('id');
      if (!balances.containsKey(id)) continue;
      balances[id] = balances[id]! + _sqlInt(r, 'delta');
    }
    return balances;
  }

  Stream<Map<String, int>> watchAccountBalances(String ledgerId) {
    // Latest row anywhere is only a change signal — cross-ledger transfers
    // live in the from-account's ledger but must refresh the to-ledger too.
    return (select(transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .watch()
        .asyncMap((_) => accountBalances(ledgerId));
  }

  /// Returns the new row id (parent or child).
  Future<String> insertManualTransaction({
    required String ledgerId,
    required String type,
    required int amountMinor,
    required String currency,
    required String accountId,
    String? toAccountId,
    String? categoryId,
    String? merchant,
    String? note,
    List<String>? tags,
    DateTime? happenAt,
    double? fxRate,
    int? toAmountMinor,
    int includeInStat = 1,
    int includeInBudget = 1,
    String? occurrenceKey,
    String? parentId,
    String? subTypeId,
    String? transferGroupId,
  }) async {
    final ts = nowMs();
    final happen = happenAt?.toUtc().millisecondsSinceEpoch ?? ts;
    final id = newId();
    await into(transactions).insert(
      TransactionsCompanion.insert(
        id: id,
        ledgerId: ledgerId,
        type: type,
        amountMinor: amountMinor,
        currency: currency,
        accountId: accountId,
        toAccountId: Value(toAccountId),
        categoryId: Value(categoryId),
        note: Value(composeNote(merchant: merchant, note: note)),
        tags: Value(encodeTxnTags(tags)),
        happenAt: happen,
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        includeInStat: Value(includeInStat),
        includeInBudget: Value(includeInBudget),
        occurrenceKey: Value(occurrenceKey),
        parentId: Value(parentId),
        subTypeId: Value(subTypeId),
        transferGroupId: Value(transferGroupId),
        createdAt: ts,
        updatedAt: ts,
      ),
    );
    return id;
  }

  // --- Last-used / note-level quick bookkeeping memory (settings JSON) ---

  static const lastBookkeepingKey = 'last_bookkeeping';

  /// Last type/account/category used in the manual panel, so the next 记一笔
  /// starts from the same place. Null when nothing was saved yet.
  Future<LastBookkeepingChoice?> loadLastBookkeeping() async {
    final raw = await getSetting(lastBookkeepingKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return LastBookkeepingChoice.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastBookkeeping(LastBookkeepingChoice choice) async {
    await setSetting(lastBookkeepingKey, jsonEncode(choice.toJson()));
  }

  /// Note → category id for 手动记账 (「午饭」→ 餐饮). Same idea as
  /// [MerchantRules] but keyed on the note the user typed, incl. 1–2 字.
  static const noteCategoryMapKey = 'note_category_map';
  static const int noteCategoryMapLimit = 300;

  Future<Map<String, String>> loadNoteCategoryMap() async {
    final raw = await getSetting(noteCategoryMapKey);
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      // Keep the decode order explicit: eviction relies on insertion order
      // (oldest first). Do NOT transform keys here — normalisation happens
      // once in [noteCategoryKey].
      return <String, String>{
        for (final e in decoded.entries)
          if (e.key is String && e.value is String)
            '${e.key}': '${e.value}'.trim(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Remember the category chosen for [notes] (one or more note texts).
  Future<void> rememberNoteCategories(
    Iterable<String> notes,
    String categoryId,
  ) async {
    // Preserve order: the JSON must keep the most-recent key last so eviction
    // (which drops the first key) removes the oldest entry, not a fresh one.
    // Set.from() over a list literal is not order-stable across hash seeds.
    final keys = <String>[];
    for (final n in notes) {
      final k = noteCategoryKey(n);
      if (k != null && !keys.contains(k)) keys.add(k);
    }
    if (keys.isEmpty) return;
    final map = await loadNoteCategoryMap();
    for (final k in keys) {
      map.remove(k);
      map[k] = categoryId;
    }
    while (map.length > noteCategoryMapLimit) {
      map.remove(map.keys.first);
    }
    await setSetting(noteCategoryMapKey, jsonEncode(map));
  }

  /// Category previously used for [note], if remembered. 精确命中优先，
  /// 再退回「整句包含某个记忆碎片」的模糊命中（如「午饭和同事」→「午饭」）。
  Future<String?> recallCategoryForNote(String? note) async {
    final key = noteCategoryKey(note);
    if (key == null) return null;
    final map = await loadNoteCategoryMap();
    final exact = map[key];
    if (exact != null) return exact;
    String? best;
    var bestLen = 0;
    for (final e in map.entries) {
      if (e.key.length < 2) continue;
      if (key.contains(e.key) && e.key.length > bestLen) {
        best = e.value;
        bestLen = e.key.length;
      }
    }
    return best;
  }

  Future<void> createAccount({
    required String ledgerId,
    required String name,
    required String currency,
    required String type,
    int openingBalanceMinor = 0,
    String? icon,
  }) async {
    final ts = nowMs();
    final typeId = await resolveAssetTypeId(ledgerId: ledgerId, raw: type);
    final assetType = await getAssetType(typeId);
    final existing = await loadActiveAccounts(ledgerId);
    final order = existing.isEmpty
        ? 0
        : existing.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final iconKey = (icon ?? '').trim().isNotEmpty
        ? icon!.trim()
        : defaultIconKeyForAccount(
            name: name,
            type: typeId,
            typeName: assetType?.name,
            typeIcon: assetType?.icon,
          );
    await into(accounts).insert(
      AccountsCompanion.insert(
        id: newId(),
        ledgerId: ledgerId,
        name: name,
        currency: currency,
        type: typeId,
        icon: Value(iconKey),
        openingBalanceMinor: Value(openingBalanceMinor),
        sortOrder: Value(order),
        createdAt: ts,
        updatedAt: ts,
      ),
    );
  }

  Future<void> updateAccount({
    required String id,
    required String name,
    required String currency,
    required String type,
    required int openingBalanceMinor,
    String? icon,
  }) async {
    final ts = nowMs();
    final existing = await (select(accounts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    final typeId = existing == null
        ? type
        : await resolveAssetTypeId(ledgerId: existing.ledgerId, raw: type);
    await (update(accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        name: Value(name),
        currency: Value(currency),
        type: Value(typeId),
        openingBalanceMinor: Value(openingBalanceMinor),
        icon: Value(icon),
        updatedAt: Value(ts),
      ),
    );
  }

  Future<List<Account>> loadActiveAccounts(String ledgerId) {
    return (select(accounts)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.archived.equals(0))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// All non-archived accounts across ledgers (cross-ledger transfer picker).
  Future<List<Account>> loadAllActiveAccounts() {
    return (select(accounts)
          ..where((t) => t.archived.equals(0))
          ..orderBy([
            (t) => OrderingTerm.asc(t.ledgerId),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .get();
  }

  /// ledgerId → name for picker labels.
  Future<Map<String, String>> loadLedgerNameMap({bool includeArchived = false}) async {
    final rows = await loadAllLedgers(includeArchived: includeArchived);
    return {for (final l in rows) l.id: l.name};
  }

  /// Active + archived accounts (search filters / historical txns).
  Future<List<Account>> loadAccountsIncludingArchived(String ledgerId) {
    return (select(accounts)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.archived),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .get();
  }


  /// Category + account maps for list tiles (one load, many sync lookups).
  Future<TxnListLookups> loadTxnListLookups(String ledgerId) async {
    final cats = await (select(categories)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .get();
    // All accounts so cross-ledger transfer counterpart names resolve.
    final accs = await select(accounts).get();
    return TxnListLookups(
      categoriesById: {for (final c in cats) c.id: c},
      accountsById: {for (final a in accs) a.id: a},
    );
  }

  Future<List<Category>> loadCategories(String ledgerId, String kind) {
    return (select(categories)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.archived.equals(0) &
                t.kind.equals(kind),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Stream<List<Category>> watchCategories(String ledgerId, String kind) {
    return (select(categories)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.archived.equals(0) &
                t.kind.equals(kind),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<void> createCategory({
    required String ledgerId,
    required String name,
    required String kind,
    String? parentId,
    String? icon,
  }) async {
    final ts = nowMs();
    final siblings = await (select(categories)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.kind.equals(kind) &
                t.archived.equals(0) &
                (parentId == null
                    ? t.parentId.isNull()
                    : t.parentId.equals(parentId)),
          ))
        .get();
    final order = siblings.isEmpty
        ? 0
        : siblings.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final iconKey = (icon ?? '').trim().isNotEmpty
        ? icon!.trim()
        : defaultIconKeyForCategoryName(name);
    await into(categories).insert(
      CategoriesCompanion.insert(
        id: newId(),
        ledgerId: ledgerId,
        name: name,
        parentId: Value(parentId),
        kind: kind,
        icon: Value(iconKey),
        sortOrder: Value(order),
        createdAt: ts,
      ),
    );
  }

  Future<void> renameCategory({
    required String id,
    required String name,
    String? icon,
    bool updateIcon = false,
  }) async {
    await (update(categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        icon: updateIcon ? Value(icon) : const Value.absent(),
      ),
    );
  }

  Future<void> updateCategoryIcon({
    required String id,
    String? icon,
  }) async {
    await (update(categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(icon: Value(icon)),
    );
  }

  /// Persist sibling display order. [orderedIds] must be one sibling group
  /// (same parent / all roots); indices become sort_order 0..n-1.
  Future<void> reorderCategories(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(categories)..where((t) => t.id.equals(orderedIds[i])))
            .write(CategoriesCompanion(sortOrder: Value(i)));
      }
    });
  }

  /// Soft-archive. Docs: categories with transactions must not be hard-deleted.
  Future<void> archiveCategory(String id) async {
    await (update(categories)..where((t) => t.id.equals(id))).write(
      const CategoriesCompanion(archived: Value(1)),
    );
    // Also archive direct children so they leave active lists.
    await (update(categories)..where((t) => t.parentId.equals(id))).write(
      const CategoriesCompanion(archived: Value(1)),
    );
  }

  Future<List<Category>> loadArchivedCategories(String ledgerId, String kind) {
    return (select(categories)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.archived.equals(1) &
                t.kind.equals(kind),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Stream<List<Category>> watchArchivedCategories(String ledgerId, String kind) {
    return (select(categories)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.archived.equals(1) &
                t.kind.equals(kind),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  /// Restore soft-archived category. Cascades to direct children when
  /// [restoreChildren] is true. If this is a child whose parent is still
  /// archived, the parent is unarchived first so the tree stays consistent.
  Future<void> unarchiveCategory(
    String id, {
    bool restoreChildren = true,
  }) async {
    final cat = await getCategory(id);
    if (cat == null) return;
    if (cat.parentId != null) {
      final parent = await getCategory(cat.parentId!);
      if (parent != null && parent.archived != 0) {
        await (update(categories)..where((t) => t.id.equals(parent.id))).write(
          const CategoriesCompanion(archived: Value(0)),
        );
      }
    }
    await (update(categories)..where((t) => t.id.equals(id))).write(
      const CategoriesCompanion(archived: Value(0)),
    );
    if (restoreChildren) {
      await (update(categories)..where((t) => t.parentId.equals(id))).write(
        const CategoriesCompanion(archived: Value(0)),
      );
    }
  }

  Future<int> countTransactionsForCategory(String categoryId) async {
    final rows = await (select(transactions)
          ..where(
            (t) =>
                t.categoryId.equals(categoryId) & t.deletedAt.isNull(),
          ))
        .get();
    return rows.length;
  }

  Future<Transaction?> getTransaction(String id) {
    return (select(transactions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<Transaction?> watchTransaction(String id) {
    return (select(transactions)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  Future<Category?> getCategory(String id) {
    return (select(categories)..where((t) => t.id.equals(id))).getSingleOrNull();
  }


  /// Soft-delete (sets deleted_at). Home / range queries already filter null deletedAt.

  /// Distinct tags across non-deleted txns in [ledgerId] (for chip suggestions).
  Future<List<String>> listDistinctTags(String ledgerId) async {
    final rows = await (select(transactions)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.deletedAt.isNull() & t.tags.isNotNull()))
        .get();
    final seen = <String>{};
    for (final r in rows) {
      for (final tag in decodeTxnTags(r.tags)) {
        seen.add(tag);
      }
    }
    final list = seen.toList()..sort();
    return list;
  }

  /// Replace tags on an existing transaction (detail editor).
  Future<void> updateTransactionTags(String id, List<String> tags) async {
    final ts = nowMs();
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        tags: Value(encodeTxnTags(tags)),
        updatedAt: Value(ts),
      ),
    );
  }

  Future<void> softDeleteTransaction(String id) async {
    final ts = nowMs();
    final patch = TransactionsCompanion(
      deletedAt: Value(ts),
      updatedAt: Value(ts),
    );
    await (update(transactions)..where((t) => t.id.equals(id))).write(patch);
    // Cascade soft-delete child sub-transactions.
    await (update(transactions)
          ..where((t) => t.parentId.equals(id) & t.deletedAt.isNull()))
        .write(patch);
  }

  /// Soft-delete many top-level bills (and their live children). Returns count.
  Future<int> softDeleteTransactions(Iterable<String> ids) async {
    final list = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (list.isEmpty) return 0;
    var n = 0;
    await transaction(() async {
      for (final id in list) {
        final row = await (select(transactions)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
        if (row == null || row.deletedAt != null) continue;
        await softDeleteTransaction(id);
        n++;
      }
    });
    return n;
  }

  /// Soft-deleted top-level bills only (children restored with their parent).
  Stream<List<Transaction>> watchDeletedTransactions(String ledgerId) {
    return (select(transactions)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.deletedAt.isNotNull() &
                t.parentId.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  Future<int> countDeletedTransactions(String ledgerId) async {
    final q = selectOnly(transactions)
      ..addColumns([transactions.id.count()])
      ..where(
        transactions.ledgerId.equals(ledgerId) &
            transactions.deletedAt.isNotNull() &
            transactions.parentId.isNull(),
      );
    final rows = await q.get();
    if (rows.isEmpty) return 0;
    return rows.first.read(transactions.id.count()) ?? 0;
  }

  /// Clear deleted_at so the txn reappears in home / stats.
  ///
  /// Cascades only to children that were soft-deleted together with this
  /// parent (same [deletedAt]); earlier soft-deleted children stay deleted.
  /// Restoring a child whose parent is still deleted also restores the parent
  /// (avoids orphan live children).
  Future<void> undeleteTransaction(String id) async {
    final row = await (select(transactions)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    final parentId = row.parentId;
    if (parentId != null) {
      final parent = await (select(transactions)
            ..where((t) => t.id.equals(parentId)))
          .getSingleOrNull();
      if (parent != null && parent.deletedAt != null) {
        await undeleteTransaction(parentId);
        return;
      }
    }
    final ts = nowMs();
    final patch = TransactionsCompanion(
      deletedAt: const Value(null),
      updatedAt: Value(ts),
    );
    await (update(transactions)..where((t) => t.id.equals(id))).write(patch);
    final deletedAt = row.deletedAt;
    if (deletedAt != null) {
      await (update(transactions)
            ..where(
              (t) =>
                  t.parentId.equals(id) & t.deletedAt.equals(deletedAt),
            ))
          .write(patch);
    }
  }

  // --- Sub-transaction types (global templates) ---

  static const kDefaultSubTransactionTypes = <(String name, int sign)>[
    ('AA', 1),
    ('退款', 1),
    ('返现', 1),
    ('手续费', -1),
    ('补差价', -1),
  ];

  static const kSubTypesSeededKey = 'sub_types_seeded';

  /// Seed built-in sub-transaction types once.
  ///
  /// Called from onCreate / v14 migration only — not from [beforeOpen], so
  /// deleting every type stays deleted (no resurrection).
  Future<void> seedDefaultSubTransactionTypes() async {
    final flagged = await getSetting(kSubTypesSeededKey);
    if (flagged == '1') return;
    final existing = await (select(subTransactionTypes)..limit(1)).get();
    if (existing.isNotEmpty) {
      await setSetting(kSubTypesSeededKey, '1');
      return;
    }
    final ts = nowMs();
    await transaction(() async {
      for (var i = 0; i < kDefaultSubTransactionTypes.length; i++) {
        final (name, sign) = kDefaultSubTransactionTypes[i];
        await into(subTransactionTypes).insert(
          SubTransactionTypesCompanion.insert(
            id: newId(),
            name: name,
            sign: sign,
            sortOrder: Value(i),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
      }
      await setSetting(kSubTypesSeededKey, '1');
    });
  }

  Stream<List<SubTransactionType>> watchSubTransactionTypes() {
    return (select(subTransactionTypes)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<List<SubTransactionType>> loadSubTransactionTypes() {
    return (select(subTransactionTypes)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// All templates including soft-deleted (backup / restore).
  Future<List<SubTransactionType>> loadSubTransactionTypesForExport() {
    return (select(subTransactionTypes)
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  /// Upsert sub-transaction types from import (by id). Missing maps are no-ops.
  Future<int> upsertSubTransactionTypesFromImport(
    List<Map<String, dynamic>> maps,
  ) async {
    if (maps.isEmpty) return 0;
    var n = 0;
    final ts = nowMs();
    for (final raw in maps) {
      final m = Map<String, dynamic>.from(raw);
      // Accept snake_case from Excel.
      if (m.containsKey('icon_key') && !m.containsKey('iconKey')) {
        m['iconKey'] = m['icon_key'];
      }
      if (m.containsKey('sort_order') && !m.containsKey('sortOrder')) {
        m['sortOrder'] = m['sort_order'];
      }
      if (m.containsKey('deleted_at') && !m.containsKey('deletedAt')) {
        m['deletedAt'] = m['deleted_at'];
      }
      if (m.containsKey('created_at') && !m.containsKey('createdAt')) {
        m['createdAt'] = m['created_at'];
      }
      if (m.containsKey('updated_at') && !m.containsKey('updatedAt')) {
        m['updatedAt'] = m['updated_at'];
      }
      m.putIfAbsent('createdAt', () => ts);
      m.putIfAbsent('updatedAt', () => ts);
      m.putIfAbsent('sortOrder', () => 0);
      m.putIfAbsent('sign', () => 1);
      final id = '${m['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      m['id'] = id;
      final name = '${m['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      m['name'] = name;
      final row = SubTransactionType.fromJson(m);
      final existing = await (select(subTransactionTypes)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (existing == null) {
        await into(subTransactionTypes).insert(row.toCompanion(true));
      } else {
        await (update(subTransactionTypes)..where((t) => t.id.equals(id)))
            .write(row.toCompanion(true));
      }
      n++;
    }
    if (n > 0) {
      await setSetting(kSubTypesSeededKey, '1');
    }
    return n;
  }

  Future<SubTransactionType?> getSubTransactionType(String id) {
    return (select(subTransactionTypes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<String> insertSubTransactionType({
    required String name,
    required int sign,
    String? iconKey,
  }) async {
    final ts = nowMs();
    final siblings = await loadSubTransactionTypes();
    final order = siblings.isEmpty
        ? 0
        : siblings.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final id = newId();
    await into(subTransactionTypes).insert(
      SubTransactionTypesCompanion.insert(
        id: id,
        name: name.trim(),
        sign: sign >= 0 ? 1 : -1,
        iconKey: Value(iconKey),
        sortOrder: Value(order),
        createdAt: ts,
        updatedAt: ts,
      ),
    );
    return id;
  }

  Future<void> updateSubTransactionType({
    required String id,
    String? name,
    int? sign,
    String? iconKey,
    bool updateIcon = false,
  }) async {
    await (update(subTransactionTypes)..where((t) => t.id.equals(id))).write(
      SubTransactionTypesCompanion(
        name: name != null ? Value(name.trim()) : const Value.absent(),
        sign: sign != null ? Value(sign >= 0 ? 1 : -1) : const Value.absent(),
        iconKey: updateIcon ? Value(iconKey) : const Value.absent(),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  Future<void> reorderSubTransactionTypes(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final ts = nowMs();
    await transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (update(subTransactionTypes)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(
          SubTransactionTypesCompanion(
            sortOrder: Value(i),
            updatedAt: Value(ts),
          ),
        );
      }
    });
  }

  Future<void> softDeleteSubTransactionType(String id) async {
    final ts = nowMs();
    await (update(subTransactionTypes)..where((t) => t.id.equals(id))).write(
      SubTransactionTypesCompanion(
        deletedAt: Value(ts),
        updatedAt: Value(ts),
      ),
    );
  }

  Stream<List<Transaction>> watchChildTransactions(String parentId) {
    return (select(transactions)
          ..where(
            (t) => t.parentId.equals(parentId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<Transaction>> loadChildTransactions(String parentId) {
    return (select(transactions)
          ..where(
            (t) => t.parentId.equals(parentId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<int> undeleteTransactions(Iterable<String> ids) async {
    final list = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (list.isEmpty) return 0;
    final ts = nowMs();
    final rows =
        await (select(transactions)..where((t) => t.id.isIn(list))).get();
    final extra = <String>{};
    for (final row in rows) {
      // If restoring a child whose parent is still deleted, bring parent too.
      final parentId = row.parentId;
      if (parentId != null) {
        final parent = await (select(transactions)
              ..where((t) => t.id.equals(parentId)))
            .getSingleOrNull();
        if (parent != null && parent.deletedAt != null) {
          extra.add(parent.id);
          final pDeleted = parent.deletedAt!;
          final siblings = await (select(transactions)
                ..where(
                  (t) =>
                      t.parentId.equals(parent.id) &
                      t.deletedAt.equals(pDeleted),
                ))
              .get();
          for (final c in siblings) {
            extra.add(c.id);
          }
        }
      }
      final deletedAt = row.deletedAt;
      if (deletedAt == null) continue;
      final children = await (select(transactions)
            ..where(
              (t) =>
                  t.parentId.equals(row.id) & t.deletedAt.equals(deletedAt),
            ))
          .get();
      for (final c in children) {
        extra.add(c.id);
      }
    }
    final all = {...list, ...extra}.toList();
    return (update(transactions)..where((t) => t.id.isIn(all))).write(
      TransactionsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(ts),
      ),
    );
  }

  /// Permanently remove a soft-deleted txn (and any child rows by parent_id).
  Future<void> purgeDeletedTransaction(String id) async {
    await (delete(transactions)..where((t) => t.parentId.equals(id))).go();
    await (delete(transactions)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNotNull()))
        .go();
  }

  Future<int> purgeDeletedTransactions(Iterable<String> ids) async {
    final list = ids.where((id) => id.isNotEmpty).toList();
    if (list.isEmpty) return 0;
    await (delete(transactions)..where((t) => t.parentId.isIn(list))).go();
    return (delete(transactions)
          ..where((t) => t.id.isIn(list) & t.deletedAt.isNotNull()))
        .go();
  }

  Future<int> purgeAllDeletedTransactions(String ledgerId) async {
    return (delete(transactions)
          ..where(
            (t) => t.ledgerId.equals(ledgerId) & t.deletedAt.isNotNull(),
          ))
        .go();
  }

  /// 永久删除回收站中 [deletedAt] 早于 [beforeMs] 的记录（跨账本或指定账本）。
  Future<int> purgeDeletedOlderThan(int beforeMs, {String? ledgerId}) async {
    return (delete(transactions)..where((t) {
          var expr = t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(beforeMs);
          if (ledgerId != null) {
            expr = expr & t.ledgerId.equals(ledgerId);
          }
          return expr;
        })).go();
  }

  /// 该分类最近一笔未删除流水的账户与备注（用于记账记忆）。
  Future<({String? accountId, String? note})?> lastFieldsForCategory({
    required String ledgerId,
    required String categoryId,
  }) async {
    final row = await (select(transactions)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.categoryId.equals(categoryId) &
                t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(1))
        .getSingleOrNull();
    if (row == null) return null;
    final n = row.note?.trim();
    return (
      accountId: row.accountId,
      note: (n == null || n.isEmpty) ? null : n,
    );
  }

  Future<void> setIncludeInStat(String id, bool include) async {
    final ts = nowMs();
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        includeInStat: Value(include ? 1 : 0),
        updatedAt: Value(ts),
      ),
    );
  }

  Future<void> setIncludeInBudget(String id, bool include) async {
    final ts = nowMs();
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        includeInBudget: Value(include ? 1 : 0),
        updatedAt: Value(ts),
      ),
    );
  }

  Future<void> updateManualTransaction({
    required String id,
    required String type,
    required int amountMinor,
    required String currency,
    required String accountId,
    String? toAccountId,
    String? categoryId,
    String? merchant,
    String? note,
    List<String>? tags,
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
        note: Value(composeNote(merchant: merchant, note: note)),
        tags: Value(encodeTxnTags(tags)),
        happenAt: happen != null ? Value(happen) : const Value.absent(),
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        updatedAt: Value(ts),
      ),
    );
  }

  /// Field-level update for bill-detail row edits. Only provided arguments
  /// change; source / occurrence columns are preserved.
  ///
  /// 可空字段用 [Value] 包裹：`Value(null)` 表示清空，省略表示不改。
  Future<void> updateTransactionFields({
    required String id,
    String? type,
    int? amountMinor,
    String? currency,
    String? accountId,
    Value<String?>? toAccountId,
    String? categoryId,
    DateTime? happenAt,
    List<String>? tags,
    String? note,
    int? includeInStat,
    int? includeInBudget,
    Value<int?>? toAmountMinor,
    Value<double?>? fxRate,
    String? parentId,
    String? subTypeId,
  }) async {
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        type: type != null ? Value(type) : const Value.absent(),
        amountMinor:
            amountMinor != null ? Value(amountMinor) : const Value.absent(),
        currency: currency != null ? Value(currency) : const Value.absent(),
        accountId: accountId != null ? Value(accountId) : const Value.absent(),
        toAccountId: toAccountId ?? const Value.absent(),
        categoryId: categoryId != null
            ? Value(categoryId)
            : const Value.absent(),
        happenAt: happenAt != null
            ? Value(happenAt.toUtc().millisecondsSinceEpoch)
            : const Value.absent(),
        tags: tags != null ? Value(encodeTxnTags(tags)) : const Value.absent(),
        note: note != null ? Value(note) : const Value.absent(),
        includeInStat:
            includeInStat != null ? Value(includeInStat) : const Value.absent(),
        includeInBudget: includeInBudget != null
            ? Value(includeInBudget)
            : const Value.absent(),
        toAmountMinor: toAmountMinor ?? const Value.absent(),
        fxRate: fxRate ?? const Value.absent(),
        parentId: parentId != null ? Value(parentId) : const Value.absent(),
        subTypeId: subTypeId != null ? Value(subTypeId) : const Value.absent(),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  Future<Account?> getAccount(String id) {
    return (select(accounts)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Account?> watchAccount(String id) {
    return (select(accounts)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  /// Transactions that debit or credit [accountId] within [startMs, endMs).
  Stream<List<Transaction>> watchAccountTransactionsInRange(
    String accountId,
    int startMs,
    int endMs, {
    int limit = 200,
  }) {
    return (select(transactions)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.happenAt.isBiggerOrEqualValue(startMs) &
                t.happenAt.isSmallerThanValue(endMs) &
                (t.accountId.equals(accountId) |
                    t.toAccountId.equals(accountId)),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(limit))
        .watch();
  }

  /// Soft-archive account so it leaves active asset lists.
  Future<void> archiveAccount(String id) async {
    final ts = nowMs();
    await (update(accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        archived: const Value(1),
        updatedAt: Value(ts),
      ),
    );
  }

  Future<List<Account>> loadArchivedAccounts(String ledgerId) {
    return (select(accounts)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.archived.equals(1))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Stream<List<Account>> watchArchivedAccounts(String ledgerId) {
    return (select(accounts)
          ..where((t) => t.ledgerId.equals(ledgerId) & t.archived.equals(1))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  /// Restore soft-archived account so it returns to active asset lists.
  Future<void> unarchiveAccount(String id) async {
    final ts = nowMs();
    await (update(accounts)..where((t) => t.id.equals(id))).write(
      AccountsCompanion(
        archived: const Value(0),
        updatedAt: Value(ts),
      ),
    );
  }

  /// Live (non-deleted) transactions that debit/credit this account.
  Future<int> countLiveTransactionsForAccount(String accountId) async {
    final q = selectOnly(transactions)
      ..addColumns([transactions.id.count()])
      ..where(
        transactions.deletedAt.isNull() &
            (transactions.accountId.equals(accountId) |
                transactions.toAccountId.equals(accountId)),
      );
    final rows = await q.get();
    if (rows.isEmpty) return 0;
    return rows.first.read(transactions.id.count()) ?? 0;
  }

  /// Hard-delete an account when it has no live transactions.
  ///
  /// Throws [StateError] with a Chinese message when blocked.
  Future<void> deleteAccount(String id) async {
    final live = await countLiveTransactionsForAccount(id);
    if (live > 0) {
      throw StateError('该资产账户仍有 $live 笔流水，请先删除流水或先归档');
    }
    // Purge soft-deleted history that still references the account, then drop.
    await (delete(transactions)
          ..where(
            (t) =>
                t.deletedAt.isNotNull() &
                (t.accountId.equals(id) | t.toAccountId.equals(id)),
          ))
        .go();
    await (delete(accounts)..where((t) => t.id.equals(id))).go();
  }

  Future<int> countLiveTransactionsForLedger(String ledgerId) async {
    final q = selectOnly(transactions)
      ..addColumns([transactions.id.count()])
      ..where(
        transactions.ledgerId.equals(ledgerId) & transactions.deletedAt.isNull(),
      );
    final rows = await q.get();
    if (rows.isEmpty) return 0;
    return rows.first.read(transactions.id.count()) ?? 0;
  }

  /// Hard-delete a ledger when it is not the sole active one and has no live txns.
  ///
  /// Cascades empty accounts / categories / pending for that ledger.
  /// Throws [StateError] with a Chinese message when blocked.
  Future<void> deleteLedger(String id) async {
    final active = await (select(ledgers)..where((t) => t.archived.equals(0))).get();
    final isActive = active.any((l) => l.id == id);
    if (isActive && active.length <= 1) {
      throw StateError('至少保留一个未归档记账本，无法删除');
    }
    final live = await countLiveTransactionsForLedger(id);
    if (live > 0) {
      throw StateError('该记账本仍有 $live 笔流水，请先删除流水或先归档');
    }
    await transaction(() async {
      await (delete(transactions)..where((t) => t.ledgerId.equals(id))).go();
      await (delete(pendingCaptures)..where((t) => t.ledgerId.equals(id))).go();
      await (delete(accounts)..where((t) => t.ledgerId.equals(id))).go();
      await (delete(categories)..where((t) => t.ledgerId.equals(id))).go();
      try {
        await (delete(budgets)..where((t) => t.ledgerId.equals(id))).go();
      } catch (_) {}
      await (delete(ledgers)..where((t) => t.id.equals(id))).go();
      final current = await currentLedgerId();
      if (current == id) {
        final others = await (select(ledgers)
              ..where((t) => t.archived.equals(0)))
            .get();
        if (others.isNotEmpty) {
          await setCurrentLedgerId(others.first.id);
        }
      }
    });
  }

  /// Adjust balance by posting an in/out balance-correction txn (excluded from stats).
  /// Policy: do not rewrite opening_balance; correction is auditable in the ledger.
  Future<void> adjustAccountBalance({
    required Account account,
    required int targetBalanceMinor,
    required int currentBalanceMinor,
  }) async {
    final diff = targetBalanceMinor - currentBalanceMinor;
    if (diff == 0) return;
    final type = diff > 0 ? 'in' : 'out';
    await insertManualTransaction(
      ledgerId: account.ledgerId,
      type: type,
      amountMinor: diff.abs(),
      currency: account.currency,
      accountId: account.id,
      note: '余额校正',
      includeInStat: 0,
      includeInBudget: 0,
    );
  }

  // --- Pending captures / notification ingest (P1) ---

  Stream<List<PendingCapture>> watchPendingCaptures(
    String ledgerId, {
    String status = 'pending',
  }) {
    return (select(pendingCaptures)
          ..where(
            (t) => t.ledgerId.equals(ledgerId) & t.status.equals(status),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)]))
        .watch();
  }

  /// Pending rows that parsed ok (parse_ok = 1) — "待确认" tab.
  Stream<List<PendingCapture>> watchPendingOkCaptures(String ledgerId) {
    return (select(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.status.equals('pending') &
                t.parseOk.equals(1),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)]))
        .watch();
  }

  /// Pending rows that failed amount/merchant parse (parse_ok = 0).
  Stream<List<PendingCapture>> watchParseFailedCaptures(String ledgerId) {
    return (select(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.status.equals('pending') &
                t.parseOk.equals(0),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)]))
        .watch();
  }

  /// Confirmed / unknown statuses — "已入账" tab (partition complement).
  /// status NOT IN ('pending','ignored') so unknown statuses are not lost.
  Stream<List<PendingCapture>> watchConfirmedCaptures(String ledgerId) {
    return (select(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.status.isNotIn(['pending', 'ignored']),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)]))
        .watch();
  }

  Stream<int> watchPendingCount(String ledgerId) {
    final q = selectOnly(pendingCaptures)
      ..addColumns([pendingCaptures.id.count()])
      ..where(
        pendingCaptures.ledgerId.equals(ledgerId) &
            pendingCaptures.status.equals('pending'),
      );
    return q.watch().map((rows) {
      if (rows.isEmpty) return 0;
      return rows.first.read(pendingCaptures.id.count()) ?? 0;
    });
  }

  /// True if a **pending** row already holds [key].
  ///
  /// Confirmed / ignored rows must not block forever — WeChat often reuses the
  /// same [StatusBarNotification] key for later payments. Those rows retire
  /// their key on confirm/ignore; this check only looks at live pending.
  Future<bool> existsDedupeKey(String key) async {
    final row = await (select(pendingCaptures)
          ..where(
            (t) => t.dedupeKey.equals(key) & t.status.equals('pending'),
          )
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Free [dedupeKey] unique slot after confirm/ignore so the next payment
  /// with the same notification key can create a new pending row.
  Future<void> _retireDedupeKey(String id, String oldKey) async {
    final retired = oldKey.startsWith('done|')
        ? oldKey
        : (oldKey.length <= 120 ? 'done|$id|$oldKey' : 'done|$id');
    if (retired == oldKey) return;
    await (update(pendingCaptures)..where((t) => t.id.equals(id))).write(
      PendingCapturesCompanion(
        dedupeKey: Value(retired),
        updatedAt: Value(nowMs()),
      ),
    );
  }

  /// Legacy confirmed/ignored rows may still hold the live key (unique).
  /// Retire them so a new insert can proceed.
  Future<void> _retireInactiveDedupeKey(String key) async {
    final rows = await (select(pendingCaptures)
          ..where(
            (t) =>
                t.dedupeKey.equals(key) & t.status.isNotValue('pending'),
          ))
        .get();
    for (final r in rows) {
      await _retireDedupeKey(r.id, r.dedupeKey);
    }
  }

  Future<PendingCapture?> getPendingCapture(String id) {
    return (select(pendingCaptures)
          ..where((t) => t.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<MerchantRule?> findMerchantRule(
    String ledgerId,
    String merchantKey,
  ) {
    return (select(merchantRules)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.merchantKey.equals(merchantKey),
          )
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> upsertMerchantRule({
    required String ledgerId,
    required String merchantKey,
    String? categoryId,
    String? accountId,
  }) async {
    final ts = nowMs();
    final existing = await findMerchantRule(ledgerId, merchantKey);
    if (existing == null) {
      await into(merchantRules).insert(
        MerchantRulesCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          merchantKey: merchantKey,
          categoryId: Value(categoryId),
          accountId: Value(accountId),
          updatedAt: ts,
        ),
      );
      return;
    }
    await (update(merchantRules)..where((t) => t.id.equals(existing.id)))
        .write(
      MerchantRulesCompanion(
        categoryId: Value(categoryId ?? existing.categoryId),
        accountId: Value(accountId ?? existing.accountId),
        hitCount: Value(existing.hitCount + 1),
        updatedAt: Value(ts),
      ),
    );
  }

  static const captureAccountMapKey = 'capture_account_map';

  /// Per-app default account map: hint/pkg key → accountId.
  Future<Map<String, String>> getCaptureAccountMap() async {
    final raw = await getSetting(captureAccountMapKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.key is String && e.value is String && (e.value as String).isNotEmpty)
            e.key as String: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> setCaptureAccountMap(Map<String, String> map) async {
    final cleaned = {
      for (final e in map.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    await setSetting(captureAccountMapKey, jsonEncode(cleaned));
  }

  Future<void> setCaptureAccountForHint(String hint, String? accountId) async {
    final map = await getCaptureAccountMap();
    if (accountId == null || accountId.isEmpty) {
      map.remove(hint);
    } else {
      map[hint] = accountId;
    }
    await setCaptureAccountMap(map);
  }

  Future<String?> defaultAccountIdForPkg(
    String ledgerId,
    String pkg, {
    String? hint,
  }) async {
    final map = await getCaptureAccountMap();
    final h = hint ?? '';
    // Prefer explicit user mapping by hint, then by package.
    final mapped = map[h] ?? map[pkg];
    if (mapped != null && mapped.isNotEmpty) {
      final accounts = await loadActiveAccounts(ledgerId);
      if (accounts.any((a) => a.id == mapped)) return mapped;
    }

    String? name;
    if (h == 'alipay' || pkg.contains('Alipay') || pkg.contains('alipay')) {
      name = '支付宝';
    } else if (h == 'wechat' || pkg.contains('tencent.mm')) {
      name = '微信';
    }
    if (name == null) return null;
    final list = await loadActiveAccounts(ledgerId);
    for (final a in list) {
      if (a.name == name) return a.id;
    }
    return list.isEmpty ? null : list.first.id;
  }

  /// Insert a parsed notification into pending_captures (deduped).
  /// Returns the new id, or null if skipped (dedupe / blank).
  Future<String?> ingestParsedNotification({
    required String ledgerId,
    required String sourcePkg,
    String? rawTitle,
    required String rawText,
    required String dedupeKey,
    int? amountMinor,
    String? currency,
    String? merchant,
    int? happenAt,
    bool parseOk = false,
    String? accountHint,
    String? direction,
  }) async {
    if (rawText.trim().isEmpty && (rawTitle ?? '').trim().isEmpty) {
      return null;
    }
    if (await existsDedupeKey(dedupeKey)) return null;
    // Old confirmed/ignored rows may still occupy the unique key.
    await _retireInactiveDedupeKey(dedupeKey);

    String? suggestedCategory;
    String? suggestedAccount =
        await defaultAccountIdForPkg(ledgerId, sourcePkg, hint: accountHint);

    if (merchant != null && merchant.trim().isNotEmpty) {
      final key = merchant.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final rule = await findMerchantRule(ledgerId, key);
      if (rule != null) {
        suggestedCategory = rule.categoryId;
        suggestedAccount = rule.accountId ?? suggestedAccount;
      }
    }

    final ts = nowMs();
    final id = newId();
    try {
      await into(pendingCaptures).insert(
        PendingCapturesCompanion.insert(
          id: id,
          ledgerId: ledgerId,
          sourcePkg: sourcePkg,
          rawTitle: Value(rawTitle),
          rawText: rawText,
          amountMinor: Value(amountMinor),
          currency: Value(currency ?? 'CNY'),
          note: Value(composeNote(merchant: merchant, note: null)),
          happenAt: Value(happenAt ?? ts),
          suggestedCategoryId: Value(suggestedCategory),
          suggestedAccountId: Value(suggestedAccount),
          status: 'pending',
          dedupeKey: dedupeKey,
          parseOk: Value(parseOk ? 1 : 0),
          direction: Value(direction),
          createdAt: ts,
          updatedAt: ts,
        ),
      );
    } catch (_) {
      // Unique race / leftover key — treat as dedupe skip.
      return null;
    }
    return id;
  }


  /// Map pending `sourcePkg` to transactions.source for detail display.
  /// `manual:ocr` → `ocr`; real notification pkgs → `notification`.
  static String _txnSourceFromPendingPkg(String sourcePkg) {
    if (sourcePkg.startsWith('manual:')) {
      final kind = sourcePkg.substring('manual:'.length);
      if (kind.isEmpty) return 'manual';
      return kind;
    }
    return 'notification';
  }

  Future<void> confirmPendingCapture({
    required String pendingId,
    required int amountMinor,
    required String currency,
    required String accountId,
    required String categoryId,
    String? note,
    String? merchantForRule,
    String type = 'out',
    List<String>? tags,
    int includeInStat = 1,
    int includeInBudget = 1,
    /// Target ledger; defaults to pending.ledgerId. If [accountId] belongs to
    /// another ledger, that account's ledger wins (avoids mis-attribution).
    String? ledgerId,
  }) async {
    final pending = await (select(pendingCaptures)
          ..where((t) => t.id.equals(pendingId)))
        .getSingle();

    // Already confirmed (e.g. Native overlay won the race) → idempotent OK.
    if (pending.status == 'confirmed') {
      final existing = await (select(transactions)
            ..where((t) => t.pendingId.equals(pendingId)))
          .get();
      if (existing.isNotEmpty) return;
    }
    if (pending.status != 'pending') {
      throw StateError('该记录不是待确认状态');
    }

    final ts = nowMs();
    // Derive real source from pending.sourcePkg (manual:ocr / clipboard / …)
    // so screenshot imports are not mislabeled as notification.
    final source = _txnSourceFromPendingPkg(pending.sourcePkg);
    await transaction(() async {
      final already = await (select(transactions)
            ..where((t) => t.pendingId.equals(pendingId)))
          .get();
      if (already.isEmpty) {
        try {
          // Prefer account's own ledger when it differs from pending / override.
          var targetLedgerId = ledgerId ?? pending.ledgerId;
          final accRow = await (select(accounts)
                ..where((t) => t.id.equals(accountId)))
              .getSingleOrNull();
          if (accRow != null && accRow.ledgerId.isNotEmpty) {
            targetLedgerId = accRow.ledgerId;
          }
          await into(transactions).insert(
            TransactionsCompanion.insert(
              id: newId(),
              ledgerId: targetLedgerId,
              type: type,
              amountMinor: amountMinor,
              currency: currency,
              accountId: accountId,
              categoryId: Value(categoryId),
              note: Value(note ?? pending.note),
              happenAt: pending.happenAt ?? ts,
              source: Value(source),
              tags: Value(encodeTxnTags(tags)),
              pendingId: Value(pending.id),
              includeInStat: Value(includeInStat),
              includeInBudget: Value(includeInBudget),
              createdAt: ts,
              updatedAt: ts,
            ),
          );
        } catch (e) {
          // Unique idx_transactions_pending_id: Native already inserted.
          final raced = await (select(transactions)
                ..where((t) => t.pendingId.equals(pendingId)))
              .get();
          if (raced.isEmpty) rethrow;
        }
      }
      final claimed = await (update(pendingCaptures)
            ..where(
              (t) => t.id.equals(pendingId) & t.status.equals('pending'),
            ))
          .write(
        PendingCapturesCompanion(
          status: const Value('confirmed'),
          amountMinor: Value(amountMinor),
          currency: Value(currency),
          note: Value(note ?? pending.note),
          suggestedCategoryId: Value(categoryId),
          suggestedAccountId: Value(accountId),
          updatedAt: Value(ts),
        ),
      );
      if (claimed > 0) {
        await _retireDedupeKey(pending.id, pending.dedupeKey);
      }
      final m = merchantForRule?.trim();
      if (m != null && m.isNotEmpty && claimed > 0) {
        final key = m.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        await upsertMerchantRule(
          ledgerId: pending.ledgerId,
          merchantKey: key,
          categoryId: categoryId,
          accountId: accountId,
        );
      }
    });
  }

  Future<int> countPendingCaptures(String ledgerId) async {
    final q = selectOnly(pendingCaptures)
      ..addColumns([pendingCaptures.id.count()])
      ..where(
        pendingCaptures.ledgerId.equals(ledgerId) &
            pendingCaptures.status.equals('pending'),
      );
    final rows = await q.get();
    if (rows.isEmpty) return 0;
    return rows.first.read(pendingCaptures.id.count()) ?? 0;
  }

  /// Deletes all pending (unconfirmed) captures for [ledgerId].
  /// Confirmed / ignored rows are kept. Returns deleted count.
  Future<int> clearPendingCaptures(String ledgerId) async {
    final rows = await (select(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.status.equals('pending'),
          ))
        .get();
    if (rows.isEmpty) return 0;
    await (delete(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.status.equals('pending'),
          ))
        .go();
    return rows.length;
  }

  Future<void> ignorePendingCapture(String pendingId) async {
    final pending = await (select(pendingCaptures)
          ..where((t) => t.id.equals(pendingId)))
        .getSingleOrNull();
    final ts = nowMs();
    await (update(pendingCaptures)..where((t) => t.id.equals(pendingId)))
        .write(
      PendingCapturesCompanion(
        status: const Value('ignored'),
        updatedAt: Value(ts),
      ),
    );
    if (pending != null) {
      await _retireDedupeKey(pending.id, pending.dedupeKey);
    }
  }

  /// Mark all status=pending captures as ignored. Returns affected count.
  Future<int> ignoreAllPendingCaptures(String ledgerId) async {
    final rows = await (select(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.status.equals('pending'),
          ))
        .get();
    if (rows.isEmpty) return 0;
    final ts = nowMs();
    await (update(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.status.equals('pending'),
          ))
        .write(
      PendingCapturesCompanion(
        status: const Value('ignored'),
        updatedAt: Value(ts),
      ),
    );
    for (final r in rows) {
      await _retireDedupeKey(r.id, r.dedupeKey);
    }
    return rows.length;
  }

  Future<void> unignorePendingCapture(String pendingId) async {
    final ts = nowMs();
    await (update(pendingCaptures)..where((t) => t.id.equals(pendingId)))
        .write(
      PendingCapturesCompanion(
        status: const Value('pending'),
        updatedAt: Value(ts),
      ),
    );
  }

  /// Hard-delete ignored captures for [ledgerId]. Returns deleted count.
  Future<int> clearIgnoredCaptures(String ledgerId) async {
    final rows = await (select(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.status.equals('ignored'),
          ))
        .get();
    if (rows.isEmpty) return 0;
    await (delete(pendingCaptures)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.status.equals('ignored'),
          ))
        .go();
    return rows.length;
  }

  Stream<int> watchIgnoredCount(String ledgerId) {
    final q = selectOnly(pendingCaptures)
      ..addColumns([pendingCaptures.id.count()])
      ..where(
        pendingCaptures.ledgerId.equals(ledgerId) &
            pendingCaptures.status.equals('ignored'),
      );
    return q.watch().map((rows) {
      if (rows.isEmpty) return 0;
      return rows.first.read(pendingCaptures.id.count()) ?? 0;
    });
  }


  // --- P2 export dumps ---

  Future<List<Account>> loadAllAccounts(String ledgerId) {
    return (select(accounts)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<List<Category>> loadAllCategories(String ledgerId) {
    return (select(categories)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.kind),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .get();
  }

  Future<List<Transaction>> loadTransactionsForExport(
    String ledgerId, {
    bool includeDeleted = false,
  }) {
    return (select(transactions)
          ..where((t) {
            final base = t.ledgerId.equals(ledgerId);
            if (includeDeleted) return base;
            return base & t.deletedAt.isNull();
          })
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)]))
        .get();
  }

  Future<List<PendingCapture>> loadPendingCapturesForExport(String ledgerId) {
    return (select(pendingCaptures)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<List<MerchantRule>> loadMerchantRules(String ledgerId) {
    return (select(merchantRules)
          ..where((t) => t.ledgerId.equals(ledgerId))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<List<FxRate>> loadAllFxRates() {
    return select(fxRates).get();
  }

  Future<FxBook> loadFxBook() async {
    final cached = _fxBookCache;
    if (cached != null) return cached;
    final rows = await loadAllFxRates();
    final book = FxBook([
      for (final r in rows)
        FxQuote(
          day: r.day,
          fromCcy: r.fromCcy,
          toCcy: r.toCcy,
          rate: r.rate,
        ),
    ]);
    _fxBookCache = book;
    return book;
  }

  /// Upsert one FX quote. [rate] means 1 [fromCcy] = [rate] [toCcy].
  Future<void> upsertFxRate({
    required String day,
    required String fromCcy,
    required String toCcy,
    required double rate,
    String? source,
  }) async {
    _dropFxBookCache();
    if (rate <= 0) {
      throw ArgumentError('汇率必须大于 0');
    }
    if (fromCcy == toCcy) {
      throw ArgumentError('转出与转入币种不能相同');
    }
    final ts = nowMs();
    await into(fxRates).insertOnConflictUpdate(
      FxRatesCompanion.insert(
        day: day,
        fromCcy: fromCcy,
        toCcy: toCcy,
        rate: rate,
        source: Value(source),
        updatedAt: ts,
      ),
    );
  }

  Future<void> deleteFxRate({
    required String day,
    required String fromCcy,
    required String toCcy,
  }) async {
    _dropFxBookCache();
    await (delete(fxRates)
          ..where(
            (t) =>
                t.day.equals(day) &
                t.fromCcy.equals(fromCcy) &
                t.toCcy.equals(toCcy),
          ))
        .go();
  }

  Stream<List<FxRate>> watchFxRates() {
    return (select(fxRates)
          ..orderBy([
            (t) => OrderingTerm.desc(t.day),
            (t) => OrderingTerm.asc(t.fromCcy),
            (t) => OrderingTerm.asc(t.toCcy),
          ]))
        .watch();
  }

  int _sqlInt(QueryRow row, String name) {
    final v = row.data[name];
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    if (v is num) return v.toInt();
    return 0;
  }

  /// Base-currency SUM(amount) grouped by [type]. Foreign rows are not included.
  Future<Map<String, int>> _sumByType({
    required String ledgerId,
    required String currency,
    int? startMs,
    int? endMs,
    bool statOnly = false,
    bool budgetOnly = false,
    String? type,
    bool expenseSide = false,
  }) async {
    final where = <String>[
      'ledger_id = ?',
      'deleted_at IS NULL',
      'currency = ?',
    ];
    final vars = <Variable<Object>>[
      Variable<String>(ledgerId),
      Variable<String>(currency),
    ];
    if (statOnly) where.add('include_in_stat = 1');
    if (budgetOnly) where.add('include_in_budget = 1');
    if (startMs != null) {
      where.add('happen_at >= ?');
      vars.add(Variable<int>(startMs));
    }
    if (endMs != null) {
      where.add('happen_at < ?');
      vars.add(Variable<int>(endMs));
    }
    if (type != null) {
      where.add('type = ?');
      vars.add(Variable<String>(type));
    } else if (expenseSide) {
      where.add("type = 'out'");
    }
    final rows = await customSelect(
      'SELECT type, SUM(amount_minor) AS total FROM transactions '
      'WHERE ${where.join(' AND ')} GROUP BY type',
      variables: vars,
      readsFrom: {transactions},
    ).get();
    return {for (final r in rows) r.read<String>('type'): _sqlInt(r, 'total')};
  }

  /// Non-base rows needed for happen-day FX. Base currency stays in SQL.
  Future<List<({String type, String currency, int amount, int happenAt, String? categoryId, String? accountId})>>
      _foreignStatRows({
    required String ledgerId,
    required String baseCurrency,
    int? startMs,
    int? endMs,
    bool statOnly = false,
    bool budgetOnly = false,
    String? type,
    bool expenseSide = false,
    bool skipTransfer = false,
  }) async {
    final where = <String>[
      'ledger_id = ?',
      'deleted_at IS NULL',
      'currency != ?',
    ];
    final vars = <Variable<Object>>[
      Variable<String>(ledgerId),
      Variable<String>(baseCurrency),
    ];
    if (statOnly) where.add('include_in_stat = 1');
    if (budgetOnly) where.add('include_in_budget = 1');
    if (startMs != null) {
      where.add('happen_at >= ?');
      vars.add(Variable<int>(startMs));
    }
    if (endMs != null) {
      where.add('happen_at < ?');
      vars.add(Variable<int>(endMs));
    }
    if (type != null) {
      where.add('type = ?');
      vars.add(Variable<String>(type));
    } else if (expenseSide) {
      where.add("type = 'out'");
    }
    if (skipTransfer) where.add("type != 'transfer'");
    final rows = await customSelect(
      'SELECT type, currency, amount_minor, happen_at, category_id, account_id '
      'FROM transactions WHERE ${where.join(' AND ')}',
      variables: vars,
      readsFrom: {transactions},
    ).get();
    return [
      for (final r in rows)
        (
          type: r.read<String>('type'),
          currency: r.read<String>('currency'),
          amount: _sqlInt(r, 'amount_minor'),
          happenAt: _sqlInt(r, 'happen_at'),
          categoryId: r.readNullable<String>('category_id'),
          accountId: r.readNullable<String>('account_id'),
        ),
    ];
  }

  Future<int> _countTxns({
    required String ledgerId,
    int? startMs,
    int? endMs,
    bool statOnly = false,
    bool budgetOnly = false,
  }) async {
    final where = <String>[
      'ledger_id = ?',
      'deleted_at IS NULL',
      'parent_id IS NULL',
    ];
    final vars = <Variable<Object>>[Variable<String>(ledgerId)];
    if (statOnly) where.add('include_in_stat = 1');
    if (budgetOnly) where.add('include_in_budget = 1');
    if (startMs != null) {
      where.add('happen_at >= ?');
      vars.add(Variable<int>(startMs));
    }
    if (endMs != null) {
      where.add('happen_at < ?');
      vars.add(Variable<int>(endMs));
    }
    final rows = await customSelect(
      'SELECT COUNT(*) AS c FROM transactions WHERE ${where.join(' AND ')}',
      variables: vars,
      readsFrom: {transactions},
    ).get();
    if (rows.isEmpty) return 0;
    return _sqlInt(rows.first, 'c');
  }

  Future<Map<String, int>> _sumByCategory({
    required String ledgerId,
    required String currency,
    required String type,
    required int startMs,
    required int endMs,
  }) async {
    final rows = await customSelect(
      '''
      SELECT COALESCE(category_id, '_none') AS cid, SUM(amount_minor) AS total
      FROM transactions
      WHERE ledger_id = ? AND deleted_at IS NULL
        AND include_in_stat = 1
        AND currency = ? AND type = ?
        AND happen_at >= ? AND happen_at < ?
      GROUP BY cid
      ''',
      variables: [
        Variable<String>(ledgerId),
        Variable<String>(currency),
        Variable<String>(type),
        Variable<int>(startMs),
        Variable<int>(endMs),
      ],
      readsFrom: {transactions},
    ).get();
    return {for (final r in rows) r.read<String>('cid'): _sqlInt(r, 'total')};
  }

  Future<Map<int, int>> _sumByLocalDay({
    required String ledgerId,
    required String currency,
    required String kind,
    required int startMs,
    required int endMs,
    required int offsetMs,
  }) async {
    final rows = await customSelect(
      '''
      SELECT CAST((happen_at + ?) / 86400000 AS INTEGER) AS bucket,
             SUM(amount_minor) AS total
      FROM transactions
      WHERE ledger_id = ? AND deleted_at IS NULL
        AND include_in_stat = 1
        AND currency = ? AND type = ?
        AND happen_at >= ? AND happen_at < ?
      GROUP BY bucket
      ''',
      variables: [
        Variable<int>(offsetMs),
        Variable<String>(ledgerId),
        Variable<String>(currency),
        Variable<String>(kind),
        Variable<int>(startMs),
        Variable<int>(endMs),
      ],
      readsFrom: {transactions},
    ).get();
    return {for (final r in rows) _sqlInt(r, 'bucket'): _sqlInt(r, 'total')};
  }

  DateTime _localDayFromBucket(int bucket) {
    final utc = DateTime.fromMillisecondsSinceEpoch(
      bucket * 86400000,
      isUtc: true,
    );
    return DateTime(utc.year, utc.month, utc.day);
  }

  /// Income/expense in [baseCurrency], converting foreign txns by happen-day FX.
  /// Unconvertible foreign amounts stay in [BaseRangeSummary.unconverted].
  Future<BaseRangeSummary> rangeSummaryInBase(
    String ledgerId,
    int startMs,
    int endMs,
    String baseCurrency,
  ) async {
    final sums = await _sumByType(
      ledgerId: ledgerId,
      currency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
    );
    final foreign = await _foreignStatRows(
      ledgerId: ledgerId,
      baseCurrency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
    );
    final book = foreign.isEmpty ? null : await loadFxBook();
    var income = sums['in'] ?? 0;
    var expense = sums['out'] ?? 0;
    var converted = 0;
    if ((sums['in'] ?? 0) != 0 ||
        (sums['out'] ?? 0) != 0 ||
        sums.isNotEmpty) {
      final baseCount = await customSelect(
        '''
        SELECT COUNT(*) AS c FROM transactions
        WHERE ledger_id = ? AND deleted_at IS NULL
          AND include_in_stat = 1
          AND currency = ? AND type IN ('in','out')
          AND happen_at >= ? AND happen_at < ?
        ''',
        variables: [
          Variable<String>(ledgerId),
          Variable<String>(baseCurrency),
          Variable<int>(startMs),
          Variable<int>(endMs),
        ],
        readsFrom: {transactions},
      ).get();
      converted = baseCount.isEmpty ? 0 : _sqlInt(baseCount.first, 'c');
    }
    var unconverted = 0;
    final leftover = <String, ({int income, int expense})>{};
    for (final r in foreign) {
      if (r.type != 'in' && r.type != 'out') continue;
      final asBase = book!.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amount,
        onDay: FxBook.dayFromHappenAtMs(r.happenAt),
      );
      if (asBase == null) {
        unconverted += 1;
        final cur = leftover[r.currency] ?? (income: 0, expense: 0);
        if (r.type == 'in') {
          leftover[r.currency] =
              (income: cur.income + r.amount, expense: cur.expense);
        } else {
          leftover[r.currency] =
              (income: cur.income, expense: cur.expense + r.amount);
        }
        continue;
      }
      converted += 1;
      if (r.type == 'in') {
        income += asBase;
      } else {
        expense += asBase;
      }
    }

    return BaseRangeSummary(
      incomeMinor: income,
      expenseMinor: expense,
      unconverted: leftover,
      convertedCount: converted,
      unconvertedCount: unconverted,
    );
  }

  /// 统计页「汇总」：范围内的笔数（含转账）+ 收入 / 支出 / 结余。
  Future<StatsTotals> statsTotalsInBase(
    String ledgerId,
    int startMs,
    int endMs,
    String baseCurrency,
  ) async {
    final count = await _countTxns(
      ledgerId: ledgerId,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
    );
    final sums = await _sumByType(
      ledgerId: ledgerId,
      currency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
    );
    final foreign = await _foreignStatRows(
      ledgerId: ledgerId,
      baseCurrency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
    );
    final book = foreign.isEmpty ? null : await loadFxBook();
    var income = sums['in'] ?? 0;
    var expense = sums['out'] ?? 0;
    for (final r in foreign) {
      if (r.type != 'in' && r.type != 'out') continue;
      final asBase = book!.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amount,
        onDay: FxBook.dayFromHappenAtMs(r.happenAt),
      );
      if (asBase == null) continue;
      if (r.type == 'in') {
        income += asBase;
      } else {
        expense += asBase;
      }
    }
    return StatsTotals(
      count: count,
      incomeMinor: income,
      expenseMinor: expense,
    );
  }

  /// All-time income / expense in [baseCurrency] (deleted + excluded skipped),
  /// for the 总收入 / 总支出 line on the home summary card.
  Future<({int incomeMinor, int expenseMinor})> lifetimeTotalsInBase(
    String ledgerId,
    String baseCurrency,
  ) async {
    final sums = await _sumByType(
      ledgerId: ledgerId,
      currency: baseCurrency,
      statOnly: true,
    );
    final foreign = await _foreignStatRows(
      ledgerId: ledgerId,
      baseCurrency: baseCurrency,
      statOnly: true,
    );
    final book = foreign.isEmpty ? null : await loadFxBook();
    var income = sums['in'] ?? 0;
    var expense = sums['out'] ?? 0;
    for (final r in foreign) {
      if (r.type != 'in' && r.type != 'out') continue;
      final asBase = book!.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amount,
        onDay: FxBook.dayFromHappenAtMs(r.happenAt),
      );
      if (asBase == null) continue;
      if (r.type == 'in') {
        income += asBase;
      } else {
        expense += asBase;
      }
    }
    return (incomeMinor: income, expenseMinor: expense);
  }

  /// 统计页环形图：按 `kind` 汇总分类。
  ///
  /// - `out` / `in`：只取支出 / 收入分类；
  /// - `all`：支出与收入**分开**返回（环形图里两类各自成段，颜色跟随方向）。
  Future<({List<({String categoryId, String name, int totalMinor})> expenses,
      List<({String categoryId, String name, int totalMinor})> incomes})>
      statsAllCategoriesInBase(
    String ledgerId,
    int startMs,
    int endMs,
    String baseCurrency,
  ) async {
    final out = await categoryBreakdownInBase(
      ledgerId,
      startMs,
      endMs,
      kind: 'out',
      baseCurrency: baseCurrency,
    );
    final inc = await categoryBreakdownInBase(
      ledgerId,
      startMs,
      endMs,
      kind: 'in',
      baseCurrency: baseCurrency,
    );
    return (expenses: out, incomes: inc);
  }

  /// 统计页「资产账户」卡：按资产账户汇总收入 / 支出（**不含转账**）。
  ///
  /// 收入记到 `accountId`，支出也记到 `accountId`（付款资产账户）；退款冲减支出。
  /// 资产账户名来自资产账户表，已归档资产账户也保留（有历史数据就会显示）。
  Future<List<StatsAccountRow>> statsByAccountInBase(
    String ledgerId,
    int startMs,
    int endMs,
    String baseCurrency,
  ) async {
    final baseRows = await customSelect(
      '''
      SELECT account_id, type, SUM(amount_minor) AS total
      FROM transactions
      WHERE ledger_id = ? AND deleted_at IS NULL
        AND include_in_stat = 1
        AND currency = ? AND type != 'transfer'
        AND happen_at >= ? AND happen_at < ?
      GROUP BY account_id, type
      ''',
      variables: [
        Variable<String>(ledgerId),
        Variable<String>(baseCurrency),
        Variable<int>(startMs),
        Variable<int>(endMs),
      ],
      readsFrom: {transactions},
    ).get();
    final foreign = await _foreignStatRows(
      ledgerId: ledgerId,
      baseCurrency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
      skipTransfer: true,
    );
    final accounts = await loadAccountsIncludingArchived(ledgerId);
    final nameById = {for (final a in accounts) a.id: a.name};
    final book = foreign.isEmpty ? null : await loadFxBook();
    final income = <String, int>{};
    final expense = <String, int>{};
    for (final r in baseRows) {
      final id = r.read<String>('account_id');
      final type = r.read<String>('type');
      final total = _sqlInt(r, 'total');
      if (type == 'in') {
        income[id] = (income[id] ?? 0) + total;
      } else if (type == 'out') {
        expense[id] = (expense[id] ?? 0) + total;
      }
    }
    for (final r in foreign) {
      if (r.type != 'in' && r.type != 'out') continue;
      final id = r.accountId;
      if (id == null) continue;
      final asBase = book!.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amount,
        onDay: FxBook.dayFromHappenAtMs(r.happenAt),
      );
      if (asBase == null) continue;
      if (r.type == 'in') {
        income[id] = (income[id] ?? 0) + asBase;
      } else {
        expense[id] = (expense[id] ?? 0) + asBase;
      }
    }
    final ids = {...income.keys, ...expense.keys};
    return [
      for (final id in ids)
        StatsAccountRow(
          accountId: id,
          name: nameById[id] ?? id,
          incomeMinor: income[id] ?? 0,
          expenseMinor: expense[id] ?? 0,
        ),
    ]..sort((a, b) {
        final byAbs = (b.incomeMinor.abs() + b.expenseMinor.abs())
            .compareTo(a.incomeMinor.abs() + a.expenseMinor.abs());
        if (byAbs != 0) return byAbs;
        return a.name.compareTo(b.name);
      });
  }

  /// Category totals in [baseCurrency]; skips txns that cannot be converted.
  Future<List<({String categoryId, String name, int totalMinor})>>
      categoryBreakdownInBase(
    String ledgerId,
    int startMs,
    int endMs, {
    required String kind,
    required String baseCurrency,
  }) async {
    final totals = await _sumByCategory(
      ledgerId: ledgerId,
      currency: baseCurrency,
      type: kind,
      startMs: startMs,
      endMs: endMs,
    );
    final foreign = await _foreignStatRows(
      ledgerId: ledgerId,
      baseCurrency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
      type: kind,
    );
    final cats = await loadCategories(ledgerId, kind);
    final nameById = {for (final c in cats) c.id: c.name};
    final book = foreign.isEmpty ? null : await loadFxBook();
    for (final r in foreign) {
      final asBase = book!.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amount,
        onDay: FxBook.dayFromHappenAtMs(r.happenAt),
      );
      if (asBase == null) continue;
      final cid = r.categoryId ?? '_none';
      totals[cid] = (totals[cid] ?? 0) + asBase;
    }

    final list = totals.entries
        .map(
          (e) => (
            categoryId: e.key,
            name: nameById[e.key] ?? '\u672a\u5206\u7c7b',
            totalMinor: e.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
    return list;
  }

  /// Active-account net worth in [baseCurrency] using today's (or prior) FX.
  Future<BaseNetWorth> netWorthInBase(
    String ledgerId,
    String baseCurrency, {
    String? onDay,
  }) async {
    final accounts = await loadActiveAccounts(ledgerId);
    final balances = await accountBalances(ledgerId);
    final book = await loadFxBook();
    final day = onDay ?? FxBook.todayLocal();
    var total = 0;
    var convertedAccounts = 0;
    var unconvertedAccounts = 0;
    final leftover = <String, int>{};

    for (final a in accounts) {
      final bal = balances[a.id] ?? a.openingBalanceMinor;
      final asBase = book.convertMinor(
        fromCcy: a.currency,
        toCcy: baseCurrency,
        amountMinor: bal,
        onDay: day,
      );
      if (asBase == null) {
        unconvertedAccounts += 1;
        leftover[a.currency] = (leftover[a.currency] ?? 0) + bal;
      } else {
        convertedAccounts += 1;
        total += asBase;
      }
    }

    return BaseNetWorth(
      totalMinor: total,
      unconvertedByCcy: leftover,
      convertedAccountCount: convertedAccounts,
      unconvertedAccountCount: unconvertedAccounts,
    );
  }

  /// Per-local-day totals in [baseCurrency] for [kind] (`out` / `in`).
  /// Days in [startMs, endMs) with no convertible txns are filled with 0.
  Future<List<({DateTime dayLocal, int totalMinor})>> dailySeriesInBase(
    String ledgerId,
    int startMs,
    int endMs, {
    required String kind,
    required String baseCurrency,
  }) async {
    // China has no DST; the device offset is the local calendar day.
    final offsetMs = DateTime.now().timeZoneOffset.inMilliseconds;
    final buckets = await _sumByLocalDay(
      ledgerId: ledgerId,
      currency: baseCurrency,
      kind: kind,
      startMs: startMs,
      endMs: endMs,
      offsetMs: offsetMs,
    );
    final foreign = await _foreignStatRows(
      ledgerId: ledgerId,
      baseCurrency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      statOnly: true,
      type: kind,
    );
    final book = foreign.isEmpty ? null : await loadFxBook();
    final byDay = <String, int>{};
    for (final e in buckets.entries) {
      final day = _localDayFromBucket(e.key);
      byDay[FxBook.formatDay(day)] = e.value;
    }
    for (final r in foreign) {
      final day = FxBook.dayFromHappenAtMs(r.happenAt);
      final asBase = book!.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amount,
        onDay: day,
      );
      if (asBase == null) continue;
      byDay[day] = (byDay[day] ?? 0) + asBase;
    }

    final startLocal =
        DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true).toLocal();
    final endLocal =
        DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true).toLocal();
    var cursor = DateTime(startLocal.year, startLocal.month, startLocal.day);
    final endDay = DateTime(endLocal.year, endLocal.month, endLocal.day);
    final out = <({DateTime dayLocal, int totalMinor})>[];
    while (cursor.isBefore(endDay)) {
      final key = FxBook.formatDay(cursor);
      out.add((dayLocal: cursor, totalMinor: byDay[key] ?? 0));
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }

  /// Stats drill-down: range txns for one category (or uncategorized `_none`).
  Stream<List<Transaction>> watchCategoryTransactionsInRange(
    String ledgerId,
    int startMs,
    int endMs, {
    required String kind,
    required String categoryId,
    int limit = 500,
  }) {
    return (select(transactions)
          ..where((t) {
            final base = t.ledgerId.equals(ledgerId) &
                t.deletedAt.isNull() &
                t.includeInStat.equals(1) &
                t.type.equals(kind) &
                t.happenAt.isBiggerOrEqualValue(startMs) &
                t.happenAt.isSmallerThanValue(endMs);
            if (categoryId == '_none') {
              return base & t.categoryId.isNull();
            }
            return base & t.categoryId.equals(categoryId);
          })
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(limit))
        .watch();
  }


  // --- Budgets (P3 MVP) ---

  Stream<List<Budget>> watchBudgetsForMonth(String ledgerId, String yearMonth) {
    return (select(budgets)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) & t.yearMonth.equals(yearMonth),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.categoryId)]))
        .watch();
  }

  Future<List<Budget>> loadBudgetsForMonth(
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

  Future<void> upsertBudget({
    required String ledgerId,
    required String yearMonth,
    required String categoryId,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) {
      await deleteBudgetByKey(
        ledgerId: ledgerId,
        yearMonth: yearMonth,
        categoryId: categoryId,
      );
      return;
    }
    final existing = await (select(budgets)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.yearMonth.equals(yearMonth) &
                t.categoryId.equals(categoryId),
          ))
        .getSingleOrNull();
    final ts = nowMs();
    if (existing == null) {
      await into(budgets).insert(
        BudgetsCompanion.insert(
          id: newId(),
          ledgerId: ledgerId,
          yearMonth: yearMonth,
          categoryId: Value(categoryId),
          amountMinor: amountMinor,
          createdAt: ts,
          updatedAt: ts,
        ),
      );
    } else {
      await (update(budgets)..where((t) => t.id.equals(existing.id))).write(
        BudgetsCompanion(
          amountMinor: Value(amountMinor),
          updatedAt: Value(ts),
        ),
      );
    }
  }

  Future<void> deleteBudgetByKey({
    required String ledgerId,
    required String yearMonth,
    required String categoryId,
  }) async {
    await (delete(budgets)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.yearMonth.equals(yearMonth) &
                t.categoryId.equals(categoryId),
          ))
        .go();
  }

  Future<void> deleteBudget(String id) async {
    await (delete(budgets)..where((t) => t.id.equals(id))).go();
  }

  /// Spent vs limits for [yearMonth] (`yyyy-MM`), amounts in [baseCurrency].
  /// Uses `include_in_budget=1` expense txns; FX same as stats.
  Future<MonthBudgetProgress> monthBudgetProgress(
    String ledgerId,
    String yearMonth,
    String baseCurrency,
  ) async {
    final parts = yearMonth.split('-');
    if (parts.length != 2) {
      throw ArgumentError('月份格式须为 yyyy-MM');
    }
    final y = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final startLocal = DateTime(y, m, 1);
    final endLocal = DateTime(y, m + 1, 1);
    final startMs = startLocal.toUtc().millisecondsSinceEpoch;
    final endMs = endLocal.toUtc().millisecondsSinceEpoch;

    final budgetRows = await loadBudgetsForMonth(ledgerId, yearMonth);
    int? totalLimit;
    final catLimits = <String, int>{};
    for (final b in budgetRows) {
      if (b.categoryId.isEmpty) {
        totalLimit = b.amountMinor;
      } else {
        catLimits[b.categoryId] = b.amountMinor;
      }
    }

    final baseCats = await customSelect(
      '''
      SELECT COALESCE(category_id, '') AS cid, type, SUM(amount_minor) AS total
      FROM transactions
      WHERE ledger_id = ? AND deleted_at IS NULL
        AND include_in_budget = 1
        AND currency = ? AND type = 'out'
        AND happen_at >= ? AND happen_at < ?
      GROUP BY cid, type
      ''',
      variables: [
        Variable<String>(ledgerId),
        Variable<String>(baseCurrency),
        Variable<int>(startMs),
        Variable<int>(endMs),
      ],
      readsFrom: {transactions},
    ).get();
    final foreign = await _foreignStatRows(
      ledgerId: ledgerId,
      baseCurrency: baseCurrency,
      startMs: startMs,
      endMs: endMs,
      budgetOnly: true,
      expenseSide: true,
    );
    final book = foreign.isEmpty ? null : await loadFxBook();
    var spentTotal = 0;
    final spentByCat = <String, int>{};
    final leftover = <String, int>{};
    for (final r in baseCats) {
      final total = _sqlInt(r, 'total');
      spentTotal += total;
      final cid = r.read<String>('cid');
      if (cid.isNotEmpty) {
        spentByCat[cid] = (spentByCat[cid] ?? 0) + total;
      }
    }
    for (final r in foreign) {
      if (r.type != 'out') continue;
      final asBase = book!.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amount,
        onDay: FxBook.dayFromHappenAtMs(r.happenAt),
      );
      if (asBase == null) {
        leftover[r.currency] = (leftover[r.currency] ?? 0) + r.amount;
        continue;
      }
      spentTotal += asBase;
      final cid = r.categoryId;
      if (cid != null && cid.isNotEmpty) {
        spentByCat[cid] = (spentByCat[cid] ?? 0) + asBase;
      }
    }

    final cats = await loadCategories(ledgerId, 'out');
    final nameById = {for (final c in cats) c.id: c.name};
    final catProgress = <CategoryBudgetProgress>[];
    for (final e in catLimits.entries) {
      catProgress.add(
        CategoryBudgetProgress(
          categoryId: e.key,
          name: nameById[e.key] ?? '\u672a\u77e5\u5206\u7c7b',
          limitMinor: e.value,
          spentMinor: spentByCat[e.key] ?? 0,
        ),
      );
    }
    catProgress.sort((a, b) {
      final ra = a.limitMinor == 0 ? 0.0 : a.spentMinor / a.limitMinor;
      final rb = b.limitMinor == 0 ? 0.0 : b.spentMinor / b.limitMinor;
      final c = rb.compareTo(ra);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });

    return MonthBudgetProgress(
      yearMonth: yearMonth,
      baseCurrency: baseCurrency,
      totalLimitMinor: totalLimit,
      spentTotalMinor: spentTotal,
      categories: catProgress,
      unconvertedByCcy: leftover,
    );
  }



  // --- P3 import / restore ---

  /// Replace one ledger's rows (+ optional FX + budgets), insert backup maps, merge settings.
  /// Other ledgers are left intact. [replaceFxRates] false keeps existing FX (Excel path).
  /// [settingsSkipKeys] are left unchanged (e.g. app_lock*). Always sets current_ledger_id.

  /// Fold legacy `merchant` into `note` for import/restore maps (T1).
  static Map<String, dynamic> _normalizeTxnImportMap(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    final composed = composeNote(
      merchant: out['merchant']?.toString(),
      note: out['note']?.toString(),
    );
    out.remove('merchant');
    out['note'] = composed;
    // Excel / older JSON may use snake_case; Drift fromJson expects camelCase.
    if (out.containsKey('parent_id') && !out.containsKey('parentId')) {
      final v = out['parent_id'];
      out['parentId'] = (v == null || '$v'.isEmpty) ? null : '$v';
    }
    if (out.containsKey('sub_type_id') && !out.containsKey('subTypeId')) {
      final v = out['sub_type_id'];
      out['subTypeId'] = (v == null || '$v'.isEmpty) ? null : '$v';
    }
    out.putIfAbsent('parentId', () => null);
    out.putIfAbsent('subTypeId', () => null);
    return out;
  }

  static Map<String, dynamic> _normalizePendingImportMap(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    final composed = composeNote(
      merchant: out['merchant']?.toString(),
      note: out['note']?.toString(),
    );
    out.remove('merchant');
    out['note'] = composed;
    return out;
  }

  /// 合并追加到 [targetLedgerId]（默认当前账本）：不 wipe；
  /// 仅插入本地缺失 id 的账户 / 分类 / 流水等；不切换当前账本。
  Future<RestoreImportStats> mergeFromImportBundle({
    required Map<String, dynamic> ledgerMap,
    required List<Map<String, dynamic>> accountMaps,
    List<Map<String, dynamic>> assetTypeMaps = const [],
    required List<Map<String, dynamic>> categoryMaps,
    List<Map<String, dynamic>> subTransactionTypeMaps = const [],
    required List<Map<String, dynamic>> transactionMaps,
    required List<Map<String, dynamic>> merchantRuleMaps,
    required List<Map<String, dynamic>> pendingCaptureMaps,
    required List<Map<String, dynamic>> fxRateMaps,
    required List<Map<String, dynamic>> budgetMaps,
    required Map<String, String> settingsMap,
    required Set<String> settingsSkipKeys,
    bool mergeFxRates = false,
    String? targetLedgerId,
  }) async {
    // 校验备份账本字段；实际写入目标是当前账本，不用备份里的 ledger id。
    Ledger.fromJson(ledgerMap);
    final currentId = await currentLedgerId();
    // 合进当前账本，避免写到备份里的另一本并把视角切走（看起来像「原记录没了」）。
    final lid = (targetLedgerId ?? currentId)?.trim();
    if (lid == null || lid.isEmpty) {
      throw StateError('没有当前记账本，无法合并追加');
    }
    final targetLedger =
        await (select(ledgers)..where((t) => t.id.equals(lid))).getSingleOrNull();
    if (targetLedger == null) {
      throw StateError('当前记账本不存在，无法合并追加');
    }

    final accountRows = [
      for (final m in accountMaps) Account.fromJson(m).copyWith(ledgerId: lid),
    ];
    final categoryRows = _sortCategoriesForInsert([
      for (final m in categoryMaps)
        Category.fromJson(m).copyWith(ledgerId: lid),
    ]);
    final txnRows = [
      for (final m in transactionMaps)
        Transaction.fromJson(_normalizeTxnImportMap(m)).copyWith(ledgerId: lid),
    ];
    final ruleRows = [
      for (final m in merchantRuleMaps)
        MerchantRule.fromJson(m).copyWith(ledgerId: lid),
    ];
    final pendingRows = [
      for (final m in pendingCaptureMaps)
        PendingCapture.fromJson(_normalizePendingImportMap(m))
            .copyWith(ledgerId: lid),
    ];
    final fxRows = [for (final m in fxRateMaps) FxRate.fromJson(m)];
    final budgetRows = [
      for (final m in budgetMaps) Budget.fromJson(m).copyWith(ledgerId: lid),
    ];

    var insertedAccounts = 0;
    var insertedCategories = 0;
    var insertedTxns = 0;
    var insertedRules = 0;
    var insertedPending = 0;
    var insertedFx = 0;
    var insertedBudgets = 0;
    const settingsWritten = 0;

    await transaction(() async {
      // 目标账本已存在；不改名、不 wipe、不切 current_ledger_id。

      for (final m in assetTypeMaps) {
        final name = '${m['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final existing = await (select(assetTypes)
              ..where((t) => t.ledgerId.equals(lid) & t.name.equals(name)))
            .get();
        if (existing.isNotEmpty) continue;
        final id = '${m['id'] ?? ''}'.trim().isEmpty ? newId() : '${m['id']}';
        final ts = nowMs();
        await into(assetTypes).insert(
          AssetTypesCompanion.insert(
            id: id,
            ledgerId: lid,
            name: name,
            icon: Value(m['icon']?.toString()),
            sortOrder: Value(
              m['sortOrder'] as int? ?? m['sort_order'] as int? ?? 99,
            ),
            archived: Value(m['archived'] as int? ?? 0),
            createdAt: m['createdAt'] as int? ?? ts,
            updatedAt: m['updatedAt'] as int? ?? ts,
          ),
        );
      }

      final existingAccIds = {
        for (final a in await (select(accounts)
              ..where((t) => t.ledgerId.equals(lid)))
            .get())
          a.id,
      };
      for (final a in accountRows) {
        if (existingAccIds.contains(a.id)) continue;
        final typeId = await resolveAssetTypeId(ledgerId: lid, raw: a.type);
        await into(accounts).insert(
          a.copyWith(type: typeId).toCompanion(true),
        );
        existingAccIds.add(a.id);
        insertedAccounts++;
      }

      final existingCatIds = {
        for (final c in await (select(categories)
              ..where((t) => t.ledgerId.equals(lid)))
            .get())
          c.id,
      };
      for (final c in categoryRows) {
        if (existingCatIds.contains(c.id)) continue;
        await into(categories).insert(c.toCompanion(true));
        existingCatIds.add(c.id);
        insertedCategories++;
      }

      final existingBudgetIds = {
        for (final b in await (select(budgets)
              ..where((t) => t.ledgerId.equals(lid)))
            .get())
          b.id,
      };
      for (final b in budgetRows) {
        if (existingBudgetIds.contains(b.id)) continue;
        await into(budgets).insert(b.toCompanion(true));
        existingBudgetIds.add(b.id);
        insertedBudgets++;
      }

      await upsertSubTransactionTypesFromImport(subTransactionTypeMaps);

      final existingTxnIds = {
        for (final t in await (select(transactions)
              ..where((t) => t.ledgerId.equals(lid)))
            .get())
          t.id,
      };
      final newTxns = [
        for (final t in txnRows)
          if (!existingTxnIds.contains(t.id)) t,
      ];
      if (newTxns.isNotEmpty) {
        await batch((b) {
          b.insertAll(
            transactions,
            [for (final t in newTxns) t.toCompanion(true)],
          );
        });
        insertedTxns = newTxns.length;
      }

      final existingRuleIds = {
        for (final r in await (select(merchantRules)
              ..where((t) => t.ledgerId.equals(lid)))
            .get())
          r.id,
      };
      for (final r in ruleRows) {
        if (existingRuleIds.contains(r.id)) continue;
        await into(merchantRules).insert(r.toCompanion(true));
        existingRuleIds.add(r.id);
        insertedRules++;
      }

      final existingPendingIds = {
        for (final p in await (select(pendingCaptures)
              ..where((t) => t.ledgerId.equals(lid)))
            .get())
          p.id,
      };
      for (final p in pendingRows) {
        if (existingPendingIds.contains(p.id)) continue;
        await into(pendingCaptures).insert(p.toCompanion(true));
        existingPendingIds.add(p.id);
        insertedPending++;
      }

      if (mergeFxRates) {
        final existingFxKeys = {
          for (final f in await select(fxRates).get())
            '${f.day}|${f.fromCcy}|${f.toCcy}',
        };
        for (final f in fxRows) {
          final key = '${f.day}|${f.fromCcy}|${f.toCcy}';
          if (existingFxKeys.contains(key)) continue;
          await into(fxRates).insert(f.toCompanion(true));
          existingFxKeys.add(key);
          insertedFx++;
        }
        if (insertedFx > 0) _dropFxBookCache();
      }

      // 合并：不写设置、不切换当前账本，避免本机偏好被备份冲掉。
    });

    return RestoreImportStats(
      ledgerId: targetLedger.id,
      ledgerName: targetLedger.name,
      accounts: insertedAccounts,
      categories: insertedCategories,
      transactions: insertedTxns,
      merchantRules: insertedRules,
      pendingCaptures: insertedPending,
      fxRates: insertedFx,
      budgets: insertedBudgets,
      settingsWritten: settingsWritten,
    );
  }

  Future<RestoreImportStats> restoreFromImportBundle({
    required Map<String, dynamic> ledgerMap,
    required List<Map<String, dynamic>> accountMaps,
    List<Map<String, dynamic>> assetTypeMaps = const [],
    required List<Map<String, dynamic>> categoryMaps,
    List<Map<String, dynamic>> subTransactionTypeMaps = const [],
    required List<Map<String, dynamic>> transactionMaps,
    required List<Map<String, dynamic>> merchantRuleMaps,
    required List<Map<String, dynamic>> pendingCaptureMaps,
    required List<Map<String, dynamic>> fxRateMaps,
    required List<Map<String, dynamic>> budgetMaps,
    required Map<String, String> settingsMap,
    required Set<String> settingsSkipKeys,
    bool replaceFxRates = true,
  }) async {
    final ledgerRow = Ledger.fromJson(ledgerMap);
    final lid = ledgerRow.id;
    // Force every child row onto the restored ledger (R1-3 / audit).
    final accountRows = [
      for (final m in accountMaps) Account.fromJson(m).copyWith(ledgerId: lid),
    ];
    final categoryRows = _sortCategoriesForInsert([
      for (final m in categoryMaps)
        Category.fromJson(m).copyWith(ledgerId: lid),
    ]);
    final txnRows = [
      for (final m in transactionMaps)
        Transaction.fromJson(_normalizeTxnImportMap(m)).copyWith(ledgerId: lid),
    ];
    final ruleRows = [
      for (final m in merchantRuleMaps)
        MerchantRule.fromJson(m).copyWith(ledgerId: lid),
    ];
    final pendingRows = [
      for (final m in pendingCaptureMaps)
        PendingCapture.fromJson(_normalizePendingImportMap(m))
            .copyWith(ledgerId: lid),
    ];
    final fxRows = [for (final m in fxRateMaps) FxRate.fromJson(m)];
    final budgetRows = [
      for (final m in budgetMaps) Budget.fromJson(m).copyWith(ledgerId: lid),
    ];

    var settingsWritten = 0;

    await transaction(() async {
      // Scoped wipe: only the ledger being restored (export is single-ledger).
      await (delete(transactions)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(pendingCaptures)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(merchantRules)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(budgets)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(categories)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(accounts)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(assetTypes)..where((t) => t.ledgerId.equals(lid))).go();
      await (delete(ledgers)..where((t) => t.id.equals(lid))).go();
      if (replaceFxRates) {
        _dropFxBookCache();
        await delete(fxRates).go();
      }

      await into(ledgers).insert(ledgerRow.toCompanion(true));
      await seedDefaultAssetTypes(lid);
      // Recreate custom asset types from backup (by name; keep exported ids when possible).
      for (final m in assetTypeMaps) {
        final name = '${m['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final existing = await (select(assetTypes)
              ..where((t) => t.ledgerId.equals(lid) & t.name.equals(name)))
            .get();
        if (existing.isNotEmpty) continue;
        final id = '${m['id'] ?? ''}'.trim().isEmpty ? newId() : '${m['id']}';
        final ts = nowMs();
        await into(assetTypes).insert(
          AssetTypesCompanion.insert(
            id: id,
            ledgerId: lid,
            name: name,
            icon: Value(m['icon']?.toString()),
            sortOrder: Value(m['sortOrder'] as int? ?? m['sort_order'] as int? ?? 99),
            archived: Value(m['archived'] as int? ?? 0),
            createdAt: m['createdAt'] as int? ?? ts,
            updatedAt: m['updatedAt'] as int? ?? ts,
          ),
        );
      }
      for (final a in accountRows) {
        final typeId = await resolveAssetTypeId(ledgerId: lid, raw: a.type);
        await into(accounts).insert(
          a.copyWith(type: typeId).toCompanion(true),
        );
      }
      final typeIds = {
        for (final t in await loadAssetTypes(lid, includeArchived: true)) t.id
      };
      final other = await resolveAssetTypeId(ledgerId: lid, raw: '其他');
      for (final a in await (select(accounts)
            ..where((t) => t.ledgerId.equals(lid)))
          .get()) {
        if (!typeIds.contains(a.type)) {
          await (update(accounts)..where((t) => t.id.equals(a.id))).write(
            AccountsCompanion(type: Value(other)),
          );
        }
      }
      for (final c in categoryRows) {
        await into(categories).insert(c.toCompanion(true));
      }
      for (final b in budgetRows) {
        await into(budgets).insert(b.toCompanion(true));
      }
      await upsertSubTransactionTypesFromImport(subTransactionTypeMaps);
      if (txnRows.isNotEmpty) {
        await batch((b) {
          b.insertAll(
            transactions,
            [for (final t in txnRows) t.toCompanion(true)],
          );
        });
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
      }

      for (final e in settingsMap.entries) {
        if (settingsSkipKeys.contains(e.key)) continue;
        if (e.key == 'current_ledger_id') continue;
        await setSetting(e.key, e.value);
        settingsWritten++;
      }
      await setSetting('current_ledger_id', ledgerRow.id);
      settingsWritten++;
    });

    return RestoreImportStats(
      ledgerId: ledgerRow.id,
      ledgerName: ledgerRow.name,
      accounts: accountRows.length,
      categories: categoryRows.length,
      transactions: txnRows.length,
      merchantRules: ruleRows.length,
      pendingCaptures: pendingRows.length,
      fxRates: replaceFxRates ? fxRows.length : 0,
      budgets: budgetRows.length,
      settingsWritten: settingsWritten,
    );
  }

  /// Parents (null parentId) first, then children; stable by sortOrder within tier.
  List<Category> _sortCategoriesForInsert(List<Category> rows) {
    final remaining = {for (final c in rows) c.id: c};
    final out = <Category>[];
    while (remaining.isNotEmpty) {
      final ready = remaining.values.where((c) {
        final p = c.parentId;
        return p == null || p.isEmpty || !remaining.containsKey(p);
      }).toList()
        ..sort((a, b) {
          final k = a.kind.compareTo(b.kind);
          if (k != 0) return k;
          return a.sortOrder.compareTo(b.sortOrder);
        });
      if (ready.isEmpty) {
        final rest = remaining.values.toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        out.addAll(rest);
        break;
      }
      for (final c in ready) {
        out.add(c);
        remaining.remove(c.id);
      }
    }
    return out;
  }

  Future<Map<String, String>> loadAllSettings() async {
    final rows = await select(appSettings).get();
    return {for (final r in rows) r.key: r.value};
  }

}


/// `yyyy-MM` for local [date] (defaults to now).
String budgetYearMonth([DateTime? date]) {
  final d = date ?? DateTime.now();
  final mm = d.month.toString().padLeft(2, '0');
  return '${d.year}-$mm';
}



class TxnListLookups {
  const TxnListLookups({
    required this.categoriesById,
    required this.accountsById,
  });

  final Map<String, Category> categoriesById;
  final Map<String, Account> accountsById;

  static const empty = TxnListLookups(
    categoriesById: {},
    accountsById: {},
  );
}

class CategoryBudgetProgress {
  const CategoryBudgetProgress({
    required this.categoryId,
    required this.name,
    required this.limitMinor,
    required this.spentMinor,
  });

  final String categoryId;
  final String name;
  final int limitMinor;
  final int spentMinor;

  double get ratio =>
      limitMinor <= 0 ? 0.0 : spentMinor / limitMinor;

  bool get over => spentMinor > limitMinor;
}

class MonthBudgetProgress {
  const MonthBudgetProgress({
    required this.yearMonth,
    required this.baseCurrency,
    required this.totalLimitMinor,
    required this.spentTotalMinor,
    required this.categories,
    this.unconvertedByCcy = const {},
  });

  final String yearMonth;
  final String baseCurrency;
  final int? totalLimitMinor;
  final int spentTotalMinor;
  final List<CategoryBudgetProgress> categories;

  /// Foreign amounts that could not be converted into [baseCurrency] (excluded from spent).
  final Map<String, int> unconvertedByCcy;

  bool get hasAnyBudget =>
      totalLimitMinor != null || categories.isNotEmpty;

  bool get hasUnconverted => unconvertedByCcy.isNotEmpty;
}


class RestoreImportStats {
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

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'centli.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
/// Normalised lookup key for note → category memory. Lowercase, whitespace
/// collapsed, punctuation stripped; null for empty / 1-char noise.
String? noteCategoryKey(String? note) {
  final raw = (note ?? '').trim().toLowerCase();
  if (raw.isEmpty) return null;
  final cleaned = raw
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[，。！？、；：,.!?;:"“”‘’（）()\[\]【】]'), '')
      .trim();
  if (cleaned.length < 2) return null;
  return cleaned;
}

/// Remembered starting state for the manual 记一笔 panel.
class LastBookkeepingChoice {
  const LastBookkeepingChoice({
    this.type = 'out',
    this.accountId,
    this.categoryId,
    this.categoryByType = const {},
  });

  /// `out` / `in` / `transfer`.
  final String type;
  final String? accountId;
  final String? categoryId;

  /// categoryId per type (`out` / `in`), so switching方向 keeps its own choice.
  final Map<String, String> categoryByType;

  factory LastBookkeepingChoice.fromJson(Map<String, dynamic> j) {
    final byType = <String, String>{};
    final raw = j['categoryByType'];
    if (raw is Map) {
      for (final e in raw.entries) {
        if (e.key is String && e.value is String) {
          byType['${e.key}'] = '${e.value}';
        }
      }
    }
    return LastBookkeepingChoice(
      type: (j['type'] as String?) ?? 'out',
      accountId: j['accountId'] as String?,
      categoryId: j['categoryId'] as String?,
      categoryByType: byType,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'accountId': accountId,
        'categoryId': categoryId,
        'categoryByType': categoryByType,
      };

  LastBookkeepingChoice copyWith({
    String? type,
    String? accountId,
    String? categoryId,
    Map<String, String>? categoryByType,
  }) {
    return LastBookkeepingChoice(
      type: type ?? this.type,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      categoryByType: categoryByType ?? this.categoryByType,
    );
  }
}

/// 统计页汇总行（本币，转账不计入收入 / 支出，但计入 [count]）。
class StatsTotals {
  const StatsTotals({
    required this.count,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final int count;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}

/// 资产账户维度汇总（转账完全排除）。
class StatsAccountRow {
  const StatsAccountRow({
    required this.accountId,
    required this.name,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final String accountId;
  final String name;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}

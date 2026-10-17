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
import 'tables/transactions.dart';
import 'txn_tags.dart';
import '../txn_templates.dart';

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
  ],
)
class CentliDatabase extends _$CentliDatabase {
  CentliDatabase() : super(_openConnection());

  CentliDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 10;

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
            await m.addColumn(transactions, transactions.member);
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
            await m.alterTable(TableMigration(transactions));
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
          await _ensureQueryIndexes();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _ensureQueryIndexes();
        },
      );


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
      throw StateError('同账本已有同名分类');
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
    if (clash.isNotEmpty) throw StateError('同账本已有同名分类');
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
      throw StateError('有 ${inUse.length} 个账户在用，无法删除（可先归档）');
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
        key: 'hide_amount',
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

  Stream<bool> watchHideAmount() {
    return (select(appSettings)..where((t) => t.key.equals('hide_amount')))
        .watchSingleOrNull()
        .map((row) => row?.value == 'true');
  }

  Future<void> toggleHideAmount() async {
    final cur = await getSetting('hide_amount');
    await setSetting('hide_amount', cur == 'true' ? 'false' : 'true');
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

  /// Create a new ledger with default accounts + categories (mirrors seedDefaults).
  Future<Ledger> createLedgerWithDefaults({
    required String name,
    String baseCurrency = 'CNY',
    bool switchTo = true,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('请填写账本名称');
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
            (t) => t.ledgerId.equals(ledgerId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(limit))
        .watch();
  }

  Stream<List<Transaction>> watchTransactionsInRange(
    String ledgerId,
    int startMs,
    int endMs, {
    int limit = 200,
  }) {
    return (select(transactions)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.deletedAt.isNull() &
                t.happenAt.isBiggerOrEqualValue(startMs) &
                t.happenAt.isSmallerThanValue(endMs),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(limit))
        .watch();
  }

  /// Bill search: optional keyword (note / merchant / amount) plus filters.
  ///
  /// Keyword may be empty when at least one filter is set (type / category /
  /// account / date range). Account filter matches [accountId] or [toAccountId].
  Future<List<Transaction>> searchTransactions(
    String ledgerId,
    String query, {
    String? type,
    String? categoryId,
    String? accountId,
    int? startMs,
    int? endMs,
    int limit = 200,
  }) async {
    final q = query.trim();
    final hasFilter = type != null ||
        categoryId != null ||
        accountId != null ||
        startMs != null ||
        endMs != null;
    if (q.isEmpty && !hasFilter) return const [];

    final pattern = q.isEmpty ? null : '%${q.toLowerCase()}%';
    final amountMinors =
        q.isEmpty ? const <int>[] : _amountMinorCandidates(q);

    // Resolve category / account name hits (and 转账 keyword → transfer type).
    var nameCatIds = const <String>[];
    var nameAccIds = const <String>[];
    var matchTransferByName = false;
    if (pattern != null) {
      final cats = await (select(categories)
            ..where((t) => t.ledgerId.equals(ledgerId)))
          .get();
      nameCatIds = [
        for (final c in cats)
          if (c.name.toLowerCase().contains(q.toLowerCase())) c.id,
      ];
      final accs = await (select(accounts)
            ..where((t) => t.ledgerId.equals(ledgerId)))
          .get();
      nameAccIds = [
        for (final a in accs)
          if (a.name.toLowerCase().contains(q.toLowerCase())) a.id,
      ];
      matchTransferByName = '\u8f6c\u8d26'.contains(q) || q.contains('\u8f6c\u8d26');
    }

    // Fetch one extra row to detect truncation for UI notice.
    final fetchLimit = limit < 0 ? 200 : limit + 1;

    final rows = await (select(transactions)
          ..where((t) {
            Expression<bool> pred =
                t.ledgerId.equals(ledgerId) & t.deletedAt.isNull();

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

            if (pattern != null) {
              Expression<bool> textHit =
                  t.note.lower().like(pattern) |
                  t.tags.lower().like(pattern);
              if (nameCatIds.isNotEmpty) {
                textHit = textHit | t.categoryId.isIn(nameCatIds);
              }
              if (nameAccIds.isNotEmpty) {
                textHit = textHit |
                    t.accountId.isIn(nameAccIds) |
                    t.toAccountId.isIn(nameAccIds);
              }
              if (matchTransferByName) {
                textHit = textHit | t.type.equals('transfer');
              }
              if (amountMinors.isEmpty) {
                pred = pred & textHit;
              } else {
                pred = pred & (textHit | t.amountMinor.isIn(amountMinors));
              }
            }
            return pred;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.happenAt)])
          ..limit(fetchLimit))
        .get();
    return rows;
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
      if (r.type != 'in' && r.type != 'out' && r.type != 'refund') continue;
      final cur = map[r.currency] ?? (income: 0, expense: 0);
      if (r.type == 'in') {
        map[r.currency] =
            (income: cur.income + r.amountMinor, expense: cur.expense);
      } else if (r.type == 'refund') {
        // Refund reduces net expense; never income.
        map[r.currency] =
            (income: cur.income, expense: cur.expense - r.amountMinor);
      } else {
        // out (may be negative for partial refunds)
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
  Future<Map<String, int>> accountBalances(String ledgerId) async {
    final accs = await loadActiveAccounts(ledgerId);
    final balances = {for (final a in accs) a.id: a.openingBalanceMinor};

    final rows = await (select(transactions)
          ..where(
            (t) => t.ledgerId.equals(ledgerId) & t.deletedAt.isNull(),
          ))
        .get();

    for (final r in rows) {
      if (r.type == 'in' || r.type == 'refund') {
        balances[r.accountId] = (balances[r.accountId] ?? 0) + r.amountMinor;
      } else if (r.type == 'out') {
        balances[r.accountId] = (balances[r.accountId] ?? 0) - r.amountMinor;
      } else if (r.type == 'transfer') {
        balances[r.accountId] = (balances[r.accountId] ?? 0) - r.amountMinor;
        final toId = r.toAccountId;
        if (toId != null) {
          final credit = r.toAmountMinor ?? r.amountMinor;
          balances[toId] = (balances[toId] ?? 0) + credit;
        }
      }
    }
    return balances;
  }

  Stream<Map<String, int>> watchAccountBalances(String ledgerId) {
    return watchRecentTransactions(ledgerId, limit: 100000).asyncMap((_) {
      return accountBalances(ledgerId);
    });
  }

  Future<void> insertManualTransaction({
    required String ledgerId,
    required String type,
    required int amountMinor,
    required String currency,
    required String accountId,
    String? toAccountId,
    String? categoryId,
    String? merchant,
    String? member,
    String? note,
    List<String>? tags,
    DateTime? happenAt,
    double? fxRate,
    int? toAmountMinor,
    int includeInStat = 1,
    int includeInBudget = 1,
    String? occurrenceKey,
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
        member: Value(member),
        note: Value(composeNote(merchant: merchant, note: note)),
        tags: Value(encodeTxnTags(tags)),
        happenAt: happen,
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        includeInStat: Value(includeInStat),
        includeInBudget: Value(includeInBudget),
        occurrenceKey: Value(occurrenceKey),
        createdAt: ts,
        updatedAt: ts,
      ),
    );
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
    final accs = await (select(accounts)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .get();
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
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: Value(ts),
        updatedAt: Value(ts),
      ),
    );
  }

  Stream<List<Transaction>> watchDeletedTransactions(String ledgerId) {
    return (select(transactions)
          ..where(
            (t) => t.ledgerId.equals(ledgerId) & t.deletedAt.isNotNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  Future<int> countDeletedTransactions(String ledgerId) async {
    final q = selectOnly(transactions)
      ..addColumns([transactions.id.count()])
      ..where(
        transactions.ledgerId.equals(ledgerId) &
            transactions.deletedAt.isNotNull(),
      );
    final rows = await q.get();
    if (rows.isEmpty) return 0;
    return rows.first.read(transactions.id.count()) ?? 0;
  }

  /// Clear deleted_at so the txn reappears in home / stats.
  Future<void> undeleteTransaction(String id) async {
    final ts = nowMs();
    await (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(ts),
      ),
    );
  }

  /// Permanently remove a soft-deleted txn.
  Future<void> purgeDeletedTransaction(String id) async {
    await (delete(transactions)
          ..where((t) => t.id.equals(id) & t.deletedAt.isNotNull()))
        .go();
  }

  Future<int> purgeAllDeletedTransactions(String ledgerId) async {
    return (delete(transactions)
          ..where(
            (t) => t.ledgerId.equals(ledgerId) & t.deletedAt.isNotNull(),
          ))
        .go();
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
    String? member,
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
        member: Value(member),
        note: Value(composeNote(merchant: merchant, note: note)),
        tags: Value(encodeTxnTags(tags)),
        happenAt: happen != null ? Value(happen) : const Value.absent(),
        fxRate: Value(fxRate),
        toAmountMinor: Value(toAmountMinor),
        updatedAt: Value(ts),
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

  Future<bool> existsDedupeKey(String key) async {
    final row = await (select(pendingCaptures)
          ..where((t) => t.dedupeKey.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  static String _txnTemplatesKey(String ledgerId) => 'txn_templates_$ledgerId';

  Future<List<TxnTemplate>> loadTxnTemplates(String ledgerId) async {
    final raw = await getSetting(_txnTemplatesKey(ledgerId));
    return TxnTemplate.decodeList(raw);
  }

  Future<void> saveTxnTemplate(String ledgerId, TxnTemplate template) async {
    final list = await loadTxnTemplates(ledgerId);
    final next = [
      template,
      for (final t in list)
        if (t.id != template.id) t,
    ];
    // Cap to keep settings payload small.
    final capped = next.take(50).toList();
    await setSetting(_txnTemplatesKey(ledgerId), TxnTemplate.encodeList(capped));
  }

  Future<void> deleteTxnTemplate(String ledgerId, String templateId) async {
    final list = await loadTxnTemplates(ledgerId);
    final next = [for (final t in list) if (t.id != templateId) t];
    await setSetting(_txnTemplatesKey(ledgerId), TxnTemplate.encodeList(next));
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
  }) async {
    final pending = await (select(pendingCaptures)
          ..where((t) => t.id.equals(pendingId)))
        .getSingle();
    if (pending.status != 'pending') {
      throw StateError('该记录不是待确认状态');
    }

    final ts = nowMs();
    // Derive real source from pending.sourcePkg (manual:ocr / clipboard / …)
    // so screenshot imports are not mislabeled as notification.
    final source = _txnSourceFromPendingPkg(pending.sourcePkg);
    await transaction(() async {
      await into(transactions).insert(
        TransactionsCompanion.insert(
          id: newId(),
          ledgerId: pending.ledgerId,
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
      await (update(pendingCaptures)..where((t) => t.id.equals(pendingId)))
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
      final m = merchantForRule?.trim();
      if (m != null && m.isNotEmpty) {
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
    final ts = nowMs();
    await (update(pendingCaptures)..where((t) => t.id.equals(pendingId)))
        .write(
      PendingCapturesCompanion(
        status: const Value('ignored'),
        updatedAt: Value(ts),
      ),
    );
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
    final rows = await loadAllFxRates();
    return FxBook([
      for (final r in rows)
        FxQuote(
          day: r.day,
          fromCcy: r.fromCcy,
          toCcy: r.toCcy,
          rate: r.rate,
        ),
    ]);
  }

  /// Upsert one FX quote. [rate] means 1 [fromCcy] = [rate] [toCcy].
  Future<void> upsertFxRate({
    required String day,
    required String fromCcy,
    required String toCcy,
    required double rate,
    String? source,
  }) async {
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

  /// Income/expense in [baseCurrency], converting foreign txns by happen-day FX.
  /// Unconvertible foreign amounts stay in [BaseRangeSummary.unconverted].
  Future<BaseRangeSummary> rangeSummaryInBase(
    String ledgerId,
    int startMs,
    int endMs,
    String baseCurrency,
  ) async {
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
    final book = await loadFxBook();
    var income = 0;
    var expense = 0;
    var converted = 0;
    var unconverted = 0;
    final leftover = <String, ({int income, int expense})>{};

    for (final r in rows) {
      if (r.type != 'in' && r.type != 'out' && r.type != 'refund') continue;
      final day = FxBook.dayFromHappenAtMs(r.happenAt);
      final asBase = book.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amountMinor,
        onDay: day,
      );
      if (asBase == null) {
        unconverted += 1;
        final cur = leftover[r.currency] ?? (income: 0, expense: 0);
        if (r.type == 'in') {
          leftover[r.currency] =
              (income: cur.income + r.amountMinor, expense: cur.expense);
        } else if (r.type == 'refund') {
          leftover[r.currency] =
              (income: cur.income, expense: cur.expense - r.amountMinor);
        } else {
          leftover[r.currency] =
              (income: cur.income, expense: cur.expense + r.amountMinor);
        }
        continue;
      }
      converted += 1;
      if (r.type == 'in') {
        income += asBase;
      } else if (r.type == 'refund') {
        expense -= asBase;
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

  /// Category totals in [baseCurrency]; skips txns that cannot be converted.
  Future<List<({String categoryId, String name, int totalMinor})>>
      categoryBreakdownInBase(
    String ledgerId,
    int startMs,
    int endMs, {
    required String kind,
    required String baseCurrency,
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
    final book = await loadFxBook();
    final totals = <String, int>{};

    for (final r in rows) {
      final day = FxBook.dayFromHappenAtMs(r.happenAt);
      final asBase = book.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amountMinor,
        onDay: day,
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
    final book = await loadFxBook();
    final byDay = <String, int>{};

    for (final r in rows) {
      final day = FxBook.dayFromHappenAtMs(r.happenAt);
      final asBase = book.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amountMinor,
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

    final rows = await (select(transactions)
          ..where(
            (t) =>
                t.ledgerId.equals(ledgerId) &
                t.deletedAt.isNull() &
                t.includeInBudget.equals(1) &
                (t.type.equals('out') | t.type.equals('refund')) &
                t.happenAt.isBiggerOrEqualValue(startMs) &
                t.happenAt.isSmallerThanValue(endMs),
          ))
        .get();
    final book = await loadFxBook();
    var spentTotal = 0;
    final spentByCat = <String, int>{};
    final leftover = <String, int>{};

    for (final r in rows) {
      final day = FxBook.dayFromHappenAtMs(r.happenAt);
      final asBase = book.convertMinor(
        fromCcy: r.currency,
        toCcy: baseCurrency,
        amountMinor: r.amountMinor,
        onDay: day,
      );
      if (asBase == null) {
        // Still exclude from spent (do not invent FX); surface for UI tip.
        final signedRaw = r.type == 'refund' ? -r.amountMinor : r.amountMinor;
        leftover[r.currency] = (leftover[r.currency] ?? 0) + signedRaw;
        continue;
      }
      final signed = r.type == 'refund' ? -asBase : asBase;
      spentTotal += signed;
      final cid = r.categoryId;
      if (cid != null && cid.isNotEmpty) {
        spentByCat[cid] = (spentByCat[cid] ?? 0) + signed;
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

  Future<RestoreImportStats> restoreFromImportBundle({
    required Map<String, dynamic> ledgerMap,
    required List<Map<String, dynamic>> accountMaps,
    List<Map<String, dynamic>> assetTypeMaps = const [],
    required List<Map<String, dynamic>> categoryMaps,
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
import 'dart:convert';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/txn_tags.dart';
import 'package:centli/data/export/import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode/decode txn tags round-trip and limits', () {
    expect(encodeTxnTags(null), isNull);
    expect(encodeTxnTags([]), isNull);
    expect(encodeTxnTags(['  ']), isNull);
    expect(decodeTxnTags(null), isEmpty);
    expect(decodeTxnTags(''), isEmpty);

    final encoded = encodeTxnTags(['报销', '旅行', '家庭', 'a', 'b', 'c']);
    expect(encoded, isNotNull);
    final list = decodeTxnTags(encoded);
    expect(list.length, 5);
    expect(list.first, '报销');

    final long = encodeTxnTags(['一二三四五六七八九十一二三']);
    expect(decodeTxnTags(long).single.length, 12);
  });

  test('v5 onCreate: tags+member columns, indexes (PRAGMA), soft-delete keeps tags', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await (db.select(db.accounts)
          ..where((t) => t.ledgerId.equals(ledger.id)))
        .get())
        .first;

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 1250,
      currency: 'CNY',
      accountId: account.id,
      tags: ['报销', '旅行'],
    );
    final rows = (await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledger.id)))
        .get())
        .where((t) => t.deletedAt == null)
        .toList();
    expect(rows.length, 1);
    expect(decodeTxnTags(rows.first.tags), ['报销', '旅行']);

    // PRAGMA index evidence (created in beforeOpen / onUpgrade)
    final idxRows =
        await db.customSelect("PRAGMA index_list('transactions')").get();
    final names = idxRows.map((r) => r.read<String>('name')).toSet();
    expect(names.contains('idx_txn_ledger_happen'), isTrue);
    expect(names.contains('idx_txn_account_happen'), isTrue);

    final accIdx =
        await db.customSelect("PRAGMA index_list('accounts')").get();
    expect(
      accIdx
          .map((r) => r.read<String>('name'))
          .contains('idx_accounts_ledger_archived'),
      isTrue,
    );

    final catIdx =
        await db.customSelect("PRAGMA index_list('categories')").get();
    expect(
      catIdx
          .map((r) => r.read<String>('name'))
          .contains('idx_categories_ledger_kind_archived'),
      isTrue,
    );

    final pendIdx =
        await db.customSelect("PRAGMA index_list('pending_captures')").get();
    expect(
      pendIdx
          .map((r) => r.read<String>('name'))
          .contains('idx_pending_status_created'),
      isTrue,
    );

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 5);

    final cols = {
      for (final r in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(cols.contains('tags'), isTrue);
    expect(cols.contains('member'), isTrue);

    await db.softDeleteTransaction(rows.first.id);
    final deleted = await (db.select(db.transactions)
          ..where((t) => t.id.equals(rows.first.id)))
        .getSingle();
    expect(deleted.deletedAt, isNotNull);
    expect(decodeTxnTags(deleted.tags), ['报销', '旅行']);
  });

  test('searchTransactions matches tags JSON', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await (db.select(db.accounts)
          ..where((t) => t.ledgerId.equals(ledger.id)))
        .get())
        .first;

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 300,
      currency: 'CNY',
      accountId: account.id,
      tags: ['旅行'],
      note: 'plain',
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 100,
      currency: 'CNY',
      accountId: account.id,
      note: 'no-tag-here',
    );

    final hit = await db.searchTransactions(ledger.id, '旅行');
    expect(hit.length, 1);
    expect(decodeTxnTags(hit.first.tags), ['旅行']);
  });

  test('import schema_version 3 bundle without tags succeeds', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final svc = ImportService(db);
    final ts = DateTime.now().millisecondsSinceEpoch;
    const ledgerId = 'led-imp';
    const accountId = 'acc-imp';
    const categoryId = 'cat-imp';
    final bundleMap = {
      'format': 'centli-export',
      'export_version': 1,
      'schema_version': 3,
      'exported_at': '2026-10-16T00:00:00Z',
      'app_version': '1.0.0+1',
      'ledger': {
        'id': ledgerId,
        'name': '导入账本',
        'baseCurrency': 'CNY',
        'createdAt': ts,
        'archived': 0,
      },
      'accounts': [
        {
          'id': accountId,
          'ledgerId': ledgerId,
          'name': '现金',
          'currency': 'CNY',
          'type': 'cash',
          'openingBalanceMinor': 0,
          'sortOrder': 0,
          'archived': 0,
          'createdAt': ts,
          'updatedAt': ts,
        },
      ],
      'categories': [
        {
          'id': categoryId,
          'ledgerId': ledgerId,
          'name': '其他',
          'parentId': null,
          'kind': 'out',
          'icon': null,
          'sortOrder': 0,
          'archived': 0,
          'createdAt': ts,
        },
      ],
      'transactions': [
        {
          'id': 'txn-old',
          'ledgerId': ledgerId,
          'type': 'out',
          'amountMinor': 42,
          'currency': 'CNY',
          'accountId': accountId,
          'toAccountId': null,
          'categoryId': categoryId,
          'merchant': null,
          'note': null,
          'happenAt': ts,
          'includeInStat': 1,
          'includeInBudget': 1,
          'source': 'manual',
          'createdAt': ts,
          'updatedAt': ts,
          // no tags key — old backup
        },
      ],
      'merchant_rules': <Map<String, dynamic>>[],
      'pending_captures': <Map<String, dynamic>>[],
      'fx_rates': <Map<String, dynamic>>[],
      'budgets': <Map<String, dynamic>>[],
      'settings': <String, String>{'onboarding_done': '1'},
    };
    final bundle = svc.parseJsonString(jsonEncode(bundleMap));
    expect(bundle.schemaVersion, 3);
    await svc.restore(bundle, replaceFxRates: false);
    final row = await (db.select(db.transactions)
          ..where((t) => t.id.equals('txn-old')))
        .getSingle();
    expect(row.amountMinor, 42);
    expect(row.tags, isNull);
  });
}

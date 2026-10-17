import 'dart:convert';

import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/export/import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _bundle({
  required String ledgerId,
  required String ledgerName,
  required List<Map<String, dynamic>> accounts,
  required List<Map<String, dynamic>> categories,
  required List<Map<String, dynamic>> transactions,
  List<Map<String, dynamic>> fxRates = const [],
  List<Map<String, dynamic>> budgets = const [],
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  return {
    'format': 'centli-export',
    'export_version': 1,
    'schema_version': 2,
    'exported_at': '2026-10-16T00:00:00Z',
    'app_version': '1.0.0+1',
    'ledger': {
      'id': ledgerId,
      'name': ledgerName,
      'baseCurrency': 'CNY',
      'createdAt': ts,
      'archived': 0,
    },
    'accounts': accounts,
    'categories': categories,
    'transactions': transactions,
    'merchant_rules': <Map<String, dynamic>>[],
    'pending_captures': <Map<String, dynamic>>[],
    'fx_rates': fxRates,
    'budgets': budgets,
    'settings': <String, String>{'onboarding_done': '1'},
  };
}

Map<String, dynamic> _account({
  required String id,
  required String ledgerId,
  required String name,
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  return {
    'id': id,
    'ledgerId': ledgerId,
    'name': name,
    'currency': 'CNY',
    'type': 'cash',
    'openingBalanceMinor': 0,
    'sortOrder': 0,
    'archived': 0,
    'createdAt': ts,
    'updatedAt': ts,
  };
}

Map<String, dynamic> _category({
  required String id,
  required String ledgerId,
  required String name,
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  return {
    'id': id,
    'ledgerId': ledgerId,
    'name': name,
    'parentId': null,
    'kind': 'out',
    'icon': null,
    'sortOrder': 0,
    'archived': 0,
    'createdAt': ts,
  };
}

Map<String, dynamic> _txn({
  required String id,
  required String ledgerId,
  required String accountId,
  required String categoryId,
  required int amountMinor,
  String? note,
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  return {
    'id': id,
    'ledgerId': ledgerId,
    'type': 'out',
    'amountMinor': amountMinor,
    'currency': 'CNY',
    'accountId': accountId,
    'toAccountId': null,
    'categoryId': categoryId,
    'note': note,
    'happenAt': ts,
    'includeInStat': 1,
    'includeInBudget': 1,
    'source': 'manual',
    'createdAt': ts,
    'updatedAt': ts,
  };
}

Map<String, dynamic> _fx({
  required String day,
  required String fromCcy,
  required String toCcy,
  required double rate,
}) {
  return {
    'day': day,
    'fromCcy': fromCcy,
    'toCcy': toCcy,
    'rate': rate,
    'source': 'test',
    'updatedAt': DateTime.now().millisecondsSinceEpoch,
  };
}

void main() {
  test('multi-ledger: restore A does not touch B', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('select 1').get();

    final svc = ImportService(db);

    // Install ledger A
    final bundleA1 = svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledA',
      ledgerName: '账本A',
      accounts: [_account(id: 'accA', ledgerId: 'ledA', name: '现金A')],
      categories: [_category(id: 'catA', ledgerId: 'ledA', name: '餐饮A')],
      transactions: [
        _txn(
          id: 'txnA1',
          ledgerId: 'ledA',
          accountId: 'accA',
          categoryId: 'catA',
          amountMinor: 1000,
          note: 'A-old',
        ),
      ],
    )));
    await svc.restore(bundleA1);

    // Install ledger B (independent)
    final bundleB = svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledB',
      ledgerName: '账本B',
      accounts: [_account(id: 'accB', ledgerId: 'ledB', name: '现金B')],
      categories: [_category(id: 'catB', ledgerId: 'ledB', name: '交通B')],
      transactions: [
        _txn(
          id: 'txnB1',
          ledgerId: 'ledB',
          accountId: 'accB',
          categoryId: 'catB',
          amountMinor: 2500,
          note: 'B-keep',
        ),
      ],
      fxRates: [],
    )));
    await svc.restore(bundleB, replaceFxRates: false);

    final bBefore = await db.loadTransactionsForExport('ledB');
    expect(bBefore, hasLength(1));
    expect(bBefore.single.note, 'B-keep');
    expect(bBefore.single.amountMinor, 2500);
    final bAccBefore = await db.loadAllAccounts('ledB');
    final bCatBefore = await db.loadAllCategories('ledB');
    expect(bAccBefore, hasLength(1));
    expect(bCatBefore, hasLength(1));

    // Re-restore A with different data
    final bundleA2 = svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledA',
      ledgerName: '账本A',
      accounts: [_account(id: 'accA2', ledgerId: 'ledA', name: '现金A2')],
      categories: [_category(id: 'catA2', ledgerId: 'ledA', name: '日用A2')],
      transactions: [
        _txn(
          id: 'txnA2',
          ledgerId: 'ledA',
          accountId: 'accA2',
          categoryId: 'catA2',
          amountMinor: 8888,
          note: 'A-new',
        ),
      ],
    )));
    await svc.restore(bundleA2, replaceFxRates: false);

    final aAfter = await db.loadTransactionsForExport('ledA');
    expect(aAfter.map((e) => e.id).toList(), ['txnA2']);
    expect(aAfter.single.note, 'A-new');
    expect(aAfter.single.amountMinor, 8888);

    final bAfter = await db.loadTransactionsForExport('ledB');
    expect(bAfter, hasLength(1));
    expect(bAfter.single.id, 'txnB1');
    expect(bAfter.single.note, 'B-keep');
    expect(bAfter.single.amountMinor, 2500);
    final bAccAfter = await db.loadAllAccounts('ledB');
    final bCatAfter = await db.loadAllCategories('ledB');
    expect(bAccAfter.single.id, bAccBefore.single.id);
    expect(bCatAfter.single.id, bCatBefore.single.id);
    expect(bAccAfter.single.name, '现金B');
    expect(bCatAfter.single.name, '交通B');
  });

  test('child ledgerId pointing at B is rewritten to top-level A', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('select 1').get();

    final svc = ImportService(db);

    // B exists locally first
    await svc.restore(svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledB',
      ledgerName: '账本B',
      accounts: [_account(id: 'accB', ledgerId: 'ledB', name: '现金B')],
      categories: [_category(id: 'catB', ledgerId: 'ledB', name: '交通B')],
      transactions: [],
    ))), replaceFxRates: false);

    // Bundle top-level A, but transaction.ledgerId wrongly says B
    final bundle = svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledA',
      ledgerName: '账本A',
      accounts: [_account(id: 'accA', ledgerId: 'ledA', name: '现金A')],
      categories: [_category(id: 'catA', ledgerId: 'ledA', name: '餐饮A')],
      transactions: [
        _txn(
          id: 'txnCross',
          ledgerId: 'ledB', // wrong — should be forced onto A
          accountId: 'accA',
          categoryId: 'catA',
          amountMinor: 4242,
          note: 'cross',
        ),
      ],
    )));
    await svc.restore(bundle, replaceFxRates: false);

    final inA = await db.loadTransactionsForExport('ledA');
    expect(inA.map((e) => e.id), contains('txnCross'));
    expect(inA.singleWhere((e) => e.id == 'txnCross').ledgerId, 'ledA');

    final inB = await db.loadTransactionsForExport('ledB');
    expect(inB.where((e) => e.id == 'txnCross'), isEmpty);
  });

  test('fx_rates: replaceFxRates true replaces, false keeps', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('select 1').get();

    final svc = ImportService(db);

    await svc.restore(svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledFx1',
      ledgerName: 'FX1',
      accounts: [_account(id: 'acc1', ledgerId: 'ledFx1', name: 'cash')],
      categories: [_category(id: 'cat1', ledgerId: 'ledFx1', name: 'food')],
      transactions: [],
      fxRates: [
        _fx(day: '2026-10-01', fromCcy: 'USD', toCcy: 'CNY', rate: 7.1),
      ],
    ))), replaceFxRates: true);

    var fx = await db.loadAllFxRates();
    expect(fx, hasLength(1));
    expect(fx.single.rate, 7.1);

    // replaceFxRates: false — keep old FX even if bundle has different
    await svc.restore(svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledFx2',
      ledgerName: 'FX2',
      accounts: [_account(id: 'acc2', ledgerId: 'ledFx2', name: 'cash')],
      categories: [_category(id: 'cat2', ledgerId: 'ledFx2', name: 'food')],
      transactions: [],
      fxRates: [
        _fx(day: '2026-10-02', fromCcy: 'EUR', toCcy: 'CNY', rate: 8.0),
      ],
    ))), replaceFxRates: false);

    fx = await db.loadAllFxRates();
    expect(fx, hasLength(1));
    expect(fx.single.fromCcy, 'USD');
    expect(fx.single.rate, 7.1);

    // replaceFxRates: true — wipe and insert bundle FX
    await svc.restore(svc.parseJsonString(jsonEncode(_bundle(
      ledgerId: 'ledFx3',
      ledgerName: 'FX3',
      accounts: [_account(id: 'acc3', ledgerId: 'ledFx3', name: 'cash')],
      categories: [_category(id: 'cat3', ledgerId: 'ledFx3', name: 'food')],
      transactions: [],
      fxRates: [
        _fx(day: '2026-10-03', fromCcy: 'JPY', toCcy: 'CNY', rate: 0.05),
      ],
    ))), replaceFxRates: true);

    fx = await db.loadAllFxRates();
    expect(fx, hasLength(1));
    expect(fx.single.fromCcy, 'JPY');
    expect(fx.single.rate, 0.05);
  });
}

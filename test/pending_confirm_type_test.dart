import 'dart:io';

import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending_page confirm passes type: txnType from category kind', () {
    final src = File('lib/features/pending/pending_page.dart').readAsStringSync();
    expect(
      src.contains('type: txnType'),
      isTrue,
      reason: 'confirmPendingCapture must pass type: txnType',
    );
    expect(
      src.contains("inCats.any((x) => x.id == _categoryId) ? 'in' : 'out'"),
      isTrue,
      reason: 'txnType must still resolve from category lists (B1-2)',
    );
    expect(
      src.contains("if (_direction == 'refund')"),
      isTrue,
      reason: 'refund direction must map to type refund (T4-2)',
    );
  });

  test('confirmPendingCapture with income category stores type in', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final account = (await db.loadActiveAccounts(ledger.id)).first;
    final inCats = await db.loadCategories(ledger.id, 'in');
    final outCats = await db.loadCategories(ledger.id, 'out');
    expect(inCats, isNotEmpty);
    expect(outCats, isNotEmpty);

    final incomeCat = inCats.first;
    final expenseCat = outCats.first;

    // Mirror pending_page.dart resolution against loaded lists.
    String resolveType(String? categoryId) {
      final known = outCats.any((x) => x.id == categoryId) ||
          inCats.any((x) => x.id == categoryId);
      final txnType = !known
          ? 'out'
          : (inCats.any((x) => x.id == categoryId) ? 'in' : 'out');
      return txnType;
    }

    expect(resolveType(incomeCat.id), 'in');
    expect(resolveType(expenseCat.id), 'out');
    expect(resolveType('deleted-cat-id'), 'out');

    final pendingInId = await db.ingestParsedNotification(
      ledgerId: ledger.id,
      sourcePkg: 'manual:test',
      rawText: '工资到账 5000',
      dedupeKey: 'test-income-${DateTime.now().microsecondsSinceEpoch}',
      amountMinor: 500000,
      currency: 'CNY',
      merchant: '公司',
      parseOk: true,
    );
    expect(pendingInId, isNotNull);

    final txnType = resolveType(incomeCat.id);
    await db.confirmPendingCapture(
      pendingId: pendingInId!,
      amountMinor: 500000,
      currency: 'CNY',
      accountId: account.id,
      categoryId: incomeCat.id,
      type: txnType,
    );

    final rows = await (db.select(db.transactions)
          ..where((t) => t.ledgerId.equals(ledger.id)))
        .get();
    final live = rows.where((t) => t.deletedAt == null).toList();
    expect(live, isNotEmpty);
    final incomeTxn = live.singleWhere((t) => t.categoryId == incomeCat.id);
    expect(incomeTxn.type, 'in');
  });

  test('pending_page _applySuggestions prefers category kind by direction', () {
    final src = File('lib/features/pending/pending_page.dart').readAsStringSync();
    expect(src.contains("preferredKind = _direction == 'in' ? 'in' : 'out'"), isTrue);
    expect(src.contains('type: txnType'), isTrue, reason: 'B1-2 must remain');
  });

}

import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loadTxnListLookups returns maps keyed by id', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final lookups = await db.loadTxnListLookups(ledger.id);
    expect(lookups.accountsById, isNotEmpty);
    expect(lookups.categoriesById, isNotEmpty);
    expect(lookups.ledgerNamesById, isNotEmpty);
    expect(lookups.ledgerNamesById[ledger.id], ledger.name);
    final acc = lookups.accountsById.values.first;
    expect(lookups.accountsById[acc.id]?.name, acc.name);
    final cat = lookups.categoriesById.values.first;
    expect(lookups.categoriesById[cat.id]?.name, cat.name);
  });
}

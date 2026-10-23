import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v9 onCreate has no subscriptions table', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 13);
    final tables = {
      for (final r in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get())
        r.read<String>('name')
    };
    expect(tables.contains('subscriptions'), isFalse);
    expect(tables.contains('recurring_rules'), isTrue);
    expect(tables.contains('transactions'), isTrue);
  });
}

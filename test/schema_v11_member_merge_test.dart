import 'dart:io';

import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

File _copyFixture(String assetName, String tempName) {
  final src = File('test/fixtures/$assetName');
  final dest = File('${Directory.systemTemp.path}/$tempName');
  if (dest.existsSync()) dest.deleteSync();
  src.copySync(dest.path);
  return dest;
}

void main() {
  test('v11 onCreate has no member column', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 12);
    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(cols.contains('member'), isFalse);
    expect(cols.contains('note'), isTrue);
  });

  test('v10→v11 merges 4 member rows into note and drops column', () async {
    final file = _copyFixture('schema_v10_member.db', 'centli_v10_member_merge.db');
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final db = CentliDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 12);

    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(cols.contains('member'), isFalse);

    final rows = await db.customSelect(
      'SELECT id, note, amount_minor, currency, account_id FROM transactions ORDER BY id',
    ).get();
    expect(rows.length, 4);

    String? noteOf(String id) =>
        rows.firstWhere((r) => r.read<String>('id') == id).read<String?>('note');

    expect(noteOf('T1'), '午餐 · Alice');
    expect(noteOf('T2'), 'Bob');
    expect(noteOf('T3'), '仅备注');
    expect(noteOf('T4'), '保留备注');

    for (final r in rows) {
      expect(r.read<String>('currency'), 'CNY');
      expect(r.read<String>('account_id'), 'A1');
    }
    expect(
      rows.firstWhere((r) => r.read<String>('id') == 'T1').read<int>('amount_minor'),
      100,
    );
    expect(
      rows.firstWhere((r) => r.read<String>('id') == 'T2').read<int>('amount_minor'),
      200,
    );
  });

  test('v4→v11 cross-version ends without member', () async {
    final file = _copyFixture('schema_v4.db', 'centli_v4_to_v11.db');
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final db = CentliDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 12);

    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(cols.contains('member'), isFalse);
    expect(cols.contains('merchant'), isFalse);
    expect(cols.contains('occurrence_key'), isTrue);

    final row = await db.customSelect(
      "SELECT note, amount_minor FROM transactions WHERE id = 'T1'",
    ).getSingle();
    expect(row.read<String>('note'), '星巴克 · 原备注');
    expect(row.read<int>('amount_minor'), 100);
  });
}

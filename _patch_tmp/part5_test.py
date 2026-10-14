from pathlib import Path
Path(r"D:\Resource\Codebase\studyProject\Centli\test\export_import_budgets_test.dart").write_text("""import 'dart:convert';

import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/export/import_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _minimalBundle({
  List<Map<String, dynamic>>? budgets,
  int schemaVersion = 2,
}) {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final map = <String, dynamic>{
    'format': 'centli-export',
    'export_version': 1,
    'schema_version': schemaVersion,
    'exported_at': '2026-10-14T00:00:00Z',
    'app_version': '1.0.0+1',
    'ledger': {
      'id': 'led1',
      'name': 'test',
      'baseCurrency': 'CNY',
      'createdAt': ts,
      'archived': 0,
    },
    'accounts': [
      {
        'id': 'acc1',
        'ledgerId': 'led1',
        'name': 'cash',
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
        'id': 'cat1',
        'ledgerId': 'led1',
        'name': 'food',
        'parentId': null,
        'kind': 'out',
        'icon': null,
        'sortOrder': 0,
        'archived': 0,
        'createdAt': ts,
      },
    ],
    'transactions': <Map<String, dynamic>>[],
    'merchant_rules': <Map<String, dynamic>>[],
    'pending_captures': <Map<String, dynamic>>[],
    'fx_rates': <Map<String, dynamic>>[],
    'settings': <String, String>{'onboarding_done': '1'},
  };
  if (budgets != null) {
    map['budgets'] = budgets;
  }
  return map;
}

void main() {
  test('parseJsonString keeps budgets; missing key => empty', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final svc = ImportService(db);
    final withBudgets = _minimalBundle(budgets: [
      {
        'id': 'b1',
        'ledgerId': 'led1',
        'yearMonth': '2026-10',
        'categoryId': '',
        'amountMinor': 500000,
        'createdAt': 1,
        'updatedAt': 1,
      },
      {
        'id': 'b2',
        'ledgerId': 'led1',
        'yearMonth': '2026-10',
        'categoryId': 'cat1',
        'amountMinor': 100000,
        'createdAt': 1,
        'updatedAt': 1,
      },
    ]);
    final parsed = svc.parseJsonString(jsonEncode(withBudgets));
    expect(parsed.schemaVersion, 2);
    expect(parsed.budgets, hasLength(2));
    expect(parsed.budgets[0]['amountMinor'], 500000);
    expect(parsed.budgets[1]['categoryId'], 'cat1');

    final legacy = _minimalBundle(schemaVersion: 1);
    final old = svc.parseJsonString(jsonEncode(legacy));
    expect(old.budgets, isEmpty);
  });

  test('restore re-inserts budgets after wipe', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Create schema (onCreate + seed).
    await db.customSelect('select 1').get();

    final svc = ImportService(db);
    final bundle = svc.parseJsonString(jsonEncode(_minimalBundle(budgets: [
      {
        'id': 'b1',
        'ledgerId': 'led1',
        'yearMonth': '2026-10',
        'categoryId': '',
        'amountMinor': 500000,
        'createdAt': 1,
        'updatedAt': 1,
      },
      {
        'id': 'b2',
        'ledgerId': 'led1',
        'yearMonth': '2026-10',
        'categoryId': 'cat1',
        'amountMinor': 100000,
        'createdAt': 1,
        'updatedAt': 1,
      },
    ])));

    final result = await svc.restore(bundle);
    expect(result.budgets, 2);
    final rows = await db.loadBudgetsForExport('led1');
    expect(rows, hasLength(2));
    expect(rows.map((e) => e.amountMinor).toSet(), {500000, 100000});
  });
}
""", encoding="utf-8")
print("test written")

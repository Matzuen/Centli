import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/export/export_service.dart';
import 'package:centli/data/export/import_service.dart';
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('excel round-trip preserves include_in_budget and include_in_stat',
      () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();

    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    final cats = await db.loadCategories(ledger.id, 'out');
    expect(accounts, isNotEmpty);
    expect(cats, isNotEmpty);

    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 1000,
      currency: 'CNY',
      accountId: accounts.first.id,
      categoryId: cats.first.id,
      includeInStat: 0,
      includeInBudget: 0,
    );
    await db.insertManualTransaction(
      ledgerId: ledger.id,
      type: 'out',
      amountMinor: 2000,
      currency: 'CNY',
      accountId: accounts.first.id,
      categoryId: cats.first.id,
      includeInStat: 1,
      includeInBudget: 1,
    );

    final exportSvc = ExportService(db);
    final bundleMap = await exportSvc.buildBundle(
      ledgerId: ledger.id,
      options: const ExportOptions(includePending: false),
    );
    final bytes = exportSvc.buildExcelBytes(bundleMap);

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel['transactions'];
    final header = sheet.rows.first.map((c) => '${c?.value ?? ''}').toList();
    expect(header, contains('include_in_budget'));
    expect(header, contains('include_in_stat'));
    final budgetIdx = header.indexOf('include_in_budget');
    final statIdx = header.indexOf('include_in_stat');
    final amtIdx = header.indexOf('amount_minor');
    final byAmt = <int, List<int>>{};
    for (final row in sheet.rows.skip(1)) {
      final raw = row[amtIdx]?.value;
      final amt = raw is IntCellValue
          ? raw.value
          : int.tryParse('${raw ?? ''}') ?? 0;
      if (amt == 0) continue;
      final sRaw = row[statIdx]?.value;
      final bRaw = row[budgetIdx]?.value;
      final s = sRaw is IntCellValue
          ? sRaw.value
          : int.tryParse('${sRaw ?? ''}') ?? -1;
      final b = bRaw is IntCellValue
          ? bRaw.value
          : int.tryParse('${bRaw ?? ''}') ?? -1;
      byAmt[amt] = [s, b];
    }
    expect(byAmt[1000], [0, 0]);
    expect(byAmt[2000], [1, 1]);

    final importSvc = ImportService(db);
    final parsed = importSvc.parseExcelBytes(bytes);
    final imported = {
      for (final t in parsed.bundle.transactions)
        t['amountMinor'] as int: t,
    };
    expect(imported[1000]!['includeInBudget'], 0);
    expect(imported[1000]!['includeInStat'], 0);
    expect(imported[2000]!['includeInBudget'], 1);
    expect(imported[2000]!['includeInStat'], 1);
  });

  test('excel import errors on missing required headers', () {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final excel = Excel.createExcel();
    // rename default sheet or use tables
    final summary = excel['summary'];
    summary.appendRow([TextCellValue('key'), TextCellValue('value')]);
    summary.appendRow([
      TextCellValue('format'),
      TextCellValue('centli-export'),
    ]);
    summary.appendRow([TextCellValue('ledger_id'), TextCellValue('led1')]);
    summary.appendRow([TextCellValue('ledger_name'), TextCellValue('t')]);
    summary.appendRow([
      TextCellValue('base_currency'),
      TextCellValue('CNY'),
    ]);

    final sheet = excel['transactions'];
    sheet.appendRow([
      TextCellValue('id'),
      TextCellValue('happen_at_iso'),
      TextCellValue('type'),
      TextCellValue('amount'), // not amount_minor
      TextCellValue('currency'),
      TextCellValue('account_id'),
    ]);
    sheet.appendRow([
      TextCellValue('x'),
      TextCellValue('2026-01-01T00:00:00'),
      TextCellValue('out'),
      DoubleCellValue(1.0),
      TextCellValue('CNY'),
      TextCellValue('a1'),
    ]);

    final bytes = excel.encode()!;
    final svc = ImportService(db);
    expect(
      () => svc.parseExcelBytes(bytes),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('amount_minor'),
        ),
      ),
    );
  });

  test('excel import defaults include_in_budget to 1 when column missing',
      () {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final excel = Excel.createExcel();
    final summary = excel['summary'];
    summary.appendRow([TextCellValue('key'), TextCellValue('value')]);
    summary.appendRow([
      TextCellValue('format'),
      TextCellValue('centli-export'),
    ]);
    summary.appendRow([TextCellValue('ledger_id'), TextCellValue('led1')]);
    summary.appendRow([TextCellValue('ledger_name'), TextCellValue('t')]);
    summary.appendRow([
      TextCellValue('base_currency'),
      TextCellValue('CNY'),
    ]);

    // Older export shape: has include_in_stat but no include_in_budget.
    final sheet = excel['transactions'];
    sheet.appendRow([
      TextCellValue('id'),
      TextCellValue('happen_at_iso'),
      TextCellValue('type'),
      TextCellValue('amount_minor'),
      TextCellValue('amount'),
      TextCellValue('currency'),
      TextCellValue('account_id'),
      TextCellValue('account_name'),
      TextCellValue('to_account_id'),
      TextCellValue('to_account_name'),
      TextCellValue('category_id'),
      TextCellValue('category_name'),
      TextCellValue('merchant'),
      TextCellValue('note'),
      TextCellValue('tags'),
      TextCellValue('source'),
      TextCellValue('include_in_stat'),
      TextCellValue('fx_rate'),
      TextCellValue('to_amount_minor'),
      TextCellValue('deleted_at'),
    ]);
    sheet.appendRow([
      TextCellValue('t-old'),
      TextCellValue('2026-01-01T12:00:00'),
      TextCellValue('out'),
      IntCellValue(500),
      DoubleCellValue(5.0),
      TextCellValue('CNY'),
      TextCellValue('a1'),
      TextCellValue('cash'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('c1'),
      TextCellValue('food'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue('manual'),
      IntCellValue(1),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
    ]);

    final bytes = excel.encode()!;
    final parsed = ImportService(db).parseExcelBytes(bytes);
    final t =
        parsed.bundle.transactions.firstWhere((e) => e['id'] == 't-old');
    expect(t['includeInBudget'], 1);
    expect(t['includeInStat'], 1);
    expect(t['amountMinor'], 500);
  });
}

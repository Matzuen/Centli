import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/export/export_service.dart';
import 'package:centli/data/export/import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('excel export type names round-trip; legacy codes & unknown map', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();

    final houseId =
        await db.createAssetType(ledgerId: ledger.id, name: '房产');
    await db.createAccount(
      ledgerId: ledger.id,
      name: '学区房',
      currency: 'CNY',
      type: houseId,
      openingBalanceMinor: 1000000,
    );

    final export = ExportService(db);
    final bundle = await export.buildBundle(
      ledgerId: ledger.id,
      options: const ExportOptions(wantJson: false, wantExcel: true),
    );
    final bytes = export.buildExcelBytes(bundle);

    final importer = ImportService(db);
    final parsed = importer.parseExcelBytes(bytes);
    final house = parsed.bundle.accounts.firstWhere((a) => a['name'] == '学区房');
    expect(house['type'], '房产');
    expect(
      parsed.bundle.assetTypes.any((t) => t['name'] == '房产'),
      isTrue,
    );

    final legacyRow = Map<String, dynamic>.from(house)
      ..['id'] = 'legacy-acc-1'
      ..['name'] = '旧现金'
      ..['type'] = 'cash';
    final unknownRow = Map<String, dynamic>.from(house)
      ..['id'] = 'unknown-acc-1'
      ..['name'] = '幽灵'
      ..['type'] = '火星币';

    await importer.restore(
      ImportBundle(
        raw: parsed.bundle.raw,
        exportVersion: parsed.bundle.exportVersion,
        schemaVersion: parsed.bundle.schemaVersion,
        exportedAt: parsed.bundle.exportedAt,
        appVersion: parsed.bundle.appVersion,
        ledger: parsed.bundle.ledger,
        accounts: [...parsed.bundle.accounts, legacyRow, unknownRow],
        assetTypes: parsed.bundle.assetTypes,
        categories: parsed.bundle.categories,
        transactions: const [],
        merchantRules: const [],
        pendingCaptures: const [],
        fxRates: const [],
        budgets: const [],
        settings: parsed.bundle.settings,
      ),
    );

    final types = await db.loadAssetTypes(ledger.id, includeArchived: true);
    final n2id = {for (final t in types) t.name: t.id};
    final after = {
      for (final a in await db.loadActiveAccounts(ledger.id)) a.name: a
    };

    expect(n2id.containsKey('房产'), isTrue);
    expect(after['学区房']!.type, n2id['房产']);
    expect(after['旧现金']!.type, n2id['现金']);
    expect(after['幽灵']!.type, n2id['其他']);
    for (final a in after.values) {
      expect(n2id.values.contains(a.type), isTrue);
    }
  });
}

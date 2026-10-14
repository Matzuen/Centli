import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/export/export_service.dart';
import 'package:centli/data/export/import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('excel best-effort parse from Centli export workbook', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customSelect('select 1').get();

    final ledgerId = await db.currentLedgerId();
    expect(ledgerId, isNotNull);

    final exportSvc = ExportService(db);
    final bundleMap = await exportSvc.buildBundle(
      ledgerId: ledgerId!,
      options: const ExportOptions(includePending: true),
    );
    final bytes = exportSvc.buildExcelBytes(bundleMap);

    final importSvc = ImportService(db);
    final parsed = importSvc.parseExcelBytes(bytes);
    expect(parsed.bundle.ledgerId, ledgerId);
    expect(parsed.bundle.accounts, isNotEmpty);
    expect(parsed.bundle.categories, isNotEmpty);
    expect(parsed.warnings, isNotEmpty);
    // Excel path never carries fx/settings sheets.
    expect(parsed.bundle.fxRates, isEmpty);
    expect(parsed.bundle.settings, isEmpty);
  });
}

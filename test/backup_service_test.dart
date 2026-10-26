import 'dart:convert';
import 'dart:io';

import 'package:centli/core/constants/pref_keys.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/export/backup_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late CentliDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    tempDir = await Directory.systemTemp.createTemp('centli_backup_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('runBackup writes JSON per ledger and records success', () async {
    final svc = BackupService(db);
    await svc.setDirectory(tempDir.path);
    await svc.setFrequency(BackupFrequency.daily);

    final result = await svc.runBackup();
    expect(result.ledgerCount, greaterThanOrEqualTo(1));
    expect(result.fileNames, isNotEmpty);

    for (final name in result.fileNames) {
      final file = File(p.join(tempDir.path, name));
      expect(await file.exists(), isTrue, reason: name);
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(map['format'], 'centli-export');
      expect(map['ledger'], isA<Map>());
    }

    final config = await svc.loadConfig();
    expect(config.hasDirectory, isTrue);
    expect(config.frequency, BackupFrequency.daily);
    expect(config.lastSuccessAt, isNotNull);
    expect(config.lastError, isNull);

    final storedDir = await db.getSetting(PrefKeys.backupDir);
    expect(storedDir, tempDir.path);
  });

  test('maybeAutoBackup skips when frequency off', () async {
    final svc = BackupService(db);
    await svc.setDirectory(tempDir.path);
    // setDirectory defaults frequency to weekly — force off.
    await svc.setFrequency(BackupFrequency.off);
    final ran = await svc.maybeAutoBackup(now: DateTime(2026, 10, 26));
    expect(ran, isFalse);
    expect(tempDir.listSync().whereType<File>(), isEmpty);
  });

  test('maybeAutoBackup runs when due and never backed up', () async {
    final svc = BackupService(db);
    await db.setSetting(PrefKeys.backupDir, tempDir.path);
    await db.setSetting(PrefKeys.backupFrequency, 'daily');
    final ran = await svc.maybeAutoBackup(now: DateTime(2026, 10, 26, 12));
    expect(ran, isTrue);
    expect(
      tempDir.listSync().whereType<File>().length,
      greaterThanOrEqualTo(1),
    );
  });

  test('runBackup without directory throws', () async {
    final svc = BackupService(db);
    await expectLater(svc.runBackup(), throwsA(isA<StateError>()));
  });
}

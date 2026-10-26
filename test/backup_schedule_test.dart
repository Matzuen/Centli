import 'package:centli/data/export/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBackupFrequency', () {
    test('known values', () {
      expect(parseBackupFrequency('daily'), BackupFrequency.daily);
      expect(parseBackupFrequency('weekly'), BackupFrequency.weekly);
      expect(parseBackupFrequency('monthly'), BackupFrequency.monthly);
      expect(parseBackupFrequency('off'), BackupFrequency.off);
    });

    test('empty / unknown => off', () {
      expect(parseBackupFrequency(null), BackupFrequency.off);
      expect(parseBackupFrequency(''), BackupFrequency.off);
      expect(parseBackupFrequency('weird'), BackupFrequency.off);
    });
  });

  group('isBackupDue', () {
    final now = DateTime(2026, 10, 26, 15, 30);

    test('off never due', () {
      expect(
        isBackupDue(
          frequency: BackupFrequency.off,
          lastSuccessAt: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('null last => due for any active frequency', () {
      for (final f in [
        BackupFrequency.daily,
        BackupFrequency.weekly,
        BackupFrequency.monthly,
      ]) {
        expect(
          isBackupDue(frequency: f, lastSuccessAt: null, now: now),
          isTrue,
          reason: f.name,
        );
      }
    });

    test('daily: same calendar day not due; next day due', () {
      final sameDay = DateTime(2026, 10, 26, 8, 0);
      final prevDay = DateTime(2026, 10, 25, 23, 0);
      expect(
        isBackupDue(
          frequency: BackupFrequency.daily,
          lastSuccessAt: sameDay,
          now: now,
        ),
        isFalse,
      );
      expect(
        isBackupDue(
          frequency: BackupFrequency.daily,
          lastSuccessAt: prevDay,
          now: now,
        ),
        isTrue,
      );
    });

    test('weekly: needs 7 calendar days', () {
      expect(
        isBackupDue(
          frequency: BackupFrequency.weekly,
          lastSuccessAt: DateTime(2026, 10, 20, 10),
          now: now,
        ),
        isFalse,
      );
      expect(
        isBackupDue(
          frequency: BackupFrequency.weekly,
          lastSuccessAt: DateTime(2026, 10, 19, 10),
          now: now,
        ),
        isTrue,
      );
    });

    test('monthly: new calendar month', () {
      expect(
        isBackupDue(
          frequency: BackupFrequency.monthly,
          lastSuccessAt: DateTime(2026, 10, 1, 9),
          now: now,
        ),
        isFalse,
      );
      expect(
        isBackupDue(
          frequency: BackupFrequency.monthly,
          lastSuccessAt: DateTime(2026, 9, 30, 9),
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('naming helpers', () {
    test('backupSafeName strips odd chars', () {
      expect(backupSafeName('我的账本'), '我的账本');
      expect(backupSafeName('a/b:c'), 'a_b_c');
      expect(backupSafeName(''), 'ledger');
    });

    test('backupFileStamp shape', () {
      final s = backupFileStamp(DateTime(2026, 3, 5, 7, 8, 9));
      expect(s, matches(RegExp(r'^\d{8}_\d{6}$')));
      expect(s.contains('20260305'), isTrue);
    });
  });

  test('frequency labels are Chinese', () {
    expect(BackupFrequency.daily.labelZh, '每天');
    expect(BackupFrequency.weekly.labelZh, '每周');
    expect(BackupFrequency.monthly.labelZh, '每月');
    expect(BackupFrequency.off.labelZh, '关闭');
  });
}

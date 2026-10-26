import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/pref_keys.dart';
import '../db/centli_database.dart';
import 'export_service.dart';

/// 自动备份频率。
enum BackupFrequency {
  off,
  daily,
  weekly,
  monthly,
}

extension BackupFrequencyX on BackupFrequency {
  String get storageValue => name;

  String get labelZh => switch (this) {
        BackupFrequency.off => '关闭',
        BackupFrequency.daily => '每天',
        BackupFrequency.weekly => '每周',
        BackupFrequency.monthly => '每月',
      };
}

BackupFrequency parseBackupFrequency(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'daily':
      return BackupFrequency.daily;
    case 'weekly':
      return BackupFrequency.weekly;
    case 'monthly':
      return BackupFrequency.monthly;
    case 'off':
    case '':
    default:
      return BackupFrequency.off;
  }
}

/// 是否已到自动备份时间（[now] / [lastSuccessAt] 用本地日历语义）。
bool isBackupDue({
  required BackupFrequency frequency,
  required DateTime? lastSuccessAt,
  required DateTime now,
}) {
  if (frequency == BackupFrequency.off) return false;
  if (lastSuccessAt == null) return true;

  final localNow = now.toLocal();
  final localLast = lastSuccessAt.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);
  final lastDay = DateTime(localLast.year, localLast.month, localLast.day);

  switch (frequency) {
    case BackupFrequency.off:
      return false;
    case BackupFrequency.daily:
      return today.isAfter(lastDay);
    case BackupFrequency.weekly:
      return today.difference(lastDay).inDays >= 7;
    case BackupFrequency.monthly:
      return localNow.year > localLast.year ||
          (localNow.year == localLast.year &&
              localNow.month > localLast.month);
  }
}

DateTime? parseBackupTimestamp(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

String backupFileStamp(DateTime n) {
  String two(int v) => v.toString().padLeft(2, '0');
  final local = n.toLocal();
  return '${local.year}${two(local.month)}${two(local.day)}_'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
}

String backupSafeName(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-]+'), '_');
  if (cleaned.isEmpty) return 'ledger';
  return cleaned.length > 32 ? cleaned.substring(0, 32) : cleaned;
}

/// 当前备份配置快照。
class BackupConfig {
  const BackupConfig({
    required this.directory,
    required this.frequency,
    required this.lastSuccessAt,
    required this.lastError,
    required this.promptSeen,
  });

  final String? directory;
  final BackupFrequency frequency;
  final DateTime? lastSuccessAt;
  final String? lastError;
  final bool promptSeen;

  bool get hasDirectory =>
      directory != null && directory!.trim().isNotEmpty;

  bool get isConfigured => hasDirectory;
}

class BackupRunResult {
  const BackupRunResult({
    required this.directory,
    required this.fileNames,
    required this.ledgerCount,
  });

  final String directory;
  final List<String> fileNames;
  final int ledgerCount;
}

/// 纯本地文件夹备份（JSON，与导出格式一致，可用「导入」还原）。
///
/// 目录由系统选择器 / SAF 选定；不接网盘 API。
/// 自动调度：App 启动与回前台时检查是否到期（不依赖后台 Job）。
class BackupService {
  BackupService(this.db);

  final CentliDatabase db;

  Future<BackupConfig> loadConfig() async {
    final dir = await db.getSetting(PrefKeys.backupDir);
    final freq = parseBackupFrequency(
      await db.getSetting(PrefKeys.backupFrequency),
    );
    final last = parseBackupTimestamp(
      await db.getSetting(PrefKeys.backupLastOkAt),
    );
    final err = await db.getSetting(PrefKeys.backupLastError);
    final seenRaw = await db.getSetting(PrefKeys.backupPromptSeen);
    return BackupConfig(
      directory: (dir == null || dir.trim().isEmpty) ? null : dir.trim(),
      frequency: freq,
      lastSuccessAt: last,
      lastError: (err == null || err.trim().isEmpty) ? null : err.trim(),
      promptSeen: seenRaw == 'true' || seenRaw == '1',
    );
  }

  Future<void> setDirectory(String path) async {
    await db.setSetting(PrefKeys.backupDir, path.trim());
    await db.setSetting(PrefKeys.backupPromptSeen, 'true');
    // 首次选目录且频率仍为关闭时，默认每周，避免「选了目录却从不自动备份」。
    final freq = parseBackupFrequency(
      await db.getSetting(PrefKeys.backupFrequency),
    );
    if (freq == BackupFrequency.off) {
      await db.setSetting(
        PrefKeys.backupFrequency,
        BackupFrequency.weekly.storageValue,
      );
    }
  }

  Future<void> clearDirectory() async {
    await db.setSetting(PrefKeys.backupDir, '');
  }

  Future<void> setFrequency(BackupFrequency frequency) async {
    await db.setSetting(PrefKeys.backupFrequency, frequency.storageValue);
    await db.setSetting(PrefKeys.backupPromptSeen, 'true');
  }

  Future<void> markPromptSeen() async {
    await db.setSetting(PrefKeys.backupPromptSeen, 'true');
  }

  /// 系统目录选择（Android 走 SAF tree；Windows/桌面为文件夹对话框）。
  Future<String?> pickDirectory() async {
    return FilePicker.getDirectoryPath(
      dialogTitle: '选择备份文件夹',
    );
  }

  /// 立即备份：为每个未归档记账本写一份 JSON 到所选目录。
  Future<BackupRunResult> runBackup() async {
    final config = await loadConfig();
    final dirPath = config.directory;
    if (dirPath == null || dirPath.isEmpty) {
      throw StateError('尚未选择备份目录');
    }

    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw StateError('备份目录不存在或无法访问');
    }

    // 写权限探测（部分 Android SAF 路径可能无法用 dart:io 直写）。
    try {
      final probe = File(
        p.join(dir.path, '.centli_backup_write_probe'),
      );
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } catch (e) {
      throw StateError(
        '无法写入所选目录（若在 Android，请选「下载 / Documents」等可访问位置，'
        '或改用「我的 → 导出」手动分享）。详情: $e',
      );
    }

    final ledgers = await db.loadAllLedgers(includeArchived: false);
    if (ledgers.isEmpty) {
      throw StateError('没有可备份的记账本');
    }

    final export = ExportService(db);
    final stamp = backupFileStamp(DateTime.now());
    final written = <String>[];

    for (final ledger in ledgers) {
      final bundle = await export.buildBundle(
        ledgerId: ledger.id,
        options: const ExportOptions(
          wantJson: true,
          wantExcel: false,
          includePending: true,
          includeDeleted: false,
        ),
      );
      final fileName =
          'centli_${backupSafeName(ledger.name)}_$stamp.json';
      final file = File(p.join(dir.path, fileName));
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundle),
        flush: true,
      );
      written.add(fileName);
    }

    await db.setSetting(
      PrefKeys.backupLastOkAt,
      DateTime.now().toUtc().toIso8601String(),
    );
    await db.setSetting(PrefKeys.backupLastError, '');
    await db.setSetting(PrefKeys.backupPromptSeen, 'true');

    return BackupRunResult(
      directory: dir.path,
      fileNames: written,
      ledgerCount: ledgers.length,
    );
  }

  /// 启动 / 回前台：若频率未关且已到期则自动备份；失败写入 [PrefKeys.backupLastError]。
  Future<bool> maybeAutoBackup({DateTime? now}) async {
    final config = await loadConfig();
    if (!config.hasDirectory) return false;
    if (!isBackupDue(
      frequency: config.frequency,
      lastSuccessAt: config.lastSuccessAt,
      now: now ?? DateTime.now(),
    )) {
      return false;
    }
    try {
      await runBackup();
      return true;
    } catch (e) {
      await db.setSetting(PrefKeys.backupLastError, '$e');
      return false;
    }
  }
}

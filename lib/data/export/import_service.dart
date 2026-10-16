import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';

import '../db/centli_database.dart';

/// Parsed + validated centli-export JSON (export_version 1).
class ImportBundle {
  ImportBundle({
    required this.raw,
    required this.exportVersion,
    required this.schemaVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.ledger,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.merchantRules,
    required this.pendingCaptures,
    required this.fxRates,
    required this.budgets,
    required this.settings,
  });

  final Map<String, dynamic> raw;
  final int exportVersion;
  final int schemaVersion;
  final String? exportedAt;
  final String? appVersion;
  final Map<String, dynamic> ledger;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> merchantRules;
  final List<Map<String, dynamic>> pendingCaptures;
  final List<Map<String, dynamic>> fxRates;
  final List<Map<String, dynamic>> budgets;
  final Map<String, String> settings;

  String get ledgerId => '${ledger['id']}';
  String get ledgerName => '${ledger['name'] ?? ''}';
  String get baseCurrency => '${ledger['baseCurrency'] ?? ''}';
}

class ImportPreview {
  const ImportPreview({
    required this.bundle,
    required this.sourceLabel,
    this.sourceKind = 'json',
    this.warnings = const [],
  });

  final ImportBundle bundle;
  final String sourceLabel;

  /// `json` | `excel`
  final String sourceKind;

  /// Best-effort notes (e.g. Excel missing fx/settings).
  final List<String> warnings;
}

class ImportResult {
  const ImportResult({
    required this.ledgerId,
    required this.ledgerName,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.merchantRules,
    required this.pendingCaptures,
    required this.fxRates,
    required this.budgets,
    required this.settingsWritten,
  });

  final String ledgerId;
  final String ledgerName;
  final int accounts;
  final int categories;
  final int transactions;
  final int merchantRules;
  final int pendingCaptures;
  final int fxRates;
  final int budgets;
  final int settingsWritten;
}

/// Keys we never overwrite from a backup (device lock state stays local).
const _settingsSkipKeys = <String>{
  'app_lock',
  'app_lock_biometric',
};

class ImportService {
  ImportService(this.db);

  final CentliDatabase db;

  static const supportedExportVersion = 1;

  /// Parse UTF-8 JSON text into a validated [ImportBundle].
  ImportBundle parseJsonString(String text) {
    late final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw StateError('JSON 解析失败：${e.message}');
    }
    if (decoded is! Map) {
      throw StateError('根节点必须是 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);

    if (map['format'] != 'centli-export') {
      throw StateError('不是 Centli 导出文件（格式标识应为 centli-export）');
    }
    final exportVersion = _asInt(map['export_version'], 'export_version');
    if (exportVersion != supportedExportVersion) {
      throw StateError(
        '不支持的 export_version=$exportVersion（当前支持 $supportedExportVersion）',
      );
    }
    final schemaVersion = _asInt(map['schema_version'], 'schema_version');
    if (schemaVersion < 1 || schemaVersion > 4) {
      throw StateError('不支持的数据版本 schema_version=$schemaVersion');
    }

    final ledgerRaw = map['ledger'];
    if (ledgerRaw is! Map) {
      throw StateError('缺少账本信息');
    }
    final ledger = _normalizeLedger(Map<String, dynamic>.from(ledgerRaw));
    if ('${ledger['id']}'.isEmpty) {
      throw StateError('账本 ID 不能为空');
    }

    // Missing required arrays must fail before wipe (null != empty).
    for (final key in ['accounts', 'categories', 'transactions']) {
      if (!map.containsKey(key)) {
        throw StateError('missing required field: $key');
      }
    }

    final accounts = _asMapList(map['accounts'], 'accounts')
        .map(_normalizeAccount)
        .toList();
    final categories = _asMapList(map['categories'], 'categories')
        .map(_normalizeCategory)
        .toList();
    final transactions = _asMapList(map['transactions'], 'transactions')
        .map(_normalizeTransaction)
        .toList();
    final rules = _asMapList(map['merchant_rules'] ?? const <dynamic>[], 'merchant_rules')
        .map(_normalizeMerchantRule)
        .toList();
    final pending = _asMapList(map['pending_captures'] ?? const <dynamic>[], 'pending_captures')
        .map(_normalizePending)
        .toList();
    final fx = _asMapList(map['fx_rates'] ?? const <dynamic>[], 'fx_rates')
        .map(_normalizeFx)
        .toList();
    final budgetRows = _asMapList(map['budgets'] ?? const <dynamic>[], 'budgets')
        .map(_normalizeBudget)
        .toList();

    final settings = <String, String>{};
    final settingsRaw = map['settings'];
    if (settingsRaw is Map) {
      settingsRaw.forEach((k, v) {
        if (k == null) return;
        settings['$k'] = v?.toString() ?? '';
      });
    }

    // Dry-run Drift fromJson so bad rows fail before wipe.
    try {
      Ledger.fromJson(ledger);
      for (final a in accounts) {
        Account.fromJson(a);
      }
      for (final c in categories) {
        Category.fromJson(c);
      }
      for (final t in transactions) {
        Transaction.fromJson(t);
      }
      for (final r in rules) {
        MerchantRule.fromJson(r);
      }
      for (final p in pending) {
        PendingCapture.fromJson(p);
      }
      for (final f in fx) {
        FxRate.fromJson(f);
      }
      for (final b in budgetRows) {
        Budget.fromJson(b);
      }
    } catch (e) {
      throw StateError('导出字段无法映射到数据库：$e');
    }

    return ImportBundle(
      raw: map,
      exportVersion: exportVersion,
      schemaVersion: schemaVersion,
      exportedAt: map['exported_at']?.toString(),
      appVersion: map['app_version']?.toString(),
      ledger: ledger,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      merchantRules: rules,
      pendingCaptures: pending,
      fxRates: fx,
      budgets: budgetRows,
      settings: settings,
    );
  }

  Future<ImportPreview> previewFile(File file) async {
    final text = await file.readAsString();
    final bundle = parseJsonString(text);
    return ImportPreview(
      bundle: bundle,
      sourceLabel: file.uri.pathSegments.isEmpty
          ? file.path
          : file.uri.pathSegments.last,
    );
  }

  Future<ImportPreview> previewPath(String path) => previewFile(File(path));

  /// Full restore: wipe local ledger-scoped data (+ FX), insert backup.
  /// Does not touch flutter_secure_storage PIN; skips app_lock* settings.
  Future<ImportResult> restore(
    ImportBundle bundle, {
    bool replaceFxRates = true,
  }) async {
    final stats = await db.restoreFromImportBundle(
      ledgerMap: bundle.ledger,
      accountMaps: bundle.accounts,
      categoryMaps: bundle.categories,
      transactionMaps: bundle.transactions,
      merchantRuleMaps: bundle.merchantRules,
      pendingCaptureMaps: bundle.pendingCaptures,
      fxRateMaps: bundle.fxRates,
      budgetMaps: bundle.budgets,
      settingsMap: bundle.settings,
      settingsSkipKeys: _settingsSkipKeys,
      replaceFxRates: replaceFxRates,
    );
    return ImportResult(
      ledgerId: stats.ledgerId,
      ledgerName: stats.ledgerName,
      accounts: stats.accounts,
      categories: stats.categories,
      transactions: stats.transactions,
      merchantRules: stats.merchantRules,
      pendingCaptures: stats.pendingCaptures,
      fxRates: stats.fxRates,
      budgets: stats.budgets,
      settingsWritten: stats.settingsWritten,
    );
  }

  static int _asInt(Object? v, String field) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      final p = int.tryParse(v);
      if (p != null) return p;
    }
    throw StateError('$field 必须是整数');
  }

  static List<Map<String, dynamic>> _asMapList(Object? v, String field) {
    if (v == null) {
      throw StateError('$field cannot be null');
    }
    if (v is! List) {
      throw StateError('$field 必须是数组');
    }
    return [
      for (final e in v)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  static Map<String, dynamic> _normalizeLedger(Map<String, dynamic> m) {
    m.putIfAbsent('archived', () => 0);
    m.putIfAbsent('createdAt', () => DateTime.now().millisecondsSinceEpoch);
    return m;
  }

  static Map<String, dynamic> _normalizeAccount(Map<String, dynamic> m) {
    m.putIfAbsent('openingBalanceMinor', () => 0);
    m.putIfAbsent('sortOrder', () => 0);
    m.putIfAbsent('archived', () => 0);
    final ts = DateTime.now().millisecondsSinceEpoch;
    m.putIfAbsent('createdAt', () => ts);
    m.putIfAbsent('updatedAt', () => ts);
    return m;
  }

  static Map<String, dynamic> _normalizeCategory(Map<String, dynamic> m) {
    m.putIfAbsent('sortOrder', () => 0);
    m.putIfAbsent('archived', () => 0);
    m.putIfAbsent('createdAt', () => DateTime.now().millisecondsSinceEpoch);
    return m;
  }

  static Map<String, dynamic> _normalizeTransaction(Map<String, dynamic> m) {
    m.putIfAbsent('includeInStat', () => 1);
    m.putIfAbsent('includeInBudget', () => 1);
    m.putIfAbsent('source', () => 'manual');
    // Old backups may omit tags; treat as empty.
    if (!m.containsKey('tags') || m['tags'] == null) {
      m['tags'] = null;
    } else if (m['tags'] is List) {
      m['tags'] = jsonEncode(m['tags']);
    } else if (m['tags'] is! String) {
      m['tags'] = null;
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    m.putIfAbsent('createdAt', () => ts);
    m.putIfAbsent('updatedAt', () => ts);
    return m;
  }

  static Map<String, dynamic> _normalizeMerchantRule(Map<String, dynamic> m) {
    m.putIfAbsent('hitCount', () => 1);
    m.putIfAbsent('updatedAt', () => DateTime.now().millisecondsSinceEpoch);
    return m;
  }

  static Map<String, dynamic> _normalizePending(Map<String, dynamic> m) {
    m.putIfAbsent('parseOk', () => 0);
    m.putIfAbsent('status', () => 'pending');
    final ts = DateTime.now().millisecondsSinceEpoch;
    m.putIfAbsent('createdAt', () => ts);
    m.putIfAbsent('updatedAt', () => ts);
    m.putIfAbsent('rawText', () => '');
    m.putIfAbsent('sourcePkg', () => '');
    m.putIfAbsent('dedupeKey', () => m['id'] ?? 'missing-dedupe');
    return m;
  }

  static Map<String, dynamic> _normalizeFx(Map<String, dynamic> m) {
    m.putIfAbsent('updatedAt', () => DateTime.now().millisecondsSinceEpoch);
    return m;
  }

  static Map<String, dynamic> _normalizeBudget(Map<String, dynamic> m) {
    m.putIfAbsent('categoryId', () => '');
    final ts = DateTime.now().millisecondsSinceEpoch;
    m.putIfAbsent('createdAt', () => ts);
    m.putIfAbsent('updatedAt', () => ts);
    return m;
  }

  /// Best-effort restore from a Centli-exported `.xlsx`.
  ///
  /// Excel export is human-oriented: it has no `fx_rates` / `settings` sheets,
  /// and some JSON-only fields are filled with defaults. Prefer JSON for a
  /// lossless backup. See [excelRestoreLimitations].
  Future<ImportPreview> previewExcelFile(File file) async {
    final bytes = await file.readAsBytes();
    return previewExcelBytes(
      bytes,
      sourceLabel: file.uri.pathSegments.isEmpty
          ? file.path
          : file.uri.pathSegments.last,
    );
  }

  Future<ImportPreview> previewExcelBytes(
    List<int> bytes, {
    required String sourceLabel,
  }) async {
    final parsed = parseExcelBytes(bytes);
    return ImportPreview(
      bundle: parsed.bundle,
      sourceLabel: sourceLabel,
      sourceKind: 'excel',
      warnings: parsed.warnings,
    );
  }

  /// Public limitations copy for UI.
  static const excelRestoreLimitations = <String>[
    'Excel 为尽力而为还原：不含 fx_rates / settings 工作表（汇率与设置保持本机或清空后为空）。',
    '缺少的时间戳 / ledgerId / includeInBudget 等字段会用默认值补齐。',
    '完整无损备份请使用 JSON（format: centli-export）。',
  ];

  ({ImportBundle bundle, List<String> warnings}) parseExcelBytes(
    List<int> bytes,
  ) {
    late final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw StateError('无法读取 Excel：$e');
    }

    final warnings = List<String>.from(excelRestoreLimitations);
    final summary = _sheetRows(excel, 'summary');
    final summaryMap = <String, String>{};
    for (final row in summary.skip(1)) {
      if (row.isEmpty) continue;
      final k = _cellStr(row, 0);
      if (k.isEmpty) continue;
      summaryMap[k] = _cellStr(row, 1);
    }

    final format = summaryMap['format'] ?? '';
    if (format.isNotEmpty && format != 'centli-export') {
      throw StateError('不是 Centli 导出文件（摘要格式=$format）');
    }
    if (format.isEmpty) {
      warnings.add('summary 未找到 format=centli-export，仍按 Centli 表结构尽力解析。');
    }

    final ledgerId = summaryMap['ledger_id'] ?? '';
    final ledgerName = summaryMap['ledger_name'] ?? '导入账本';
    final baseCurrency = summaryMap['base_currency'] ?? 'CNY';
    if (ledgerId.isEmpty) {
      throw StateError('摘要缺少账本 ID，无法还原');
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final ledger = <String, dynamic>{
      'id': ledgerId,
      'name': ledgerName,
      'baseCurrency': baseCurrency,
      'createdAt': ts,
      'archived': 0,
    };

    final accounts = <Map<String, dynamic>>[];
    for (final row in _dataRows(excel, 'accounts')) {
      final id = _cellStr(row, 0);
      if (id.isEmpty || id == 'id') continue;
      final ccy = _cellStr(row, 3, fallback: baseCurrency);
      accounts.add({
        'id': id,
        'ledgerId': ledgerId,
        'name': _cellStr(row, 1, fallback: id),
        'type': _cellStr(row, 2, fallback: 'cash'),
        'currency': ccy,
        'openingBalanceMinor': _cellInt(row, 4),
        'archived': _cellInt(row, 6),
        'sortOrder': _cellInt(row, 7),
        'createdAt': ts,
        'updatedAt': ts,
      });
    }

    final categories = <Map<String, dynamic>>[];
    for (final row in _dataRows(excel, 'categories')) {
      final id = _cellStr(row, 0);
      if (id.isEmpty || id == 'id') continue;
      final parent = _cellStr(row, 3);
      categories.add({
        'id': id,
        'ledgerId': ledgerId,
        'kind': _cellStr(row, 1, fallback: 'out'),
        'name': _cellStr(row, 2, fallback: id),
        'parentId': parent.isEmpty ? null : parent,
        'archived': _cellInt(row, 5),
        'sortOrder': _cellInt(row, 6),
        'createdAt': ts,
      });
    }

    final transactions = <Map<String, dynamic>>[];
    for (final row in _dataRows(excel, 'transactions')) {
      final id = _cellStr(row, 0);
      if (id.isEmpty || id == 'id') continue;
      final iso = _cellStr(row, 1);
      final happenAt = _parseIsoToMs(iso) ?? ts;
      final ccy = _cellStr(row, 5, fallback: baseCurrency);
      final toAccount = _cellStr(row, 8);
      final categoryId = _cellStr(row, 10);
      final merchant = _cellStr(row, 12);
      final note = _cellStr(row, 13);
      final tags = _cellStr(row, 14);
      final fxRaw = _cellStr(row, 17);
      final toAmtRaw = _cellStr(row, 18);
      final delRaw = _cellStr(row, 19);
      transactions.add({
        'id': id,
        'ledgerId': ledgerId,
        'happenAt': happenAt,
        'type': _cellStr(row, 2, fallback: 'out'),
        'amountMinor': _cellInt(row, 3),
        'currency': ccy,
        'accountId': _cellStr(row, 6),
        'toAccountId': toAccount.isEmpty ? null : toAccount,
        'categoryId': categoryId.isEmpty ? null : categoryId,
        'merchant': merchant.isEmpty ? null : merchant,
        'note': note.isEmpty ? null : note,
        'tags': tags.isEmpty ? null : tags,
        'source': _cellStr(row, 15, fallback: 'manual'),
        'includeInStat': _cellInt(row, 16, fallback: 1),
        'includeInBudget': 1,
        'fxRate': fxRaw.isEmpty ? null : double.tryParse(fxRaw),
        'toAmountMinor': toAmtRaw.isEmpty ? null : int.tryParse(toAmtRaw),
        'deletedAt': delRaw.isEmpty ? null : int.tryParse(delRaw),
        'createdAt': ts,
        'updatedAt': ts,
      });
    }

    final pending = <Map<String, dynamic>>[];
    for (final row in _dataRows(excel, 'pending')) {
      final id = _cellStr(row, 0);
      if (id.isEmpty || id == 'id') continue;
      final iso = _cellStr(row, 7);
      final amtRaw = _cellStr(row, 3);
      final ccy = _cellStr(row, 5, fallback: 'CNY');
      final merchant = _cellStr(row, 6);
      final title = _cellStr(row, 9);
      pending.add({
        'id': id,
        'ledgerId': ledgerId,
        'status': _cellStr(row, 1, fallback: 'pending'),
        'sourcePkg': _cellStr(row, 2),
        'amountMinor': amtRaw.isEmpty ? null : int.tryParse(amtRaw),
        'currency': ccy,
        'merchant': merchant.isEmpty ? null : merchant,
        'happenAt': _parseIsoToMs(iso),
        'parseOk': _cellInt(row, 8),
        'rawTitle': title.isEmpty ? null : title,
        'rawText': _cellStr(row, 10),
        'dedupeKey': id,
        'createdAt': ts,
        'updatedAt': ts,
      });
    }

    final rules = <Map<String, dynamic>>[];
    for (final row in _dataRows(excel, 'merchant_rules')) {
      final id = _cellStr(row, 0);
      if (id.isEmpty || id == 'id') continue;
      final cat = _cellStr(row, 2);
      final acc = _cellStr(row, 4);
      rules.add({
        'id': id,
        'ledgerId': ledgerId,
        'merchantKey': _cellStr(row, 1),
        'categoryId': cat.isEmpty ? null : cat,
        'accountId': acc.isEmpty ? null : acc,
        'hitCount': _cellInt(row, 6, fallback: 1),
        'updatedAt': ts,
      });
    }

    final budgets = <Map<String, dynamic>>[];
    for (final row in _dataRows(excel, 'budgets')) {
      final id = _cellStr(row, 0);
      if (id.isEmpty || id == 'id') continue;
      budgets.add({
        'id': id,
        'ledgerId': _cellStr(row, 1, fallback: ledgerId),
        'yearMonth': _cellStr(row, 2),
        'categoryId': _cellStr(row, 3),
        'amountMinor': _cellInt(row, 5),
        'createdAt': _cellInt(row, 7, fallback: ts),
        'updatedAt': _cellInt(row, 8, fallback: ts),
      });
    }

    final map = <String, dynamic>{
      'format': 'centli-export',
      'export_version': int.tryParse(summaryMap['export_version'] ?? '') ?? 1,
      'schema_version':
          int.tryParse(summaryMap['schema_version'] ?? '') ?? 2,
      'exported_at': summaryMap['exported_at'],
      'app_version': summaryMap['app_version'],
      'ledger': ledger,
      'accounts': accounts,
      'categories': categories,
      'transactions': transactions,
      'merchant_rules': rules,
      'pending_captures': pending,
      'fx_rates': <Map<String, dynamic>>[],
      'budgets': budgets,
      'settings': <String, String>{},
    };

    final bundle = parseJsonString(jsonEncode(map));
    return (bundle: bundle, warnings: warnings);
  }

  static List<List<Data?>> _sheetRows(Excel excel, String name) {
    final sheet = excel.tables[name];
    if (sheet == null) return const [];
    return sheet.rows;
  }

  static Iterable<List<Data?>> _dataRows(Excel excel, String name) {
    final rows = _sheetRows(excel, name);
    if (rows.isEmpty) return const [];
    return rows.skip(1);
  }

  static String _cellStr(List<Data?> row, int i, {String fallback = ''}) {
    if (i < 0 || i >= row.length) return fallback;
    final raw = _cellRaw(row[i]);
    if (raw == null) return fallback;
    final s = '$raw'.trim();
    return s.isEmpty ? fallback : s;
  }

  static int _cellInt(List<Data?> row, int i, {int fallback = 0}) {
    final raw = _cellRaw(i < row.length ? row[i] : null);
    if (raw == null) return fallback;
    if (raw is int) return raw;
    if (raw is double) return raw.round();
    return int.tryParse('$raw'.trim()) ?? fallback;
  }

  static Object? _cellRaw(Data? d) {
    final v = d?.value;
    if (v == null) return null;
    if (v is TextCellValue) return v.value;
    if (v is IntCellValue) return v.value;
    if (v is DoubleCellValue) return v.value;
    if (v is BoolCellValue) return v.value;
    return v.toString();
  }

  static int? _parseIsoToMs(String iso) {
    if (iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    return dt.toUtc().millisecondsSinceEpoch;
  }
}

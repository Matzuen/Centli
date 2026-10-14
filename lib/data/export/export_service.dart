import 'dart:convert';
import 'dart:ui';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/money.dart';
import '../db/centli_database.dart';

/// Options for a ledger export.
class ExportOptions {
  const ExportOptions({
    this.includeDeleted = false,
    this.includePending = true,
    this.wantJson = true,
    this.wantExcel = true,
  });

  final bool includeDeleted;
  final bool includePending;
  final bool wantJson;
  final bool wantExcel;
}

/// Result paths written under app documents/exports/.
class ExportResult {
  const ExportResult({this.jsonFile, this.excelFile});

  final File? jsonFile;
  final File? excelFile;

  List<File> get files => [
        ?jsonFile,
        ?excelFile,
      ];
}

class ExportService {
  ExportService(this.db);

  final CentliDatabase db;

  static const exportVersion = 1;
  static const appVersion = '1.0.0+1';

  Future<Map<String, dynamic>> buildBundle({
    required String ledgerId,
    required ExportOptions options,
  }) async {
    final ledger = await db.getLedger(ledgerId);
    if (ledger == null) {
      throw StateError('ledger not found: $ledgerId');
    }

    final accounts = await db.loadAllAccounts(ledgerId);
    final categories = await db.loadAllCategories(ledgerId);
    final txns = await db.loadTransactionsForExport(
      ledgerId,
      includeDeleted: options.includeDeleted,
    );
    final rules = await db.loadMerchantRules(ledgerId);
    final fx = await db.loadAllFxRates();
    final settings = await db.loadAllSettings();
    final budgetRows = await db.loadBudgetsForExport(ledgerId);
    final pending = options.includePending
        ? await db.loadPendingCapturesForExport(ledgerId)
        : <PendingCapture>[];

    return <String, dynamic>{
      'format': 'centli-export',
      'export_version': exportVersion,
      'schema_version': 2,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': appVersion,
      'ledger': ledger.toJson(),
      'accounts': accounts.map((e) => e.toJson()).toList(),
      'categories': categories.map((e) => e.toJson()).toList(),
      'transactions': txns.map((e) => e.toJson()).toList(),
      'merchant_rules': rules.map((e) => e.toJson()).toList(),
      'pending_captures': pending.map((e) => e.toJson()).toList(),
      'fx_rates': fx.map((e) => e.toJson()).toList(),
      'budgets': budgetRows.map((e) => e.toJson()).toList(),
      'settings': settings,
    };
  }

  Future<ExportResult> exportAndShare({
    required String ledgerId,
    required ExportOptions options,
    Rect? shareOrigin,
  }) async {
    if (!options.wantJson && !options.wantExcel) {
      throw ArgumentError('select at least one format');
    }

    final bundle = await buildBundle(ledgerId: ledgerId, options: options);
    final stamp = _fileStamp();
    final ledgerName = _safeName(
      (bundle['ledger'] as Map)['name']?.toString() ?? 'ledger',
    );

    final dir = await _exportsDir();
    File? jsonFile;
    File? excelFile;

    if (options.wantJson) {
      final path = p.join(dir.path, 'centli_${ledgerName}_$stamp.json');
      jsonFile = File(path);
      await jsonFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundle),
        flush: true,
      );
    }

    if (options.wantExcel) {
      final path = p.join(dir.path, 'centli_${ledgerName}_$stamp.xlsx');
      excelFile = File(path);
      final bytes = _buildExcel(bundle);
      await excelFile.writeAsBytes(bytes, flush: true);
    }

    final result = ExportResult(jsonFile: jsonFile, excelFile: excelFile);
    await shareFiles(result.files, shareOrigin: shareOrigin);
    return result;
  }

  Future<void> shareFiles(List<File> files, {Rect? shareOrigin}) async {
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [
          for (final f in files)
            XFile(
              f.path,
              mimeType: f.path.endsWith('.xlsx')
                  ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                  : 'application/json',
              name: p.basename(f.path),
            ),
        ],
        subject: 'Centli export',
        text: 'Centli \u5bfc\u51fa',
        sharePositionOrigin: shareOrigin,
      ),
    );
  }

  Future<Directory> _exportsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'exports'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _fileStamp() {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${two(n.month)}${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
  }

  String _safeName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\w\u4e00-\u9fff\-]+'), '_');
    if (cleaned.isEmpty) return 'ledger';
    return cleaned.length > 32 ? cleaned.substring(0, 32) : cleaned;
  }

  /// Public for restore tests / callers that already have a bundle map.
  List<int> buildExcelBytes(Map<String, dynamic> bundle) => _buildExcel(bundle);

  List<int> _buildExcel(Map<String, dynamic> bundle) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';

    // summary
    excel.rename(defaultSheet, 'summary');
    final summary = excel['summary'];
    final ledger = Map<String, dynamic>.from(bundle['ledger'] as Map);
    final accounts = (bundle['accounts'] as List).cast<Map>();
    final categories = (bundle['categories'] as List).cast<Map>();
    final txns = (bundle['transactions'] as List).cast<Map>();
    final pending = (bundle['pending_captures'] as List).cast<Map>();
    final rules = (bundle['merchant_rules'] as List).cast<Map>();
    final budgetList = (bundle['budgets'] as List? ?? const []).cast<Map>();

    void row(Sheet sheet, List<CellValue> cells) {
      sheet.appendRow(cells);
    }

    row(summary, [
      TextCellValue('key'),
      TextCellValue('value'),
    ]);
    row(summary, [
      TextCellValue('format'),
      TextCellValue('${bundle['format']}'),
    ]);
    row(summary, [
      TextCellValue('export_version'),
      IntCellValue(bundle['export_version'] as int),
    ]);
    row(summary, [
      TextCellValue('schema_version'),
      IntCellValue(bundle['schema_version'] as int),
    ]);
    row(summary, [
      TextCellValue('exported_at'),
      TextCellValue('${bundle['exported_at']}'),
    ]);
    row(summary, [
      TextCellValue('app_version'),
      TextCellValue('${bundle['app_version']}'),
    ]);
    row(summary, [
      TextCellValue('ledger_id'),
      TextCellValue('${ledger['id']}'),
    ]);
    row(summary, [
      TextCellValue('ledger_name'),
      TextCellValue('${ledger['name']}'),
    ]);
    row(summary, [
      TextCellValue('base_currency'),
      TextCellValue('${ledger['baseCurrency']}'),
    ]);
    row(summary, [
      TextCellValue('accounts'),
      IntCellValue(accounts.length),
    ]);
    row(summary, [
      TextCellValue('categories'),
      IntCellValue(categories.length),
    ]);
    row(summary, [
      TextCellValue('transactions'),
      IntCellValue(txns.length),
    ]);
    row(summary, [
      TextCellValue('pending_captures'),
      IntCellValue(pending.length),
    ]);
    row(summary, [
      TextCellValue('merchant_rules'),
      IntCellValue(rules.length),
    ]);
    row(summary, [
      TextCellValue('budgets'),
      IntCellValue(budgetList.length),
    ]);

    final accountName = <String, String>{
      for (final a in accounts) '${a['id']}': '${a['name']}',
    };
    final categoryName = <String, String>{
      for (final c in categories) '${c['id']}': '${c['name']}',
    };

    // accounts
    final accSheet = excel['accounts'];
    row(accSheet, [
      TextCellValue('id'),
      TextCellValue('name'),
      TextCellValue('type'),
      TextCellValue('currency'),
      TextCellValue('opening_balance_minor'),
      TextCellValue('opening_balance'),
      TextCellValue('archived'),
      TextCellValue('sort_order'),
    ]);
    for (final a in accounts) {
      final ccy = '${a['currency']}';
      final minor = a['openingBalanceMinor'] as int? ?? 0;
      row(accSheet, [
        TextCellValue('${a['id']}'),
        TextCellValue('${a['name']}'),
        TextCellValue('${a['type']}'),
        TextCellValue(ccy),
        IntCellValue(minor),
        DoubleCellValue(fromMinor(ccy, minor)),
        IntCellValue(a['archived'] as int? ?? 0),
        IntCellValue(a['sortOrder'] as int? ?? 0),
      ]);
    }

    // categories
    final catSheet = excel['categories'];
    row(catSheet, [
      TextCellValue('id'),
      TextCellValue('kind'),
      TextCellValue('name'),
      TextCellValue('parent_id'),
      TextCellValue('parent_name'),
      TextCellValue('archived'),
      TextCellValue('sort_order'),
    ]);
    for (final c in categories) {
      final parentId = c['parentId']?.toString();
      row(catSheet, [
        TextCellValue('${c['id']}'),
        TextCellValue('${c['kind']}'),
        TextCellValue('${c['name']}'),
        TextCellValue(parentId ?? ''),
        TextCellValue(
          parentId == null ? '' : (categoryName[parentId] ?? ''),
        ),
        IntCellValue(c['archived'] as int? ?? 0),
        IntCellValue(c['sortOrder'] as int? ?? 0),
      ]);
    }

    // transactions
    final txnSheet = excel['transactions'];
    row(txnSheet, [
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
      TextCellValue('source'),
      TextCellValue('include_in_stat'),
      TextCellValue('fx_rate'),
      TextCellValue('to_amount_minor'),
      TextCellValue('deleted_at'),
    ]);
    for (final t in txns) {
      final ccy = '${t['currency']}';
      final minor = t['amountMinor'] as int? ?? 0;
      final happenAt = t['happenAt'] as int? ?? 0;
      final iso = DateTime.fromMillisecondsSinceEpoch(happenAt, isUtc: true)
          .toLocal()
          .toIso8601String();
      final accountId = '${t['accountId']}';
      final toAccountId = t['toAccountId']?.toString();
      final categoryId = t['categoryId']?.toString();
      final fx = t['fxRate'];
      row(txnSheet, [
        TextCellValue('${t['id']}'),
        TextCellValue(iso),
        TextCellValue('${t['type']}'),
        IntCellValue(minor),
        DoubleCellValue(fromMinor(ccy, minor)),
        TextCellValue(ccy),
        TextCellValue(accountId),
        TextCellValue(accountName[accountId] ?? ''),
        TextCellValue(toAccountId ?? ''),
        TextCellValue(
          toAccountId == null ? '' : (accountName[toAccountId] ?? ''),
        ),
        TextCellValue(categoryId ?? ''),
        TextCellValue(
          categoryId == null ? '' : (categoryName[categoryId] ?? ''),
        ),
        TextCellValue('${t['merchant'] ?? ''}'),
        TextCellValue('${t['note'] ?? ''}'),
        TextCellValue('${t['source'] ?? ''}'),
        IntCellValue(t['includeInStat'] as int? ?? 1),
        fx == null ? TextCellValue('') : DoubleCellValue((fx as num).toDouble()),
        t['toAmountMinor'] == null
            ? TextCellValue('')
            : IntCellValue(t['toAmountMinor'] as int),
        t['deletedAt'] == null
            ? TextCellValue('')
            : IntCellValue(t['deletedAt'] as int),
      ]);
    }

    // pending
    final pendSheet = excel['pending'];
    row(pendSheet, [
      TextCellValue('id'),
      TextCellValue('status'),
      TextCellValue('source_pkg'),
      TextCellValue('amount_minor'),
      TextCellValue('amount'),
      TextCellValue('currency'),
      TextCellValue('merchant'),
      TextCellValue('happen_at_iso'),
      TextCellValue('parse_ok'),
      TextCellValue('raw_title'),
      TextCellValue('raw_text'),
    ]);
    for (final c in pending) {
      final ccy = '${c['currency'] ?? 'CNY'}';
      final minor = c['amountMinor'] as int?;
      final happenAt = c['happenAt'] as int?;
      final iso = happenAt == null
          ? ''
          : DateTime.fromMillisecondsSinceEpoch(happenAt, isUtc: true)
              .toLocal()
              .toIso8601String();
      row(pendSheet, [
        TextCellValue('${c['id']}'),
        TextCellValue('${c['status']}'),
        TextCellValue('${c['sourcePkg']}'),
        minor == null ? TextCellValue('') : IntCellValue(minor),
        minor == null
            ? TextCellValue('')
            : DoubleCellValue(fromMinor(ccy, minor)),
        TextCellValue(ccy),
        TextCellValue('${c['merchant'] ?? ''}'),
        TextCellValue(iso),
        IntCellValue(c['parseOk'] as int? ?? 0),
        TextCellValue('${c['rawTitle'] ?? ''}'),
        TextCellValue('${c['rawText'] ?? ''}'),
      ]);
    }

    // merchant_rules
    final ruleSheet = excel['merchant_rules'];
    row(ruleSheet, [
      TextCellValue('id'),
      TextCellValue('merchant_key'),
      TextCellValue('category_id'),
      TextCellValue('category_name'),
      TextCellValue('account_id'),
      TextCellValue('account_name'),
      TextCellValue('hit_count'),
    ]);
    for (final r in rules) {
      final categoryId = r['categoryId']?.toString();
      final accountId = r['accountId']?.toString();
      row(ruleSheet, [
        TextCellValue('${r['id']}'),
        TextCellValue('${r['merchantKey']}'),
        TextCellValue(categoryId ?? ''),
        TextCellValue(
          categoryId == null ? '' : (categoryName[categoryId] ?? ''),
        ),
        TextCellValue(accountId ?? ''),
        TextCellValue(
          accountId == null ? '' : (accountName[accountId] ?? ''),
        ),
        IntCellValue(r['hitCount'] as int? ?? 0),
      ]);
    }


    // budgets
    final baseCcy = '${ledger['baseCurrency'] ?? 'CNY'}';
    final budgetSheet = excel['budgets'];
    row(budgetSheet, [
      TextCellValue('id'),
      TextCellValue('ledger_id'),
      TextCellValue('year_month'),
      TextCellValue('category_id'),
      TextCellValue('category_name'),
      TextCellValue('amount_minor'),
      TextCellValue('amount'),
      TextCellValue('created_at'),
      TextCellValue('updated_at'),
    ]);
    for (final b in budgetList) {
      final categoryId = '${b['categoryId'] ?? ''}';
      final minor = b['amountMinor'] as int? ?? 0;
      final catLabel = categoryId.isEmpty
          ? '\u603b\u989d'
          : (categoryName[categoryId] ?? '');
      row(budgetSheet, [
        TextCellValue('${b['id']}'),
        TextCellValue('${b['ledgerId']}'),
        TextCellValue('${b['yearMonth']}'),
        TextCellValue(categoryId),
        TextCellValue(catLabel),
        IntCellValue(minor),
        DoubleCellValue(fromMinor(baseCcy, minor)),
        IntCellValue(b['createdAt'] as int? ?? 0),
        IntCellValue(b['updatedAt'] as int? ?? 0),
      ]);
    }

    final saved = excel.save();
    if (saved == null) {
      throw StateError('excel.save returned null');
    }
    return List<int>.from(saved);
  }
}

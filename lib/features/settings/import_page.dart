import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/export/import_service.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key});

  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

enum _ImportMode { overwrite, merge }

class _ImportPageState extends ConsumerState<ImportPage> {
  ImportPreview? _preview;
  bool _busy = false;
  String? _error;
  _ImportMode _mode = _ImportMode.overwrite;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'xlsx'],
      );
      if (files.isEmpty) {
        return;
      }
      final picked = files.single;
      final svc = ImportService(ref.read(databaseProvider));
      ImportPreview preview;
      final name = picked.name.toLowerCase();
      final path = picked.path;
      final isExcel = name.endsWith('.xlsx');

      if (isExcel) {
        if (path != null && path.isNotEmpty) {
          preview = await svc.previewExcelFile(File(path));
        } else {
          final bytes = await picked.readAsBytes();
          preview = await svc.previewExcelBytes(
            bytes,
            sourceLabel: picked.name,
          );
        }
      } else if (path != null && path.isNotEmpty) {
        preview = await svc.previewPath(path);
      } else {
        final bytes = await picked.readAsBytes();
        final decoded = utf8.decode(bytes);
        final bundle = svc.parseJsonString(decoded);
        preview = ImportPreview(
          bundle: bundle,
          sourceLabel: picked.name,
          warnings: svc.schemaWarningsFor(bundle),
        );
      }
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _error = '$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final preview = _preview;
    if (preview == null || _busy) return;

    final b = preview.bundle;
    final mergeMode = _mode == _ImportMode.merge;
    if (b.schemaVersion < ImportService.latestSchemaVersion) {
      final proceed = await showGlassDialog<bool>(
        context: context,
        builder: (ctx) => CentliGlassDialog(
          title: const Text('低版本备份'),
          content: Text(
            '备份 schema_version=${b.schemaVersion} 低于当前 '
            '${ImportService.latestSchemaVersion}，部分字段可能缺失。仍要继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: Text(mergeMode ? '确认合并导入？' : '确认还原？'),
        content: Text(
          mergeMode
              ? '将向记账本「${b.ledgerName}」追加备份中本地尚不存在的账户、分类、流水等（按 id 跳过已有）。'
                  '不会清空本机已有数据。\n\n'
                  '通知识别规则与应用锁 PIN 不受影响。'
              : '将清空本机记账本「${b.ledgerName}」下的资产账户、分类、流水、待确认、商户规则与预算，'
                  '再写入备份内容。其它记账本不受影响。\n\n'
                  '${preview.sourceKind == 'excel'
                      ? 'Excel 不含汇率：本机汇率缓存会保留。\n\n'
                      : '汇率缓存会按备份整体替换（全局）。\n\n'}'
                  '通知识别规则（我的规则）不在此备份范围内，不会被清空或覆盖。\n'
                  '本机 PIN 与应用锁开关也不会从备份覆盖。\n\n'
                  '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(mergeMode ? '合并追加' : '清空并还原'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = ImportService(ref.read(databaseProvider));
      final result = mergeMode
          ? await svc.merge(
              b,
              mergeFxRates: preview.sourceKind != 'excel',
            )
          : await svc.restore(
              b,
              replaceFxRates: preview.sourceKind != 'excel',
            );
      ref.invalidate(currentLedgerIdProvider);
      ref.invalidate(currentLedgerProvider);
      ref.invalidate(fxBookProvider);
      ref.invalidate(onboardingDoneProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${mergeMode ? '已合并' : '已还原'}「${result.ledgerName}」：'
            '${result.transactions} 笔流水 / '
            '${result.accounts} 资产账户 / '
            '${result.categories} 分类 / '
            '${result.budgets} 预算',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${mergeMode ? '合并' : '还原'}失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final scheme = Theme.of(context).colorScheme;
    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('\u5bfc\u5165 / \u8fd8\u539f')),
      body: ListView(
        padding: CentliSpacing.pagePadding,
        children: [
          Text(
            '\u4ece\u672c\u673a\u9009\u62e9 Centli \u5bfc\u51fa\u6587\u4ef6\uff1aJSON\uff08\u5b8c\u6574\uff09\u6216 Excel .xlsx\uff08\u5c3d\u529b\u800c\u4e3a\uff09\u3002'
            '\u9884\u89c8\u540e\u53ef\u4e00\u952e\u8fd8\u539f\u3002Excel \u4e0d\u542b\u6c47\u7387/\u8bbe\u7f6e\uff0c\u5efa\u8bae\u4f18\u5148\u4f7f\u7528 JSON\u3002',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: CentliSpacing.section),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pick,
            icon: _busy && preview == null
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open),
            label: Text(
              _busy && preview == null
                  ? '\u8bfb\u53d6\u4e2d\u2026'
                  : '\u9009\u62e9 JSON / Excel \u6587\u4ef6',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: CentliSpacing.item),
            Text(
              _error!,
              style: TextStyle(color: scheme.error),
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: CentliSpacing.section),
            CentliSoftCard(
              child: Column(
                children: [
                  ListTile(
                    title: const Text('\u6587\u4ef6'),
                    subtitle: Text(
                      '${preview.sourceLabel}\n'
                      '\u6765\u6e90: ${preview.sourceKind == 'excel' ? 'Excel (\u5c3d\u529b\u800c\u4e3a)' : 'JSON'}',
                    ),
                    isThreeLine: true,
                  ),
                  if (preview.warnings.isNotEmpty) ...[
                    const Divider(height: 1, indent: 16),
                    Padding(
                      padding: const EdgeInsets.all(CentliSpacing.cardPad),
                      child: Text(
                        preview.warnings.map((w) => '\u2022 $w').join('\n'),
                        style: TextStyle(
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    title: const Text('\u8d26\u672c'),
                    subtitle: Text(
                      '${preview.bundle.ledgerName} \u00b7 ${preview.bundle.baseCurrency}\n'
                      '\u8d26\u672c ID\uff1a${preview.bundle.ledgerId}',
                    ),
                    isThreeLine: true,
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    title: const Text('\u5907\u4efd\u4fe1\u606f'),
                    subtitle: Text(
                      '\u5bfc\u51fa\u683c\u5f0f v${preview.bundle.exportVersion} \u00b7 '
                      '\u5e93\u7248\u672c ${preview.bundle.schemaVersion}\n'
                      '\u5bfc\u51fa\u65f6\u95f4\uff1a${preview.bundle.exportedAt ?? '\u2014'}\n'
                      '\u6765\u6e90\u5e94\u7528\uff1a${preview.bundle.appVersion ?? '\u2014'}',
                    ),
                    isThreeLine: true,
                  ),
                  const Divider(height: 1, indent: 16),
                  ListTile(
                    title: const Text('\u5185\u5bb9\u7edf\u8ba1'),
                    subtitle: Text(
                      '\u8d44\u4ea7\u8d26\u6237 ${preview.bundle.accounts.length} \u00b7 '
                      '\u5206\u7c7b ${preview.bundle.categories.length} \u00b7 '
                      '\u6d41\u6c34 ${preview.bundle.transactions.length}\n'
                      '\u5f85\u786e\u8ba4 ${preview.bundle.pendingCaptures.length} \u00b7 '
                      '\u89c4\u5219 ${preview.bundle.merchantRules.length} \u00b7 '
                      '\u6c47\u7387 ${preview.bundle.fxRates.length} \u00b7 '
                      '\u9884\u7b97 ${preview.bundle.budgets.length} \u00b7 '
                      '\u8bbe\u7f6e\u952e ${preview.bundle.settings.length}',
                    ),
                    isThreeLine: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: CentliSpacing.section),
            Text('导入模式', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: CentliSpacing.item),
            SegmentedButton<_ImportMode>(
              segments: const [
                ButtonSegment(
                  value: _ImportMode.overwrite,
                  label: Text('覆盖当前账本'),
                  icon: Icon(Icons.restore, size: 18),
                ),
                ButtonSegment(
                  value: _ImportMode.merge,
                  label: Text('合并追加'),
                  icon: Icon(Icons.merge_type, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: CentliSpacing.item),
            Text(
              _mode == _ImportMode.merge
                  ? '合并：只插入本地尚不存在的记录（按 id），不删除已有数据。'
                  : '覆盖：清空该记账本本地数据后写入备份。应用锁 PIN 保留在本机安全存储中。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: CentliSpacing.section),
            FilledButton.icon(
              onPressed: _busy ? null : _restore,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _mode == _ImportMode.merge
                          ? Icons.merge_type
                          : Icons.restore,
                    ),
              label: Text(
                _busy
                    ? (_mode == _ImportMode.merge ? '合并中…' : '还原中…')
                    : (_mode == _ImportMode.merge ? '合并追加' : '清空并还原'),
              ),
            ),
          ],
          const SizedBox(height: CentliSpacing.sectionLoose),
        ],
      ),
    );
  }

}

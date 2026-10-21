import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/export/export_service.dart';
import '../../app/theme.dart';

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});

  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  bool _wantJson = true;
  bool _wantExcel = true;
  bool _includePending = true;
  bool _includeDeleted = false;
  bool _busy = false;

  Future<void> _run() async {
    if (!_wantJson && !_wantExcel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u81f3\u5c11\u9009\u62e9\u4e00\u79cd\u683c\u5f0f\uff08JSON \u6216 Excel\uff09'),
        ),
      );
      return;
    }

    final ledgerId = await ref.read(currentLedgerIdProvider.future);
    if (ledgerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8d26\u672c\u672a\u521d\u59cb\u5316')),
      );
      return;
    }

    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    setState(() => _busy = true);
    try {
      final svc = ExportService(ref.read(databaseProvider));
      final result = await svc.exportAndShare(
        ledgerId: ledgerId,
        options: ExportOptions(
          wantJson: _wantJson,
          wantExcel: _wantExcel,
          includePending: _includePending,
          includeDeleted: _includeDeleted,
        ),
        shareOrigin: origin,
      );

      if (!mounted) return;
      final names = result.files.map((f) => f.uri.pathSegments.last).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            names.isEmpty
                ? '\u5bfc\u51fa\u5b8c\u6210'
                : '\u5df2\u751f\u6210\u5e76\u5206\u4eab\uff1a$names',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('\u5bfc\u51fa\u5931\u8d25\uff1a$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('导出')),
      body: ListView(
        padding: CentliSpacing.pagePadding,
        children: [
          Text(
            '导出当前记账本为文件并打开系统分享。还原请到「我的 → 导入」。本页仅导出并分享，不会清空本机数据。\n'
            '不含通知识别规则（我的规则请在「自动记账 → 识别规则」单独导出）。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: CentliSpacing.section),
          CentliSoftCard(
            child: Column(
              children: [
                const ListTile(
                  title: Text('格式'),
                  subtitle: Text('JSON = 完整备份（可还原）；Excel = 表格查看'),
                ),
                SwitchListTile(
                  title: const Text('JSON 备份'),
                  subtitle: const Text('完整数据包（centli-export 格式）'),
                  value: _wantJson,
                  onChanged: _busy ? null : (v) => setState(() => _wantJson = v),
                ),
                SwitchListTile(
                  title: const Text('Excel 表格（.xlsx）'),
                  subtitle: const Text(
                    '含摘要、资产账户、分类、流水、待确认、商户规则、预算等工作表',
                  ),
                  value: _wantExcel,
                  onChanged: _busy ? null : (v) => setState(() => _wantExcel = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: CentliSpacing.section),
          CentliSoftCard(
            child: Column(
              children: [
                const ListTile(title: Text('选项')),
                SwitchListTile(
                  title: const Text('包含待确认/忽略通知'),
                  value: _includePending,
                  onChanged:
                      _busy ? null : (v) => setState(() => _includePending = v),
                ),
                SwitchListTile(
                  title: const Text('包含已删除流水'),
                  subtitle: const Text('默认不导出软删除记录'),
                  value: _includeDeleted,
                  onChanged:
                      _busy ? null : (v) => setState(() => _includeDeleted = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: CentliSpacing.sectionLoose),
          Padding(
            padding: EdgeInsets.zero,
            child: FilledButton.icon(
              onPressed: _busy ? null : _run,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share),
              label: Text(_busy ? '\u5bfc\u51fa\u4e2d\u2026' : '\u5bfc\u51fa\u5e76\u5206\u4eab'),
            ),
          ),
          const SizedBox(height: CentliSpacing.section),
        ],
      ),
    );
  }
}

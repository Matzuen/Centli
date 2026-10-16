import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../../data/export/export_service.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('\u5bfc\u51fa')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '\u5bfc\u51fa\u5f53\u524d\u8d26\u672c\u6570\u636e\u4e3a\u6587\u4ef6\uff0c\u5e76\u6253\u5f00\u7cfb\u7edf\u5206\u4eab\u3002'
              '\u8fd8\u539f\u8bf7\u5230\u300c\u6211\u7684 \u2192 \u5bfc\u5165\u300d\u3002\u672c\u9875\u4ec5\u5bfc\u51fa\u5e76\u5206\u4eab\u3002',
              style: TextStyle(height: 1.4),
            ),
          ),
          const Divider(),
          const ListTile(
            title: Text('\u683c\u5f0f'),
            subtitle: Text('JSON = \u5907\u4efd/\u53ef\u8bfb\u53d6\uff1bExcel = \u8868\u683c\u67e5\u770b'),
          ),
          SwitchListTile(
            title: const Text('JSON 备份'),
            subtitle: const Text('\u5b8c\u6574\u6570\u636e\u5305\uff08centli-export \u683c\u5f0f\uff09'),
            value: _wantJson,
            onChanged: _busy ? null : (v) => setState(() => _wantJson = v),
          ),
          SwitchListTile(
            title: const Text('Excel 表格（.xlsx）'),
            subtitle: const Text(
              '\u542b\u6458\u8981\u3001\u8d26\u6237\u3001\u5206\u7c7b\u3001\u6d41\u6c34\u3001\u5f85\u786e\u8ba4\u3001\u5546\u6237\u89c4\u5219\u3001\u9884\u7b97\u7b49\u5de5\u4f5c\u8868',
            ),
            value: _wantExcel,
            onChanged: _busy ? null : (v) => setState(() => _wantExcel = v),
          ),
          const Divider(),
          const ListTile(title: Text('\u9009\u9879')),
          SwitchListTile(
            title: const Text('\u5305\u542b\u5f85\u786e\u8ba4/\u5ffd\u7565\u901a\u77e5'),
            value: _includePending,
            onChanged:
                _busy ? null : (v) => setState(() => _includePending = v),
          ),
          SwitchListTile(
            title: const Text('\u5305\u542b\u5df2\u5220\u9664\u6d41\u6c34'),
            subtitle: const Text('\u9ed8\u8ba4\u4e0d\u5bfc\u51fa\u8f6f\u5220\u9664\u8bb0\u5f55'),
            value: _includeDeleted,
            onChanged:
                _busy ? null : (v) => setState(() => _includeDeleted = v),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

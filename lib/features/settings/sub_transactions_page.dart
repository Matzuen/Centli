import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/glass.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';

final subTransactionTypesProvider =
    StreamProvider<List<SubTransactionType>>((ref) {
  return ref.watch(databaseProvider).watchSubTransactionTypes();
});

/// 我的 · 通用 · 子交易管理：全局类型模板（适用于全部交易）。
class SubTransactionsPage extends ConsumerWidget {
  const SubTransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(subTransactionTypesProvider);
    final scheme = Theme.of(context).colorScheme;

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('子交易管理'),
        actions: [
          IconButton(
            tooltip: '添加',
            icon: const Icon(Icons.add),
            onPressed: () => _promptCreate(context, ref),
          ),
          IconButton(
            tooltip: '说明',
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfo(context),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (types) {
          if (types.isEmpty) {
            return Center(
              child: Text(
                '暂无子交易类型，点右上角 + 添加',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  '适用于全部交易',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              CentliSoftCard(
                clipBehavior: Clip.antiAlias,
                padding: EdgeInsets.zero,
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: types.length,
                  onReorderItem: (oldIndex, newIndex) async {
                    final list = List<SubTransactionType>.from(types);
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    await ref
                        .read(databaseProvider)
                        .reorderSubTransactionTypes(
                          list.map((e) => e.id).toList(),
                        );
                  },
                  itemBuilder: (context, index) {
                    final t = types[index];
                    final positive = t.sign >= 0;
                    return ListTile(
                      key: ValueKey(t.id),
                      leading: _SignBadge(positive: positive),
                      title: Text(t.name),
                      trailing: ReorderableDragStartListener(
                        index: index,
                        child: Icon(
                          Icons.drag_handle,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () => _promptEdit(context, ref, t),
                      onLongPress: () => _confirmDelete(context, ref, t),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showInfo(BuildContext context) {
    return showGlassDialog<void>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('子交易'),
        content: const Text(
          '子交易挂在某笔流水下，用于 AA、退款、手续费等附加进出。'
          '这里配置的类型会在流水详情「可选操作」与记一笔「附加」中出现。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _promptCreate(BuildContext context, WidgetRef ref) async {
    final result = await _editTypeSheet(context);
    if (result == null) return;
    await ref.read(databaseProvider).insertSubTransactionType(
          name: result.name,
          sign: result.sign,
        );
  }

  Future<void> _promptEdit(
    BuildContext context,
    WidgetRef ref,
    SubTransactionType type,
  ) async {
    final result = await _editTypeSheet(
      context,
      initialName: type.name,
      initialSign: type.sign,
      allowDelete: true,
    );
    if (result == null) return;
    if (result.delete) {
      await ref.read(databaseProvider).softDeleteSubTransactionType(type.id);
      return;
    }
    await ref.read(databaseProvider).updateSubTransactionType(
          id: type.id,
          name: result.name,
          sign: result.sign,
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SubTransactionType type,
  ) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: Text('删除「${type.name}」？'),
        content: const Text('已挂到流水上的子交易不会删除，仅从可选类型中移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: centliDangerFilledStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(databaseProvider).softDeleteSubTransactionType(type.id);
    }
  }
}

class _SignBadge extends StatelessWidget {
  const _SignBadge({required this.positive});

  final bool positive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = positive ? CentliTheme.incomeGreen : CentliTheme.expenseRed;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(
        positive ? Icons.add : Icons.remove,
        size: 18,
        color: color,
        shadows: [
          Shadow(color: scheme.shadow.withValues(alpha: 0.08), blurRadius: 2),
        ],
      ),
    );
  }
}

class _TypeEditResult {
  const _TypeEditResult({
    required this.name,
    required this.sign,
    this.delete = false,
  });

  final String name;
  final int sign;
  final bool delete;
}

Future<_TypeEditResult?> _editTypeSheet(
  BuildContext context, {
  String initialName = '',
  int initialSign = 1,
  bool allowDelete = false,
}) {
  return showGlassSheet<_TypeEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _TypeEditBody(
      initialName: initialName,
      initialSign: initialSign,
      allowDelete: allowDelete,
    ),
  );
}

class _TypeEditBody extends StatefulWidget {
  const _TypeEditBody({
    required this.initialName,
    required this.initialSign,
    required this.allowDelete,
  });

  final String initialName;
  final int initialSign;
  final bool allowDelete;

  @override
  State<_TypeEditBody> createState() => _TypeEditBodyState();
}

class _TypeEditBodyState extends State<_TypeEditBody> {
  late final TextEditingController _nameCtrl;
  late int _sign;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _sign = widget.initialSign >= 0 ? 1 : -1;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.initialName.isEmpty ? '新建子交易类型' : '编辑子交易类型',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '名称',
              hintText: '如 AA、手续费',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 1, label: Text('增加 (+)')),
              ButtonSegment(value: -1, label: Text('减少 (−)')),
            ],
            selected: {_sign},
            onSelectionChanged: (s) => setState(() => _sign = s.first),
          ),
          const SizedBox(height: 20),
          CentliFormActionBar(
            onCancel: () => Navigator.pop(context),
            onConfirm: _submit,
          ),
          if (widget.allowDelete) ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(
                context,
                const _TypeEditResult(name: '', sign: 1, delete: true),
              ),
              child: const Text('删除'),
            ),
          ],
        ],
      ),
    );
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showGlassSnackBar(context, '请输入名称');
      return;
    }
    Navigator.pop(context, _TypeEditResult(name: name, sign: _sign));
  }
}

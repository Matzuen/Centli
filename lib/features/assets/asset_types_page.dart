import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/widgets/centli_icon.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../core/widgets/glass.dart';

final _assetTypesManageProvider =
    StreamProvider.family<List<AssetType>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchAssetTypes(
        ledgerId,
        includeArchived: true,
      );
});

/// Manage per-ledger asset categories (name / icon / count / sort / archive / delete).
class AssetTypesPage extends ConsumerWidget {
  const AssetTypesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerIdProvider);

    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('资产分类')),
      floatingActionButton: ledgerAsync.valueOrNull == null
          ? null
          : FloatingActionButton(
              tooltip: '新增分类',
              onPressed: () => _promptCreate(context, ref, ledgerAsync.valueOrNull!),
              child: const Icon(Icons.add_rounded),
            ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledgerId) {
          if (ledgerId == null) {
            return const Center(child: Text('尚未初始化记账本'));
          }
          final typesAsync = ref.watch(_assetTypesManageProvider(ledgerId));
          return typesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (types) {
              if (types.isEmpty) {
                return const Center(child: Text('暂无分类'));
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                itemCount: types.length,
                separatorBuilder: (_, _) => const SizedBox(height: CentliSpacing.item),
                itemBuilder: (context, index) {
                  final t = types[index];
                  return _AssetTypeTile(
                    type: t,
                    index: index,
                    total: types.length,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AssetTypeTile extends ConsumerWidget {
  const _AssetTypeTile({
    required this.type,
    required this.index,
    required this.total,
  });

  final AssetType type;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return FutureBuilder<int>(
      future: db.countAccountsForAssetType(type.id),
      builder: (context, snap) {
        final count = snap.data ?? 0;
        final archived = type.archived != 0;
        final scheme = Theme.of(context).colorScheme;
        return CentliSoftCard(
          child: ListTile(
            leading: CentliIconChip(
              name: type.name,
              iconKey: type.icon,
              size: 40,
              roundedSquare: true,
            ),
            title: Text(type.name),
            subtitle: Text(
              archived
                  ? '已归档 · $count 个资产账户'
                  : '$count 个资产账户在用',
              style: TextStyle(
                color: archived ? scheme.outline : null,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '上移',
                  onPressed: index <= 0
                      ? null
                      : () async {
                          await db.reorderAssetType(type.id, up: true);
                        },
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
                IconButton(
                  tooltip: '下移',
                  onPressed: index >= total - 1
                      ? null
                      : () async {
                          await db.reorderAssetType(type.id, up: false);
                        },
                  icon: const Icon(Icons.arrow_downward_rounded),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    try {
                      if (v == 'rename') {
                        await _promptRename(context, ref, type);
                      } else if (v == 'archive') {
                        await db.setAssetTypeArchived(type.id, true);
                      } else if (v == 'unarchive') {
                        await db.setAssetTypeArchived(type.id, false);
                      } else if (v == 'delete') {
                        await _promptDelete(context, ref, type, count);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('$e')),
                        );
                      }
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'rename', child: Text('重命名')),
                    if (archived)
                      const PopupMenuItem(
                          value: 'unarchive', child: Text('取消归档'))
                    else
                      const PopupMenuItem(
                          value: 'archive', child: Text('归档')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _promptCreate(
  BuildContext context,
  WidgetRef ref,
  String ledgerId,
) async {
  final ctrl = TextEditingController();
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('新增资产分类'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '名称',
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(databaseProvider).createAssetType(
          ledgerId: ledgerId,
          name: ctrl.text,
        );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> _promptRename(
  BuildContext context,
  WidgetRef ref,
  AssetType type,
) async {
  final ctrl = TextEditingController(text: type.name);
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('重命名分类'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '名称',
          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(databaseProvider).renameAssetType(
          id: type.id,
          name: ctrl.text,
        );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

Future<void> _promptDelete(
  BuildContext context,
  WidgetRef ref,
  AssetType type,
  int count,
) async {
  if (count > 0) {
    await showGlassDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('无法删除'),
        content: Text('有 $count 个资产账户在用「${type.name}」，请先改到其他分类或归档。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return;
  }
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('删除分类'),
      content: Text('确定删除「${type.name}」？此操作不可撤销。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await ref.read(databaseProvider).deleteAssetType(type.id);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

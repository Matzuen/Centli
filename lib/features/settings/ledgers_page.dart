import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/currencies.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'me_page.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

final _allLedgersProvider = StreamProvider<List<Ledger>>((ref) {
  return ref.watch(databaseProvider).watchAllLedgers(includeArchived: true);
});

/// Multi-ledger manager: switch current, create, archive/restore, edit.
class LedgersPage extends ConsumerWidget {
  const LedgersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(_allLedgersProvider);
    final currentAsync = ref.watch(currentLedgerProvider);
    final currentId = currentAsync.valueOrNull?.id;

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('记账本管理'),
        actions: [
          IconButton(
            tooltip: '添加账本',
            icon: const Icon(Icons.add),
            onPressed: () => _create(context, ref),
          ),
        ],
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledgers) {
          if (ledgers.isEmpty) {
            return CentliEmptyState(
              icon: Icons.menu_book_outlined,
              title: '暂无记账本',
              message: '创建第一个记账本开始记账。点右上角 + 即可。',
              action: FilledButton.tonalIcon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('新建记账本'),
              ),
            );
          }
          final active = ledgers.where((l) => l.archived == 0).toList();
          final archived = ledgers.where((l) => l.archived != 0).toList();
          return ListView(
            padding: CentliSpacing.pagePadding,
            children: [
              Text(
                '可创建多个记账本并切换当前记账本。归档后不再出现在首页，可随时恢复。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              const SizedBox(height: CentliSpacing.section),
              for (final l in active) ...[
                CentliSoftCard(
                  margin: const EdgeInsets.only(bottom: CentliSpacing.item),
                  child: _LedgerTile(
                    ledger: l,
                    isCurrent: l.id == currentId,
                    onSwitch: () => _switchTo(context, ref, l),
                    onEdit: () => showLedgerEditor(context, ref, ledger: l),
                    onArchive: () => _archive(context, ref, l, archive: true),
                    onDelete: () => _delete(context, ref, l),
                  ),
                ),
              ],
              if (archived.isNotEmpty) ...[
                const SizedBox(height: CentliSpacing.section),
                Text(
                  '已归档',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: CentliSpacing.item),
                for (final l in archived) ...[
                  CentliSoftCard(
                    margin: const EdgeInsets.only(bottom: CentliSpacing.item),
                    child: _LedgerTile(
                      ledger: l,
                      isCurrent: false,
                      archived: true,
                      onSwitch: null,
                      onEdit: () => showLedgerEditor(context, ref, ledger: l),
                      onArchive: () => _archive(context, ref, l, archive: false),
                      onDelete: () => _delete(context, ref, l),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 72),
            ],
          );
        },
      ),
    );
  }

  Future<void> _switchTo(BuildContext context, WidgetRef ref, Ledger l) async {
    await ref.read(databaseProvider).setCurrentLedgerId(l.id);
    ref.invalidate(currentLedgerIdProvider);
    ref.invalidate(currentLedgerProvider);
    if (context.mounted) {
      showGlassSnackBar(context, '已切换到「${l.name}」');
    }
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    Ledger l, {
    required bool archive,
  }) async {
    if (archive) {
      final active = await ref.read(databaseProvider).loadAllLedgers();
      if (active.length <= 1) {
        if (context.mounted) {
          showGlassSnackBar(context, '至少保留一个未归档记账本');
        }
        return;
      }
    }
    await ref.read(databaseProvider).setLedgerArchived(l.id, archive);
    ref.invalidate(currentLedgerIdProvider);
    ref.invalidate(currentLedgerProvider);
    if (context.mounted) {
      showGlassSnackBar(context, archive ? '已归档' : '已恢复归档');
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Ledger l,
  ) async {
    final ok = await showGlassConfirmDialog(
      context: context,
      title: '删除记账本',
      content:
          '确定永久删除「${l.name}」？仅当该记账本没有未删除流水时可删；删除后账户与分类也会一并清除，且无法恢复。',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(databaseProvider).deleteLedger(l.id);
      ref.invalidate(currentLedgerIdProvider);
      ref.invalidate(currentLedgerProvider);
      if (context.mounted) {
        showGlassSnackBar(context, '已删除记账本「${l.name}」');
      }
    } catch (e) {
      if (context.mounted) {
        showGlassSnackBar(
          context,
          e is StateError ? e.message : '删除失败：$e',
        );
      }
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    var base = 'CNY';
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return CentliGlassDialog(
              title: const Text('新建记账本'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '记账本名称',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: base,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(value: c, child: Text(currencyLabel(c))),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => base = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '本位币',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true) return;
    if (name.isEmpty) {
      if (context.mounted) {
        showGlassSnackBar(context, '请输入记账本名称');
      }
      return;
    }
    final ledger = await ref.read(databaseProvider).createLedgerWithDefaults(
          name: name,
          baseCurrency: base,
          switchTo: true,
        );
    ref.invalidate(currentLedgerIdProvider);
    ref.invalidate(currentLedgerProvider);
    if (context.mounted) {
      showGlassSnackBar(context, '已创建并切换到「${ledger.name}」');
    }
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.ledger,
    required this.isCurrent,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
    this.onSwitch,
    this.archived = false,
  });

  final Ledger ledger;
  final bool isCurrent;
  final bool archived;
  final VoidCallback? onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        child: Icon(isCurrent ? Icons.book : Icons.book_outlined),
      ),
      title: Text(ledger.name),
      subtitle: Text(
        '${ledger.baseCurrency}'
        '${isCurrent ? ' · 当前' : ''}'
        '${archived ? ' · 已归档' : ''}',
      ),
      trailing: CentliGlassPopupButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'switch':
              onSwitch?.call();
            case 'edit':
              onEdit();
            case 'archive':
              onArchive();
            case 'delete':
              onDelete();
          }
        },
        items: [
          if (!archived && !isCurrent && onSwitch != null)
            const CentliMenuItem(value: 'switch', label: '设为当前'),
          const CentliMenuItem(value: 'edit', label: '编辑'),
          CentliMenuItem(
            value: 'archive',
            label: archived ? '取消归档' : '归档',
          ),
          const CentliMenuItem(value: 'delete', label: '删除'),
        ],
      ),
      onTap: archived
          ? onEdit
          : (isCurrent ? onEdit : onSwitch),
    );
  }
}

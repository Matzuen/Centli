import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/currencies.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'me_page.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('账本管理'),
        actions: [
          IconButton(
            tooltip: '新建账本',
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
            return const Center(child: Text('暂无账本'));
          }
          final active = ledgers.where((l) => l.archived == 0).toList();
          final archived = ledgers.where((l) => l.archived != 0).toList();
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '可创建多个账本并切换当前账本。归档后不再出现在首页，可随时恢复。',
                  style: TextStyle(height: 1.4),
                ),
              ),
              const Divider(),
              for (final l in active)
                _LedgerTile(
                  ledger: l,
                  isCurrent: l.id == currentId,
                  onSwitch: () => _switchTo(context, ref, l),
                  onEdit: () => showLedgerEditor(context, ref, ledger: l),
                  onArchive: () => _archive(context, ref, l, archive: true),
                ),
              if (archived.isNotEmpty) ...[
                const Divider(),
                const ListTile(title: Text('已归档')),
                for (final l in archived)
                  _LedgerTile(
                    ledger: l,
                    isCurrent: false,
                    archived: true,
                    onSwitch: null,
                    onEdit: () => showLedgerEditor(context, ref, ledger: l),
                    onArchive: () => _archive(context, ref, l, archive: false),
                  ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('新建账本'),
      ),
    );
  }

  Future<void> _switchTo(BuildContext context, WidgetRef ref, Ledger l) async {
    await ref.read(databaseProvider).setCurrentLedgerId(l.id);
    ref.invalidate(currentLedgerIdProvider);
    ref.invalidate(currentLedgerProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到「${l.name}」')),
      );
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('至少保留一个未归档账本')),
          );
        }
        return;
      }
    }
    await ref.read(databaseProvider).setLedgerArchived(l.id, archive);
    ref.invalidate(currentLedgerIdProvider);
    ref.invalidate(currentLedgerProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archive ? '已归档' : '已恢复归档')),
      );
    }
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    var base = 'CNY';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('新建账本'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '账本名称',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: base,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => base = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '本位币',
                      border: OutlineInputBorder(),
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
                  child: const Text('创建'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入账本名称')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建并切换到「${ledger.name}」')),
      );
    }
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.ledger,
    required this.isCurrent,
    required this.onEdit,
    required this.onArchive,
    this.onSwitch,
    this.archived = false,
  });

  final Ledger ledger;
  final bool isCurrent;
  final bool archived;
  final VoidCallback? onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

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
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'switch':
              onSwitch?.call();
            case 'edit':
              onEdit();
            case 'archive':
              onArchive();
          }
        },
        itemBuilder: (ctx) => [
          if (!archived && !isCurrent && onSwitch != null)
            const PopupMenuItem(value: 'switch', child: Text('设为当前')),
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          PopupMenuItem(
            value: 'archive',
            child: Text(archived ? '取消归档' : '归档'),
          ),
        ],
      ),
      onTap: archived
          ? onEdit
          : (isCurrent ? onEdit : onSwitch),
    );
  }
}

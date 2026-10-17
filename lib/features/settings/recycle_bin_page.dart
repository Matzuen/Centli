import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../app/theme.dart';

final _deletedTxProvider =
    StreamProvider.family<List<Transaction>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchDeletedTransactions(ledgerId);
});

/// Soft-deleted transactions: undelete or purge permanently.
class RecycleBinPage extends ConsumerWidget {
  const RecycleBinPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          IconButton(
            tooltip: '清空回收站',
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: () => _purgeAll(context, ref),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) {
          if (ledger == null) {
            return const Center(child: Text('账本未初始化'));
          }
          final listAsync = ref.watch(_deletedTxProvider(ledger.id));
          return listAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (items) {
              if (items.isEmpty) {
                return CentliEmptyState(
                  icon: Icons.delete_outline,
                  title: '回收站为空',
                  message: '删除流水后可在此恢复。永久清空不可撤销。',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(CentliSpacing.pageH, CentliSpacing.section, CentliSpacing.pageH, CentliSpacing.pageBottom),
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final t = items[i];
                  final when = DateFormat('yyyy-MM-dd HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(t.happenAt, isUtc: true)
                        .toLocal(),
                  );
                  final deleted = t.deletedAt == null
                      ? ''
                      : DateFormat('MM-dd HH:mm').format(
                          DateTime.fromMillisecondsSinceEpoch(
                            t.deletedAt!,
                            isUtc: true,
                          ).toLocal(),
                        );
                  final title = (t.note ?? '').isNotEmpty
                      ? t.note!
                      : (t.note ?? t.type);
                  return CentliSoftCard(
                    child: ListTile(
                      title: Text(title),
                      subtitle: Text(
                        '$when · ${t.type}\n'
                        '删除于 $deleted',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        formatMinor(t.currency, t.amountMinor),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      onTap: () => _showActions(context, ref, t),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    Transaction t,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('恢复'),
              onTap: () => Navigator.pop(ctx, 'undelete'),
            ),
            ListTile(
              leading: Icon(Icons.delete_forever, color: Theme.of(ctx).colorScheme.error),
              title: Text(
                '永久删除',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () => Navigator.pop(ctx, 'purge'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (action == 'undelete') {
      await db.undeleteTransaction(t.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复')),
        );
      }
    } else if (action == 'purge') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('永久删除？'),
          content: const Text('此操作不可撤销。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok != true) return;
      await db.purgeDeletedTransaction(t.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已永久删除')),
        );
      }
    }
  }

  Future<void> _purgeAll(BuildContext context, WidgetRef ref) async {
    final ledger = ref.read(currentLedgerProvider).valueOrNull;
    if (ledger == null) return;
    final count = await ref.read(databaseProvider).countDeletedTransactions(ledger.id);
    if (count == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('回收站为空')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站？'),
        content: Text('将永久删除 $count 条流水，不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await ref.read(databaseProvider).purgeAllDeletedTransactions(ledger.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空 $n 条')),
      );
    }
  }
}

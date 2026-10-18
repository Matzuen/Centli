import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/db/txn_tags.dart';
import '../../app/theme.dart';
import '../../core/widgets/centli_error_state.dart';
import '../../core/widgets/category_visuals.dart';

final _deletedTxProvider =
    StreamProvider.family<List<Transaction>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchDeletedTransactions(ledgerId);
});

final _recycleLookupsProvider =
    FutureProvider.family<TxnListLookups, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).loadTxnListLookups(ledgerId);
});

/// Soft-deleted transactions: full details + undelete / purge permanently.
class RecycleBinPage extends ConsumerWidget {
  const RecycleBinPage({super.key});

  static String typeLabel(String type) {
    switch (type) {
      case 'in':
        return '收入';
      case 'transfer':
        return '转账';
      case 'refund':
        return '退款';
      default:
        return '支出';
    }
  }

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
        error: (e, _) => CentliErrorState(error: e),
        data: (ledger) {
          if (ledger == null) {
            return const Center(child: Text('账本未初始化'));
          }
          final lookups = ref.watch(_recycleLookupsProvider(ledger.id))
                  .valueOrNull ??
              TxnListLookups.empty;
          final listAsync = ref.watch(_deletedTxProvider(ledger.id));
          return listAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => CentliErrorState(error: e),
            data: (items) {
              if (items.isEmpty) {
                return CentliEmptyState(
                  icon: Icons.delete_outline,
                  title: '回收站为空',
                  message: '删除流水后可在此查看详情并恢复。永久清空不可撤销。',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  CentliSpacing.pageH,
                  CentliSpacing.section,
                  CentliSpacing.pageH,
                  CentliSpacing.pageBottom,
                ),
                itemCount: items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: CentliSpacing.item),
                itemBuilder: (context, i) => _DeletedTile(
                  txn: items[i],
                  lookups: lookups,
                  onTap: () => _showDetails(context, ref, items[i], lookups),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showDetails(
    BuildContext context,
    WidgetRef ref,
    Transaction t,
    TxnListLookups lookups,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _DeletedDetailSheet(
        txn: t,
        lookups: lookups,
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
    final count =
        await ref.read(databaseProvider).countDeletedTransactions(ledger.id);
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
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final n = await ref
        .read(databaseProvider)
        .purgeAllDeletedTransactions(ledger.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空 $n 条')),
      );
    }
  }
}

class _DeletedTile extends StatelessWidget {
  const _DeletedTile({
    required this.txn,
    required this.lookups,
    required this.onTap,
  });

  final Transaction txn;
  final TxnListLookups lookups;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true).toLocal(),
    );
    final deleted = txn.deletedAt == null
        ? ''
        : DateFormat('MM-dd HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(txn.deletedAt!, isUtc: true)
                .toLocal(),
          );
    final cat = txn.categoryId == null
        ? null
        : lookups.categoriesById[txn.categoryId!];
    final from = lookups.accountsById[txn.accountId]?.name;
    final to = txn.toAccountId == null
        ? null
        : lookups.accountsById[txn.toAccountId!]?.name;
    final title = txn.type == 'transfer'
        ? '转账'
        : (cat?.name ?? '未分类');
    final parts = <String>[
      RecycleBinPage.typeLabel(txn.type),
      if (from != null)
        txn.type == 'transfer' && to != null ? '$from → $to' : from,
      if ((txn.note ?? '').trim().isNotEmpty) txn.note!.trim(),
    ];
    final amountColor = txn.type == 'in' || txn.type == 'refund'
        ? const Color(0xFF43A047)
        : (txn.type == 'transfer'
            ? scheme.onSurface
            : const Color(0xFFE53935));

    return CentliSoftCard(
      child: ListTile(
        onTap: onTap,
        leading: CategoryCircleIcon(
          name: (cat?.name ?? '').trim(),
          kind: txn.type == 'transfer' ? 'transfer' : txn.type,
          iconKey: cat?.icon,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${parts.join(' · ')}\n$when · 删除于 $deleted',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Text(
          formatMinor(txn.currency, txn.amountMinor),
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: amountColor),
        ),
      ),
    );
  }
}

/// Full snapshot of a deleted bill (read-only) + 恢复 / 永久删除.
class _DeletedDetailSheet extends StatelessWidget {
  const _DeletedDetailSheet({required this.txn, required this.lookups});

  final Transaction txn;
  final TxnListLookups lookups;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final cat = txn.categoryId == null
        ? null
        : lookups.categoriesById[txn.categoryId!];
    final from = lookups.accountsById[txn.accountId]?.name;
    final to = txn.toAccountId == null
        ? null
        : lookups.accountsById[txn.toAccountId!]?.name;
    final happen = DateFormat('yyyy-MM-dd HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true).toLocal(),
    );
    final deleted = txn.deletedAt == null
        ? '—'
        : DateFormat('yyyy-MM-dd HH:mm').format(
            DateTime.fromMillisecondsSinceEpoch(txn.deletedAt!, isUtc: true)
                .toLocal(),
          );
    final tags = decodeTxnTags(txn.tags);

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              formatMinor(txn.currency, txn.amountMinor),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              RecycleBinPage.typeLabel(txn.type),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: CentliSpacing.item),
            const Divider(),
            row('时间', happen),
            row('账户', txn.type == 'transfer'
                ? '${from ?? '—'} → ${to ?? '—'}'
                : (from ?? '—')),
            row('分类', cat?.name ?? (txn.type == 'transfer' ? '转账' : '未分类')),
            row('备注', (txn.note ?? '').trim().isEmpty
                ? '—'
                : txn.note!.trim()),
            row('标签', tags.isEmpty ? '—' : tags.join('，')),
            row('计入统计', txn.includeInStat == 1 ? '是' : '否'),
            row('计入预算', txn.includeInBudget == 1 ? '是' : '否'),
            row('来源', txn.source.isEmpty ? '—' : txn.source),
            row('删除于', deleted),
            const Divider(),
            const SizedBox(height: CentliSpacing.item),
            FilledButton.icon(
              key: const Key('recycle_restore'),
              onPressed: () => Navigator.pop(context, 'undelete'),
              icon: const Icon(Icons.restore),
              label: const Text('恢复这笔账单'),
            ),
            TextButton.icon(
              key: const Key('recycle_purge'),
              onPressed: () => Navigator.pop(context, 'purge'),
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              icon: const Icon(Icons.delete_forever),
              label: const Text('永久删除'),
            ),
          ],
        ),
      ),
    );
  }
}

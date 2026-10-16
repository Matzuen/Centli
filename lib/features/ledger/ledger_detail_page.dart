import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'bookkeeping_sheet.dart' deferred as bookkeeping;
import '../../app/theme.dart';

final _txnProvider =
    StreamProvider.family<Transaction?, String>((ref, id) {
  return ref.watch(databaseProvider).watchTransaction(id);
});

/// P0 bill detail: view fields, soft-delete, edit via bookkeeping sheet,
/// toggle include-in-stat.
class LedgerDetailPage extends ConsumerWidget {
  const LedgerDetailPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_txnProvider(transactionId));
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;
    final scheme = Theme.of(context).colorScheme;

    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('\u8d26\u5355')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('\u8d26\u5355')),
        body: Center(child: Text('\u52a0\u8f7d\u5931\u8d25: $e')),
      ),
      data: (txn) {
        if (txn == null || txn.deletedAt != null) {
          return Scaffold(
            appBar: AppBar(title: const Text('\u8d26\u5355')),
            body: const Center(child: Text('\u8d26\u5355\u4e0d\u5b58\u5728\u6216\u5df2\u5220\u9664')),
          );
        }
        return _DetailBody(txn: txn, hide: hide, scheme: scheme);
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.txn,
    required this.hide,
    required this.scheme,
  });

  final Transaction txn;
  final bool hide;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = txn.type == 'out';
    final isTransfer = txn.type == 'transfer';
    final prefix = isTransfer ? '' : (isOut ? '-' : '+');
    final amountColor = isTransfer
        ? scheme.onSurface
        : (isOut ? scheme.error : scheme.primary);
    final time = DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true)
        .toLocal();
    final timeLabel = DateFormat('yyyy-MM-dd HH:mm').format(time);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u8d26\u5355'),
        actions: [
          IconButton(
            tooltip: '\u5220\u9664',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
          IconButton(
            tooltip: '\u7f16\u8f91',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editTxn(context, txn),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Text(
              '$prefix${formatMinor(txn.currency, txn.amountMinor, hide: hide)}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: FutureBuilder<(String?, String?, String?)>(
              future: _labels(ref),
              builder: (context, snap) {
                final (cat, acc, toAcc) = snap.data ?? (null, null, null);
                final typeLabel = _typeLabel(txn.type);
                final subtitle = isTransfer
                    ? '$typeLabel  ·  ${acc ?? "?"} \u2192 ${toAcc ?? "?"}'
                    : '$typeLabel${cat != null ? "  ·  $cat" : ""}';
                return Text(
                  subtitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          CentliSoftCard(
            child: Column(
              children: [
                _row(
                  context,
                  label: isTransfer ? '\u8f6c\u51fa\u8d26\u6237' : '\u8d26\u6237',
                  future: ref
                      .read(databaseProvider)
                      .getAccount(txn.accountId)
                      .then((a) => a?.name ?? txn.accountId),
                ),
                if (isTransfer) ...[
                  const Divider(height: 1),
                  _row(
                    context,
                    label: '\u8f6c\u5165\u8d26\u6237',
                    future: () async {
                      final id = txn.toAccountId;
                      if (id == null) return '\u2014';
                      final a = await ref.read(databaseProvider).getAccount(id);
                      return a?.name ?? id;
                    }(),
                  ),
                  if (txn.toAmountMinor != null) ...[
                    const Divider(height: 1),
                    FutureBuilder<String>(
                      future: () async {
                        final id = txn.toAccountId;
                        if (id == null) {
                          return formatMinor(
                            txn.currency,
                            txn.toAmountMinor!,
                            hide: hide,
                          );
                        }
                        final a =
                            await ref.read(databaseProvider).getAccount(id);
                        final ccy = a?.currency ?? txn.currency;
                        return formatMinor(
                          ccy,
                          txn.toAmountMinor!,
                          hide: hide,
                        );
                      }(),
                      builder: (context, snap) => ListTile(
                        title: const Text('\u5bf9\u65b9\u91d1\u989d'),
                        trailing: Text(
                          snap.data ?? '\u2026',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                  if (txn.fxRate != null) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: const Text('\u6c47\u7387'),
                      trailing: Text(txn.fxRate!.toStringAsFixed(6)),
                    ),
                  ],
                ],
                const Divider(height: 1),
                ListTile(
                  title: const Text('\u65f6\u95f4'),
                  trailing: Text(timeLabel),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('\u6765\u6e90'),
                  trailing: Text(_sourceLabel(txn.source)),
                ),
                if (txn.merchant != null && txn.merchant!.isNotEmpty) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('\u5546\u6237'),
                    trailing: Text(txn.merchant!),
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  title: const Text('\u5907\u6ce8'),
                  trailing: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      (txn.note == null || txn.note!.isEmpty)
                          ? '\u2014'
                          : txn.note!,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('\u8ba1\u5165\u7edf\u8ba1'),
                  value: txn.includeInStat == 1,
                  onChanged: isTransfer
                      ? null
                      : (v) async {
                          await ref
                              .read(databaseProvider)
                              .setIncludeInStat(txn.id, v);
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<(String?, String?, String?)> _labels(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    String? cat;
    if (txn.categoryId != null) {
      final c = await db.getCategory(txn.categoryId!);
      cat = c?.name;
    }
    final acc = await db.getAccount(txn.accountId);
    String? toAcc;
    if (txn.toAccountId != null) {
      final t = await db.getAccount(txn.toAccountId!);
      toAcc = t?.name;
    }
    return (cat, acc?.name, toAcc);
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required Future<String> future,
  }) {
    return FutureBuilder<String>(
      future: future,
      builder: (context, snap) {
        return ListTile(
          title: Text(label),
          trailing: Text(snap.data ?? '\u2026'),
        );
      },
    );
  }

  Future<void> _editTxn(BuildContext context, Transaction txn) async {
    await bookkeeping.loadLibrary();
    if (!context.mounted) return;
    await bookkeeping.showBookkeepingSheet(context, existing: txn);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\u5220\u9664\u8d26\u5355'),
        content: const Text('\u786e\u5b9a\u5220\u9664\u8fd9\u7b14\u8d26\u5355\uff1f\u53ef\u4ee5\u5728\u6570\u636e\u5e93\u4e2d\u4ee5\u8f6f\u5220\u9664\u4fdd\u7559\u3002'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('\u5220\u9664'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(databaseProvider).softDeleteTransaction(txn.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u5df2\u5220\u9664')),
      );
      context.pop();
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'in':
        return '\u6536\u5165';
      case 'transfer':
        return '\u8f6c\u8d26';
      default:
        return '\u652f\u51fa';
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'notification':
        return '\u901a\u77e5\u81ea\u52a8';
      default:
        return '\u624b\u52a8';
    }
  }
}

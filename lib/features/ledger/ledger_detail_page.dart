import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/txn_tags.dart';
import '../../data/db/database_provider.dart';
import '../../data/txn_templates.dart';
import '../../core/utils/id_gen.dart';
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
    final prefix = isTransfer ? '' : (isOut ? '-' : '+'); // refund → +
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
          if (txn.type != 'transfer')
            IconButton(
              tooltip: '\u5b58\u4e3a\u6a21\u677f',
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () => _saveAsTemplate(context, ref, txn),
            ),
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
          if ((txn.note ?? '').trim() == '\u4f59\u989d\u6821\u6b63') ...[
            const SizedBox(height: 8),
            Center(
              child: Chip(
                avatar: Icon(Icons.tune, size: 16, color: scheme.primary),
                label: const Text('\u4f59\u989d\u6821\u6b63\uff08\u4e0d\u8ba1\u5165\u7edf\u8ba1\uff09'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          CentliSoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(context, '\u57fa\u672c\u4fe1\u606f'),
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
                _sectionHeader(context, '\u6765\u6e90\u4e0e\u65f6\u95f4'),
                ListTile(
                  title: const Text('\u65f6\u95f4'),
                  trailing: Text(timeLabel),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('\u6765\u6e90'),
                  trailing: Text(_sourceLabel(txn.source)),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('\u5546\u6237'),
                  trailing: Text(
                    (txn.merchant == null || txn.merchant!.isEmpty)
                        ? '\u2014'
                        : txn.merchant!,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('\u6210\u5458'),
                  trailing: Text(
                    (txn.member == null || txn.member!.isEmpty)
                        ? '\u2014'
                        : txn.member!,
                  ),
                ),
                _sectionHeader(context, '\u5176\u5b83'),
                ListTile(
                  title: const Text('\u6807\u7b7e'),
                  subtitle: decodeTxnTags(txn.tags).isEmpty
                      ? const Text('\\u2014')
                      : Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final t in decodeTxnTags(txn.tags))
                              Chip(
                                label: Text(t),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                  trailing: IconButton(
                    tooltip: '\\u7f16\\u8f91\\u6807\\u7b7e',
                    icon: const Icon(Icons.sell_outlined),
                    onPressed: () => _editTags(context, ref),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('\u5907\u6ce8'),
                  subtitle: Text(
                    (txn.note == null || txn.note!.isEmpty)
                        ? '\u2014'
                        : txn.note!,
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('\u8ba1\u5165\u7edf\u8ba1'),
                  subtitle: const Text('\u5f71\u54cd\u6536\u652f\u7edf\u8ba1\u4e0e\u8d8b\u52bf'),
                  value: txn.includeInStat == 1,
                  onChanged: isTransfer
                      ? null
                      : (v) async {
                          await ref
                              .read(databaseProvider)
                              .setIncludeInStat(txn.id, v);
                        },
                ),
                SwitchListTile(
                  title: const Text('\u8ba1\u5165\u9884\u7b97'),
                  subtitle: const Text('\u5f71\u54cd\u6708\u5ea6\u9884\u7b97\u8fdb\u5ea6'),
                  value: txn.includeInBudget == 1,
                  onChanged: isTransfer
                      ? null
                      : (v) async {
                          await ref
                              .read(databaseProvider)
                              .setIncludeInBudget(txn.id, v);
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


  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
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


  Future<void> _editTags(BuildContext context, WidgetRef ref) async {
    final current = List<String>.from(decodeTxnTags(txn.tags));
    final ctrl = TextEditingController();
    final suggestions =
        await ref.read(databaseProvider).listDistinctTags(txn.ledgerId);
    if (!context.mounted) return;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void addTag(String raw) {
              var t = raw.trim();
              if (t.isEmpty) return;
              if (t.length > 12) t = t.substring(0, 12);
              if (current.contains(t) || current.length >= 5) return;
              setLocal(() => current.add(t));
              ctrl.clear();
            }

            return AlertDialog(
              title: const Text('\u7f16\u8f91\u6807\u7b7e'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final t in current)
                          InputChip(
                            label: Text(t),
                            onDeleted: () => setLocal(() => current.remove(t)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: '\u65b0\u6807\u7b7e',
                        hintText: '\u56de\u8f66\u786e\u8ba4\uff0c\u6700\u591a 5 \u4e2a',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: addTag,
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final s in suggestions.take(12))
                            ActionChip(
                              label: Text(s),
                              onPressed: () => addTag(s),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('\u53d6\u6d88'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, List<String>.from(current)),
                  child: const Text('\u4fdd\u5b58'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    if (result == null || !context.mounted) return;
    await ref.read(databaseProvider).updateTransactionTags(txn.id, result);
  }


  Future<void> _saveAsTemplate(
    BuildContext context,
    WidgetRef ref,
    Transaction txn,
  ) async {
    final nameCtrl = TextEditingController(
      text: (txn.merchant ?? txn.note ?? '').trim().isEmpty
          ? '\u5e38\u7528\u6d41\u6c34'
          : (txn.merchant ?? txn.note)!.trim(),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\u5b58\u4e3a\u6a21\u677f'),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '\u6a21\u677f\u540d\u79f0',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('\u53d6\u6d88'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('\u4fdd\u5b58'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (name.isEmpty) return;
    final db = ref.read(databaseProvider);
    await db.saveTxnTemplate(
      txn.ledgerId,
      TxnTemplate(
        id: newId(),
        name: name,
        type: txn.type,
        amountMinor: txn.amountMinor.abs(),
        currency: txn.currency,
        accountId: txn.accountId,
        categoryId: txn.categoryId,
        merchant: txn.merchant,
        note: txn.note,
        tags: decodeTxnTags(txn.tags),
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u5df2\u5b58\u4e3a\u6a21\u677f')),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('\u5220\u9664\u8d26\u5355'),
        content: const Text('\u786e\u5b9a\u5220\u9664\u8fd9\u7b14\u8d26\u5355\uff1f\u53ef\u5728\u300c\u56de\u6536\u7ad9\u300d\u6062\u590d\u3002'),
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
      case 'refund':
        return '\u9000\u6b3e';
      default:
        return '\u652f\u51fa';
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'notification':
        return '\u901a\u77e5\u81ea\u52a8';
      case 'ocr':
        return '\u622a\u56fe\u5bfc\u5165';
      case 'clipboard':
        return '\u526a\u8d34\u677f\u5bfc\u5165';
      case 'share':
        return '\u5206\u4eab\u5bfc\u5165';
      case 'share_image':
        return '\u5206\u4eab\u56fe\u7247';
      case 'url':
        return '\u94fe\u63a5\u5bfc\u5165';
      case 'manual':
        return '\u624b\u52a8';
      default:
        return '\u624b\u52a8';
    }
  }
}

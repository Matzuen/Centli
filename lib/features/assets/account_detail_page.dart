import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/currencies.dart';
import '../../core/utils/date_range.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/txn_grouped_list.dart';
import '../../core/widgets/txn_list_tile.dart';
import '../../core/widgets/date_range_control.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../security/app_lock_controller.dart';
import 'assets_page.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

final _accountProvider =
    StreamProvider.family<Account?, String>((ref, id) {
  return ref.watch(databaseProvider).watchAccount(id);
});

final _accountRangeProvider =
    StateProvider.family<DateRangeWindow, String>((ref, accountId) {
  final now = DateTime.now();
  return DateRangeWindow.forMonth(now.year, now.month);
});

final _accountTxProvider = StreamProvider.family<
    List<Transaction>,
    ({String accountId, String key, int startMs, int endMs})>((ref, args) {
  return ref.watch(databaseProvider).watchAccountTransactionsInRange(
        args.accountId,
        args.startMs,
        args.endMs,
      );
});

final _assetTypeByIdProvider =
    FutureProvider.family<AssetType?, String>((ref, id) {
  return ref.watch(databaseProvider).getAssetType(id);
});

/// P0 account detail `/assets/:id`:
/// balance / currency / opening + monthly (range)流水; edit / adjust / archive / unarchive.
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_accountProvider(accountId));
    final hide = ref.watch(hideAmountProvider);

    return async.when(
      loading: () => CentliGradientScaffold(
        appBar: AppBar(title: const Text('\u8d44\u4ea7\u8d26\u6237')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => CentliGradientScaffold(
        appBar: AppBar(title: const Text('\u8d44\u4ea7\u8d26\u6237')),
        body: Center(child: Text('\u52a0\u8f7d\u5931\u8d25: $e')),
      ),
      data: (account) {
        if (account == null) {
          return CentliGradientScaffold(
            appBar: AppBar(title: const Text('\u8d44\u4ea7\u8d26\u6237')),
            body: const Center(
              child: Text('\u8d44\u4ea7\u8d26\u6237\u4e0d\u5b58\u5728'),
            ),
          );
        }
        return _AccountDetailBody(
          account: account,
          hide: hide,
        );
      },
    );
  }
}

class _AccountDetailBody extends ConsumerWidget {
  const _AccountDetailBody({
    required this.account,
    required this.hide,
  });

  final Account account;
  final bool hide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final range = ref.watch(_accountRangeProvider(account.id));
    final balancesAsync =
        ref.watch(_balancesForLedgerProvider(account.ledgerId));
    final bal = balancesAsync.valueOrNull?[account.id] ??
        account.openingBalanceMinor;
    final txArgs = (
      accountId: account.id,
      key: range.key,
      startMs: range.startMs,
      endMs: range.endMs,
    );
    final txAsync = ref.watch(_accountTxProvider(txArgs));

    return CentliGradientScaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CentliIconChip(
              name: account.name,
              iconKey: account.icon,
              size: 32,
              roundedSquare: true,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                account.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (account.archived != 0)
            FilledButton.tonalIcon(
              onPressed: () => _confirmUnarchive(context, ref, account),
              icon: const Icon(Icons.unarchive_outlined),
              label: const Text('\u53d6\u6d88\u5f52\u6863'),
            )
          else ...[
            IconButton(
              tooltip: '\u7f16\u8f91',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showAccountEditor(
                context,
                ref,
                ledgerId: account.ledgerId,
                existing: account,
              ),
            ),
            CentliGlassPopupButton<String>(
              onSelected: (v) async {
                if (v == 'adjust') {
                  await _showAdjustBalance(context, ref, account, bal);
                } else if (v == 'archive') {
                  await _confirmArchive(context, ref, account);
                }
              },
              items: const [
                CentliMenuItem(value: 'adjust', label: '调整余额'),
                CentliMenuItem(value: 'archive', label: '归档资产账户'),
              ],
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (account.archived != 0)
            CentliSoftCard(
              color: scheme.secondaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.inventory_2_outlined,
                  color: scheme.onSecondaryContainer,
                ),
                title: Text(
                  '\u6b64\u8d44\u4ea7\u8d26\u6237\u5df2\u5f52\u6863',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
                subtitle: Text(
                  '\u4e0d\u8ba1\u5165\u8d44\u4ea7\u5217\u8868\u4e0e\u603b\u8d44\u4ea7\uff1b\u5386\u53f2\u6d41\u6c34\u4ecd\u53ef\u67e5\u770b\u3002\u70b9\u53f3\u4e0a\u89d2\u53d6\u6d88\u5f52\u6863\u5373\u53ef\u6062\u590d\u3002',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ),
          if (account.archived != 0) const SizedBox(height: CentliSpacing.item),
          CentliSoftCard(
            child: Padding(
              padding: const EdgeInsets.all(CentliSpacing.cardPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u4f59\u989d',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  Text(
                    formatMinor(account.currency, bal, hide: hide),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  Row(
                    children: [
                      _chip(context, '\u5e01\u79cd', account.currency),
                      const SizedBox(width: 8),
                      _chip(context, '\u7c7b\u578b', ref.watch(_assetTypeByIdProvider(account.type)).valueOrNull?.name ?? '其他'),
                    ],
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  Text(
                    '\u671f\u521d ${formatMinor(account.currency, account.openingBalanceMinor, hide: hide)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: CentliSpacing.dense),
                  Text(
                    '\u8c03\u6574\u4f59\u989d\u4f1a\u8bb0\u4e00\u7b14\u300c\u4f59\u989d\u6821\u6b63\u300d\uff08\u4e0d\u8ba1\u5165\u7edf\u8ba1\uff09',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: CentliSpacing.item),
          DateRangeControl(
            range: range,
            onChanged: (next) {
              ref.read(_accountRangeProvider(account.id).notifier).state = next;
            },
          ),
          const SizedBox(height: CentliSpacing.item),
          Text('\u6d41\u6c34', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: CentliSpacing.item),
          txAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(CentliSpacing.cardPad),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e'),
            data: (txns) {
              if (txns.isEmpty) {
                return CentliSoftCard(
                  child: Padding(
                    padding: const EdgeInsets.all(CentliSpacing.cardPad),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 40, color: scheme.outline),
                        const SizedBox(height: CentliSpacing.item),
                        Text(
                          '\u8be5\u65f6\u6bb5\u65e0\u6d41\u6c34',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final groups = groupTransactionsByDate(txns);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var gi = 0; gi < groups.length; gi++) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(4, gi == 0 ? 8 : 20, 4, 8),
                      child: Text(
                        groups[gi].label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                    Material(
                      color: scheme.surface,
                      child: Column(
                        children: [
                          for (var i = 0; i < groups[gi].items.length; i++)
                            _AccountTxnTile(
                              txn: groups[gi].items[i],
                              accountId: account.id,
                              accountCurrency: account.currency,
                              hide: hide,
                              showSeparator: i > 0,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, String value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label · $value'),
    );
  }

}

final _balancesForLedgerProvider =
    StreamProvider.family<Map<String, int>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchAccountBalances(ledgerId);
});

class _AccountTxnTile extends ConsumerWidget {
  const _AccountTxnTile({
    required this.txn,
    required this.accountId,
    required this.accountCurrency,
    required this.hide,
    this.showSeparator = false,
  });

  final Transaction txn;
  final String accountId;
  final String accountCurrency;
  final bool hide;
  final bool showSeparator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final signed = _signedMinor();
    final isNeg = signed < 0;
    final isZero = signed == 0;
    final amountColor = txn.type == 'transfer'
        ? kTxnTransferBlue
        : isZero
            ? scheme.onSurface
            : (isNeg ? kTxnExpenseRed : kTxnIncomeGreen);
    final time =
        DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true).toLocal();
    final timeLabel = DateFormat('HH:mm').format(time);
    final db = ref.read(databaseProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSeparator)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 72,
            endIndent: 16,
            color: Color(0xFFEEEEEE),
          ),
        InkWell(
          onTap: () => context.push('/ledger/${txn.id}'),
          child: Padding(
            padding: const EdgeInsets.all(CentliSpacing.cardPad),
            child: Row(
              children: [
                FutureBuilder<({String name, String? icon})>(
                  future: _categoryMeta(db),
                  builder: (context, snap) {
                    final name = snap.data?.name ?? '';
                    return CentliIconChip(
                      name: name,
                      kind: txn.type == 'transfer'
                          ? 'transfer'
                          : (isNeg ? 'out' : 'in'),
                      iconKey: snap.data?.icon,
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String>(
                        future: _title(db),
                        builder: (context, snap) => Text(
                          snap.data ?? '\u2026',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                        ),
                      ),
                      const SizedBox(height: CentliSpacing.dense),
                      FutureBuilder<String>(
                        future: _subtitle(db),
                        builder: (context, snap) {
                          final t = snap.data ?? '';
                          if (t.isEmpty) return const SizedBox.shrink();
                          return Text(
                            t,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: muted, height: 1.2),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _amountLabel(signed.abs()),
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: CentliSpacing.dense),
                    Text(
                      timeLabel,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: muted, height: 1.2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _amountLabel(int minorAbs) {
    if (hide) return '****';
    final ccy = _displayCurrency();
    final symbol = currencySymbols[ccy] ?? ccy;
    final decimals = currencyDecimals[ccy] ?? 2;
    final major = fromMinor(ccy, minorAbs);
    final numStr = decimals == 0
        ? '${major.round()}'
        : major.toStringAsFixed(decimals);
    return '$symbol $numStr';
  }

  Future<String> _categoryName(CentliDatabase db) async {
    if (txn.type == 'transfer') return '\u8f6c\u8d26';
    if (txn.categoryId != null && txn.categoryId!.isNotEmpty) {
      final cat = await db.getCategory(txn.categoryId!);
      final n = (cat?.name ?? '').trim();
      if (n.isNotEmpty) return n;
    }
    return '\u672a\u5206\u7c7b';
  }

  Future<({String name, String? icon})> _categoryMeta(CentliDatabase db) async {
    if (txn.type == 'transfer') {
      return (name: '转账', icon: 'swap_horiz');
    }
    if (txn.categoryId == null || txn.categoryId!.isEmpty) {
      return (name: '未分类', icon: null);
    }
    final cat = await db.getCategory(txn.categoryId!);
    final n = (cat?.name ?? '').trim();
    return (
      name: n.isNotEmpty ? n : '未分类',
      icon: cat?.icon,
    );
  }


  Future<String> _title(CentliDatabase db) => _categoryName(db);

  Future<String> _subtitle(CentliDatabase db) async {
    final note = (txn.note ?? '').trim();
    final right = note;
    final typeLabel = _typeLabel(txn.type);
    if (right.isEmpty) return typeLabel;
    return '$typeLabel \u00b7 $right';
  }

  /// Effect on this account's balance in account currency units.
  int _signedMinor() {
    if (txn.type == 'in') return txn.amountMinor;
    if (txn.type == 'out') return -txn.amountMinor;
    if (txn.accountId == accountId) return -txn.amountMinor;
    return txn.toAmountMinor ?? txn.amountMinor;
  }

  String _displayCurrency() {
    if (txn.type == 'transfer' &&
        txn.accountId != accountId &&
        txn.toAmountMinor != null) {
      return accountCurrency;
    }
    return txn.currency;
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
}

Future<void> _showAdjustBalance(
  BuildContext context,
  WidgetRef ref,
  Account account,
  int currentBalanceMinor,
) async {
  final decimals = currencyDecimals[account.currency] ?? 2;
  final ctrl = TextEditingController(
    text: fromMinor(account.currency, currentBalanceMinor)
        .toStringAsFixed(decimals),
  );

  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => CentliGlassDialog(
      title: const Text('\u8c03\u6574\u4f59\u989d'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u5f53\u524d ${formatMinor(account.currency, currentBalanceMinor)}',
          ),
          const SizedBox(height: CentliSpacing.section),
          TextField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '\u76ee\u6807\u4f59\u989d',
              border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
              helperText:
                  '\u5c06\u8bb0\u4e00\u7b14\u300c\u4f59\u989d\u6821\u6b63\u300d\uff0c\u4e0d\u4fee\u6539\u671f\u521d\uff0c\u4e0d\u8ba1\u5165\u7edf\u8ba1',
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('\u786e\u5b9a'),
        ),
      ],
    ),
  );

  if (ok != true) {
    ctrl.dispose();
    return;
  }
  final major = double.tryParse(ctrl.text.trim());
  ctrl.dispose();
  if (major == null) {
    if (context.mounted) {
      showGlassSnackBar(context, '\u8bf7\u8f93\u5165\u6709\u6548\u91d1\u989d');
    }
    return;
  }
  final target = toMinor(account.currency, major);
  await ref.read(databaseProvider).adjustAccountBalance(
        account: account,
        targetBalanceMinor: target,
        currentBalanceMinor: currentBalanceMinor,
      );
  if (context.mounted) {
    showGlassSnackBar(context, '\u5df2\u8bb0\u5165\u4f59\u989d\u6821\u6b63');
  }
}

Future<void> _confirmArchive(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => CentliGlassDialog(
      title: const Text('\u5f52\u6863\u8d44\u4ea7\u8d26\u6237'),
      content: Text(
        '\u786e\u5b9a\u5f52\u6863\u300c${account.name}\u300d\uff1f\u5f52\u6863\u540e\u4e0d\u518d\u51fa\u73b0\u5728\u8d44\u4ea7\u5217\u8868\uff0c\u5386\u53f2\u6d41\u6c34\u4fdd\u7559\u3002',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('\u5f52\u6863'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await ref.read(databaseProvider).archiveAccount(account.id);
  if (context.mounted) {
    showGlassSnackBar(context, '\u5df2\u5f52\u6863');
    context.pop();
  }
}

Future<void> _confirmUnarchive(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => CentliGlassDialog(
      title: const Text('\u53d6\u6d88\u5f52\u6863'),
      content: Text(
        '\u786e\u5b9a\u53d6\u6d88\u5f52\u6863\u300c${account.name}\u300d\uff1f\u5c06\u91cd\u65b0\u51fa\u73b0\u5728\u8d44\u4ea7\u5217\u8868\u4e0e\u8bb0\u8d26\u9762\u677f\u3002',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('\u53d6\u6d88'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('\u53d6\u6d88\u5f52\u6863'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await ref.read(databaseProvider).unarchiveAccount(account.id);
  if (context.mounted) {
    showGlassSnackBar(context, '\u5df2\u53d6\u6d88\u5f52\u6863');
  }
}

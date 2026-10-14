import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/currencies.dart';
import '../../core/utils/date_range.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/date_range_control.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'assets_page.dart';

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

/// P0 account detail `/assets/:id`:
/// balance / currency / opening + monthly (range)流水; edit / adjust / archive / unarchive.
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_accountProvider(accountId));
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;

    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('\u8d26\u6237')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('\u8d26\u6237')),
        body: Center(child: Text('\u52a0\u8f7d\u5931\u8d25: $e')),
      ),
      data: (account) {
        if (account == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('\u8d26\u6237')),
            body: const Center(
              child: Text('\u8d26\u6237\u4e0d\u5b58\u5728'),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(account.name),
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
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'adjust') {
                  await _showAdjustBalance(context, ref, account, bal);
                } else if (v == 'archive') {
                  await _confirmArchive(context, ref, account);
                }
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'adjust',
                  child: Text('\u8c03\u6574\u4f59\u989d'),
                ),
                PopupMenuItem(
                  value: 'archive',
                  child: Text('\u5f52\u6863\u8d26\u6237'),
                ),
              ],
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (account.archived != 0)
            Card(
              color: scheme.secondaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.inventory_2_outlined,
                  color: scheme.onSecondaryContainer,
                ),
                title: Text(
                  '\u6b64\u8d26\u6237\u5df2\u5f52\u6863',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
                subtitle: Text(
                  '\u4e0d\u8ba1\u5165\u8d44\u4ea7\u5217\u8868\u4e0e\u603b\u8d44\u4ea7\uff1b\u5386\u53f2\u6d41\u6c34\u4ecd\u53ef\u67e5\u770b\u3002\u70b9\u53f3\u4e0a\u89d2\u53d6\u6d88\u5f52\u6863\u5373\u53ef\u6062\u590d\u3002',
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
            ),
          if (account.archived != 0) const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\u4f59\u989d',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatMinor(account.currency, bal, hide: hide),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _chip(context, '\u5e01\u79cd', account.currency),
                      const SizedBox(width: 8),
                      _chip(context, '\u7c7b\u578b', _typeLabel(account.type)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\u671f\u521d ${formatMinor(account.currency, account.openingBalanceMinor, hide: hide)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
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
          const SizedBox(height: 8),
          DateRangeControl(
            range: range,
            onChanged: (next) {
              ref.read(_accountRangeProvider(account.id).notifier).state = next;
            },
          ),
          const SizedBox(height: 8),
          Text('\u6d41\u6c34', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          txAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e'),
            data: (txns) {
              if (txns.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 40, color: scheme.outline),
                        const SizedBox(height: 8),
                        Text(
                          '\u8be5\u65f6\u6bb5\u65e0\u6d41\u6c34',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < txns.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _AccountTxnTile(
                        txn: txns[i],
                        accountId: account.id,
                        accountCurrency: account.currency,
                        hide: hide,
                      ),
                    ],
                  ],
                ),
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

  String _typeLabel(String type) {
    switch (type) {
      case 'cash':
        return '\u73b0\u91d1';
      case 'ewallet':
        return '\u7535\u5b50\u94b1\u5305';
      case 'bank':
        return '\u94f6\u884c\u5361';
      default:
        return '\u5176\u4ed6';
    }
  }
}

final _balancesForLedgerProvider =
    StreamProvider.family<Map<String, int>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchAccountBalances(ledgerId);
});

class _AccountTxnTile extends StatelessWidget {
  const _AccountTxnTile({
    required this.txn,
    required this.accountId,
    required this.accountCurrency,
    required this.hide,
  });

  final Transaction txn;
  final String accountId;
  final String accountCurrency;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signed = _signedMinor();
    final isNeg = signed < 0;
    final isZero = signed == 0;
    final prefix = isZero ? '' : (isNeg ? '-' : '+');
    final color = isZero
        ? scheme.onSurface
        : (isNeg ? scheme.error : scheme.primary);
    final time =
        DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true).toLocal();
    final timeLabel = DateFormat('MM-dd HH:mm').format(time);
    final title = txn.note?.isNotEmpty == true
        ? txn.note!
        : (txn.merchant ?? _typeLabel(txn.type));

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          txn.type == 'transfer'
              ? Icons.swap_horiz
              : (isNeg ? Icons.arrow_upward : Icons.arrow_downward),
          size: 18,
        ),
      ),
      title: Text(title),
      subtitle: Text('$timeLabel · ${_typeLabel(txn.type)}'),
      trailing: Text(
        '$prefix${formatMinor(_displayCurrency(), signed.abs(), hide: hide)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      onTap: () => context.push('/ledger/${txn.id}'),
    );
  }

  /// Effect on this account's balance in account currency units.
  int _signedMinor() {
    if (txn.type == 'in') return txn.amountMinor;
    if (txn.type == 'out') return -txn.amountMinor;
    // transfer
    if (txn.accountId == accountId) return -txn.amountMinor;
    // incoming leg
    return txn.toAmountMinor ?? txn.amountMinor;
  }

  String _displayCurrency() {
    // Incoming cross-currency transfer credits are in this account's currency.
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

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('\u8c03\u6574\u4f59\u989d'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '\u5f53\u524d ${formatMinor(account.currency, currentBalanceMinor)}',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '\u76ee\u6807\u4f59\u989d',
              border: const OutlineInputBorder(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u8f93\u5165\u6709\u6548\u91d1\u989d')),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u5df2\u8bb0\u5165\u4f59\u989d\u6821\u6b63')),
    );
  }
}

Future<void> _confirmArchive(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('\u5f52\u6863\u8d26\u6237'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u5df2\u5f52\u6863')),
    );
    context.pop();
  }
}

Future<void> _confirmUnarchive(
  BuildContext context,
  WidgetRef ref,
  Account account,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('\u5df2\u53d6\u6d88\u5f52\u6863')),
    );
  }
}

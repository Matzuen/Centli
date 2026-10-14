import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/currencies.dart';
import '../../core/utils/money.dart';
import '../../core/utils/fx.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';

final _accountsProvider =
    StreamProvider.family<List<Account>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchActiveAccounts(ledgerId);
});

final _archivedAccountsProvider =
    StreamProvider.family<List<Account>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchArchivedAccounts(ledgerId);
});

final _balancesProvider =
    StreamProvider.family<Map<String, int>, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).watchAccountBalances(ledgerId);
});

final _netWorthBaseProvider = FutureProvider.family<
    BaseNetWorth, ({String ledgerId, String base})>((ref, args) async {
  // Recompute when balances or FX book change.
  await ref.watch(_balancesProvider(args.ledgerId).future);
  await ref.watch(fxBookProvider.future);
  return ref.read(databaseProvider).netWorthInBase(args.ledgerId, args.base);
});

class AssetsPage extends ConsumerStatefulWidget {
  const AssetsPage({super.key});

  @override
  ConsumerState<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends ConsumerState<AssetsPage> {
  /// false = active, true = archived
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('资产'),
        actions: [
          if (!_showArchived)
            IconButton(
              tooltip: '添加账户',
              onPressed: () async {
                final ledger = ledgerAsync.valueOrNull;
                if (ledger == null) return;
                await showAccountEditor(context, ref, ledgerId: ledger.id);
              },
              icon: const Icon(Icons.add),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('使用中'),
                  icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('已归档'),
                  icon: Icon(Icons.inventory_2_outlined, size: 18),
                ),
              ],
              selected: {_showArchived},
              onSelectionChanged: (s) {
                setState(() => _showArchived = s.first);
              },
            ),
          ),
        ),
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) {
          if (ledger == null) {
            return const Center(child: Text('尚未初始化账本'));
          }
          final ledgerId = ledger.id;
          final base = ledger.baseCurrency;
          final accountsAsync = _showArchived
              ? ref.watch(_archivedAccountsProvider(ledgerId))
              : ref.watch(_accountsProvider(ledgerId));
          final balancesAsync = ref.watch(_balancesProvider(ledgerId));
          return accountsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (accounts) {
              final balances = balancesAsync.valueOrNull ?? {};
              if (accounts.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showArchived
                              ? Icons.inventory_2_outlined
                              : Icons.account_balance_wallet_outlined,
                          size: 56,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _showArchived
                              ? '暂无已归档账户'
                              : '暂无账户',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _showArchived
                              ? '归档的账户会出现在这里'
                              : '点右上角 + 添加',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final byCcy = <String, List<Account>>{};
              for (final a in accounts) {
                byCcy.putIfAbsent(a.currency, () => []).add(a);
              }
              final orderedKeys = [
                ...supportedCurrencies.where(byCcy.containsKey),
                ...byCcy.keys.where((k) => !supportedCurrencies.contains(k)),
              ];

              final nwArgs = (ledgerId: ledgerId, base: base);
              final netWorthAsync = _showArchived
                  ? null
                  : ref.watch(_netWorthBaseProvider(nwArgs));

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!_showArchived)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: netWorthAsync == null
                            ? const SizedBox.shrink()
                            : netWorthAsync.when(
                                loading: () => const SizedBox(
                                  height: 72,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                error: (e, _) => Text('$e'),
                                data: (nw) {
                                  final leftover = nw.unconvertedByCcy.entries
                                      .toList()
                                    ..sort((a, b) => a.key.compareTo(b.key));
                                  final subtitle = leftover.isEmpty
                                      ? '\u4f59\u989d = \u671f\u521d + \u6536\u5165 - \u652f\u51fa \u00b1 \u8f6c\u8d26\uff08\u5916\u5e01\u6309\u4eca\u65e5/\u8fd1\u65e5\u6c47\u7387\u6298\u7b97\uff09'
                                      : '\u90e8\u5206\u5e01\u79cd\u672a\u6298\u7b97\uff1a${leftover.map((e) => '${e.key} ${formatMinor(e.key, e.value, hide: hide)}').join(' \u00b7 ')}';
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '\u51c0\u989d\uff08\u672c\u4f4d\u5e01 $base\uff09',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        formatMinor(base, nw.totalMinor,
                                            hide: hide),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ),
                  if (!_showArchived) const SizedBox(height: 16),
                  if (_showArchived)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '已归档账户不计入总资产，可点进详情取消归档。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  for (final ccy in orderedKeys) ...[
                    Text(ccy, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < byCcy[ccy]!.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            Builder(
                              builder: (context) {
                                final a = byCcy[ccy]![i];
                                final bal =
                                    balances[a.id] ?? a.openingBalanceMinor;
                                return ListTile(
                                  leading: CircleAvatar(
                                    child: Text(_typeIcon(a.type)),
                                  ),
                                  title: Text(a.name),
                                  subtitle: Text(
                                    _showArchived
                                        ? '${_typeLabel(a.type)} · 已归档'
                                        : _typeLabel(a.type),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formatMinor(a.currency, bal,
                                            hide: hide),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: _showArchived
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                              : null,
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right),
                                    ],
                                  ),
                                  onTap: () =>
                                      context.push('/assets/${a.id}'),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  String _typeIcon(String type) {
    switch (type) {
      case 'cash':
        return '现';
      case 'ewallet':
        return '钱';
      case 'bank':
        return '卡';
      default:
        return '户';
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'cash':
        return '现金';
      case 'ewallet':
        return '电子钱包';
      case 'bank':
        return '银行';
      default:
        return '其他';
    }
  }
}


Future<void> showAccountEditor(
  BuildContext context,
  WidgetRef ref, {
  required String ledgerId,
  Account? existing,
}) async {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final openingCtrl = TextEditingController(
    text: existing == null
        ? '0'
        : fromMinor(existing.currency, existing.openingBalanceMinor)
            .toStringAsFixed(currencyDecimals[existing.currency] ?? 2),
  );
  var currency = existing?.currency ?? 'CNY';
  var type = existing?.type ?? 'cash';

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final decimals = currencyDecimals[currency] ?? 2;
          return AlertDialog(
            title: Text(existing == null ? '\u65b0\u5efa\u8d26\u6237' : '\u7f16\u8f91\u8d26\u6237'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '\u540d\u79f0',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: existing == null
                        ? (v) {
                            if (v != null) setLocal(() => currency = v);
                          }
                        : null,
                    decoration: const InputDecoration(
                      labelText: '\u5e01\u79cd',
                      border: OutlineInputBorder(),
                      helperText: '\u5df2\u6709\u8d26\u6237\u5e01\u79cd\u4e0d\u5efa\u8bae\u4fee\u6539',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('\u73b0\u91d1')),
                      DropdownMenuItem(
                          value: 'bank', child: Text('\u94f6\u884c')),
                      DropdownMenuItem(
                          value: 'ewallet', child: Text('\u7535\u5b50\u94b1\u5305')),
                      DropdownMenuItem(
                          value: 'other', child: Text('\u5176\u4ed6')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => type = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '\u7c7b\u578b',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: openingCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '\u671f\u521d\u4f59\u989d',
                      border: const OutlineInputBorder(),
                      helperText: decimals == 0
                          ? '\u65e0\u5c0f\u6570\uff08$currency\uff09'
                          : '$decimals \u4f4d\u5c0f\u6570',
                    ),
                  ),
                ],
              ),
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
          );
        },
      );
    },
  );

  if (saved != true) {
    nameCtrl.dispose();
    openingCtrl.dispose();
    return;
  }

  final name = nameCtrl.text.trim();
  final openingMajor = double.tryParse(openingCtrl.text.trim()) ?? 0;
  nameCtrl.dispose();
  openingCtrl.dispose();

  if (name.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u8f93\u5165\u8d26\u6237\u540d\u79f0')),
      );
    }
    return;
  }

  final db = ref.read(databaseProvider);
  final openingMinor = toMinor(currency, openingMajor);
  if (existing == null) {
    await db.createAccount(
      ledgerId: ledgerId,
      name: name,
      currency: currency,
      type: type,
      openingBalanceMinor: openingMinor,
    );
  } else {
    await db.updateAccount(
      id: existing.id,
      name: name,
      currency: currency,
      type: type,
      openingBalanceMinor: openingMinor,
    );
  }
}
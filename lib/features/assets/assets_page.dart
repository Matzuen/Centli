import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/icon_picker_sheet.dart';
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
  bool _showArchived = false;

  static const _donutColors = [
    Color(0xFFE53935),
    Color(0xFF26A69A),
    Color(0xFFFBC02D),
    Color(0xFFFF8A65),
    Color(0xFF7E57C2),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFAB47BC),
  ];

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: CentliTheme.scaffoldGradient(dark: dark),
        child: SafeArea(
          bottom: false,
          child: ledgerAsync.when(
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
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (accounts) {
                  final balances = balancesAsync.valueOrNull ?? {};
                  final nwArgs = (ledgerId: ledgerId, base: base);
                  final netWorthAsync = _showArchived
                      ? null
                      : ref.watch(_netWorthBaseProvider(nwArgs));

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    children: [
                      Row(
                        children: [
                          Text(
                            '资产',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          if (!_showArchived)
                            IconButton(
                              tooltip: '添加账户',
                              onPressed: () async {
                                await showAccountEditor(
                                  context,
                                  ref,
                                  ledgerId: ledger.id,
                                );
                              },
                              icon: const Icon(Icons.add_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _Seg(
                                label: '使用中',
                                selected: !_showArchived,
                                onTap: () =>
                                    setState(() => _showArchived = false),
                              ),
                            ),
                            Expanded(
                              child: _Seg(
                                label: '已归档',
                                selected: _showArchived,
                                onTap: () =>
                                    setState(() => _showArchived = true),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!_showArchived && netWorthAsync != null)
                        netWorthAsync.when(
                          loading: () => const CentliSoftCard(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) => Text('$e'),
                          data: (nw) {
                            final net = nw.totalMinor;
                            final positives = <({Account a, int bal})>[];
                            var assetSum = 0;
                            var liabilitySum = 0;
                            for (final a in accounts) {
                              final bal =
                                  balances[a.id] ?? a.openingBalanceMinor;
                              if (bal >= 0) {
                                assetSum += bal;
                                positives.add((a: a, bal: bal));
                              } else {
                                liabilitySum += -bal;
                              }
                            }
                            // Prefer converted net for headline when single-ccy.
                            return Column(
                              children: [
                                CentliSoftCard(
                                  padding: const EdgeInsets.fromLTRB(
                                      18, 16, 18, 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '净资产',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        formatMinor(base, net, hide: hide),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                const Icon(Icons.circle,
                                                    size: 8,
                                                    color: CentliTheme
                                                        .incomeGreen),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '总资产  ${formatMinor(base, assetSum > 0 ? assetSum : (net > 0 ? net : 0), hide: hide)}',
                                                  style: const TextStyle(
                                                      fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Row(
                                              children: [
                                                const Icon(Icons.circle,
                                                    size: 8,
                                                    color: CentliTheme
                                                        .expenseRed),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '总负债  ${formatMinor(base, liabilitySum, hide: hide)}',
                                                  style: const TextStyle(
                                                      fontSize: 13),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (positives.isNotEmpty)
                                  CentliSoftCard(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 14, 16, 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '资产分析',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          height: 150,
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: PieChart(
                                                  PieChartData(
                                                    sectionsSpace: 2,
                                                    centerSpaceRadius: 34,
                                                    sections: [
                                                      for (var i = 0;
                                                          i < positives.length;
                                                          i++)
                                                        PieChartSectionData(
                                                          value: positives[i]
                                                              .bal
                                                              .toDouble()
                                                              .clamp(
                                                                  1, 1e18),
                                                          color: _donutColors[
                                                              i %
                                                                  _donutColors
                                                                      .length],
                                                          radius: 28,
                                                          title: '',
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: ListView(
                                                  children: [
                                                    for (var i = 0;
                                                        i < positives.length &&
                                                            i < 6;
                                                        i++)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                bottom: 6),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              width: 10,
                                                              height: 10,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: _donutColors[
                                                                    i %
                                                                        _donutColors
                                                                            .length],
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            2),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 6),
                                                            Expanded(
                                                              child: Text(
                                                                positives[i]
                                                                    .a
                                                                    .name,
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style:
                                                                    const TextStyle(
                                                                        fontSize:
                                                                            12),
                                                              ),
                                                            ),
                                                            Text(
                                                              _pct(
                                                                positives[i]
                                                                    .bal,
                                                                assetSum == 0
                                                                    ? 1
                                                                    : assetSum,
                                                              ),
                                                              style:
                                                                  const TextStyle(
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      if (_showArchived)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12, top: 4),
                          child: Text(
                            '已归档账户不计入总资产，可点进详情取消归档。',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      if (accounts.isEmpty)
                        CentliSoftCard(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              Icon(
                                _showArchived
                                    ? Icons.inventory_2_outlined
                                    : Icons.account_balance_wallet_outlined,
                                size: 48,
                                color: scheme.outline,
                              ),
                              const SizedBox(height: 10),
                              Text(_showArchived ? '暂无已归档账户' : '暂无账户'),
                            ],
                          ),
                        )
                      else ...[
                        const SizedBox(height: 12),
                        ..._groupedCards(
                          context,
                          accounts: accounts,
                          balances: balances,
                          hide: hide,
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  String _pct(int part, int total) {
    final p = total <= 0 ? 0.0 : part * 100.0 / total;
    return '${p.toStringAsFixed(p >= 10 ? 0 : 1)}%';
  }

  List<Widget> _groupedCards(
    BuildContext context, {
    required List<Account> accounts,
    required Map<String, int> balances,
    required bool hide,
  }) {
    final groups = <String, List<Account>>{
      '在线': [],
      '储蓄': [],
      '现金': [],
      '其他': [],
    };
    for (final a in accounts) {
      switch (a.type) {
        case 'ewallet':
          groups['在线']!.add(a);
          break;
        case 'bank':
          groups['储蓄']!.add(a);
          break;
        case 'cash':
          groups['现金']!.add(a);
          break;
        default:
          groups['其他']!.add(a);
      }
    }
    final out = <Widget>[];
    for (final entry in groups.entries) {
      if (entry.value.isEmpty) continue;
      var sum = 0;
      for (final a in entry.value) {
        sum += balances[a.id] ?? a.openingBalanceMinor;
      }
      final ccy = entry.value.first.currency;
      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CentliSoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        entry.key,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        formatMinor(ccy, sum, hide: hide),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < entry.value.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(
                    builder: (context) {
                      final a = entry.value[i];
                      final bal = balances[a.id] ?? a.openingBalanceMinor;
                      return ListTile(
                        leading: CentliIconChip(
                          name: a.name,
                          iconKey: a.icon,
                          size: 40,
                          roundedSquare: true,
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
                              formatMinor(a.currency, bal, hide: hide),
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
                        onTap: () => context.push('/assets/${a.id}'),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return out;
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

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
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
  String? iconKey = existing?.icon;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final decimals = currencyDecimals[currency] ?? 2;
          return AlertDialog(
            title: Text(existing == null ? '新建账户' : '编辑账户'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      final picked = await showCentliIconPicker(
                        ctx,
                        currentIconKey: iconKey,
                        entityName: nameCtrl.text.trim(),
                      );
                      if (picked != null) {
                        setLocal(() => iconKey = picked.iconKey);
                      }
                    },
                    child: Column(
                      children: [
                        CentliIconChip(
                          name: nameCtrl.text.trim().isEmpty
                              ? '账户'
                              : nameCtrl.text.trim(),
                          iconKey: iconKey,
                          size: 56,
                          roundedSquare: true,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '点按选择图标',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Theme.of(ctx).colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setLocal(() {}),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(value: c, child: Text(currencyLabel(c))),
                    ],
                    onChanged: existing == null
                        ? (v) {
                            if (v != null) setLocal(() => currency = v);
                          }
                        : null,
                    decoration: const InputDecoration(
                      labelText: '币种',
                      border: OutlineInputBorder(),
                      helperText: '已有账户币种不建议修改',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('现金')),
                      DropdownMenuItem(value: 'bank', child: Text('银行')),
                      DropdownMenuItem(
                          value: 'ewallet', child: Text('电子钱包')),
                      DropdownMenuItem(value: 'other', child: Text('其他')),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => type = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '类型',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: openingCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '期初余额',
                      border: const OutlineInputBorder(),
                      helperText: decimals == 0
                          ? '无小数（$currency）'
                          : '$decimals 位小数',
                    ),
                  ),
                ],
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
        const SnackBar(content: Text('请输入账户名称')),
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
      icon: iconKey,
    );
  } else {
    await db.updateAccount(
      id: existing.id,
      name: name,
      currency: currency,
      type: type,
      openingBalanceMinor: openingMinor,
      icon: iconKey,
    );
  }
}

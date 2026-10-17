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

final _accountsProvider = StreamProvider.family<List<Account>, String>((
  ref,
  ledgerId,
) {
  return ref.watch(databaseProvider).watchActiveAccounts(ledgerId);
});

final _archivedAccountsProvider = StreamProvider.family<List<Account>, String>((
  ref,
  ledgerId,
) {
  return ref.watch(databaseProvider).watchArchivedAccounts(ledgerId);
});

final _balancesProvider = StreamProvider.family<Map<String, int>, String>((
  ref,
  ledgerId,
) {
  // Opening balance lives on accounts — restart when accounts change.
  ref.watch(_accountsProvider(ledgerId));
  return ref.watch(databaseProvider).watchAccountBalances(ledgerId);
});

final _assetTypesProvider =
    StreamProvider.family<List<AssetType>, String>((ref, ledgerId) {
  return ref
      .watch(databaseProvider)
      .watchAssetTypes(ledgerId, includeArchived: true);
});


final _netWorthBaseProvider =
    FutureProvider.family<BaseNetWorth, ({String ledgerId, String base})>((
      ref,
      args,
    ) async {
      await ref.watch(_balancesProvider(args.ledgerId).future);
      await ref.watch(_accountsProvider(args.ledgerId).future);
      await ref.watch(fxBookProvider.future);
      return ref
          .read(databaseProvider)
          .netWorthInBase(args.ledgerId, args.base);
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
              final activeAccountsAsync = ref.watch(_accountsProvider(ledgerId));
              final accountsAsync = _showArchived
                  ? ref.watch(_archivedAccountsProvider(ledgerId))
                  : activeAccountsAsync;
              final balancesAsync = ref.watch(_balancesProvider(ledgerId));
              final typesAsync = ref.watch(_assetTypesProvider(ledgerId));
              return accountsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (accounts) {
                  final balances = balancesAsync.valueOrNull ?? {};
                  final nwArgs = (ledgerId: ledgerId, base: base);
                  // Always show net-worth card (active accounts); avoid empty gap in archive tab.
                  final netWorthAsync = ref.watch(_netWorthBaseProvider(nwArgs));
                  final cardAccounts =
                      activeAccountsAsync.valueOrNull ?? const <Account>[];

                  return ListView(
                    padding: CentliSpacing.pagePaddingNav,
                    children: [
                      Row(
                        children: [
                          Text(
                            '资产',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Spacer(),
                          if (!_showArchived) ...[
                            IconButton(
                              tooltip: '资产分类',
                              onPressed: () => context.push('/assets/types'),
                              icon: const Icon(Icons.category_outlined),
                            ),
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
                        ],
                      ),
                      const SizedBox(height: CentliSpacing.item),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
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
                      const SizedBox(height: CentliSpacing.section),
                      netWorthAsync.when(
                          loading: () => const CentliSoftCard(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                          error: (e, _) => Text('$e'),
                          data: (nw) {
                            final net = nw.totalMinor;
                            final book =
                                ref.watch(fxBookProvider).valueOrNull;
                            final day = FxBook.todayLocal();
                            final split = book == null
                                ? null
                                : assetLiabilityInBase(
                                    accounts: [
                                      for (final a in cardAccounts)
                                        (
                                          currency: a.currency,
                                          balanceMinor: balances[a.id] ??
                                              a.openingBalanceMinor,
                                        ),
                                    ],
                                    book: book,
                                    baseCurrency: base,
                                    onDay: day,
                                  );
                            final assetSum = split?.assetMinor ?? 0;
                            final liabilitySum = split?.liabilityMinor ?? 0;
                            final positives = <({Account a, int bal})>[];
                            for (final a in cardAccounts) {
                              final bal =
                                  balances[a.id] ?? a.openingBalanceMinor;
                              if (bal >= 0) {
                                positives.add((a: a, bal: bal));
                              }
                            }
                            final unconverted = nw.unconvertedByCcy;
                            final unconvertedHint = unconverted.isEmpty
                                ? null
                                : '未折算：${unconverted.entries.map((e) => '${e.key} ${formatMinor(e.key, e.value, hide: hide)}').join('、')}';
                            return Column(
                              children: [
                                CentliSoftCard(
                                  padding: const EdgeInsets.fromLTRB(
                                    18,
                                    16,
                                    18,
                                    16,
                                  ),
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
                                      const SizedBox(
                                        height: CentliSpacing.item,
                                      ),
                                      Text(
                                        formatMinor(base, net, hide: hide),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(
                                        height: CentliSpacing.section,
                                      ),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.circle,
                                                  size: 8,
                                                  color:
                                                      CentliTheme.incomeGreen,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    '总资产  ${formatMinor(base, assetSum, hide: hide)}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.circle,
                                                  size: 8,
                                                  color: CentliTheme.expenseRed,
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    '总负债  ${formatMinor(base, liabilitySum, hide: hide)}',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (unconvertedHint != null) ...[
                                        const SizedBox(
                                          height: CentliSpacing.item,
                                        ),
                                        Text(
                                          unconvertedHint,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(height: CentliSpacing.section),
                                if (positives.isNotEmpty)
                                  CentliSoftCard(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      14,
                                      16,
                                      14,
                                    ),
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
                                        const SizedBox(
                                          height: CentliSpacing.section,
                                        ),
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
                                                      for (
                                                        var i = 0;
                                                        i < positives.length;
                                                        i++
                                                      )
                                                        PieChartSectionData(
                                                          value: positives[i]
                                                              .bal
                                                              .toDouble()
                                                              .clamp(1, 1e18),
                                                          color:
                                                              _donutColors[i %
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
                                                    for (
                                                      var i = 0;
                                                      i < positives.length &&
                                                          i < 6;
                                                      i++
                                                    )
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              bottom: 6,
                                                            ),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              width: 10,
                                                              height: 10,
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    _donutColors[i %
                                                                        _donutColors
                                                                            .length],
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      2,
                                                                    ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
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
                                                                          12,
                                                                    ),
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
                                                              style: const TextStyle(
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12, top: 4),
                        child: Text(
                          _showArchived
                              ? '已归档账户不计入总资产，可点进详情取消归档。'
                              : '找不到账户？可到「已归档」查看；归档账户不计入总资产。',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (accounts.isEmpty)
                        CentliSoftCard(
                          child: CentliEmptyState(
                            icon: _showArchived
                                ? Icons.inventory_2_outlined
                                : Icons.account_balance_wallet_outlined,
                            title: _showArchived ? '暂无已归档账户' : '暂无账户',
                            message: _showArchived
                                ? '归档账户不计入总资产，可在详情中恢复。'
                                : '添加现金、银行卡或信用账户后，这里会汇总净资产。',
                            padding: const EdgeInsets.all(CentliSpacing.cardPad),
                          ),
                        )
                      else ...[
                        const SizedBox(height: CentliSpacing.section),
                        ..._groupedCards(
                          context,
                          accounts: accounts,
                          types: typesAsync.valueOrNull ?? const <AssetType>[],
                          balances: balances,
                          hide: hide,
                          base: base,
                          book: ref.watch(fxBookProvider).valueOrNull,
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
    required List<AssetType> types,
    required Map<String, int> balances,
    required bool hide,
    required String base,
    required FxBook? book,
  }) {
    final day = FxBook.todayLocal();
    final typeById = {for (final t in types) t.id: t};
    AssetType? otherType;
    for (final t in types) {
      if (t.name == '其他') {
        otherType = t;
        break;
      }
    }
    // Ordered buckets by sortOrder; virtual 其他 for orphans if needed.
    final orderedIds = [for (final t in types) t.id];
    final groups = <String, List<Account>>{for (final id in orderedIds) id: []};
    const virtualOther = '__virtual_other__';
    var needVirtual = false;

    for (final a in accounts) {
      if (groups.containsKey(a.type)) {
        groups[a.type]!.add(a);
      } else if (otherType != null) {
        groups[otherType.id]!.add(a);
      } else {
        needVirtual = true;
        groups.putIfAbsent(virtualOther, () => []).add(a);
      }
    }

    String labelFor(String key) {
      if (key == virtualOther) return '其他';
      return typeById[key]?.name ?? '其他';
    }

    final out = <Widget>[];
    final keys = [
      ...orderedIds,
      if (needVirtual) virtualOther,
    ];
    for (final key in keys) {
      final list = groups[key];
      if (list == null || list.isEmpty) continue;
      // Skip archived types with no accounts (already empty-skipped).
      var sumBase = 0;
      final groupUnconverted = <String, int>{};
      for (final a in list) {
        final bal = balances[a.id] ?? a.openingBalanceMinor;
        final asBase = book == null
            ? (a.currency == base ? bal : null)
            : balanceInBase(
                currency: a.currency,
                balanceMinor: bal,
                book: book,
                baseCurrency: base,
                onDay: day,
              );
        if (asBase == null) {
          groupUnconverted[a.currency] =
              (groupUnconverted[a.currency] ?? 0) + bal;
        } else {
          sumBase += asBase;
        }
      }
      final sumLabel = formatMinor(base, sumBase, hide: hide);
      final unconvertedSuffix = groupUnconverted.isEmpty
          ? ''
          : ' · 未折算：${groupUnconverted.entries.map((e) => '${e.key} ${formatMinor(e.key, e.value, hide: hide)}').join('、')}';
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
                        labelFor(key),
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          '$sumLabel$unconvertedSuffix',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  Builder(
                    builder: (context) {
                      final a = list[i];
                      final bal = balances[a.id] ?? a.openingBalanceMinor;
                      final typeName = labelFor(a.type);
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
                              ? '$typeName · 已归档'
                              : typeName,
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
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Selected pill must keep label contrast in dark mode (white + onSurface was unreadable).
    final bg = !selected
        ? Colors.transparent
        : (dark ? scheme.primaryContainer : Colors.white);
    final fg = !selected
        ? scheme.onSurfaceVariant
        : (dark ? scheme.onPrimaryContainer : scheme.onSurface);
    return Material(
      color: bg,
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
              color: fg,
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
        : fromMinor(
            existing.currency,
            existing.openingBalanceMinor,
          ).toStringAsFixed(currencyDecimals[existing.currency] ?? 2),
  );
  var currency = existing?.currency ?? 'CNY';
  final db = ref.read(databaseProvider);
  final allTypes = await db.loadAssetTypes(ledgerId, includeArchived: true);
  final activeTypes = [for (final t in allTypes) if (t.archived == 0) t];
  String type;
  if (existing != null) {
    type = existing.type;
  } else if (activeTypes.isNotEmpty) {
    type = activeTypes.first.id;
  } else if (allTypes.isNotEmpty) {
    type = allTypes.first.id;
  } else {
    type = await db.resolveAssetTypeId(ledgerId: ledgerId, raw: 'cash');
  }
  // Dropdown: active types + current value if archived
  final dropdownTypes = <AssetType>[
    ...activeTypes,
    if (existing != null &&
        !activeTypes.any((t) => t.id == existing.type))
      ...allTypes.where((t) => t.id == existing.type),
  ];
  String? iconKey = existing?.icon;

  if (!context.mounted) return;
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
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(
                          value: c,
                          child: Text(currencyLabel(c)),
                        ),
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
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: dropdownTypes.any((t) => t.id == type)
                        ? type
                        : (dropdownTypes.isNotEmpty
                            ? dropdownTypes.first.id
                            : null),
                    items: [
                      for (final t in dropdownTypes)
                        DropdownMenuItem(
                          value: t.id,
                          enabled: t.archived == 0 || t.id == type,
                          child: Text(
                            t.archived != 0 ? '${t.name}（已归档）' : t.name,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => type = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '分类',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextField(
                    controller: openingCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入账户名称')));
    }
    return;
  }

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
    if (openingMinor != existing.openingBalanceMinor) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认修改期初余额'),
          content: const Text(
            '修改期初余额会改变该账户全部历史余额的起点，确认继续？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认修改'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!context.mounted) return;
    }
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

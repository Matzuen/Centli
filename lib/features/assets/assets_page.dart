import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/widgets/centli_error_state.dart';
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


/// Test-only public alias for assets net-worth provider (G22 consistency).
@visibleForTesting
final assetsNetWorthProvider = _netWorthBaseProvider;

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

/// 环形图配色（资产分析按类型着色）。
const kAssetsDonutColors = <Color>[

    Color(0xFFE53935),
    Color(0xFF26A69A),
    Color(0xFFFBC02D),
    Color(0xFFFF8A65),
    Color(0xFF7E57C2),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFAB47BC),
  ];

class _AssetsPageState extends ConsumerState<AssetsPage> {
  bool _showArchived = false;



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
            error: (e, _) => CentliErrorState(error: e, compact: true),
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
                error: (e, _) => CentliErrorState(error: e, compact: true),
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
                          error: (e, _) => CentliErrorState(error: e, compact: true),
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
                            // 资产分析按**账户类型**汇总（银行 / 线上 / 信用卡 …），
                            // 金额折算成本位币；负余额的账户类型也计入，占比带负号。
                            final typeSlices = assetTypeSlices(
                              accounts: cardAccounts,
                              balances: balances,
                              types: typesAsync.valueOrNull ??
                                  const <AssetType>[],
                              book: book,
                              baseCurrency: base,
                              onDay: day,
                            );
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
                                            .labelMedium
                                            ?.copyWith(
                                              color:
                                                  scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: CentliSpacing.dense),
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
                                      _AssetLiabilityLine(
                                        assets:
                                            '总资产  ${formatMinor(base, assetSum, hide: hide)}',
                                        liabilities:
                                            '总负债  ${formatMinor(base, liabilitySum, hide: hide)}',
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
                                if (typeSlices.isNotEmpty)
                                  _AssetAnalysisCard(
                                    key: const Key('assets_analysis_card'),
                                    slices: typeSlices,
                                    base: base,
                                    hide: hide,
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
                                : '还没有账户。先记一笔，Centli 会自动使用默认账户；'
                                    '也可以点下面的按钮添加现金 / 银行卡 / 信用账户。',
                            padding: const EdgeInsets.all(CentliSpacing.cardPad),
                            action: _showArchived
                                ? null
                                : FilledButton.tonalIcon(
                                    key: const Key('assets_add_first'),
                                    onPressed: () async {
                                      await showAccountEditor(
                                        context,
                                        ref,
                                        ledgerId: ledger.id,
                                      );
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: const Text('添加第一个账户'),
                                  ),
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
                  padding: const EdgeInsets.fromLTRB(CentliSpacing.cardPad, CentliSpacing.cardPad, CentliSpacing.cardPad, CentliSpacing.dense),
                  child: Row(
                    children: [
                      Text(
                        labelFor(key),
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$sumLabel$unconvertedSuffix',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                        title: Text(
                          a.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _showArchived
                              ? '$typeName · 已归档'
                              : typeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // No chevron: with it the amount had to share the
                        // right edge. The row itself still navigates.
                        // 约束宽度：大字号/大金额时不能让 trailing 吃掉整行。
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            formatMinor(a.currency, bal, hide: hide),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _showArchived
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant
                                  : null,
                            ),
                          ),
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

/// 资产分析的一个扇区：按账户类型汇总（本位币）。
typedef AssetTypeSlice = ({String name, int totalMinor, String pct});

/// 百分比文字：`80%` / `0%` / `−24.6%`（负号在括号内，与设计稿一致）。
@visibleForTesting
String assetTypePctLabel(int part, int denominator) {
  if (denominator == 0) return '0%';
  final p = part * 100.0 / denominator;
  final abs = p.abs();
  // One decimal up to 100% so small slices keep their precision
  // (−24.6%, 0.5%, 2.3%), and exact integers never show a trailing .0.
  final digits = abs >= 100 ? 0 : 1;
  final body = abs.toStringAsFixed(digits);
  // Drop the trailing ".0" only when it is exactly integral.
  final trimmed = body.endsWith('.0') ? body.substring(0, body.length - 2) : body;
  if (abs == 0) return '0%';
  final sign = p < -0.05 ? '−' : '';
  return '$sign$trimmed%';
}

/// 按账户类型汇总余额（折算成本位币），返回按类型顺序排列的扇区。
///
/// - 分母是**全部**账户的绝对额之和（含负债），所以负余额类型会得到负的
///   百分比（钱包 −200 在总和 800 时是 −24.6%）。
/// - 没有账户的类型跳过；有账户但余额为 0 的类型保留（显示 0%）。
@visibleForTesting
List<AssetTypeSlice> assetTypeSlices({
  required List<Account> accounts,
  required Map<String, int> balances,
  required List<AssetType> types,
  required FxBook? book,
  required String baseCurrency,
  required String onDay,
}) {
  final visible = accounts;
  if (visible.isEmpty) return const [];
  final typeById = {for (final t in types) t.id: t};
  AssetType? fallback;
  for (final t in types) {
    if (t.name == '其他') {
      fallback = t;
      break;
    }
  }

  // Sum per type id (accounts with an unknown type fall back to 其他).
  final byType = <String, int>{};
  final order = <String>[];
  const virtualOther = '__virtual_other__';
  for (final t in types) {
    order.add(t.id);
  }
  for (final a in visible) {
    final key = types.any((t) => t.id == a.type)
        ? a.type
        : (fallback?.id ?? virtualOther);
    if (!byType.containsKey(key)) {
      byType[key] = 0;
      if (!order.contains(key)) order.add(key);
    }
    final bal = balances[a.id] ?? a.openingBalanceMinor;
    final asBase = book == null
        ? (a.currency == baseCurrency ? bal : null)
        : balanceInBase(
            currency: a.currency,
            balanceMinor: bal,
            book: book,
            baseCurrency: baseCurrency,
            onDay: onDay,
          );
    // Unconvertible foreign balances are excluded (same rule as totals).
    if (asBase != null) byType[key] = byType[key]! + asBase;
  }

  var denominator = 0;
  for (final v in byType.values) {
    denominator += v.abs();
  }

  final out = <AssetTypeSlice>[];
  for (final key in order) {
    final total = byType[key];
    if (total == null) continue;
    final name = key == virtualOther ? '其他' : (typeById[key]?.name ?? '其他');
    out.add((
      name: name,
      totalMinor: total,
      pct: assetTypePctLabel(total, denominator),
    ));
  }
  return out;
}

/// 净资产卡片底部：总资产靠左、总负债靠右，中间至少留 28。
class _AssetLiabilityLine extends StatelessWidget {
  const _AssetLiabilityLine({
    required this.assets,
    required this.liabilities,
  });

  final String assets;
  final String liabilities;

  static const _style = TextStyle(fontSize: 13);
  static const _iconWidth = 14.0;
  static const _minGap = 28.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        // TextPainter 往往比实际渲染窄一点，多留 4 避免挤出卡片。
        final leftNatural =
            _iconWidth + _textWidth(assets, scaler, direction) + 4;
        final rightNatural =
            _iconWidth + _textWidth(liabilities, scaler, direction) + 4;
        final spare = constraints.maxWidth - leftNatural - rightNatural;
        var leftW = leftNatural;
        var rightW = rightNatural;
        if (spare < _minGap) {
          final budget =
              (constraints.maxWidth - _minGap).clamp(0.0, double.infinity);
          final sum = leftNatural + rightNatural;
          if (sum > budget && sum > 0) {
            leftW = leftNatural * budget / sum;
            rightW = budget - leftW;
          }
        }
        return Row(
          children: [
            _side(CentliTheme.incomeGreen, assets, leftW),
            if (spare >= _minGap)
              const Spacer()
            else
              const SizedBox(width: _minGap),
            _side(CentliTheme.expenseRed, liabilities, rightW),
          ],
        );
      },
    );
  }

  static double _textWidth(
    String text,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: _style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  Widget _side(Color color, String text, double width) {
    return SizedBox(
      width: width,
      child: Row(
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _style,
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片 2：资产分析 —— 环形图（左）+ 图例（右，名称 + 金额 + 百分比）。
class _AssetAnalysisCard extends StatelessWidget {
  const _AssetAnalysisCard({
    super.key,
    required this.slices,
    required this.base,
    required this.hide,
  });

  final List<AssetTypeSlice> slices;
  final String base;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Negative slices are liabilities: draw them in the expense red, the rest
    // cycle through the palette.
    var paletteIndex = 0;
    const liabilityColor = CentliTheme.expenseRed;
    final colors = <Color>[];
    for (final s in slices) {
      if (s.totalMinor < 0) {
        colors.add(liabilityColor);
        continue;
      }
      var c = kAssetsDonutColors[paletteIndex % kAssetsDonutColors.length];
      // Never let a positive slice reuse the liability red.
      while (c.toARGB32() == liabilityColor.toARGB32()) {
        paletteIndex++;
        c = kAssetsDonutColors[paletteIndex % kAssetsDonutColors.length];
      }
      paletteIndex++;
      colors.add(c);
    }
    final pieTotal = slices.fold<int>(0, (a, b) => a + b.totalMinor.abs());
    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '资产分析',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CentliSpacing.section),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: pieTotal <= 0
                    ? Center(
                        child: Text(
                          '暂无余额',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 30,
                          sections: [
                            for (var i = 0; i < slices.length; i++)
                              if (slices[i].totalMinor.abs() > 0)
                                PieChartSectionData(
                                  value: slices[i].totalMinor.abs().toDouble(),
                                  color: colors[i],
                                  radius: 26,
                                  title: '',
                                ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < slices.length; i++)
                      _AnalysisLegendRow(
                        name: slices[i].name,
                        color: colors[i],
                        amount: formatMinor(
                          base,
                          slices[i].totalMinor,
                          hide: hide,
                        ),
                        pct: slices[i].pct,
                        negative: slices[i].totalMinor < 0,
                        theme: theme,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 图例一行：色块 + 名称 + 金额（百分比）—— 单行显示。
class _AnalysisLegendRow extends StatelessWidget {
  const _AnalysisLegendRow({
    required this.name,
    required this.color,
    required this.amount,
    required this.pct,
    required this.negative,
    required this.theme,
  });

  final String name;
  final Color color;
  final String amount;
  final String pct;
  final bool negative;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final money = '$amount（$pct）';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          // The amount + percent must stay whole; only the name may ellipsize.
          Flexible(
            flex: 2,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 5,
            child: Text(
              money,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: negative ? CentliTheme.expenseRed : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
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
  final db = ref.read(databaseProvider);
  // 编辑已有账户时，这个输入框表示**当前金额**（余额），保存时写一笔
  // 「余额校正」把余额调到输入值；新建账户时它才是期初余额。
  final String? currency0 = existing?.currency;
  final currentBalanceMinor = existing == null
      ? 0
      : (await db.accountBalances(existing.ledgerId))[existing.id] ??
          existing.openingBalanceMinor;
  final balanceCtrl = TextEditingController(
    text: existing == null
        ? '0'
        : fromMinor(currency0!, currentBalanceMinor)
            .toStringAsFixed(currencyDecimals[currency0] ?? 2),
  );
  var currency = existing?.currency ?? 'CNY';
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
                        const SizedBox(height: CentliSpacing.item),
                        Text(
                          '点按选择图标',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextField(
                    key: const Key('account_editor_balance'),
                    controller: balanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: existing == null ? '期初余额' : '当前金额',
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                      helperText: existing == null
                          ? (decimals == 0
                              ? '无小数（$currency）'
                              : '$decimals 位小数')
                          : '保存后会记一笔「余额校正」，把余额调整到这个数'
                              '（不改期初，不计入统计）',
                      helperMaxLines: 2,
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
    balanceCtrl.dispose();
    return;
  }

  final name = nameCtrl.text.trim();
  final typedMajor = double.tryParse(balanceCtrl.text.trim()) ?? 0;
  nameCtrl.dispose();
  balanceCtrl.dispose();

  if (name.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入账户名称')));
    }
    return;
  }

  final typedMinor = toMinor(currency, typedMajor);
  if (existing == null) {
    await db.createAccount(
      ledgerId: ledgerId,
      name: name,
      currency: currency,
      type: type,
      openingBalanceMinor: typedMinor,
      icon: iconKey,
    );
    return;
  }
  // 编辑：只更新名称 / 分类 / 图标，期初余额保持不变。
  await db.updateAccount(
    id: existing.id,
    name: name,
    currency: currency,
    type: type,
    openingBalanceMinor: existing.openingBalanceMinor,
    icon: iconKey,
  );
  // 当前金额变了 → 记一笔「余额校正」把余额调过去。
  if (typedMinor != currentBalanceMinor) {
    await db.adjustAccountBalance(
      account: existing,
      targetBalanceMinor: typedMinor,
      currentBalanceMinor: currentBalanceMinor,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已记入余额校正')),
      );
    }
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_range.dart';
import '../../core/utils/fx.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/date_range_control.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'category_drill_page.dart';
import '../../app/theme.dart';

final statsRangeProvider = StateProvider<DateRangeWindow>((ref) {
  return DateRangeWindow.lastDays(days: 30);
});

/// Breakdown kind on stats: transaction/category kind `out` or `in`.
final statsBreakdownKindProvider = StateProvider<String>((ref) => 'out');

final _statsBaseProvider =
    FutureProvider.family<
      BaseRangeSummary,
      ({String ledgerId, String key, int startMs, int endMs, String base})
    >((ref, args) async {
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
      await ref.watch(fxBookProvider.future);
      return ref
          .watch(databaseProvider)
          .rangeSummaryInBase(
            args.ledgerId,
            args.startMs,
            args.endMs,
            args.base,
          );
    });

final _statsBreakdownBaseProvider =
    FutureProvider.family<
      List<({String categoryId, String name, int totalMinor})>,
      ({
        String ledgerId,
        String key,
        int startMs,
        int endMs,
        String base,
        String kind,
      })
    >((ref, args) async {
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
      await ref.watch(fxBookProvider.future);
      return ref
          .watch(databaseProvider)
          .categoryBreakdownInBase(
            args.ledgerId,
            args.startMs,
            args.endMs,
            kind: args.kind,
            baseCurrency: args.base,
          );
    });

final _statsDailyBaseProvider =
    FutureProvider.family<
      List<({DateTime dayLocal, int totalMinor})>,
      ({
        String ledgerId,
        String key,
        int startMs,
        int endMs,
        String base,
        String kind,
      })
    >((ref, args) async {
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
      await ref.watch(fxBookProvider.future);
      return ref
          .watch(databaseProvider)
          .dailySeriesInBase(
            args.ledgerId,
            args.startMs,
            args.endMs,
            kind: args.kind,
            baseCurrency: args.base,
          );
    });

final _statsBudgetProvider =
    FutureProvider.family<
      MonthBudgetProgress,
      ({String ledgerId, String yearMonth, String base})
    >((ref, args) async {
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
      await ref.watch(fxBookProvider.future);
      return ref
          .watch(databaseProvider)
          .monthBudgetProgress(args.ledgerId, args.yearMonth, args.base);
    });

/// Test aliases (same instances as private providers above).
final statsBaseProvider = _statsBaseProvider;
final statsBreakdownBaseProvider = _statsBreakdownBaseProvider;
final statsDailyBaseProvider = _statsDailyBaseProvider;
final statsBudgetProvider = _statsBudgetProvider;

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;
    final range = ref.watch(statsRangeProvider);
    final breakdownKind = ref.watch(statsBreakdownKindProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('\u7edf\u8ba1')),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败，下拉重试')),
        data: (ledger) {
          if (ledger == null) {
            return const Center(
              child: Text('\u5c1a\u672a\u521d\u59cb\u5316\u8d26\u672c'),
            );
          }
          final ledgerId = ledger.id;
          final base = ledger.baseCurrency;
          final args = (
            ledgerId: ledgerId,
            key: range.key,
            startMs: range.startMs,
            endMs: range.endMs,
            base: base,
          );
          final summary = ref.watch(_statsBaseProvider(args));
          final bdArgs = (
            ledgerId: ledgerId,
            key: range.key,
            startMs: range.startMs,
            endMs: range.endMs,
            base: base,
            kind: breakdownKind,
          );
          final breakdown = ref.watch(_statsBreakdownBaseProvider(bdArgs));
          final daily = ref.watch(_statsDailyBaseProvider(bdArgs));
          final breakdownTitle = breakdownKind == 'in'
              ? '\u5206\u7c7b\u6536\u5165\uff08$base\uff09'
              : '\u5206\u7c7b\u652f\u51fa\uff08$base\uff09';
          final trendTitle = breakdownKind == 'in'
              ? '\u6bcf\u65e5\u6536\u5165'
              : '\u6bcf\u65e5\u652f\u51fa';
          final lineColor = breakdownKind == 'in'
              ? scheme.primary
              : scheme.error;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_statsBaseProvider(args));
              ref.invalidate(_statsBreakdownBaseProvider(bdArgs));
              ref.invalidate(_statsDailyBaseProvider(bdArgs));
              final String ym;
              if (range.kind == DateRangeKind.month) {
                ym = budgetYearMonth(range.startLocal);
              } else {
                ym = budgetYearMonth();
              }
              ref.invalidate(
                _statsBudgetProvider((
                  ledgerId: ledgerId,
                  yearMonth: ym,
                  base: base,
                )),
              );
            },
            child: ListView(
            padding: const EdgeInsets.fromLTRB(
              CentliSpacing.pageH,
              CentliSpacing.pageTop,
              CentliSpacing.pageH,
              CentliSpacing.pageBottomNav,
            ),
            children: [
              DateRangeControl(
                range: range,
                onChanged: (next) {
                  ref.read(statsRangeProvider.notifier).state = next;
                },
              ),
              const SizedBox(height: CentliSpacing.dense),
              Text(
                '\u672c\u4f4d\u5e01 $base\uff08\u6309\u53d1\u751f\u65e5\u6c47\u7387\u6298\u7b97\uff09',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: CentliSpacing.item),
              summary.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('加载失败，下拉重试'),
                data: (s) {
                  final others = s.unconverted.entries.toList()
                    ..sort((a, b) => a.key.compareTo(b.key));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CentliSoftCard(
                              child: Padding(
                                padding: const EdgeInsets.all(CentliSpacing.cardPad),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '\u652f\u51fa\u5408\u8ba1',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    const SizedBox(height: CentliSpacing.item),
                                    Text(
                                      formatMinor(
                                        base,
                                        s.expenseMinor,
                                        hide: hide,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: scheme.error,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CentliSoftCard(
                              child: Padding(
                                padding: const EdgeInsets.all(CentliSpacing.cardPad),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '\u6536\u5165\u5408\u8ba1',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                    ),
                                    const SizedBox(height: CentliSpacing.item),
                                    Text(
                                      formatMinor(
                                        base,
                                        s.incomeMinor,
                                        hide: hide,
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (others.isNotEmpty) ...[
                        const SizedBox(height: CentliSpacing.item),
                        Text(
                          '\u672a\u6298\u7b97\uff1a${others.map((e) {
                            final t = e.value;
                            return '${e.key} \u652f ${formatMinor(e.key, t.expense, hide: hide)} / \u6536 ${formatMinor(e.key, t.income, hide: hide)}';
                          }).join(' \u00b7 ')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: CentliSpacing.section),
              _StatsBudgetSection(
                ledgerId: ledgerId,
                baseCurrency: base,
                range: range,
                hide: hide,
              ),
              const SizedBox(height: CentliSpacing.section),

              Text(trendTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: CentliSpacing.item),
              daily.when(
                loading: () => const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('加载失败，下拉重试'),
                data: (series) {
                  final hasAny = series.any((e) => e.totalMinor > 0);
                  if (!hasAny) {
                    return _EmptyChartCard(
                      message: '\u6682\u65e0\u8d8b\u52bf\u6570\u636e',
                      scheme: scheme,
                    );
                  }
                  return CentliSoftCard(
                    child: Padding(
                      padding: const EdgeInsets.all(CentliSpacing.cardPad),
                      child: SizedBox(
                        height: 200,
                        child: _DailyTrendChart(
                          series: series,
                          baseCurrency: base,
                          hide: hide,
                          lineColor: lineColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: CentliSpacing.section),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'out',
                    label: Text('\u5206\u7c7b\u652f\u51fa'),
                  ),
                  ButtonSegment<String>(
                    value: 'in',
                    label: Text('\u5206\u7c7b\u6536\u5165'),
                  ),
                ],
                selected: {breakdownKind},
                onSelectionChanged: (next) {
                  if (next.isEmpty) return;
                  ref.read(statsBreakdownKindProvider.notifier).state =
                      next.first;
                },
              ),
              const SizedBox(height: CentliSpacing.section),
              Text(
                breakdownTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: CentliSpacing.item),
              breakdown.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('加载失败，下拉重试'),
                data: (items) {
                  if (items.isEmpty) {
                    return _EmptyChartCard(
                      message: '\u6682\u65e0\u5206\u7c7b\u6570\u636e',
                      scheme: scheme,
                    );
                  }
                  final total = items.fold<int>(0, (a, b) => a + b.totalMinor);
                  return Column(
                    children: [
                      CentliSoftCard(
                        child: Padding(
                          padding: const EdgeInsets.all(CentliSpacing.cardPad),
                          child: SizedBox(
                            height: 200,
                            child: _CategoryDonutChart(
                              items: items,
                              total: total,
                              colors: _categoryColors(scheme, items.length),
                              onSectionTap: (index) {
                                _openDrill(
                                  context,
                                  ledgerId: ledgerId,
                                  item: items[index],
                                  kind: breakdownKind,
                                  range: range,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: CentliSpacing.item),
                      CentliSoftCard(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                leading: CircleAvatar(
                                  radius: 8,
                                  backgroundColor: _categoryColors(
                                    scheme,
                                    items.length,
                                  )[i],
                                ),
                                title: Text(items[i].name),
                                subtitle: Text(
                                  total > 0
                                      ? '${(items[i].totalMinor * 100 / total).toStringAsFixed(0)}%'
                                      : '',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formatMinor(
                                        base,
                                        items[i].totalMinor,
                                        hide: hide,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                                onTap: () => _openDrill(
                                  context,
                                  ledgerId: ledgerId,
                                  item: items[i],
                                  kind: breakdownKind,
                                  range: range,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          );
        },
      ),
    );
  }

  void _openDrill(
    BuildContext context, {
    required String ledgerId,
    required ({String categoryId, String name, int totalMinor}) item,
    required String kind,
    required DateRangeWindow range,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryDrillPage(
          ledgerId: ledgerId,
          categoryId: item.categoryId,
          categoryName: item.name,
          kind: kind,
          startMs: range.startMs,
          endMs: range.endMs,
          rangeLabel: range.label,
        ),
      ),
    );
  }
}

class _StatsBudgetSection extends ConsumerWidget {
  const _StatsBudgetSection({
    required this.ledgerId,
    required this.baseCurrency,
    required this.range,
    required this.hide,
  });

  final String ledgerId;
  final String baseCurrency;
  final DateRangeWindow range;
  final bool hide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Prefer selected calendar month; otherwise current month.
    final String ym;
    if (range.kind == DateRangeKind.month) {
      ym = budgetYearMonth(range.startLocal);
    } else {
      ym = budgetYearMonth();
    }
    final async = ref.watch(
      _statsBudgetProvider((
        ledgerId: ledgerId,
        yearMonth: ym,
        base: baseCurrency,
      )),
    );
    final parts = ym.split('-');
    final label = '${parts[0]}\u5e74${int.parse(parts[1])}\u6708';

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text('加载失败，下拉重试'),
      data: (p) {
        final hasTotal = p.totalLimitMinor != null && p.totalLimitMinor! > 0;
        if (!p.hasAnyBudget) {
          return CentliSoftCard(
            child: ListTile(
              leading: Icon(
                Icons.account_balance_wallet_outlined,
                color: scheme.primary,
              ),
              title: Text('$label \u9884\u7b97'),
              subtitle: const Text(
                '\u672a\u8bbe\u7f6e \u00b7 \u53bb\u300c\u6211\u7684 \u203a \u9884\u7b97\u300d\u914d\u7f6e\u6708\u5ea6/\u5206\u7c7b\u989d\u5ea6',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/me/budget'),
            ),
          );
        }

        final limit = p.totalLimitMinor ?? 0;
        final spent = p.spentTotalMinor;
        final ratio = !hasTotal ? 0.0 : (spent / limit).clamp(0.0, 1.0);
        final over = hasTotal && spent > limit;
        final barColor = !hasTotal
            ? scheme.outlineVariant
            : over
            ? scheme.error
            : ratio >= 0.8
            ? scheme.tertiary
            : scheme.primary;

        return CentliSoftCard(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push('/me/budget'),
            child: Padding(
              padding: const EdgeInsets.all(CentliSpacing.cardPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$label \u9884\u7b97',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '\u7ba1\u7406',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: scheme.primary),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  if (hasTotal) ...[
                    Text(
                      '${formatMinor(baseCurrency, spent, hide: hide)}'
                      ' / ${formatMinor(baseCurrency, limit, hide: hide)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: over ? scheme.error : null,
                      ),
                    ),
                    const SizedBox(height: CentliSpacing.item),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 8,
                        color: barColor,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      over
                          ? '\u8d85\u652f ${formatMinor(baseCurrency, spent - limit, hide: hide)}'
                          : '\u5269\u4f59 ${formatMinor(baseCurrency, limit - spent, hide: hide)}'
                                ' \u00b7 ${(spent * 100 / limit).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: over ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Text(
                      '\u672c\u6708\u652f\u51fa ${formatMinor(baseCurrency, spent, hide: hide)}'
                      '\uff08\u672a\u8bbe\u603b\u989d\u5ea6\uff09',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (p.categories.isNotEmpty) ...[
                    const SizedBox(height: CentliSpacing.section),
                    for (final c in p.categories.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: c.ratio.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  color: c.over ? scheme.error : scheme.primary,
                                  backgroundColor:
                                      scheme.surfaceContainerHighest,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hide
                                  ? '****'
                                  : '${(c.ratio * 100).clamp(0, 999).toStringAsFixed(0)}%',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: c.over
                                        ? scheme.error
                                        : scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    if (p.categories.length > 3)
                      Text(
                        '\u53e6\u6709 ${p.categories.length - 3} \u4e2a\u5206\u7c7b\u9884\u7b97\u2026',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyChartCard extends StatelessWidget {
  const _EmptyChartCard({required this.message, required this.scheme});

  final String message;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return CentliSoftCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            message,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

List<Color> _categoryColors(ColorScheme scheme, int count) {
  const extras = <Color>[
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFFFA726),
    Color(0xFFAB47BC),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFEC407A),
    Color(0xFF8D6E63),
    Color(0xFF78909C),
  ];
  final base = <Color>[
    scheme.primary,
    scheme.tertiary,
    scheme.secondary,
    scheme.error,
    ...extras,
  ];
  return List.generate(count, (i) => base[i % base.length]);
}

class _DailyTrendChart extends StatelessWidget {
  const _DailyTrendChart({
    required this.series,
    required this.baseCurrency,
    required this.hide,
    required this.lineColor,
  });

  final List<({DateTime dayLocal, int totalMinor})> series;
  final String baseCurrency;
  final bool hide;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxMinor = series.fold<int>(
      0,
      (a, b) => a > b.totalMinor ? a : b.totalMinor,
    );
    final maxY = maxMinor <= 0 ? 1.0 : maxMinor.toDouble() * 1.15;
    final spots = <FlSpot>[
      for (var i = 0; i < series.length; i++)
        FlSpot(i.toDouble(), series[i].totalMinor.toDouble()),
    ];
    final n = series.length;
    final labelEvery = n <= 7 ? 1 : (n <= 14 ? 2 : (n / 6).ceil());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (n - 1).clamp(0, 9999).toDouble(),
        minY: 0,
        maxY: maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (v) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) {
                if (value <= 0 || value >= maxY) {
                  return const SizedBox.shrink();
                }
                if (hide) {
                  return Text(
                    '****',
                    style: Theme.of(context).textTheme.labelSmall,
                  );
                }
                final major = fromMinor(baseCurrency, value.round());
                final label = major >= 1000
                    ? '${(major / 1000).toStringAsFixed(1)}k'
                    : major.toStringAsFixed(major >= 10 ? 0 : 1);
                return Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall,
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= n) return const SizedBox.shrink();
                if (i % labelEvery != 0 && i != n - 1) {
                  return const SizedBox.shrink();
                }
                final d = series[i].dayLocal;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${d.month}/${d.day}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) {
              return touched.map((t) {
                final i = t.x.round().clamp(0, n - 1);
                final d = series[i].dayLocal;
                final dayLabel =
                    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                final amt = formatMinor(
                  baseCurrency,
                  series[i].totalMinor,
                  hide: hide,
                );
                return LineTooltipItem(
                  '$dayLabel\n$amt',
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: lineColor,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: n <= 14,
              getDotPainter: (spot, pct, bar, index) => FlDotCirclePainter(
                radius: 3,
                color: lineColor,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDonutChart extends StatelessWidget {
  const _CategoryDonutChart({
    required this.items,
    required this.total,
    required this.colors,
    required this.onSectionTap,
  });

  final List<({String categoryId, String name, int totalMinor})> items;
  final int total;
  final List<Color> colors;
  final ValueChanged<int> onSectionTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 48,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            if (event is! FlTapUpEvent) return;
            final idx = response?.touchedSection?.touchedSectionIndex;
            if (idx == null || idx < 0 || idx >= items.length) return;
            onSectionTap(idx);
          },
        ),
        sections: [
          for (var i = 0; i < items.length; i++)
            PieChartSectionData(
              color: colors[i],
              value: items[i].totalMinor.toDouble(),
              title: total > 0
                  ? '${(items[i].totalMinor * 100 / total).round()}%'
                  : '',
              radius: 40,
              titleStyle: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onPrimary,
              ),
              titlePositionPercentageOffset: 0.55,
            ),
        ],
      ),
    );
  }
}

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/utils/date_range.dart';
import '../../core/widgets/date_range_control.dart';
import '../../core/widgets/txn_grouped_list.dart';
import '../../core/utils/money.dart';
import '../../core/utils/fx.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_listener_stub.dart';

final _homePendingListProvider =
    StreamProvider.family<List<PendingCapture>, String>((ref, ledgerId) {
      return ref.watch(databaseProvider).watchPendingCaptures(ledgerId);
    });

final homeRangeProvider = StateProvider<DateRangeWindow>((ref) {
  return DateRangeWindow.lastDays(days: 30);
});

final _rangeBaseProvider =
    FutureProvider.family<
      BaseRangeSummary,
      ({String ledgerId, String key, int startMs, int endMs, String base})
    >((ref, args) async {
      await ref.watch(fxBookProvider.future);
      final db = ref.watch(databaseProvider);
      return db.rangeSummaryInBase(
        args.ledgerId,
        args.startMs,
        args.endMs,
        args.base,
      );
    });

final _rangeTxProvider =
    StreamProvider.family<
      List<Transaction>,
      ({String ledgerId, String key, int startMs, int endMs})
    >((ref, args) {
      final db = ref.watch(databaseProvider);
      return db.watchTransactionsInRange(
        args.ledgerId,
        args.startMs,
        args.endMs,
      );
    });

final _netWorthHomeProvider =
    FutureProvider.family<BaseNetWorth, ({String ledgerId, String base})>((
      ref,
      args,
    ) async {
      await ref.watch(fxBookProvider.future);
      return ref
          .read(databaseProvider)
          .netWorthInBase(args.ledgerId, args.base);
    });

final _dailyExpenseProvider =
    FutureProvider.family<
      List<({DateTime dayLocal, int totalMinor})>,
      ({String ledgerId, String key, int startMs, int endMs, String base})
    >((ref, args) async {
      await ref.watch(fxBookProvider.future);
      return ref
          .read(databaseProvider)
          .dailySeriesInBase(
            args.ledgerId,
            args.startMs,
            args.endMs,
            kind: 'out',
            baseCurrency: args.base,
          );
    });

final _dailyIncomeProvider =
    FutureProvider.family<
      List<({DateTime dayLocal, int totalMinor})>,
      ({String ledgerId, String key, int startMs, int endMs, String base})
    >((ref, args) async {
      await ref.watch(fxBookProvider.future);
      return ref
          .read(databaseProvider)
          .dailySeriesInBase(
            args.ledgerId,
            args.startMs,
            args.endMs,
            kind: 'in',
            baseCurrency: args.base,
          );
    });

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// 0 = 概览, 1 = 日历
  int _mode = 0;
  DateTime? _calendarDay;
  /// Local month for calendar grid; independent of [homeRangeProvider].
  DateTime? _calendarMonth;

  @override
  Widget build(BuildContext context) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final hideAsync = ref.watch(hideAmountProvider);
    final hide = hideAsync.valueOrNull ?? false;
    final range = ref.watch(homeRangeProvider);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: CentliTheme.scaffoldGradient(dark: dark),
        child: SafeArea(
          bottom: false,
          child: ledgerAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('加载失败: $e')),
            data: (ledger) {
              if (ledger == null) {
                return const Center(child: Text('尚未初始化账本'));
              }
              final ledgerId = ledger.id;
              final base = ledger.baseCurrency;
              final args = (
                ledgerId: ledgerId,
                key: range.key,
                startMs: range.startMs,
                endMs: range.endMs,
              );
              final baseArgs = (
                ledgerId: ledgerId,
                key: range.key,
                startMs: range.startMs,
                endMs: range.endMs,
                base: base,
              );
              final summary = ref.watch(_rangeBaseProvider(baseArgs));
              final recent = ref.watch(_rangeTxProvider(args));
              final nw = ref.watch(
                _netWorthHomeProvider((ledgerId: ledgerId, base: base)),
              );
              final expenseSeries = ref.watch(_dailyExpenseProvider(baseArgs));
              final incomeSeries = ref.watch(_dailyIncomeProvider(baseArgs));
              final nowLocal = DateTime.now();
              final calMonth = _calendarMonth ??
                  DateTime(nowLocal.year, nowLocal.month);
              final calRange =
                  DateRangeWindow.forMonth(calMonth.year, calMonth.month);
              final calArgs = (
                ledgerId: ledgerId,
                key: calRange.key,
                startMs: calRange.startMs,
                endMs: calRange.endMs,
              );
              final calBaseArgs = (
                ledgerId: ledgerId,
                key: calRange.key,
                startMs: calRange.startMs,
                endMs: calRange.endMs,
                base: base,
              );
              final calExpenseSeries =
                  ref.watch(_dailyExpenseProvider(calBaseArgs));
              final calIncomeSeries =
                  ref.watch(_dailyIncomeProvider(calBaseArgs));
              final calRecent = ref.watch(_rangeTxProvider(calArgs));

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      children: [
                        Text(
                          'Centli',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '搜索账单',
                          onPressed: () => context.push('/home/search'),
                          icon: const Icon(Icons.search_rounded),
                        ),
                        IconButton(
                          tooltip: hide ? '显示金额' : '隐藏金额',
                          onPressed: () async {
                            await ref.read(databaseProvider).toggleHideAmount();
                          },
                          icon: Icon(
                            hide
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Container(
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
                            child: _ModeTab(
                              label: '概览',
                              selected: _mode == 0,
                              onTap: () => setState(() {
                                _mode = 0;
                              }),
                            ),
                          ),
                          Expanded(
                            child: _ModeTab(
                              label: '日历',
                              selected: _mode == 1,
                              onTap: () {
                                final now = DateTime.now();
                                setState(() {
                                  _mode = 1;
                                  _calendarDay = null;
                                  _calendarMonth ??=
                                      DateTime(now.year, now.month);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(_rangeBaseProvider(baseArgs));
                        ref.invalidate(currentLedgerProvider);
                        ref.invalidate(
                          _netWorthHomeProvider((
                            ledgerId: ledgerId,
                            base: base,
                          )),
                        );
                      },
                      child: ListView(
                        key: ValueKey(_mode),
                        padding: const EdgeInsets.fromLTRB(
                          CentliSpacing.pageH,
                          CentliSpacing.dense,
                          CentliSpacing.pageH,
                          CentliSpacing.pageBottomNav,
                        ),
                        children: [
                          if (_mode == 0) ...[
                            _LedgerSummaryCard(
                              base: base,
                              hide: hide,
                              range: range,
                              netWorth: nw,
                              summary: summary,
                            ),
                            const SizedBox(height: CentliSpacing.section),
                            _NetChangeChartCard(
                              base: base,
                              hide: hide,
                              incomeSeries: incomeSeries,
                              expenseSeries: expenseSeries,
                            ),
                            const SizedBox(height: CentliSpacing.section),
                            _HomePendingSection(ledgerId: ledgerId, hide: hide),
                            const SizedBox(height: CentliSpacing.item),
                            CentliSoftCard(
                              padding: const EdgeInsets.all(CentliSpacing.cardPad),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DateRangeControl(
                                    range: range,
                                    onChanged: (next) {
                                      ref
                                              .read(homeRangeProvider.notifier)
                                              .state =
                                          next;
                                    },
                                  ),
                                  recent.when(
                                    loading: () => const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                    error: (e, _) => Text('$e'),
                                    data: (txns) {
                                      if (txns.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.all(24),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.receipt_long_outlined,
                                                size: 40,
                                                color: scheme.outline,
                                              ),
                                              const SizedBox(
                                                height: CentliSpacing.item,
                                              ),
                                              Text(
                                                '暂无账单',
                                                style: TextStyle(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '点底部「记账」记下第一笔',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                      return TxnGroupedSection(
                                        txns: txns,
                                        hide: hide,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            _CalendarCard(
                              month: calMonth,
                              hide: hide,
                              base: base,
                              selectedDay: _calendarDay,
                              incomeSeries: calIncomeSeries,
                              expenseSeries: calExpenseSeries,
                              onMonthChanged: (m) {
                                setState(() {
                                  _calendarMonth = m;
                                  _calendarDay = null;
                                });
                              },
                              onSelectDay: (d) =>
                                  setState(() => _calendarDay = d),
                            ),
                            const SizedBox(height: CentliSpacing.section),
                            _DailyTrendCard(
                              base: base,
                              hide: hide,
                              expenseSeries: expenseSeries,
                              incomeSeries: incomeSeries,
                            ),
                            const SizedBox(height: CentliSpacing.section),
                            CentliSoftCard(
                              padding: const EdgeInsets.all(CentliSpacing.cardPad),
                              child: calRecent.when(
                                loading: () => const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                                error: (e, _) => Text('$e'),
                                data: (txns) {
                                  var list = txns;
                                  final day = _calendarDay;
                                  if (day != null) {
                                    list = txns.where((t) {
                                      final local =
                                          DateTime.fromMillisecondsSinceEpoch(
                                            t.happenAt,
                                            isUtc: true,
                                          ).toLocal();
                                      return local.year == day.year &&
                                          local.month == day.month &&
                                          local.day == day.day;
                                    }).toList();
                                  }
                                  if (list.isEmpty) {
                                    return CentliEmptyState(
                                      icon: Icons.event_busy_outlined,
                                      title: day == null ? '本区间暂无账单' : '当日暂无账单',
                                      message: day == null
                                          ? '点底部「记账」记下第一笔'
                                          : '换一天查看，或点底部「记账」记下这一天的账单。',
                                      padding: const EdgeInsets.all(
                                        CentliSpacing.cardPad,
                                      ),
                                    );
                                  }
                                  return TxnGroupedSection(
                                    txns: list,
                                    hide: hide,
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
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

class _LedgerSummaryCard extends StatelessWidget {
  const _LedgerSummaryCard({
    required this.base,
    required this.hide,
    required this.range,
    required this.netWorth,
    required this.summary,
  });

  final String base;
  final bool hide;
  final DateRangeWindow range;
  final AsyncValue<BaseNetWorth> netWorth;
  final AsyncValue<BaseRangeSummary> summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nw = netWorth.valueOrNull;
    final s = summary.valueOrNull;
    final income = s?.incomeMinor ?? 0;
    final expense = s?.expenseMinor ?? 0;
    final delta = income - expense;
    // Assets ≈ net when no explicit liabilities; show negative balances as 负债.
    final net = nw?.totalMinor ?? 0;
    final assetTotal = net >= 0 ? net : 0;
    final liability = net < 0 ? -net : 0;

    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的账本',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            '全期净资产',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  formatMinor(base, net, hide: hide),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (delta != 0)
                Text(
                  '${delta > 0 ? '▲' : '▼'} ${formatMinor(base, delta.abs(), hide: hide)}',
                  style: TextStyle(
                    color: delta > 0
                        ? CentliTheme.incomeGreen
                        : CentliTheme.expenseRed,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _kv('资产', formatMinor(base, assetTotal, hide: hide)),
              ),
              Expanded(
                child: _kv('负债', formatMinor(base, liability, hide: hide)),
              ),
            ],
          ),
          const SizedBox(height: CentliSpacing.item),
          Row(
            children: [
              Expanded(
                child: _kv(
                  '${range.label}收入',
                  formatMinor(base, income, hide: hide),
                  valueColor: CentliTheme.incomeGreen,
                ),
              ),
              Expanded(
                child: _kv(
                  '${range.label}支出',
                  formatMinor(base, expense, hide: hide),
                  valueColor: CentliTheme.expenseRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '本位币 $base（按发生日汇率折算）',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: const TextStyle(fontSize: 12, color: Color(0xFF8A8F98))),
        const SizedBox(height: 2),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _NetChangeChartCard extends StatelessWidget {
  const _NetChangeChartCard({
    required this.base,
    required this.hide,
    required this.incomeSeries,
    required this.expenseSeries,
  });

  final String base;
  final bool hide;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> incomeSeries;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> expenseSeries;

  @override
  Widget build(BuildContext context) {
    final income = incomeSeries.valueOrNull ?? const [];
    final expense = expenseSeries.valueOrNull ?? const [];
    final n = income.length > expense.length ? income.length : expense.length;
    var running = 0.0;
    final spots = <FlSpot>[];
    for (var i = 0; i < n; i++) {
      final inV = i < income.length ? income[i].totalMinor : 0;
      final outV = i < expense.length ? expense[i].totalMinor : 0;
      running += (inV - outV) / 100.0;
      spots.add(FlSpot(i.toDouble(), running));
    }

    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '区间累计净流入',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: CentliSpacing.item),
          SizedBox(
            height: 140,
            child: spots.length < 2
                ? const Center(child: Text('暂无趋势数据'))
                : LineChart(
                    LineChartData(
                      minY:
                          spots
                              .map((s) => s.y)
                              .reduce((a, b) => a < b ? a : b) -
                          1,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: CentliTheme.incomeGreen,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: CentliTheme.incomeGreen.withValues(
                              alpha: 0.18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (!hide)
            Text(
              '区间累计净流入（$base）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.month,
    required this.hide,
    required this.base,
    required this.selectedDay,
    required this.incomeSeries,
    required this.expenseSeries,
    required this.onMonthChanged,
    required this.onSelectDay,
  });

  final DateTime month;
  final bool hide;
  final String base;
  final DateTime? selectedDay;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> incomeSeries;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> expenseSeries;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelectDay;

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // Prefer explicit month window; if still on lastDays/custom, show the
    final monthStart = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    final firstWeekday = monthStart.weekday % 7; // Sun=0
    // Key by full local date so Oct 13 amounts never paint onto Sep 13.
    final income = {
      for (final e
          in incomeSeries.valueOrNull ??
              const <({DateTime dayLocal, int totalMinor})>[])
        _dayKey(e.dayLocal): e.totalMinor,
    };
    final expense = {
      for (final e
          in expenseSeries.valueOrNull ??
              const <({DateTime dayLocal, int totalMinor})>[])
        _dayKey(e.dayLocal): e.totalMinor,
    };
    final today = DateTime.now();
    final thisMonth = DateTime(today.year, today.month, 1);
    final isCurrentMonth =
        monthStart.year == thisMonth.year && monthStart.month == thisMonth.month;
    final labels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上一月',
                onPressed: () {
                  final p = DateTime(monthStart.year, monthStart.month - 1, 1);
                  onMonthChanged(p);
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${monthStart.year}年${monthStart.month}月',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '下一月',
                onPressed: isCurrentMonth
                    ? null
                    : () {
                        final n =
                            DateTime(monthStart.year, monthStart.month + 1, 1);
                        onMonthChanged(n);
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9AA0A6),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: firstWeekday + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 2,
              childAspectRatio: 0.72,
            ),
            itemBuilder: (context, index) {
              if (index < firstWeekday) return const SizedBox.shrink();
              final day = index - firstWeekday + 1;
              final date = DateTime(monthStart.year, monthStart.month, day);
              final selected =
                  selectedDay != null &&
                  selectedDay!.year == date.year &&
                  selectedDay!.month == date.month &&
                  selectedDay!.day == date.day;
              final isToday =
                  today.year == date.year &&
                  today.month == date.month &&
                  today.day == date.day;
              final inAmt = income[_dayKey(date)] ?? 0;
              final outAmt = expense[_dayKey(date)] ?? 0;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelectDay(date),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? CentliTheme.softBlue.withValues(alpha: 0.18)
                        : (isToday
                              ? CentliTheme.softBlue.withValues(alpha: 0.08)
                              : null),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          fontWeight: selected || isToday
                              ? FontWeight.w800
                              : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      if (!hide && outAmt > 0)
                        Text(
                          _short(outAmt),
                          style: const TextStyle(
                            fontSize: 9,
                            color: CentliTheme.expenseRed,
                            height: 1.1,
                          ),
                        ),
                      if (!hide && inAmt > 0)
                        Text(
                          _short(inAmt),
                          style: const TextStyle(
                            fontSize: 9,
                            color: CentliTheme.incomeGreen,
                            height: 1.1,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _short(int minor) {
    final v = minor / 100.0;
    if (v >= 1000) return v.toStringAsFixed(0);
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

class _DailyTrendCard extends StatelessWidget {
  const _DailyTrendCard({
    required this.base,
    required this.hide,
    required this.expenseSeries,
    required this.incomeSeries,
  });

  final String base;
  final bool hide;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> expenseSeries;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> incomeSeries;

  @override
  Widget build(BuildContext context) {
    final expense = expenseSeries.valueOrNull ?? const [];
    final income = incomeSeries.valueOrNull ?? const [];
    final n = expense.length > income.length ? expense.length : income.length;
    final spots = <FlSpot>[];
    for (var i = 0; i < n; i++) {
      final outV = i < expense.length ? expense[i].totalMinor : 0;
      final inV = i < income.length ? income[i].totalMinor : 0;
      spots.add(FlSpot(i.toDouble(), (inV + outV) / 100.0));
    }

    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '每日趋势',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: CentliSpacing.item),
          SizedBox(
            height: 120,
            child: spots.length < 2
                ? const Center(child: Text('暂无趋势数据'))
                : LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: CentliTheme.softBlue,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: CentliTheme.softBlue.withValues(alpha: 0.2),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HomePendingSection extends ConsumerWidget {
  const _HomePendingSection({required this.ledgerId, required this.hide});
  final String ledgerId;
  final bool hide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(_homePendingListProvider(ledgerId));
    final items = listAsync.valueOrNull ?? const <PendingCapture>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _HomePendingCarousel(items: items, hide: hide),
    );
  }
}

class _HomePendingCarousel extends ConsumerStatefulWidget {
  const _HomePendingCarousel({required this.items, required this.hide});
  final List<PendingCapture> items;
  final bool hide;

  @override
  ConsumerState<_HomePendingCarousel> createState() =>
      _HomePendingCarouselState();
}

class _HomePendingCarouselState extends ConsumerState<_HomePendingCarousel> {
  late final PageController _pageController;
  int _index = 0;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HomePendingCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.items.length) {
      _index = widget.items.isEmpty ? 0 : widget.items.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final scheme = Theme.of(context).colorScheme;

    return CentliSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.fromLTRB(
              CentliSpacing.cardPad,
              CentliSpacing.dense,
              CentliSpacing.item,
              0,
            ),
            title: Text(
              '待确认 (${items.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            subtitle: const Text('左右滑动快速处理 · 点此查看全部'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/home/pending'),
          ),
          SizedBox(
            height: 96,
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final c = items[i];
                return _HomePendingSlide(
                  capture: c,
                  hide: widget.hide,
                  busy: _busyId == c.id,
                  onIgnore: () => _ignore(c),
                  onOpen: () => context.push('/home/pending'),
                );
              },
            ),
          ),
          if (items.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: CentliSpacing.item),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Container(
                      width: i == _index ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: i == _index
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _ignore(PendingCapture c) async {
    if (_busyId != null) return;
    setState(() => _busyId = c.id);
    try {
      await ref.read(databaseProvider).ignorePendingCapture(c.id);
      await NotificationCaptureStub.cancelPendingConfirm(c.id);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }
}

class _HomePendingSlide extends StatelessWidget {
  const _HomePendingSlide({
    required this.capture,
    required this.hide,
    required this.busy,
    required this.onIgnore,
    required this.onOpen,
  });
  final PendingCapture capture;
  final bool hide;
  final bool busy;
  final VoidCallback onIgnore;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = capture;
    final ccy = c.currency ?? 'CNY';
    final amount = c.amountMinor == null
        ? '金额未知'
        : formatMinor(ccy, c.amountMinor!, hide: hide);
    final merchant = (c.merchant ?? '').trim();
    final title = merchant.isNotEmpty
        ? '${_pkgLabel(c.sourcePkg)} · $amount · $merchant'
        : '${_pkgLabel(c.sourcePkg)} · $amount';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CentliSpacing.cardPad,
        0,
        CentliSpacing.dense,
        CentliSpacing.dense,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    _CategoryHint(capture: c),
                  ],
                ),
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: busy ? null : onIgnore,
            child: const Text('忽略'),
          ),
        ],
      ),
    );
  }

  String _pkgLabel(String pkg) {
    if (pkg.contains('Alipay') || pkg.contains('alipay')) {
      return '支付宝';
    }
    if (pkg.contains('tencent.mm')) return '微信';
    return pkg;
  }
}

class _CategoryHint extends ConsumerWidget {
  const _CategoryHint({required this.capture});
  final PendingCapture capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = capture.suggestedCategoryId;
    final scheme = Theme.of(context).colorScheme;
    if (id == null || id.isEmpty) {
      return Text(
        '待选分类',
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return FutureBuilder<Category?>(
      future: ref.read(databaseProvider).getCategory(id),
      builder: (context, snap) {
        final name = snap.data?.name;
        final label = (name == null || name.isEmpty) ? '待选分类' : '猜「$name」';
        return Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        );
      },
    );
  }
}

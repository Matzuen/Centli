import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_range.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/centli_error_state.dart';
import '../../core/widgets/date_range_control.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'category_drill_page.dart';
import '../../app/theme.dart';

final statsRangeProvider = StateProvider<DateRangeWindow>((ref) {
  return DateRangeWindow.lastDays(days: 30);
});

/// 环形图分段：支出 / 收入 / 全部。
enum StatsBreakdownKind { expense, income, all }

final statsBreakdownKindProvider =
    StateProvider<StatsBreakdownKind>((ref) => StatsBreakdownKind.expense);

/// 时间范围分段：月份 / 年份 / 自定义。
enum StatsRangeMode { month, year, custom }

final statsRangeModeProvider =
    StateProvider<StatsRangeMode>((ref) => StatsRangeMode.month);

typedef _CatTotal = ({String categoryId, String name, int totalMinor});

final _statsTotalsProvider = FutureProvider.family<
    StatsTotals,
    ({String ledgerId, String key, int startMs, int endMs, String base})>((
  ref,
  args,
) async {
  await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
  await ref.watch(fxBookProvider.future);
  return ref.watch(databaseProvider).statsTotalsInBase(
        args.ledgerId,
        args.startMs,
        args.endMs,
        args.base,
      );
});

final _statsBreakdownProvider = FutureProvider.family<
    List<_CatTotal>,
    ({
      String ledgerId,
      String key,
      int startMs,
      int endMs,
      String base,
      StatsBreakdownKind kind,
    })>((ref, args) async {
  await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
  await ref.watch(fxBookProvider.future);
  final db = ref.watch(databaseProvider);
  if (args.kind == StatsBreakdownKind.all) {
    final both = await db.statsAllCategoriesInBase(
      args.ledgerId,
      args.startMs,
      args.endMs,
      args.base,
    );
    return [...both.expenses, ...both.incomes];
  }
  return db.categoryBreakdownInBase(
    args.ledgerId,
    args.startMs,
    args.endMs,
    kind: args.kind == StatsBreakdownKind.income ? 'in' : 'out',
    baseCurrency: args.base,
  );
});

final _statsAccountsProvider = FutureProvider.family<
    List<StatsAccountRow>,
    ({String ledgerId, String key, int startMs, int endMs, String base})>((
  ref,
  args,
) async {
  await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
  await ref.watch(fxBookProvider.future);
  return ref.watch(databaseProvider).statsByAccountInBase(
        args.ledgerId,
        args.startMs,
        args.endMs,
        args.base,
      );
});

/// Test aliases (same instances as the private providers above).
@visibleForTesting
final statsTotalsProvider = _statsTotalsProvider;
@visibleForTesting
final statsBreakdownProvider = _statsBreakdownProvider;
@visibleForTesting
final statsAccountsProvider = _statsAccountsProvider;

/// 月份 / 年份窗口（[month] 为 1-12；年份窗口即该年 1..12 月）。
@visibleForTesting
DateRangeWindow statsMonthWindow(int year, int month) =>
    DateRangeWindow.forMonth(year, month);

@visibleForTesting
DateRangeWindow statsYearWindow(int year) => DateRangeWindow.custom(
      startInclusive: DateTime(year, 1, 1),
      endInclusive: DateTime(year, 12, 31),
    );

/// 「2026.10.01 — 2026.10.31」样式的区间文字。
@visibleForTesting
String statsRangeText(DateRangeWindow range) {
  String d(DateTime x) =>
      '${x.year}.${x.month.toString().padLeft(2, '0')}.${x.day.toString().padLeft(2, '0')}';
  final last = range.endLocal.subtract(const Duration(days: 1));
  if (range.startLocal.year == last.year &&
      range.startLocal.month == last.month &&
      range.startLocal.day == last.day) {
    return d(range.startLocal);
  }
  return '${d(range.startLocal)} — ${d(last)}';
}

/// 统计页：时间范围 / 分类环形图 / 汇总 / 账户。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;
    final range = ref.watch(statsRangeProvider);
    final mode = ref.watch(statsRangeModeProvider);
    final kind = ref.watch(statsBreakdownKindProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('\u7edf\u8ba1')),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => CentliErrorState(
          error: e,
          onRetry: () => ref.invalidate(currentLedgerProvider),
        ),
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
          final totals = ref.watch(_statsTotalsProvider(args));
          final breakdown = ref.watch(_statsBreakdownProvider((
            ledgerId: ledgerId,
            key: range.key,
            startMs: range.startMs,
            endMs: range.endMs,
            base: base,
            kind: kind,
          )));
          final accounts = ref.watch(_statsAccountsProvider(args));

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_statsTotalsProvider(args));
              ref.invalidate(_statsBreakdownProvider((
                ledgerId: ledgerId,
                key: range.key,
                startMs: range.startMs,
                endMs: range.endMs,
                base: base,
                kind: kind,
              )));
              ref.invalidate(_statsAccountsProvider(args));
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                CentliSpacing.pageH,
                CentliSpacing.pageTop,
                CentliSpacing.pageH,
                CentliSpacing.pageBottomNav,
              ),
              children: [
                _RangeCard(
                  key: const Key('stats_range_card'),
                  range: range,
                  mode: mode,
                  base: base,
                  onModeChanged: (m) {
                    ref.read(statsRangeModeProvider.notifier).state = m;
                    final now = DateTime.now();
                    final window = switch (m) {
                      StatsRangeMode.month => statsMonthWindow(
                          range.startLocal.year,
                          range.startLocal.month,
                        ),
                      StatsRangeMode.year => statsYearWindow(
                          range.startLocal.year,
                        ),
                      StatsRangeMode.custom => range,
                    };
                    ref.read(statsRangeProvider.notifier).state = window.isLatest
                        ? window
                        : window;
                    // Keep "current" when the new window would be in the future.
                    if (m == StatsRangeMode.year &&
                        range.startLocal.year > now.year) {
                      ref.read(statsRangeProvider.notifier).state =
                          statsYearWindow(now.year);
                    }
                  },
                  onChanged: (next) {
                    ref.read(statsRangeProvider.notifier).state = next;
                  },
                ),
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '\u672c\u4f4d\u5e01 $base\uff08\u6309\u53d1\u751f\u65e5\u6c47\u7387\u6298\u7b97\uff09',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: CentliSpacing.section),
                _BreakdownCard(
                  key: const Key('stats_breakdown_card'),
                  kind: kind,
                  items: breakdown,
                  base: base,
                  hide: hide,
                  onKindChanged: (k) {
                    ref.read(statsBreakdownKindProvider.notifier).state = k;
                  },
                  onTapItem: (item) => _openDrill(
                    context,
                    ledgerId: ledgerId,
                    item: item,
                    kind: kind == StatsBreakdownKind.income ? 'in' : 'out',
                    range: range,
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                _SummaryCard(totals: totals, base: base, hide: hide),
                const SizedBox(height: CentliSpacing.section),
                _AccountsCard(rows: accounts, base: base, hide: hide),
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

/// 卡片 1：分段「月份 / 年份 / 自定义」+ ‹ 2026.10.01 — 2026.10.31 ›
class _RangeCard extends StatelessWidget {
  const _RangeCard({
    super.key,
    required this.range,
    required this.mode,
    required this.base,
    required this.onModeChanged,
    required this.onChanged,
  });

  final DateRangeWindow range;
  final StatsRangeMode mode;
  final String base;
  final ValueChanged<StatsRangeMode> onModeChanged;
  final ValueChanged<DateRangeWindow> onChanged;

  void _step(BuildContext context, {required bool forward}) {
    final now = DateTime.now();
    switch (mode) {
      case StatsRangeMode.month:
        final m = forward
            ? DateTime(range.startLocal.year, range.startLocal.month + 1)
            : DateTime(range.startLocal.year, range.startLocal.month - 1);
        onChanged(statsMonthWindow(m.year, m.month));
      case StatsRangeMode.year:
        onChanged(statsYearWindow(range.startLocal.year + (forward ? 1 : -1)));
      case StatsRangeMode.custom:
        onChanged(forward ? range.next() : range.prev());
    }
    // Ignore: `now` is only used by the disabled state.
    assert(now.year > 0);
  }

  bool get _canForward {
    final now = DateTime.now();
    switch (mode) {
      case StatsRangeMode.month:
        final next = DateTime(range.startLocal.year, range.startLocal.month + 1);
        return !next.isAfter(DateTime(now.year, now.month));
      case StatsRangeMode.year:
        return range.startLocal.year < now.year;
      case StatsRangeMode.custom:
        return !range.isLatest;
    }
  }

  Future<void> _pickCustom(BuildContext context) async {
    final next = await showCentliDateRangeSheet(context, current: range);
    if (next != null) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      padding: const EdgeInsets.fromLTRB(
        CentliSpacing.cardPad,
        CentliSpacing.cardPad,
        CentliSpacing.cardPad,
        CentliSpacing.dense,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<StatsRangeMode>(
            key: const Key('stats_range_mode'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: StatsRangeMode.month, label: Text('月份')),
              ButtonSegment(value: StatsRangeMode.year, label: Text('年份')),
              ButtonSegment(value: StatsRangeMode.custom, label: Text('自定义')),
            ],
            selected: {mode},
            onSelectionChanged: (next) {
              if (next.isEmpty) return;
              final m = next.first;
              if (m == StatsRangeMode.custom) {
                _pickCustom(context);
                return;
              }
              onModeChanged(m);
            },
          ),
          const SizedBox(height: CentliSpacing.dense),
          Row(
            children: [
              IconButton(
                key: const Key('stats_range_prev'),
                tooltip: '上一段',
                visualDensity: VisualDensity.compact,
                onPressed: () => _step(context, forward: false),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  statsRangeText(range),
                  key: const Key('stats_range_text'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                ),
              ),
              IconButton(
                key: const Key('stats_range_next'),
                tooltip: '下一段',
                visualDensity: VisualDensity.compact,
                onPressed: _canForward
                    ? () => _step(context, forward: true)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (mode == StatsRangeMode.custom)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _pickCustom(context),
                child: Text(
                  '\u91cd\u9009\u65e5\u671f',
                  style: TextStyle(color: scheme.primary, fontSize: 12.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡片 2：分段「支出 / 收入 / 全部」+ 环形图（左）+ 图例（右）。
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    super.key,
    required this.kind,
    required this.items,
    required this.base,
    required this.hide,
    required this.onKindChanged,
    required this.onTapItem,
  });

  final StatsBreakdownKind kind;
  final AsyncValue<List<({String categoryId, String name, int totalMinor})>>
      items;
  final String base;
  final bool hide;
  final ValueChanged<StatsBreakdownKind> onKindChanged;
  final ValueChanged<({String categoryId, String name, int totalMinor})>
      onTapItem;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<StatsBreakdownKind>(
            key: const Key('stats_breakdown_kind'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: StatsBreakdownKind.expense, label: Text('支出')),
              ButtonSegment(value: StatsBreakdownKind.income, label: Text('收入')),
              ButtonSegment(value: StatsBreakdownKind.all, label: Text('全部')),
            ],
            selected: {kind},
            onSelectionChanged: (next) {
              if (next.isNotEmpty) onKindChanged(next.first);
            },
          ),
          const SizedBox(height: CentliSpacing.section),
          items.when(
            loading: () => const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => CentliErrorState(error: e, compact: true),
            data: (list) {
              if (list.isEmpty) {
                return SizedBox(
                  height: 160,
                  child: Center(
                    child: Text(
                      '该区间没有${_kindLabel(kind)}数据',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              final total = list.fold<int>(0, (a, b) => a + b.totalMinor);
              final colors = _categoryColors(scheme, list.length);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 190,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 132,
                          child: _CategoryDonutChart(
                            items: list,
                            total: total,
                            colors: colors,
                            centerLabel: _kindLabel(kind),
                            centerValue:
                                formatMinor(base, total, hide: hide),
                            onSectionTap: (i) => onTapItem(list[i]),
                          ),
                        ),
                        // Breathing room between ring and legend.
                        const SizedBox(width: 20),
                        Expanded(
                          child: _LegendList(
                            items: list,
                            colors: colors,
                            total: total,
                            base: base,
                            hide: hide,
                            onTap: onTapItem,
                          ),
                        ),
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
  }

  static String _kindLabel(StatsBreakdownKind k) => switch (k) {
        StatsBreakdownKind.expense => '支出',
        StatsBreakdownKind.income => '收入',
        StatsBreakdownKind.all => '收支',
      };
}

/// 图例：色块 + 名称 + 金额（右侧，可滚动、可点击下钻）。
class _LegendList extends StatelessWidget {
  const _LegendList({
    required this.items,
    required this.colors,
    required this.total,
    required this.base,
    required this.hide,
    required this.onTap,
  });

  final List<({String categoryId, String name, int totalMinor})> items;
  final List<Color> colors;
  final int total;
  final String base;
  final bool hide;
  final ValueChanged<({String categoryId, String name, int totalMinor})> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      key: const Key('stats_legend'),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: CentliSpacing.dense),
      itemBuilder: (context, i) {
        final it = items[i];
        final pct = total > 0 ? (it.totalMinor * 100 / total) : 0.0;
        return InkWell(
          onTap: () => onTap(it),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                // 一行显示：名称  金额（占比%）
                Expanded(
                  child: Text(
                    it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '${formatMinor(base, it.totalMinor, hide: hide)}'
                    '（${pct.toStringAsFixed(0)}%）',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 卡片 3：汇总（笔数 / 收入 / 支出 / 结余）。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.totals,
    required this.base,
    required this.hide,
  });

  final AsyncValue<StatsTotals> totals;
  final String base;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CentliSoftCard(
      key: const Key('stats_summary_card'),
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '\u6c47\u603b',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: CentliSpacing.item),
          totals.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => CentliErrorState(error: e, compact: true),
            data: (t) {
              final cells = <({String label, String value, Color color})>[
                (
                  label: '笔数',
                  value: '${t.count}',
                  color: scheme.onSurface,
                ),
                (
                  label: '收入',
                  value: formatMinor(base, t.incomeMinor, hide: hide),
                  color: CentliTheme.incomeGreen,
                ),
                (
                  label: '支出',
                  value: formatMinor(base, t.expenseMinor, hide: hide),
                  color: CentliTheme.expenseRed,
                ),
                (
                  label: '结余',
                  value: formatMinor(base, t.netMinor, hide: hide),
                  color: t.netMinor >= 0
                      ? CentliTheme.incomeGreen
                      : CentliTheme.expenseRed,
                ),
              ];
              return _TablePair(
                headers: [for (final c in cells) c.label],
                values: [
                  for (final c in cells)
                    Text(
                      c.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.color,
                      ),
                    ),
                ],
                // 笔数 is a count, the rest align right like money.
                align: const [
                  TextAlign.center,
                  TextAlign.right,
                  TextAlign.right,
                  TextAlign.right,
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 卡片 4：账户（名称 / 收入 / 支出 / 结余），右上角注明不含转账。
class _AccountsCard extends StatelessWidget {
  const _AccountsCard({
    required this.rows,
    required this.base,
    required this.hide,
  });

  final AsyncValue<List<StatsAccountRow>> rows;
  final String base;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CentliSoftCard(
      key: const Key('stats_accounts_card'),
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '\u8d26\u6237',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '\u4e0d\u5305\u542b\u8f6c\u8d26\u6570\u636e',
                key: const Key('stats_accounts_note'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: CentliSpacing.item),
          rows.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => CentliErrorState(error: e, compact: true),
            data: (list) {
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      '\u8be5\u533a\u95f4\u6ca1\u6709\u8d26\u6237\u6d41\u6c34',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }
              final width = switch (list.length) {
                <= 3 => 0.34,
                _ => 0.30,
              };
              return Table(
                columnWidths: {
                  0: FlexColumnWidth(1 - width),
                  1: FlexColumnWidth(width * 0.9),
                  2: FlexColumnWidth(width * 0.9),
                  3: FlexColumnWidth(width * 0.9),
                },
                children: [
                  TableRow(
                    children: [
                      _cell('名称', theme, scheme, header: true),
                      _cell('收入', theme, scheme, header: true, right: true),
                      _cell('支出', theme, scheme, header: true, right: true),
                      _cell('结余', theme, scheme, header: true, right: true),
                    ],
                  ),
                  for (final r in list)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        _moneyCell(
                          formatMinor(base, r.incomeMinor, hide: hide),
                          theme,
                          CentliTheme.incomeGreen,
                        ),
                        _moneyCell(
                          formatMinor(base, r.expenseMinor, hide: hide),
                          theme,
                          CentliTheme.expenseRed,
                        ),
                        _moneyCell(
                          formatMinor(base, r.netMinor, hide: hide),
                          theme,
                          r.netMinor >= 0
                              ? CentliTheme.incomeGreen
                              : CentliTheme.expenseRed,
                          bold: true,
                        ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text,
    ThemeData theme,
    ColorScheme scheme, {
    bool header = false,
    bool right = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _moneyCell(String text, ThemeData theme, Color color,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    );
  }
}

/// Two rows of equal-width cells (header row + value row).
class _TablePair extends StatelessWidget {
  const _TablePair({
    required this.headers,
    required this.values,
    required this.align,
  });

  final List<String> headers;
  final List<Widget> values;
  final List<TextAlign> align;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = headers.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Text(
                  headers[i],
                  textAlign: align[i],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: CentliSpacing.dense),
        Row(
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: Align(
                  alignment: switch (align[i]) {
                    TextAlign.right => Alignment.centerRight,
                    TextAlign.left => Alignment.centerLeft,
                    _ => Alignment.center,
                  },
                  child: values[i],
                ),
              ),
          ],
        ),
      ],
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

/// 环形图：中间显示合计 + 标签，扇区可点击下钻。
class _CategoryDonutChart extends StatelessWidget {
  const _CategoryDonutChart({
    required this.items,
    required this.total,
    required this.colors,
    required this.centerLabel,
    required this.centerValue,
    required this.onSectionTap,
  });

  final List<({String categoryId, String name, int totalMinor})> items;
  final int total;
  final List<Color> colors;
  final String centerLabel;
  final String centerValue;
  final ValueChanged<int> onSectionTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 2,
            centerSpaceRadius: 42,
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
                  // Keep the ring clean: percentages live in the legend.
                  title: '',
                  radius: 30,
                ),
            ],
          ),
        ),
        IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                centerLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

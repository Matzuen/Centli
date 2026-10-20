import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/widgets/centli_error_state.dart';
import '../../core/utils/date_range.dart';
import '../../core/widgets/date_range_control.dart';
import '../../core/widgets/txn_grouped_list.dart';
import '../../core/widgets/centli_trend_chart.dart';
import '../../core/utils/money.dart';
import '../../core/utils/fx.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../capture/capture_intake_actions.dart';
import '../ledger/bookkeeping_sheet.dart';
import '../security/app_lock_controller.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../pending/pending_confirm_sheet.dart';

/// 首页轮播：只收「解析成功、可直接确认」的待入账。
final _homePendingOkProvider =
    StreamProvider.family<List<PendingCapture>, String>((ref, ledgerId) {
      return ref.watch(databaseProvider).watchPendingOkCaptures(ledgerId);
    });

/// 解析失败条数：首页用条幅入口，不和可确认项混在同一轮播里。
final _homeParseFailedCountProvider = StreamProvider.family<int, String>((
  ref,
  ledgerId,
) {
  return ref
      .watch(databaseProvider)
      .watchParseFailedCaptures(ledgerId)
      .map((rows) => rows.length);
});

final _homeMonthBudgetsProvider = StreamProvider.family<List<Budget>, String>((
  ref,
  ledgerId,
) {
  return ref
      .watch(databaseProvider)
      .watchBudgetsForMonth(ledgerId, budgetYearMonth());
});

final _homeBudgetProgressProvider =
    FutureProvider.family<
      MonthBudgetProgress,
      ({String ledgerId, String base})
    >((ref, args) async {
      await ref.watch(fxBookProvider.future);
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
      await ref.watch(_homeMonthBudgetsProvider(args.ledgerId).future);
      return ref
          .watch(databaseProvider)
          .monthBudgetProgress(args.ledgerId, budgetYearMonth(), args.base);
    });

final homeRangeProvider = StateProvider<DateRangeWindow>((ref) {
  return DateRangeWindow.lastDays(days: 30);
});

final _rangeBaseProvider =
    FutureProvider.family<
      BaseRangeSummary,
      ({String ledgerId, String key, int startMs, int endMs, String base})
    >((ref, args) async {
      // Signal only — list may be truncated; always re-query untruncated.
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
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
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
      // Opening balance lives on accounts — refresh when accounts change.
      await ref.watch(_homeAccountsProvider(args.ledgerId).future);
      await ref.watch(fxBookProvider.future);
      return ref
          .read(databaseProvider)
          .netWorthInBase(args.ledgerId, args.base);
    });

/// All-time income / expense in base currency (总收入 / 总支出).
final _lifetimeTotalsProvider =
    FutureProvider.family<
      ({int incomeMinor, int expenseMinor}),
      ({String ledgerId, String base})
    >((ref, args) async {
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
      await ref.watch(fxBookProvider.future);
      return ref
          .read(databaseProvider)
          .lifetimeTotalsInBase(args.ledgerId, args.base);
    });

final _homeAccountsProvider = StreamProvider.family<List<Account>, String>((
  ref,
  ledgerId,
) {
  return ref.watch(databaseProvider).watchActiveAccounts(ledgerId);
});

final _homeBalancesProvider = StreamProvider.family<Map<String, int>, String>((
  ref,
  ledgerId,
) {
  return ref.watch(databaseProvider).watchAccountBalances(ledgerId);
});

final _dailyExpenseProvider =
    FutureProvider.family<
      List<({DateTime dayLocal, int totalMinor})>,
      ({String ledgerId, String key, int startMs, int endMs, String base})
    >((ref, args) async {
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
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
      await ref.watch(txnWriteSignalProvider(args.ledgerId).future);
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

/// Test aliases (same instances as private providers above).
/// Test-only public aliases for private providers (B1 refresh tests).
@visibleForTesting
final homeRangeBaseProvider = _rangeBaseProvider;
@visibleForTesting
final homeNetWorthProvider = _netWorthHomeProvider;
@visibleForTesting
final homeDailyExpenseProvider = _dailyExpenseProvider;
@visibleForTesting
final homeDailyIncomeProvider = _dailyIncomeProvider;

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
    final hide = ref.watch(hideAmountProvider);
    final lockOn = ref.watch(appLockEnabledProvider).valueOrNull ?? false;
    final range = ref.watch(homeRangeProvider);
    final scheme = Theme.of(context).colorScheme;

    return CentliGradientScaffold(
      body: SafeArea(
        bottom: false,
        child: ledgerAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => CentliErrorState(error: e, compact: true),
          data: (ledger) {
            if (ledger == null) {
              return const Center(child: Text('尚未初始化记账本'));
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
            final homeAccounts =
                ref.watch(_homeAccountsProvider(ledgerId)).valueOrNull ??
                const <Account>[];
            final homeBalances =
                ref.watch(_homeBalancesProvider(ledgerId)).valueOrNull ??
                const <String, int>{};
            final fxBook = ref.watch(fxBookProvider).valueOrNull;
            final alSplit = fxBook == null
                ? null
                : assetLiabilityInBase(
                    accounts: [
                      for (final a in homeAccounts)
                        (
                          currency: a.currency,
                          balanceMinor:
                              homeBalances[a.id] ?? a.openingBalanceMinor,
                        ),
                    ],
                    book: fxBook,
                    baseCurrency: base,
                    onDay: FxBook.todayLocal(),
                  );
            final expenseSeries = ref.watch(_dailyExpenseProvider(baseArgs));
            final incomeSeries = ref.watch(_dailyIncomeProvider(baseArgs));
            final nowLocal = DateTime.now();
            final calMonth =
                _calendarMonth ?? DateTime(nowLocal.year, nowLocal.month);
            final calRange = DateRangeWindow.forMonth(
              calMonth.year,
              calMonth.month,
            );
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
            // 概览模式不订阅日历月的流水，避免和所选区间各扫一遍。
            final calExpenseSeries = _mode == 1
                ? ref.watch(_dailyExpenseProvider(calBaseArgs))
                : AsyncValue<List<({DateTime dayLocal, int totalMinor})>>.data(
                    const [],
                  );
            final calIncomeSeries = _mode == 1
                ? ref.watch(_dailyIncomeProvider(calBaseArgs))
                : AsyncValue<List<({DateTime dayLocal, int totalMinor})>>.data(
                    const [],
                  );
            final calRecent = _mode == 1
                ? ref.watch(_rangeTxProvider(calArgs))
                : const AsyncValue<List<Transaction>>.data([]);
            final lifetime = ref.watch(
              _lifetimeTotalsProvider((ledgerId: ledgerId, base: base)),
            );
            final nowMonth = DateRangeWindow.forMonth(
              nowLocal.year,
              nowLocal.month,
            );
            final monthSummary = ref.watch(
              _rangeBaseProvider((
                ledgerId: ledgerId,
                key: nowMonth.key,
                startMs: nowMonth.startMs,
                endMs: nowMonth.endMs,
                base: base,
              )),
            );

            // 待确认 / 解析失败：都为 0 时整块（含间距）不渲染，
            // 保证概览卡→图表与图表→账单的间距完全一致。
            final pendingOk =
                ref.watch(_homePendingOkProvider(ledgerId)).valueOrNull ??
                const <PendingCapture>[];
            final parseFailedCount =
                ref
                    .watch(_homeParseFailedCountProvider(ledgerId))
                    .valueOrNull ??
                0;
            final budgetProgress = ref.watch(
              _homeBudgetProgressProvider((ledgerId: ledgerId, base: base)),
            );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => context.push('/me/ledgers'),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                ledger.name,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.unfold_more,
                                size: 20,
                                color: scheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '截图记账',
                        onPressed: () =>
                            importCaptureFromScreenshot(context, ref),
                        icon: const Icon(Icons.document_scanner_outlined),
                      ),
                      IconButton(
                        tooltip: '搜索账单',
                        onPressed: () => context.push('/home/search'),
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  // 底部留白收窄：净资产卡片稍微上移。
                  padding: const EdgeInsets.fromLTRB(
                    CentliSpacing.pageH,
                    CentliSpacing.item,
                    CentliSpacing.pageH,
                    CentliSpacing.dense,
                  ),
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
                                _calendarMonth ??= DateTime(
                                  now.year,
                                  now.month,
                                );
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
                      ref.invalidate(_dailyExpenseProvider(baseArgs));
                      ref.invalidate(_dailyIncomeProvider(baseArgs));
                      ref.invalidate(currentLedgerProvider);
                      ref.invalidate(
                        _netWorthHomeProvider((ledgerId: ledgerId, base: base)),
                      );
                    },
                    child: ListView(
                      key: ValueKey(_mode),
                      padding: const EdgeInsets.fromLTRB(
                        CentliSpacing.pageH,
                        0,
                        CentliSpacing.pageH,
                        CentliSpacing.pageBottomNav,
                      ),
                      children: [
                        if (_mode == 0) ...[
                          _LedgerSummaryCard(
                            ledgerName: ledger.name,
                            base: base,
                            hide: hide,
                            // 不开资产锁就不显示眼睛：没东西可藏。
                            showAmountEye: lockOn,
                            onToggleAmountVisibility: () =>
                                _toggleHomeAmountVisibility(
                                  context,
                                  ref,
                                  currentlyHidden: hide,
                                ),
                            range: range,
                            netWorth: nw,
                            summary: summary,
                            assetLiability: alSplit,
                            lifetime: lifetime,
                            monthSummary: monthSummary,
                            budgetProgress: budgetProgress,
                          ),
                          // 待确认 / 解析失败都空时「间距 + 卡片」整体不出现，
                          // 概览卡到图表的距离才和图表到账单的一致。
                          if (pendingOk.isNotEmpty || parseFailedCount > 0) ...[
                            const SizedBox(height: CentliSpacing.sectionLoose),
                            _HomePendingSection(
                              okItems: pendingOk,
                              parseFailedCount: parseFailedCount,
                              hide: hide,
                            ),
                          ],
                          const SizedBox(height: CentliSpacing.sectionLoose),
                          _NetChangeChartCard(
                            ledgerId: ledgerId,
                            base: base,
                            hide: hide,
                            incomeSeries: incomeSeries,
                            expenseSeries: expenseSeries,
                            netWorth: nw,
                          ),
                          const SizedBox(height: CentliSpacing.sectionLoose),
                          CentliSoftCard(
                            padding: const EdgeInsets.all(
                              CentliSpacing.cardPad,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                DateRangeControl(
                                  range: range,
                                  onChanged: (next) {
                                    ref.read(homeRangeProvider.notifier).state =
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
                                  error: (e, _) =>
                                      CentliErrorState(error: e, compact: true),
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
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(
                                              height: CentliSpacing.dense,
                                            ),
                                            Text(
                                              '建议先到「资产」建好资产账户，再点底部「记一笔」',
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
                            onSelectDay: (d) {
                              setState(() => _calendarDay = d);
                              _openCalendarDaySheet(
                                day: d,
                                hide: hide,
                                base: base,
                                monthTxns: calRecent,
                              );
                            },
                          ),
                          const SizedBox(height: CentliSpacing.section),
                          _DailyTrendCard(
                            month: calMonth,
                            base: base,
                            hide: hide,
                            expenseSeries: calExpenseSeries,
                            incomeSeries: calIncomeSeries,
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
    );
  }

  Future<void> _openCalendarDaySheet({
    required DateTime day,
    required bool hide,
    required String base,
    required AsyncValue<List<Transaction>> monthTxns,
  }) async {
    final dayTxns = _txnsOnLocalDay(monthTxns.valueOrNull ?? const [], day);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final maxH = MediaQuery.sizeOf(sheetContext).height * 0.6;
        final scheme = Theme.of(sheetContext).colorScheme;
        var incomeMinor = 0;
        var expenseMinor = 0;
        for (final txn in dayTxns) {
          if (txn.type == 'in') {
            incomeMinor += txn.amountMinor;
          } else if (txn.type == 'out') {
            expenseMinor += txn.amountMinor;
          }
        }
        return SizedBox(
          height: maxH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${day.month}月${day.day}日 · ${_weekdayCn(day)}',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      tooltip: '补记',
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        final saved = await showBookkeepingSheet(
                          context,
                          initialHappenAt: day,
                        );
                        if (!mounted) return;
                        if (saved == true) {
                          await Future<void>.delayed(
                            const Duration(milliseconds: 80),
                          );
                          if (!mounted) return;
                          final ledger = ref
                              .read(currentLedgerProvider)
                              .valueOrNull;
                          if (ledger == null) return;
                          final nowLocal = DateTime.now();
                          final calMonth =
                              _calendarMonth ??
                              DateTime(nowLocal.year, nowLocal.month);
                          final calRange = DateRangeWindow.forMonth(
                            calMonth.year,
                            calMonth.month,
                          );
                          final fresh = await ref.read(
                            _rangeTxProvider((
                              ledgerId: ledger.id,
                              key: calRange.key,
                              startMs: calRange.startMs,
                              endMs: calRange.endMs,
                            )).future,
                          );
                          if (!mounted) return;
                          setState(() => _calendarDay = day);
                          await _openCalendarDaySheet(
                            day: day,
                            hide: hide,
                            base: base,
                            monthTxns: AsyncValue.data(fresh),
                          );
                        }
                      },
                      icon: Icon(Icons.add_circle, color: scheme.primary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '支出 ${formatMinor(base, expenseMinor, hide: hide)}'
                  ' · 收入 ${formatMinor(base, incomeMinor, hide: hide)}',
                  style: Theme.of(sheetContext).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: dayTxns.isEmpty
                    ? CentliEmptyState(
                        icon: Icons.event_busy_outlined,
                        title: '这天没有记录',
                        message: '点右上角 + 补记这一天',
                        padding: const EdgeInsets.all(CentliSpacing.cardPad),
                      )
                    : SingleChildScrollView(
                        child: TxnGroupedSection(txns: dayTxns, hide: hide),
                      ),
              ),
            ],
          ),
        );
      },
    );
    if (mounted) setState(() => _calendarDay = null);
  }
}

String _weekdayCn(DateTime d) {
  const names = ['一', '二', '三', '四', '五', '六', '日'];
  return '周${names[d.weekday - 1]}';
}

List<Transaction> _txnsOnLocalDay(List<Transaction> txns, DateTime day) {
  return [
    for (final txn in txns)
      if (_isSameLocalDay(txn, day)) txn,
  ];
}

bool _isSameLocalDay(Transaction txn, DateTime day) {
  final local = DateTime.fromMillisecondsSinceEpoch(
    txn.happenAt,
    isUtc: true,
  ).toLocal();
  return local.year == day.year &&
      local.month == day.month &&
      local.day == day.day;
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

Future<void> _toggleHomeAmountVisibility(
  BuildContext context,
  WidgetRef ref, {
  required bool currentlyHidden,
}) async {
  // 只在资产锁开启时才会显示眼睛（见 showAmountEye），所以这里只有两种状态：
  // 隐藏中 → 验证后临时显示；显示中 → 直接收起，不需要验证。
  if (!currentlyHidden) {
    ref.read(amountsRevealedProvider.notifier).conceal();
    return;
  }
  final ok = await authenticateSensitiveAction(context, ref);
  if (ok) ref.read(amountsRevealedProvider.notifier).reveal();
}

/// 概览卡：
///
/// ```
/// 记账本名                            👁
/// ¥ 3,375.20                ▲ ¥ 3,375.20
/// ─────────────────────────────
/// 资产  ¥5,010.00      负债  ¥1,634.80
///   月收入 ¥5,724.00     月支出 ¥1,388.58
///   总收入 ¥11,841.96    总支出 ¥7,067.68
/// ```
class _LedgerSummaryCard extends StatelessWidget {
  const _LedgerSummaryCard({
    required this.ledgerName,
    required this.base,
    required this.hide,
    required this.showAmountEye,
    required this.onToggleAmountVisibility,
    required this.range,
    required this.netWorth,
    required this.summary,
    required this.assetLiability,
    required this.lifetime,
    required this.monthSummary,
    required this.budgetProgress,
  });

  final String ledgerName;
  final String base;
  final bool hide;
  final bool showAmountEye;
  final VoidCallback onToggleAmountVisibility;
  final DateRangeWindow range;
  final AsyncValue<BaseNetWorth> netWorth;
  final AsyncValue<BaseRangeSummary> summary;
  final BaseAssetLiability? assetLiability;
  final AsyncValue<({int incomeMinor, int expenseMinor})> lifetime;
  final AsyncValue<BaseRangeSummary> monthSummary;
  final AsyncValue<MonthBudgetProgress> budgetProgress;

  String _money(int minor) => formatMinor(base, minor, hide: hide);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final loading = netWorth.isLoading || summary.isLoading;
    final failed = netWorth.hasError || summary.hasError;
    final nw = netWorth.valueOrNull;
    final s = summary.valueOrNull;
    final income = s?.incomeMinor ?? 0;
    final expense = s?.expenseMinor ?? 0;
    final delta = income - expense;
    final net = nw?.totalMinor ?? 0;
    final asset = assetLiability?.assetMinor ?? (net > 0 ? net : 0);
    final liability = assetLiability?.liabilityMinor ?? (net < 0 ? -net : 0);
    final month = monthSummary.valueOrNull;
    final life = lifetime.valueOrNull;

    if (failed) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: CentliErrorState(
          error: netWorth.error ?? summary.error,
          compact: true,
        ),
      );
    }
    if (loading && nw == null && s == null) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: SizedBox(
          height: 120,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: scheme.primary,
            ),
          ),
        ),
      );
    }

    final deltaPositive = delta >= 0;
    final deltaColor = deltaPositive
        ? CentliTheme.incomeGreen
        : CentliTheme.expenseRed;
    final labelSmall = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final subLabel = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: 11.5,
    );
    final subValue = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 12.5,
      color: scheme.onSurface,
    );

    Widget subLine(String label, String? value, Color color) {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Text(label, style: subLabel),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                value ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: subValue?.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
    }

    // 一列：资产 / 月收入 / 总收入 或 负债 / 月支出 / 总支出
    Widget column({
      required String title,
      required String total,
      required Color totalColor,
      required String monthLabel,
      required String? monthValue,
      required Color monthColor,
      required String lifeLabel,
      required String? lifeValue,
      required Color lifeColor,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: labelSmall),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  total,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: totalColor,
                  ),
                ),
              ),
            ],
          ),
          subLine(monthLabel, monthValue, monthColor),
          subLine(lifeLabel, lifeValue, lifeColor),
        ],
      );
    }

    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 记账本名 +（资产锁开启时）眼睛
          Row(
            children: [
              Expanded(
                child: Text(
                  ledgerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelSmall,
                ),
              ),
              if (showAmountEye)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  tooltip: hide ? '验证后显示金额' : '隐藏金额',
                  onPressed: onToggleAmountVisibility,
                  icon: Icon(
                    hide
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: CentliSpacing.dense),
          // 净资产 + 区间涨跌
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _money(net),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: -0.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (s != null)
                // 大金额 + 窄屏时这一块必须能收缩，否则整行溢出。
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        deltaPositive
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 16,
                        color: deltaColor,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          _money(delta.abs()),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: deltaColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (nw != null && nw.hasUnconverted) ...[
            const SizedBox(height: CentliSpacing.item),
            Text(
              '未折算：${nw.unconvertedByCcy.entries.map((e) => '${e.key} ${formatMinor(e.key, e.value, hide: hide)}').join('、')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: CentliSpacing.section),
          const Divider(height: 1),
          const SizedBox(height: CentliSpacing.item),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: column(
                  title: '资产',
                  total: _money(asset),
                  totalColor: CentliTheme.incomeGreen,
                  monthLabel: '月收入',
                  monthValue: month == null ? null : _money(month.incomeMinor),
                  monthColor: CentliTheme.incomeGreen,
                  lifeLabel: '总收入',
                  lifeValue: life == null ? null : _money(life.incomeMinor),
                  lifeColor: CentliTheme.incomeGreen,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: column(
                  title: '负债',
                  total: _money(liability),
                  totalColor: CentliTheme.expenseRed,
                  monthLabel: '月支出',
                  monthValue: month == null ? null : _money(month.expenseMinor),
                  monthColor: CentliTheme.expenseRed,
                  lifeLabel: '总支出',
                  lifeValue: life == null ? null : _money(life.expenseMinor),
                  lifeColor: CentliTheme.expenseRed,
                ),
              ),
            ],
          ),
          _HomeBudgetStrip(
            progress: budgetProgress.valueOrNull,
            base: base,
            hide: hide,
          ),
        ],
      ),
    );
  }
}

/// 概览卡底部：有月度总预算时展示已用 / 剩余（或超支）。
class _HomeBudgetStrip extends StatelessWidget {
  const _HomeBudgetStrip({
    required this.progress,
    required this.base,
    required this.hide,
  });

  final MonthBudgetProgress? progress;
  final String base;
  final bool hide;

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final limit = p?.totalLimitMinor;
    if (p == null || limit == null || limit <= 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spent = p.spentTotalMinor;
    final remain = limit - spent;
    final over = remain < 0;
    final ratio = (spent / limit).clamp(0.0, 1.5);
    final barColor = over
        ? scheme.error
        : ratio >= 0.8
        ? scheme.tertiary
        : scheme.primary;
    final remainLabel = over
        ? '超支 ${formatMinor(base, -remain, hide: hide)}'
        : '剩余 ${formatMinor(base, remain, hide: hide)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: CentliSpacing.section),
        const Divider(height: 1),
        InkWell(
          onTap: () => context.push('/me/budget'),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.only(top: CentliSpacing.item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '本月预算',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      remainLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: over ? scheme.error : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: CentliSpacing.dense),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                    color: barColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已用 ${formatMinor(base, spent, hide: hide)}'
                  ' / ${formatMinor(base, limit, hide: hide)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 净资产变化卡：折线 + 右上「账单列表 / 分类占比」两个入口。
class _NetChangeChartCard extends StatelessWidget {
  const _NetChangeChartCard({
    required this.ledgerId,
    required this.base,
    required this.hide,
    required this.incomeSeries,
    required this.expenseSeries,
    required this.netWorth,
  });

  final String ledgerId;
  final String base;
  final bool hide;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> incomeSeries;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> expenseSeries;
  final AsyncValue<BaseNetWorth> netWorth;

  @override
  Widget build(BuildContext context) {
    final loading =
        incomeSeries.isLoading || expenseSeries.isLoading || netWorth.isLoading;
    final failed =
        incomeSeries.hasError || expenseSeries.hasError || netWorth.hasError;
    if (failed) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: CentliErrorState(
          error: incomeSeries.error ?? expenseSeries.error ?? netWorth.error,
          compact: true,
        ),
      );
    }
    if (loading &&
        incomeSeries.valueOrNull == null &&
        expenseSeries.valueOrNull == null) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final income = incomeSeries.valueOrNull ?? const [];
    final expense = expenseSeries.valueOrNull ?? const [];
    final n = income.length > expense.length ? income.length : expense.length;
    final endNetMajor = fromMinor(base, netWorth.valueOrNull?.totalMinor ?? 0);

    // Reconstruct daily net-worth path ending at current NW:
    // dayNet = income - expense; periodNet = sum(dayNet);
    // startNW = endNW - periodNet; then accumulate forward.
    var periodNet = 0.0;
    final dayNets = <double>[];
    final dayLabels = <DateTime>[];
    for (var i = 0; i < n; i++) {
      final inV = i < income.length ? income[i].totalMinor : 0;
      final outV = i < expense.length ? expense[i].totalMinor : 0;
      final dayNet = fromMinor(base, inV - outV);
      dayNets.add(dayNet);
      periodNet += dayNet;
      final day = i < income.length
          ? income[i].dayLocal
          : (i < expense.length
                ? expense[i].dayLocal
                : DateTime.fromMillisecondsSinceEpoch(0));
      dayLabels.add(day);
    }
    // 区间起点先落一个点，这样只有一天有账时也能看出台阶，而不是整条线贴平。
    var running = endNetMajor - periodNet;
    final spots = <FlSpot>[FlSpot(0, running)];
    if (dayLabels.isNotEmpty) {
      dayLabels.insert(0, dayLabels.first.subtract(const Duration(days: 1)));
    }
    for (var i = 0; i < n; i++) {
      running += dayNets[i];
      spots.add(FlSpot((i + 1).toDouble(), running));
    }

    /// 跳到底部导航的某个 tab（`/stats` 等），并替换掉当前推入的页面，
    /// 这样返回不会回到半截状态，底栏也会同步高亮对应 tab。
    void openTab(String location) {
      GoRouter.of(context).go(location);
    }

    return CentliTrendChart(
      title: '\u51c0\u8d44\u4ea7\u53d8\u5316',
      spots: spots,
      dayLabels: dayLabels,
      base: base,
      hide: hide,
      sparseMessage: '\u533a\u95f4\u53d8\u52a8\u8f83\u5c11',
      height: 112,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChartActionButton(
            key: const Key('net_change_pie'),
            tooltip: '分类占比',
            icon: Icons.pie_chart_outline,
            // 直接切到「统计」tab，而不是在当前 tab 上叠一层统计页。
            onPressed: () => openTab('/stats'),
          ),
        ],
      ),
    );
  }
}

/// Small icon button used in the chart card header.
class _ChartActionButton extends StatelessWidget {
  const _ChartActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
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

  Map<int, int> _dayMap(
    List<({DateTime dayLocal, int totalMinor})> series,
    DateTime monthStart,
  ) {
    final m = <int, int>{};
    for (final e in series) {
      if (e.dayLocal.year == monthStart.year &&
          e.dayLocal.month == monthStart.month) {
        m[e.dayLocal.day] = e.totalMinor;
      }
    }
    return m;
  }

  String _compact(int minor) {
    if (hide) return '**';
    final major = fromMinor(base, minor);
    if (major.abs() >= 10000) {
      return '${(major / 10000).toStringAsFixed(1)}\u4e07';
    }
    if (major.abs() >= 1000) {
      return '${(major / 1000).toStringAsFixed(1)}k';
    }
    if (major == major.roundToDouble()) {
      return major.toStringAsFixed(0);
    }
    return major.toStringAsFixed(0);
  }

  Widget _amtLine(BuildContext context, int minor, Color color) {
    if (minor == 0) return const SizedBox.shrink();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _compact(minor),
          maxLines: 1,
          style: TextStyle(
            fontSize: 9,
            height: 1.05,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = incomeSeries.isLoading || expenseSeries.isLoading;
    final failed = incomeSeries.hasError || expenseSeries.hasError;
    if (failed) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: Text(
          '数据加载失败，点「重试」或下拉刷新',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (loading &&
        incomeSeries.valueOrNull == null &&
        expenseSeries.valueOrNull == null) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: const SizedBox(
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final monthStart = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    final firstWeekday = monthStart.weekday % 7; // Sun=0
    final today = DateTime.now();
    final thisMonth = DateTime(today.year, today.month, 1);
    final isCurrentMonth =
        monthStart.year == thisMonth.year &&
        monthStart.month == thisMonth.month;
    final labels = [
      '\u5468\u65e5',
      '\u5468\u4e00',
      '\u5468\u4e8c',
      '\u5468\u4e09',
      '\u5468\u56db',
      '\u5468\u4e94',
      '\u5468\u516d',
    ];
    final incomeByDay = _dayMap(
      incomeSeries.valueOrNull ?? const [],
      monthStart,
    );
    final expenseByDay = _dayMap(
      expenseSeries.valueOrNull ?? const [],
      monthStart,
    );

    return CentliSoftCard(
      padding: const EdgeInsets.all(CentliSpacing.cardPad),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '\u4e0a\u4e00\u6708',
                onPressed: () {
                  final p = DateTime(monthStart.year, monthStart.month - 1, 1);
                  onMonthChanged(p);
                },
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${monthStart.year}\u5e74${monthStart.month}\u6708',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '\u4e0b\u4e00\u6708',
                onPressed: isCurrentMonth
                    ? null
                    : () {
                        final n = DateTime(
                          monthStart.year,
                          monthStart.month + 1,
                          1,
                        );
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
          const SizedBox(height: CentliSpacing.item),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: firstWeekday + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 0.82,
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
              final inMinor = incomeByDay[day] ?? 0;
              final outMinor = expenseByDay[day] ?? 0;
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
                  padding: const EdgeInsets.only(top: 2, left: 1, right: 1),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.15,
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
                        const SizedBox(height: 1),
                        _amtLine(context, inMinor, CentliTheme.incomeGreen),
                        _amtLine(context, outMinor, CentliTheme.expenseRed),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// First day (local) of [d]'s month.
DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

/// 1-based day-of-month of [d] inside the month starting at [monthStart];
/// days outside that month clamp into [1, daysInMonth] so a mis-bucketed row
/// never shifts the whole series.
int _dayOfMonth(DateTime d, DateTime monthStart) {
  if (d.year == monthStart.year && d.month == monthStart.month) return d.day;
  final lastDay = DateTime(monthStart.year, monthStart.month + 1, 0).day;
  return d.isBefore(monthStart) ? 1 : lastDay;
}

/// Per-day net (income − expense) for every day of [monthStart]'s month.
///
/// Index i is day i+1. Days without bills are 0 — they are "no bill that day",
/// not "carry the previous total". The calendar chart plots these values
/// directly: 13 号 −1、14 号 −71、16 号 63 就是这三个点，其余天为 0。
@visibleForTesting
List<double> monthlyDailyNetMajor({
  required String base,
  required DateTime monthStart,
  required List<({DateTime dayLocal, int totalMinor})> income,
  required List<({DateTime dayLocal, int totalMinor})> expense,
}) {
  final daysInMonth = DateTime(monthStart.year, monthStart.month + 1, 0).day;
  final inByDay = <int, int>{};
  final outByDay = <int, int>{};
  for (final e in income) {
    final d = _dayOfMonth(e.dayLocal, monthStart);
    if (d <= daysInMonth) inByDay[d] = e.totalMinor;
  }
  for (final e in expense) {
    final d = _dayOfMonth(e.dayLocal, monthStart);
    if (d <= daysInMonth) outByDay[d] = e.totalMinor;
  }
  return [
    for (var d = 1; d <= daysInMonth; d++)
      dailyNetMajor(base, inByDay[d] ?? 0, outByDay[d] ?? 0),
  ];
}

class _DailyTrendCard extends StatelessWidget {
  const _DailyTrendCard({
    required this.month,
    required this.base,
    required this.hide,
    required this.expenseSeries,
    required this.incomeSeries,
  });

  final DateTime month;
  final String base;
  final bool hide;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> expenseSeries;
  final AsyncValue<List<({DateTime dayLocal, int totalMinor})>> incomeSeries;

  @override
  Widget build(BuildContext context) {
    final loading = expenseSeries.isLoading || incomeSeries.isLoading;
    final failed = expenseSeries.hasError || incomeSeries.hasError;
    if (failed) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: Text(
          '数据加载失败，点「重试」或下拉刷新',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (loading &&
        expenseSeries.valueOrNull == null &&
        incomeSeries.valueOrNull == null) {
      return CentliSoftCard(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final monthStart = _firstOfMonth(month);
    final dailyNet = monthlyDailyNetMajor(
      base: base,
      monthStart: monthStart,
      income: incomeSeries.valueOrNull ?? const [],
      expense: expenseSeries.valueOrNull ?? const [],
    );
    // 每日净额：有账天 = 收入 − 支出，无账天 = 0（不是累计）。
    final spots = <FlSpot>[
      for (var i = 0; i < dailyNet.length; i++)
        FlSpot(i.toDouble(), dailyNet[i]),
    ];
    final dayLabels = <DateTime>[
      for (var i = 0; i < dailyNet.length; i++)
        DateTime(monthStart.year, monthStart.month, i + 1),
    ];

    return CentliTrendChart(
      title: '\u6bcf\u65e5\u6536\u652f',
      spots: spots,
      dayLabels: dayLabels,
      base: base,
      hide: hide,
      height: 120,
      // 单线：当日净额（收入 − 支出），可为负；不按正负拆成红绿两段。
      signColored: false,
      lineColor: CentliTheme.softBlue,
      sparseMessage: '\u672c\u6708\u6682\u65e0\u6536\u652f',
    );
  }
}

/// 首页待处理区：可确认轮播 + 解析失败入口（二者不混在同一滑动里）。
class _HomePendingSection extends ConsumerStatefulWidget {
  const _HomePendingSection({
    required this.okItems,
    required this.parseFailedCount,
    required this.hide,
  });

  final List<PendingCapture> okItems;
  final int parseFailedCount;
  final bool hide;

  @override
  ConsumerState<_HomePendingSection> createState() =>
      _HomePendingSectionState();
}

class _HomePendingSectionState extends ConsumerState<_HomePendingSection> {
  late final PageController _pageController;
  int _index = 0;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HomePendingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.okItems.length) {
      _index = widget.okItems.isEmpty ? 0 : widget.okItems.length - 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final okItems = widget.okItems;
    final failCount = widget.parseFailedCount;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final onlyFailed = okItems.isEmpty && failCount > 0;

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
          if (okItems.isNotEmpty) ...[
            InkWell(
              onTap: () => context.push('/home/pending?tab=pending'),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '待确认 (${okItems.length})',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: CentliSpacing.dense),
                        Text(
                          '左右滑动切换 · 点卡片填写并入账',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
            const SizedBox(height: CentliSpacing.item),
            SizedBox(
              height: 152,
              child: PageView.builder(
                key: const Key('home_pending_carousel'),
                controller: _pageController,
                itemCount: okItems.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final c = okItems[i];
                  return AnimatedPadding(
                    duration: const Duration(milliseconds: 160),
                    padding: EdgeInsets.only(
                      left: 2,
                      right: i == okItems.length - 1 ? 0 : 8,
                      bottom: 6,
                    ),
                    child: _HomePendingSlide(
                      key: ValueKey('pending_slide_${c.id}'),
                      capture: c,
                      hide: widget.hide,
                      busy: _busyId == c.id,
                      onConfirm: () => _confirm(c),
                      onIgnore: () => _ignore(c),
                      onOpen: () => context.push('/home/pending?tab=pending'),
                    ),
                  );
                },
              ),
            ),
            if (okItems.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: CentliSpacing.item),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < okItems.length; i++)
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
          if (failCount > 0) ...[
            if (okItems.isNotEmpty) ...[
              const Divider(height: 1),
              const SizedBox(height: CentliSpacing.dense),
            ],
            Material(
              key: const Key('home_parse_failed_banner'),
              color: scheme.errorContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push('/home/pending?tab=parse_failed'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 20,
                        color: scheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              onlyFailed
                                  ? '解析失败 ($failCount)'
                                  : '$failCount 条解析失败',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              onlyFailed ? '通知里没认出金额，点此补全或忽略' : '未认出金额，点此补全或忽略',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onErrorContainer.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: scheme.onErrorContainer),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: CentliSpacing.dense),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(PendingCapture c) async {
    if (_busyId != null) return;
    final ok = await showPendingConfirmDialog(context, ref, capture: c);
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已入账')));
    final remaining = widget.okItems.length - 1;
    if (remaining > 0) {
      final next = _index.clamp(0, remaining - 1);
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
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

/// 一张待确认卡片：渠道 · 金额 · 备注，右下角「忽略 / 入账」。
class _HomePendingSlide extends StatelessWidget {
  const _HomePendingSlide({
    super.key,
    required this.capture,
    required this.hide,
    required this.busy,
    required this.onConfirm,
    required this.onIgnore,
    required this.onOpen,
  });

  final PendingCapture capture;
  final bool hide;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onIgnore;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = capture;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ccy = c.currency ?? 'CNY';
    final amount = c.amountMinor == null
        ? '金额未知'
        : formatMinor(ccy, c.amountMinor!, hide: hide);
    final direction = pendingDirectionLabel(_captureDirection(c));
    final when = c.happenAt == null
        ? null
        : DateFormat('MM-dd HH:mm')
              .format(DateTime.fromMillisecondsSinceEpoch(c.happenAt!));
    final amountColor = _captureDirection(c) == 'in'
        ? CentliTheme.incomeGreen
        : CentliTheme.expenseRed;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      [pendingSourceLabel(c.sourcePkg), ?when].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    direction,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CentliSpacing.dense),
              Text(
                amount,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: amountColor,
                ),
              ),
              const SizedBox(height: CentliSpacing.dense),
              Text(
                (c.note ?? '').trim().isEmpty ? '无备注' : c.note!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const Spacer(),
              Row(
                children: [
                  _CategoryHint(capture: c),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: busy ? null : onIgnore,
                    child: const Text('忽略'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: busy ? null : onConfirm,
                    child: const Text('入账'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 方向：优先用落库的 direction，没有就按标题重新解析。
String _captureDirection(PendingCapture c) {
  final stored = c.direction?.trim();
  if (stored != null && stored.isNotEmpty) {
    return NotiTemplate.normalizeDirection(stored);
  }
  final templates = NotiTemplateStore.peek();
  return NotiTemplate.normalizeDirection(
    parseNotification(
      RawNotification(
        pkg: c.sourcePkg,
        title: c.rawTitle ?? '',
        text: c.rawText,
        whenMs: c.happenAt ?? c.createdAt,
      ),
      templates.isEmpty ? null : templates,
    ).direction,
  );
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

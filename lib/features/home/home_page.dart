import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/date_range.dart';
import '../../core/widgets/date_range_control.dart';
import '../../core/widgets/txn_list_tile.dart';
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

final _rangeBaseProvider = FutureProvider.family<
    BaseRangeSummary,
    ({String ledgerId, String key, int startMs, int endMs, String base})>((ref, args) async {
  await ref.watch(fxBookProvider.future);
  final db = ref.watch(databaseProvider);
  return db.rangeSummaryInBase(
    args.ledgerId,
    args.startMs,
    args.endMs,
    args.base,
  );
});

final _rangeTxProvider = StreamProvider.family<List<Transaction>,
    ({String ledgerId, String key, int startMs, int endMs})>((ref, args) {
  final db = ref.watch(databaseProvider);
  return db.watchTransactionsInRange(args.ledgerId, args.startMs, args.endMs);
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final hideAsync = ref.watch(hideAmountProvider);
    final hide = hideAsync.valueOrNull ?? false;
    final range = ref.watch(homeRangeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Centli'),
        actions: [
          IconButton(
            tooltip: '\u641c\u7d22\u8d26\u5355',
            onPressed: () => context.push('/home/search'),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: hide ? '\u663e\u793a\u91d1\u989d' : '\u9690\u85cf\u91d1\u989d',
            onPressed: () async {
              await ref.read(databaseProvider).toggleHideAmount();
            },
            icon: Icon(hide
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('\u52a0\u8f7d\u5931\u8d25: $e')),
        data: (ledger) {
          if (ledger == null) {
            return const Center(child: Text('\u5c1a\u672a\u521d\u59cb\u5316\u8d26\u672c'));
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

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_rangeBaseProvider(baseArgs));
              ref.invalidate(currentLedgerProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                DateRangeControl(
                  range: range,
                  onChanged: (next) {
                    ref.read(homeRangeProvider.notifier).state = next;
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  '\u672c\u4f4d\u5e01 $base\uff08\u6309\u53d1\u751f\u65e5\u6c47\u7387\u6298\u7b97\uff09',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                summary.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                  data: (s) {
                    final others = s.unconverted.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key));
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryCard(
                                label: '\u652f\u51fa \u00b7 $base',
                                value: formatMinor(base, s.expenseMinor,
                                    hide: hide),
                                color: scheme.error,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryCard(
                                label: '\u6536\u5165 \u00b7 $base',
                                value: formatMinor(base, s.incomeMinor,
                                    hide: hide),
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                        if (others.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '\u672a\u6298\u7b97\uff1a${others.map((e) {
                              final t = e.value;
                              final parts = <String>[];
                              if (t.expense > 0) {
                                parts.add(
                                    '\u652f ${formatMinor(e.key, t.expense, hide: hide)}');
                              }
                              if (t.income > 0) {
                                parts.add(
                                    '\u6536 ${formatMinor(e.key, t.income, hide: hide)}');
                              }
                              return '${e.key} ${parts.join(' / ')}';
                            }).join(' \u00b7 ')}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _HomePendingSection(ledgerId: ledgerId, hide: hide),
                const SizedBox(height: 8),
                Text('\u6700\u8fd1', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                recent.when(
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
                              Text('\u6682\u65e0\u8d26\u5355',
                                  style: TextStyle(
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              Text(
                                '\u70b9\u4e2d\u95f4\u300c\uff0b\u300d\u8bb0\u4e0b\u7b2c\u4e00\u7b14',
                                style: Theme.of(context).textTheme.bodySmall,
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
                            TxnListTile(txn: txns[i], hide: hide),
                          ],
                        ],
                      ),
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
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
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
    // Wireframe empty: hide whole pending block when none
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return _HomePendingCarousel(items: items, hide: hide);
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

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            dense: true,
            title: Text('\u5f85\u786e\u8ba4 (${items.length})'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/home/pending'),
          ),
          SizedBox(
            height: 108,
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _index = i),
              // Horizontal swipe browses items only; ignore is via tap on button.
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
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < items.length; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
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
        ? '\u91d1\u989d\u672a\u77e5'
        : formatMinor(ccy, c.amountMinor!, hide: hide);
    final merchant = (c.merchant ?? '').trim();
    final title = merchant.isNotEmpty
        ? '${_pkgLabel(c.sourcePkg)} \u00b7 $amount \u00b7 $merchant'
        : '${_pkgLabel(c.sourcePkg)} \u00b7 $amount';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    _CategoryHint(capture: c),
                  ],
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onIgnore,
            child: const Text('\u5ffd\u7565'),
          ),
        ],
      ),
    );
  }

  String _pkgLabel(String pkg) {
    if (pkg.contains('Alipay') || pkg.contains('alipay')) {
      return '\u652f\u4ed8\u5b9d';
    }
    if (pkg.contains('tencent.mm')) return '\u5fae\u4fe1';
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
        '\u5f85\u9009\u5206\u7c7b',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return FutureBuilder<Category?>(
      future: ref.read(databaseProvider).getCategory(id),
      builder: (context, snap) {
        final name = snap.data?.name;
        final label = (name == null || name.isEmpty)
            ? '\u5f85\u9009\u5206\u7c7b'
            : '\u731c\u300c$name\u300d';
        return Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        );
      },
    );
  }
}

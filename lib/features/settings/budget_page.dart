import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../security/app_lock_controller.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

final budgetMonthProvider = StateProvider<String>((ref) {
  return budgetYearMonth();
});

final _budgetsProvider = StreamProvider.family<List<Budget>,
    ({String ledgerId, String yearMonth})>((ref, args) {
  return ref.watch(databaseProvider).watchBudgetsForMonth(
        args.ledgerId,
        args.yearMonth,
      );
});

final _budgetProgressProvider = FutureProvider.family<
    MonthBudgetProgress,
    ({String ledgerId, String yearMonth, String base})>((ref, args) async {
  await ref.watch(fxBookProvider.future);
  await ref.watch(
    _budgetsProvider(
      (ledgerId: args.ledgerId, yearMonth: args.yearMonth),
    ).future,
  );
  return ref.watch(databaseProvider).monthBudgetProgress(
        args.ledgerId,
        args.yearMonth,
        args.base,
      );
});

/// P3 MVP: set monthly total + per-category expense budgets; show progress.
class BudgetPage extends ConsumerWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(currentLedgerProvider);
    final ym = ref.watch(budgetMonthProvider);
    final hide = ref.watch(hideAmountProvider);
    final scheme = Theme.of(context).colorScheme;

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('\u9884\u7b97'),
        actions: [
          IconButton(
            tooltip: '\u6dfb\u52a0\u5206\u7c7b\u9884\u7b97',
            onPressed: () {
              final ledger = ledgerAsync.valueOrNull;
              if (ledger == null) return;
              _showCategoryBudgetEditor(
                context,
                ref,
                ledgerId: ledger.id,
                yearMonth: ym,
                baseCurrency: ledger.baseCurrency,
              );
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ledgerAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (ledger) {
          if (ledger == null) {
            return const Center(child: Text('\u5c1a\u672a\u521d\u59cb\u5316\u8d26\u672c'));
          }
          final base = ledger.baseCurrency;
          final progressAsync = ref.watch(
            _budgetProgressProvider(
              (ledgerId: ledger.id, yearMonth: ym, base: base),
            ),
          );

          return ListView(
            padding: CentliSpacing.pagePadding,
            children: [
              _MonthSwitcher(
                yearMonth: ym,
                onPrev: () => ref.read(budgetMonthProvider.notifier).state =
                    _shiftMonth(ym, -1),
                onNext: () => ref.read(budgetMonthProvider.notifier).state =
                    _shiftMonth(ym, 1),
              ),
              const SizedBox(height: CentliSpacing.item),
              Text(
                '\u91d1\u989d\u6309\u672c\u4f4d\u5e01 $base\uff1b\u4ec5\u7edf\u8ba1\u5df2\u5f00\u542f\u300c\u8ba1\u5165\u9884\u7b97\u300d\u7684\u652f\u51fa\u3002'
                '\u5206\u7c7b\u9884\u7b97\u4e0e\u603b\u9884\u7b97\u72ec\u7acb\uff08\u4e0d\u81ea\u52a8\u52a0\u603b\uff09\u3002',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: CentliSpacing.section),
              progressAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (p) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (p.hasUnconverted) ...[
                        Text(
                          '\u672a\u6298\u7b97\uff1a${p.unconvertedByCcy.entries.map((e) => '${e.key} ${formatMinor(e.key, e.value, hide: hide)}').join('\u3001')}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: CentliSpacing.item),
                      ],
                      _BudgetProgressCard(
                        title: '\u6708\u5ea6\u603b\u9884\u7b97',
                        limitMinor: p.totalLimitMinor,
                        spentMinor: p.spentTotalMinor,
                        currency: base,
                        hide: hide,
                        scheme: scheme,
                        unsetHint: '\u70b9\u51fb\u8bbe\u7f6e\u672c\u6708\u603b\u989d\u5ea6',
                        onTap: () => _showAmountEditor(
                          context,
                          ref,
                          ledgerId: ledger.id,
                          yearMonth: ym,
                          categoryId: '',
                          baseCurrency: base,
                          initialMinor: p.totalLimitMinor,
                          title: '\u6708\u5ea6\u603b\u9884\u7b97',
                        ),
                        onClear: p.totalLimitMinor == null
                            ? null
                            : () async {
                                await ref.read(databaseProvider).deleteBudgetByKey(
                                      ledgerId: ledger.id,
                                      yearMonth: ym,
                                      categoryId: '',
                                    );
                              },
                      ),
                      const SizedBox(height: CentliSpacing.sectionLoose),
                      Text(
                        '\u5206\u7c7b\u9884\u7b97',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: CentliSpacing.item),
                      if (p.categories.isEmpty)
                        CentliSoftCard(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(Icons.pie_chart_outline,
                                    size: 40, color: scheme.outline),
                                const SizedBox(height: CentliSpacing.item),
                                const Text('\u6682\u65e0\u5206\u7c7b\u9884\u7b97'),
                                const SizedBox(height: CentliSpacing.dense),
                                Text(
                                  '\u70b9\u53f3\u4e0a\u89d2 + \u4e3a\u652f\u51fa\u5206\u7c7b\u8bbe\u989d\u5ea6',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...p.categories.map((c) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _BudgetProgressCard(
                              title: c.name,
                              limitMinor: c.limitMinor,
                              spentMinor: c.spentMinor,
                              currency: base,
                              hide: hide,
                              scheme: scheme,
                              onTap: () => _showAmountEditor(
                                context,
                                ref,
                                ledgerId: ledger.id,
                                yearMonth: ym,
                                categoryId: c.categoryId,
                                baseCurrency: base,
                                initialMinor: c.limitMinor,
                                title: c.name,
                              ),
                              onClear: () async {
                                await ref
                                    .read(databaseProvider)
                                    .deleteBudgetByKey(
                                      ledgerId: ledger.id,
                                      yearMonth: ym,
                                      categoryId: c.categoryId,
                                    );
                              },
                            ),
                          );
                        }),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.yearMonth,
    required this.onPrev,
    required this.onNext,
  });

  final String yearMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final parts = yearMonth.split('-');
    final label = '${parts[0]}\u5e74${int.parse(parts[1])}\u6708';
    return Row(
      children: [
        IconButton(tooltip: '上一月', onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        IconButton(tooltip: '下一月', onPressed: onNext, icon: const Icon(Icons.chevron_right)),
      ],
    );
  }
}

class _BudgetProgressCard extends StatelessWidget {
  const _BudgetProgressCard({
    required this.title,
    required this.limitMinor,
    required this.spentMinor,
    required this.currency,
    required this.hide,
    required this.scheme,
    required this.onTap,
    this.onClear,
    this.unsetHint,
  });

  final String title;
  final int? limitMinor;
  final int spentMinor;
  final String currency;
  final bool hide;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String? unsetHint;

  @override
  Widget build(BuildContext context) {
    final hasLimit = limitMinor != null && limitMinor! > 0;
    final limit = limitMinor ?? 0;
    final ratio = !hasLimit
        ? 0.0
        : (spentMinor / limit).clamp(0.0, 1.5);
    final over = hasLimit && spentMinor > limit;
    final barColor = !hasLimit
        ? scheme.outlineVariant
        : over
            ? scheme.error
            : ratio >= 0.8
                ? scheme.tertiary
                : scheme.primary;
    final remain = hasLimit ? limit - spentMinor : null;

    return CentliSoftCard(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(CentliSpacing.cardPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (onClear != null)
                    IconButton(
                      tooltip: '\u6e05\u9664',
                      visualDensity: VisualDensity.compact,
                      onPressed: onClear,
                      icon: const Icon(Icons.delete_outline, size: 20),
                    ),
                  Icon(Icons.edit_outlined,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: CentliSpacing.item),
              if (!hasLimit)
                Text(
                  unsetHint ?? '\u672a\u8bbe\u7f6e',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                )
              else ...[
                Text(
                  '${formatMinor(currency, spentMinor, hide: hide)}'
                  ' / ${formatMinor(currency, limit, hide: hide)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: over ? scheme.error : null,
                      ),
                ),
                const SizedBox(height: CentliSpacing.item),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio > 1 ? 1 : ratio,
                    minHeight: 8,
                    color: barColor,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: CentliSpacing.item),
                Text(
                  over
                      ? '\u8d85\u652f ${formatMinor(currency, spentMinor - limit, hide: hide)}'
                      : '\u5269\u4f59 ${formatMinor(currency, remain!, hide: hide)}'
                          ' \u00b7 ${(ratio * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: over ? scheme.error : scheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (!hasLimit && spentMinor > 0) ...[
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '\u5df2\u82b1 ${formatMinor(currency, spentMinor, hide: hide)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _shiftMonth(String ym, int delta) {
  final parts = ym.split('-');
  final d = DateTime(int.parse(parts[0]), int.parse(parts[1]) + delta, 1);
  return budgetYearMonth(d);
}

Future<void> _showAmountEditor(
  BuildContext context,
  WidgetRef ref, {
  required String ledgerId,
  required String yearMonth,
  required String categoryId,
  required String baseCurrency,
  required int? initialMinor,
  required String title,
}) async {
  final initialMajor = initialMinor == null
      ? ''
      : fromMinor(baseCurrency, initialMinor).toString();
  final ctrl = TextEditingController(text: initialMajor);
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) {
      return CentliGlassDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            labelText: '\u989d\u5ea6\uff08$baseCurrency\uff09',
            border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
            helperText: '\u7559\u7a7a\u5e76\u4fdd\u5b58\u7b49\u4e8e\u6e05\u9664\u8be5\u9884\u7b97',
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
  final raw = ctrl.text.trim();
  ctrl.dispose();
  if (ok != true) return;

  final db = ref.read(databaseProvider);
  if (raw.isEmpty) {
    await db.deleteBudgetByKey(
      ledgerId: ledgerId,
      yearMonth: yearMonth,
      categoryId: categoryId,
    );
    return;
  }
  final major = double.tryParse(raw);
  if (major == null || major < 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u8f93\u5165\u6709\u6548\u91d1\u989d')),
      );
    }
    return;
  }
  final minor = toMinor(baseCurrency, major);
  if (minor <= 0) {
    await db.deleteBudgetByKey(
      ledgerId: ledgerId,
      yearMonth: yearMonth,
      categoryId: categoryId,
    );
    return;
  }
  await db.upsertBudget(
    ledgerId: ledgerId,
    yearMonth: yearMonth,
    categoryId: categoryId,
    amountMinor: minor,
  );
}

Future<void> _showCategoryBudgetEditor(
  BuildContext context,
  WidgetRef ref, {
  required String ledgerId,
  required String yearMonth,
  required String baseCurrency,
}) async {
  final cats =
      await ref.read(databaseProvider).loadCategories(ledgerId, 'out');
  final existing = await ref
      .read(databaseProvider)
      .watchBudgetsForMonth(ledgerId, yearMonth)
      .first;
  final taken = {
    for (final b in existing)
      if (b.categoryId.isNotEmpty) b.categoryId,
  };
  final available = cats.where((c) => !taken.contains(c.id)).toList();
  if (available.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u6240\u6709\u652f\u51fa\u5206\u7c7b\u5df2\u8bbe\u9884\u7b97\uff0c\u6216\u6682\u65e0\u5206\u7c7b'),
        ),
      );
    }
    return;
  }

  String? selected = available.first.id;
  final ctrl = TextEditingController();
  if (!context.mounted) {
    ctrl.dispose();
    return;
  }
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return CentliGlassDialog(
            title: const Text('\u5206\u7c7b\u9884\u7b97'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  items: [
                    for (final c in available)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => selected = v);
                  },
                  decoration: const InputDecoration(
                    labelText: '\u5206\u7c7b',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: '\u989d\u5ea6\uff08$baseCurrency\uff09',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  ),
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
                child: const Text('\u4fdd\u5b58'),
              ),
            ],
          );
        },
      );
    },
  );
  final raw = ctrl.text.trim();
  ctrl.dispose();
  if (ok != true || selected == null) return;
  final major = double.tryParse(raw);
  if (major == null || major <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u8f93\u5165\u5927\u4e8e 0 \u7684\u91d1\u989d')),
      );
    }
    return;
  }
  await ref.read(databaseProvider).upsertBudget(
        ledgerId: ledgerId,
        yearMonth: yearMonth,
        categoryId: selected!,
        amountMinor: toMinor(baseCurrency, major),
      );
}

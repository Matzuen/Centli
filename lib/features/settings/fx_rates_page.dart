import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/currencies.dart';
import '../../core/utils/fx.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../data/fx/fx_remote_service.dart';
import '../../app/theme.dart';

final _fxRatesProvider = StreamProvider<List<FxRate>>((ref) {
  return ref.watch(databaseProvider).watchFxRates();
});

/// FX cache editor (P2) + remote daily refresh (P3).
class FxRatesPage extends ConsumerStatefulWidget {
  const FxRatesPage({super.key});

  @override
  ConsumerState<FxRatesPage> createState() => _FxRatesPageState();
}

class _FxRatesPageState extends ConsumerState<FxRatesPage> {
  bool _refreshing = false;
  String? _statusHint;
  bool _autoKickDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoKickDone) return;
    _autoKickDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoRefreshIfNeeded());
  }

  Future<void> _autoRefreshIfNeeded() async {
    final ledger = ref.read(currentLedgerProvider).valueOrNull;
    final base = ledger?.baseCurrency ?? 'CNY';
    final db = ref.read(databaseProvider);
    setState(() => _refreshing = true);
    try {
      final result = await FxRemoteService().maybeAutoRefresh(
        db: db,
        baseCurrency: base,
      );
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _statusHint =
              '已自动刷新 ${result.upserted} 条（${result.day} · ${result.source}）';
        });
      } else {
        final last = await db.getSetting(FxRemoteService.lastDayKey);
        if (!mounted) return;
        setState(() {
          _statusHint = last == null || last.isEmpty
              ? '尚未远程刷新，可点云图标拉取'
              : '今日已刷新（$last）；可点云图标强制更新';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusHint = '自动刷新失败：$e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _forceRefresh() async {
    final ledger = ref.read(currentLedgerProvider).valueOrNull;
    final base = ledger?.baseCurrency ?? 'CNY';
    setState(() {
      _refreshing = true;
      _statusHint = '正在拉取远程汇率…';
    });
    try {
      final result = await FxRemoteService().refreshToBase(
        db: ref.read(databaseProvider),
        baseCurrency: base,
      );
      if (!mounted) return;
      final skip = result.skipped.isEmpty
          ? ''
          : '；跳过 ${result.skipped.join(", ")}';
      setState(() {
        _statusHint =
            '已写入 ${result.upserted} 条 ${result.day}（→${result.baseCurrency}）'
            '$skip';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('远程汇率已更新（${result.source}）')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusHint = '刷新失败：$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _toggleAuto(bool enabled) async {
    await ref.read(databaseProvider).setSetting(
          FxRemoteService.autoKey,
          enabled ? 'true' : 'false',
        );
    if (!mounted) return;
    setState(() {
      _statusHint = enabled ? '已开启每日自动刷新' : '已关闭自动刷新（仍可手动拉取）';
    });
  }

  @override
  Widget build(BuildContext context) {
    final ratesAsync = ref.watch(_fxRatesProvider);
    final ledger = ref.watch(currentLedgerProvider).valueOrNull;
    final base = ledger?.baseCurrency ?? 'CNY';
    final autoAsync = ref.watch(_fxAutoEnabledProvider);

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('汇率'),
        actions: [
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '远程刷新',
              onPressed: _forceRefresh,
              icon: const Icon(Icons.cloud_download_outlined),
            ),
          IconButton(
            tooltip: '添加汇率',
            onPressed: () => _showEditor(context, ref, baseCurrency: base),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: CentliSpacing.pagePadding,
        children: [
          Text(
            '用于首页/统计/资产净额折算为本位币（现为 $base）。'
            '语义：1 原币 = rate 目标币。'
            '无匹配汇率时标「未折算」。'
            '远程源：${FxRemoteService.sourceId}（日频，外币→本位币）。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: CentliSpacing.item),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启动时自动刷新'),
            subtitle: const Text('每日最多一次；失败不影响手工缓存'),
            value: autoAsync.valueOrNull ?? true,
            onChanged: _refreshing ? null : _toggleAuto,
          ),
          if (_statusHint != null) ...[
            const SizedBox(height: CentliSpacing.dense),
            Text(
              _statusHint!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
          const SizedBox(height: CentliSpacing.section),
          ratesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e'),
            data: (rows) {
              if (rows.isEmpty) {
                return CentliSoftCard(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.currency_exchange,
                            size: 40,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: CentliSpacing.item),
                        const Text('暂无汇率'),
                        const SizedBox(height: CentliSpacing.dense),
                        Text(
                          '点云图标远程拉取，或右上角 + 手工添加',
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return CentliSoftCard(
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        title: Text(
                          '1 ${rows[i].fromCcy} = ${rows[i].rate} ${rows[i].toCcy}',
                        ),
                        subtitle: Text(
                          '${rows[i].day}'
                          '${rows[i].source == null || rows[i].source!.isEmpty ? '' : ' · ${rows[i].source}'}',
                        ),
                        trailing: IconButton(
                          tooltip: '删除汇率',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await ref.read(databaseProvider).deleteFxRate(
                                  day: rows[i].day,
                                  fromCcy: rows[i].fromCcy,
                                  toCcy: rows[i].toCcy,
                                );
                          },
                        ),
                        onTap: () => _showEditor(
                          context,
                          ref,
                          baseCurrency: base,
                          existing: rows[i],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

final _fxAutoEnabledProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchSetting(FxRemoteService.autoKey).map((v) => v != 'false');
});

Future<void> _showEditor(
  BuildContext context,
  WidgetRef ref, {
  required String baseCurrency,
  FxRate? existing,
}) async {
  final dayCtrl = TextEditingController(
    text: existing?.day ?? FxBook.todayLocal(),
  );
  var from = existing?.fromCcy ??
      (supportedCurrencies.contains('USD') ? 'USD' : supportedCurrencies.first);
  var to = existing?.toCcy ?? baseCurrency;
  if (from == to) {
    to = supportedCurrencies.firstWhere((c) => c != from, orElse: () => baseCurrency);
  }
  final rateCtrl = TextEditingController(
    text: existing == null ? '' : existing.rate.toString(),
  );
  final sourceCtrl = TextEditingController(text: existing?.source ?? 'manual');

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(existing == null ? '添加汇率' : '编辑汇率'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: dayCtrl,
                    decoration: const InputDecoration(
                      labelText: '日期 yyyy-MM-dd',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: from,
                          items: [
                            for (final c in supportedCurrencies)
                              DropdownMenuItem(value: c, child: Text(currencyLabel(c))),
                          ],
                          onChanged: (v) {
                            if (v != null) setLocal(() => from = v);
                          },
                          decoration: const InputDecoration(
                            labelText: '原币',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: to,
                          items: [
                            for (final c in supportedCurrencies)
                              DropdownMenuItem(value: c, child: Text(currencyLabel(c))),
                          ],
                          onChanged: (v) {
                            if (v != null) setLocal(() => to = v);
                          },
                          decoration: const InputDecoration(
                            labelText: '目标币',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextField(
                    controller: rateCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '汇率（1 原币 = ? 目标币）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextField(
                    controller: sourceCtrl,
                    decoration: const InputDecoration(
                      labelText: '来源（可选）',
                      border: OutlineInputBorder(),
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

  final day = dayCtrl.text.trim();
  final rateText = rateCtrl.text.trim();
  final source = sourceCtrl.text.trim();
  dayCtrl.dispose();
  rateCtrl.dispose();
  sourceCtrl.dispose();

  if (saved != true) return;

  final rate = double.tryParse(rateText);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
      rate == null ||
      rate <= 0 ||
      from == to) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请检查日期、币种与汇率'),
        ),
      );
    }
    return;
  }

  // If editing changed the PK, delete the old row first.
  if (existing != null &&
      (existing.day != day ||
          existing.fromCcy != from ||
          existing.toCcy != to)) {
    await ref.read(databaseProvider).deleteFxRate(
          day: existing.day,
          fromCcy: existing.fromCcy,
          toCcy: existing.toCcy,
        );
  }

  await ref.read(databaseProvider).upsertFxRate(
        day: day,
        fromCcy: from,
        toCcy: to,
        rate: rate,
        source: source.isEmpty ? null : source,
      );
}

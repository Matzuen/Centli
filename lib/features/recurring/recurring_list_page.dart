import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../../core/widgets/glass.dart';

final _recurringRulesProvider =
    StreamProvider.autoDispose<List<RecurringRule>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.recurringRules)
        ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
      .watch();
});

class RecurringListPage extends ConsumerWidget {
  const RecurringListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_recurringRulesProvider);
    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('周期记账'),
        actions: [
          IconButton(
            tooltip: '新建',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/me/recurring/new'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (rules) {
          final active = rules.where((r) => r.enabled == 1).toList();
          final paused = rules.where((r) => r.enabled == 0).toList();
          final truncated = rules.fold<int>(0, (a, r) => a + r.skippedCount);
          if (rules.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '还没有周期记账',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  FilledButton.icon(
                    onPressed: () => context.push('/me/recurring/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('新建周期'),
                  ),
                ],
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(CentliSpacing.cardPad),
            children: [
              if (truncated > 0)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '有 $truncated 期未自动生成，请手动补记',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              if (active.isNotEmpty) ...[
                Text('进行中', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: CentliSpacing.item),
                ...active.map((r) => _RuleTile(rule: r)),
                const SizedBox(height: CentliSpacing.sectionLoose),
              ],
              if (paused.isNotEmpty) ...[
                Text('已暂停', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: CentliSpacing.item),
                ...paused.map((r) => _RuleTile(rule: r)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RuleTile extends ConsumerWidget {
  const _RuleTile({required this.rule});
  final RecurringRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    final next = DateTime.fromMillisecondsSinceEpoch(rule.nextRunAt);
    final nextLabel = rule.enabled == 1
        ? '下次执行：${DateFormat('yyyy-MM-dd').format(next)}'
        : '已暂停';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(
          '${formatMinor(rule.currency, rule.amountMinor)} · ${rule.type == 'in' ? '收入' : '支出'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            if (rule.note != null && rule.note!.trim().isNotEmpty) rule.note!,
            nextLabel,
          ].join('\n'),
        ),
        isThreeLine: true,
        trailing: Switch(
          value: rule.enabled == 1,
          onChanged: (v) async {
            final ts = DateTime.now().millisecondsSinceEpoch;
            await (db.update(db.recurringRules)
                  ..where((t) => t.id.equals(rule.id)))
                .write(
              RecurringRulesCompanion(
                enabled: Value(v ? 1 : 0),
                updatedAt: Value(ts),
              ),
            );
          },
        ),
        onLongPress: () async {
          final ok = await showGlassDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('删除周期规则？'),
              content: const Text('已生成的流水不受影响。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除'),
                ),
              ],
            ),
          );
          if (ok == true) {
            await (db.delete(db.recurringRules)
                  ..where((t) => t.id.equals(rule.id)))
                .go();
          }
        },
        onTap: () async {
          await showGlassSheet<void>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(
                      rule.enabled == 1 ? Icons.pause : Icons.play_arrow,
                    ),
                    title: Text(rule.enabled == 1 ? '暂停' : '启用'),
                    onTap: () async {
                      final ts = DateTime.now().millisecondsSinceEpoch;
                      await (db.update(db.recurringRules)
                            ..where((t) => t.id.equals(rule.id)))
                          .write(
                        RecurringRulesCompanion(
                          enabled: Value(rule.enabled == 1 ? 0 : 1),
                          updatedAt: Value(ts),
                        ),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('删除'),
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await showGlassDialog<bool>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text('删除周期规则？'),
                          content: const Text('已生成的流水不受影响。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dCtx, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await (db.delete(db.recurringRules)
                              ..where((t) => t.id.equals(rule.id)))
                            .go();
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

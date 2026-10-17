import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../recurring/recurring_wizard_page.dart';

final _subsProvider = StreamProvider.autoDispose<List<Subscription>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.subscriptions)
        ..orderBy([(t) => OrderingTerm.asc(t.nextDueAt)]))
      .watch();
});

class SubscriptionListPage extends ConsumerWidget {
  const SubscriptionListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_subsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('订阅'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/me/subscriptions/edit'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (subs) {
          final now = DateTime.now();
          final in7 = now.add(const Duration(days: 7));
          final active = subs.where((s) => s.status == 'active').length;
          final trial = subs.where((s) => s.status == 'trial').length;
          final cancelled = subs.where((s) => s.status == 'cancelled').length;
          final dueSoon = subs.where((s) {
            if (s.nextDueAt == null) return false;
            if ({'owned', 'free', 'lifetime', 'cancelled'}.contains(s.status)) {
              return false;
            }
            if (s.periodKind == 'lifetime') return false;
            final d = DateTime.fromMillisecondsSinceEpoch(s.nextDueAt!);
            return !d.isAfter(in7) && !d.isBefore(DateTime(now.year, now.month, now.day));
          }).length;
          final spend = subs
              .where((s) => s.status == 'active' || s.status == 'trial')
              .fold<int>(0, (a, s) => a + s.priceMinor);

          if (subs.isEmpty) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => context.push('/me/subscriptions/edit'),
                icon: const Icon(Icons.add),
                label: const Text('添加订阅'),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '花费合计 ${formatMinor('CNY', spend)} · 订阅中 $active · 试用 $trial · 已取消 $cancelled · 7天内到期 $dueSoon',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...subs.map((s) {
                final due = s.nextDueAt == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(s.nextDueAt!);
                final soon = due != null &&
                    !due.isAfter(in7) &&
                    s.status != 'cancelled' &&
                    s.periodKind != 'lifetime';
                return Card(
                  child: ListTile(
                    title: Text(s.name),
                    subtitle: Text(
                      '${formatMinor(s.currency, s.priceMinor)} / ${_periodLabel(s.periodKind)}'
                      '${due == null ? '' : '\n下次到期 ${DateFormat('yyyy-MM-dd').format(due)}'}',
                    ),
                    isThreeLine: due != null,
                    trailing: soon
                        ? Chip(
                            label: const Text('即将到期'),
                            backgroundColor:
                                Theme.of(context).colorScheme.errorContainer,
                          )
                        : Text(_statusLabel(s.status)),
                    onTap: () => context.push('/me/subscriptions/edit', extra: s),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

String _periodLabel(String k) => switch (k) {
      'week' => '周',
      'month' => '月',
      'quarter' => '季',
      'year' => '年',
      'lifetime' => '终身',
      _ => k,
    };

String _statusLabel(String s) => switch (s) {
      'active' => '订阅中',
      'trial' => '试用',
      'cancelled' => '已取消',
      'owned' => '买断',
      'free' => '免费',
      _ => s,
    };

class SubscriptionEditPage extends ConsumerStatefulWidget {
  const SubscriptionEditPage({super.key, this.existing});
  final Subscription? existing;

  @override
  ConsumerState<SubscriptionEditPage> createState() =>
      _SubscriptionEditPageState();
}

class _SubscriptionEditPageState extends ConsumerState<SubscriptionEditPage> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  String _period = 'month';
  String _status = 'active';
  int _remind = 3;
  DateTime _started = DateTime.now();
  DateTime? _nextDue = DateTime.now().add(const Duration(days: 30));
  String? _ledgerId;
  bool _loading = true;

  bool get _hideDue =>
      _period == 'lifetime' ||
      _status == 'owned' ||
      _status == 'free';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _name.text = e.name;
      _price.text = fromMinor(e.currency, e.priceMinor).toStringAsFixed(2);
      _note.text = e.note ?? '';
      _period = e.periodKind;
      _status = e.status;
      _remind = e.remindDaysBefore;
      _started = DateTime.fromMillisecondsSinceEpoch(e.startedAt);
      _nextDue = e.nextDueAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(e.nextDueAt!);
    }
    _boot();
  }

  Future<void> _boot() async {
    final db = ref.read(databaseProvider);
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingleOrNull();
    setState(() {
      _ledgerId = ledger?.id;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写名称')));
      return;
    }
    final major = double.tryParse(_price.text.trim()) ?? -1;
    if (_status != 'free' && major <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写价格')));
      return;
    }
    if (_remind < 0 || _remind > 90) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('提醒天数 0–90')));
      return;
    }
    if (_ledgerId == null) return;
    final db = ref.read(databaseProvider);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final price = toMinor('CNY', major < 0 ? 0 : major);
    final dueMs = _hideDue ? null : _nextDue?.millisecondsSinceEpoch;
    if (widget.existing == null) {
      await db.into(db.subscriptions).insert(
            SubscriptionsCompanion.insert(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              ledgerId: _ledgerId!,
              name: name,
              priceMinor: price,
              currency: 'CNY',
              periodKind: _period,
              status: _status,
              startedAt: _started.millisecondsSinceEpoch,
              nextDueAt: Value(dueMs),
              remindDaysBefore: Value(_remind),
              note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
              createdAt: ts,
              updatedAt: ts,
            ),
          );
    } else {
      await (db.update(db.subscriptions)
            ..where((t) => t.id.equals(widget.existing!.id)))
          .write(
        SubscriptionsCompanion(
          name: Value(name),
          priceMinor: Value(price),
          periodKind: Value(_period),
          status: Value(_status),
          startedAt: Value(_started.millisecondsSinceEpoch),
          nextDueAt: Value(dueMs),
          remindDaysBefore: Value(_remind),
          note: Value(_note.text.trim().isEmpty ? null : _note.text.trim()),
          updatedAt: Value(ts),
        ),
      );
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新建订阅' : '编辑订阅'),
        actions: [
          if (widget.existing != null)
            TextButton(
              onPressed: () {
                context.push(
                  '/me/recurring/new',
                  extra: RecurringWizardArgs(
                    amountMinor: widget.existing!.priceMinor,
                    currency: widget.existing!.currency,
                    periodKind: widget.existing!.periodKind == 'lifetime'
                        ? 'month'
                        : widget.existing!.periodKind,
                    note: widget.existing!.name,
                  ),
                );
              },
              child: const Text('周期记账'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: '价格 (CNY)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _period,
            decoration: const InputDecoration(
              labelText: '周期',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'week', child: Text('周')),
              DropdownMenuItem(value: 'month', child: Text('月')),
              DropdownMenuItem(value: 'quarter', child: Text('季')),
              DropdownMenuItem(value: 'year', child: Text('年')),
              DropdownMenuItem(value: 'lifetime', child: Text('终身')),
            ],
            onChanged: (v) => setState(() {
              _period = v ?? 'month';
              if (_hideDue) _nextDue = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: '状态',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'active', child: Text('订阅中')),
              DropdownMenuItem(value: 'trial', child: Text('试用')),
              DropdownMenuItem(value: 'cancelled', child: Text('已取消')),
              DropdownMenuItem(value: 'owned', child: Text('买断')),
              DropdownMenuItem(value: 'free', child: Text('免费')),
            ],
            onChanged: (v) => setState(() {
              _status = v ?? 'active';
              if (_hideDue) _nextDue = null;
            }),
          ),
          if (!_hideDue) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('下次到期'),
              subtitle: Text(
                _nextDue == null
                    ? '未设置'
                    : DateFormat('yyyy-MM-dd').format(_nextDue!),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _nextDue ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (d != null) setState(() => _nextDue = d);
              },
            ),
            Row(
              children: [
                const Text('提前提醒(天)'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: '$_remind',
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _remind = int.tryParse(v) ?? 3,
                    decoration:
                        const InputDecoration(border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: '备注',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 24),
            Text(
              '想自动记入账本？创建一个周期记账',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                context.push(
                  '/me/recurring/new',
                  extra: RecurringWizardArgs(
                    amountMinor: widget.existing!.priceMinor,
                    currency: widget.existing!.currency,
                    periodKind: widget.existing!.periodKind == 'lifetime'
                        ? 'month'
                        : widget.existing!.periodKind,
                    note: widget.existing!.name,
                  ),
                );
              },
              child: const Text('创建周期记账'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _save, child: const Text('保存')),
        ),
      ),
    );
  }
}

/// In-app due tip helper (no txn write).
List<Subscription> subscriptionsDueSoon(
  List<Subscription> subs, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  return subs.where((s) {
    if (s.nextDueAt == null) return false;
    if ({'cancelled', 'owned', 'free'}.contains(s.status)) return false;
    if (s.periodKind == 'lifetime') return false;
    final due = DateTime.fromMillisecondsSinceEpoch(s.nextDueAt!);
    final dueDay = DateTime(due.year, due.month, due.day);
    final remindFrom = dueDay.subtract(Duration(days: s.remindDaysBefore));
    return !today.isBefore(remindFrom) && !today.isAfter(dueDay);
  }).toList();
}

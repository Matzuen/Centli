import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'txn_list_tile.dart';

/// Local calendar day label: 今天 / 昨天 / M月d日 / yyyy年M月d日.
String txnDateGroupLabel(DateTime localTime, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(localTime.year, localTime.month, localTime.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '\u4eca\u5929';
  if (diff == 1) return '\u6628\u5929';
  if (day.year == today.year) {
    return '${day.month}\u6708${day.day}\u65e5';
  }
  return '${day.year}\u5e74${day.month}\u6708${day.day}\u65e5';
}

DateTime txnLocalDay(Transaction txn) {
  final t = DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true)
      .toLocal();
  return DateTime(t.year, t.month, t.day);
}

/// Group transactions by local calendar day (preserves input order within day).
List<({String label, List<Transaction> items})> groupTransactionsByDate(
  List<Transaction> txns, {
  DateTime? now,
}) {
  final groups = <DateTime, List<Transaction>>{};
  final order = <DateTime>[];
  for (final t in txns) {
    final day = txnLocalDay(t);
    if (!groups.containsKey(day)) {
      groups[day] = [];
      order.add(day);
    }
    groups[day]!.add(t);
  }
  order.sort((a, b) => b.compareTo(a));
  return [
    for (final day in order)
      (
        label: txnDateGroupLabel(day, now: now),
        items: groups[day]!,
      ),
  ];
}

final _txnListLookupsProvider =
    FutureProvider.family<TxnListLookups, String>((ref, ledgerId) {
  return ref.watch(databaseProvider).loadTxnListLookups(ledgerId);
});

/// Date-grouped transaction list body (white card, bold date headers).
class TxnGroupedList extends ConsumerWidget {
  const TxnGroupedList({
    super.key,
    required this.txns,
    required this.hide,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
    this.physics,
    this.highlight = const [],
  });

  final List<Transaction> txns;
  final bool hide;

  /// Keywords to mark in each row (search results).
  final List<String> highlight;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerId = txns.isEmpty ? null : txns.first.ledgerId;
    final lookupsAsync = ledgerId == null
        ? const AsyncValue.data(TxnListLookups.empty)
        : ref.watch(_txnListLookupsProvider(ledgerId));
    final lookups = lookupsAsync.valueOrNull ?? TxnListLookups.empty;
    final groups = groupTransactionsByDate(txns);
    return ListView.builder(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: groups.length,
      itemBuilder: (context, gi) {
        final g = groups[gi];
        return _TxnDateGroup(
          label: g.label,
          items: g.items,
          hide: hide,
          isFirst: gi == 0,
          lookups: lookups,
          highlight: highlight,
        );
      },
    );
  }
}

/// Non-scrolling column of date groups — embed inside a parent ListView.
class TxnGroupedSection extends ConsumerWidget {
  const TxnGroupedSection({
    super.key,
    required this.txns,
    required this.hide,
  });

  final List<Transaction> txns;
  final bool hide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerId = txns.isEmpty ? null : txns.first.ledgerId;
    final lookupsAsync = ledgerId == null
        ? const AsyncValue.data(TxnListLookups.empty)
        : ref.watch(_txnListLookupsProvider(ledgerId));
    final lookups = lookupsAsync.valueOrNull ?? TxnListLookups.empty;
    final groups = groupTransactionsByDate(txns);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++)
          _TxnDateGroup(
            label: groups[i].label,
            items: groups[i].items,
            hide: hide,
            isFirst: i == 0,
            lookups: lookups,
          ),
      ],
    );
  }
}

class _TxnDateGroup extends StatelessWidget {
  const _TxnDateGroup({
    required this.label,
    required this.items,
    required this.hide,
    required this.isFirst,
    required this.lookups,
    this.highlight = const [],
  });

  final String label;
  final List<Transaction> items;
  final bool hide;
  final bool isFirst;
  final TxnListLookups lookups;
  final List<String> highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, isFirst ? 8 : 18, 16, 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
              height: 1.2,
            ),
          ),
        ),
        Material(
          color: scheme.surface,
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++)
                TxnListTile(
                  txn: items[i],
                  hide: hide,
                  showSeparator: i > 0,
                  lookups: lookups,
                  highlight: highlight,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

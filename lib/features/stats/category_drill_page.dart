import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/txn_list_tile.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';

/// Filtered bill list for one category within a stats date range.
class CategoryDrillPage extends ConsumerWidget {
  const CategoryDrillPage({
    super.key,
    required this.ledgerId,
    required this.categoryId,
    required this.categoryName,
    required this.kind,
    required this.startMs,
    required this.endMs,
    required this.rangeLabel,
  });

  final String ledgerId;
  final String categoryId;
  final String categoryName;
  final String kind;
  final int startMs;
  final int endMs;
  final String rangeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(hideAmountProvider).valueOrNull ?? false;
    final stream = ref.watch(databaseProvider).watchCategoryTransactionsInRange(
          ledgerId,
          startMs,
          endMs,
          kind: kind,
          categoryId: categoryId,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              rangeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Transaction>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: Text(
                '\u6682\u65e0\u8d26\u5355',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              return TxnListTile(txn: items[i], hide: hide);
            },
          );
        },
      ),
    );
  }
}

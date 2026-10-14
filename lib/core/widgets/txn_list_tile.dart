import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../utils/money.dart';
import '../utils/fx.dart';

/// Shared transaction row for home, account detail, stats drill-down, and search.
class TxnListTile extends ConsumerWidget {
  const TxnListTile({
    super.key,
    required this.txn,
    required this.hide,
  });

  final Transaction txn;
  final bool hide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = txn.type == 'out';
    final isTransfer = txn.type == 'transfer';
    final prefix = isTransfer ? '' : (isOut ? '-' : '+');
    final color = isTransfer
        ? Theme.of(context).colorScheme.onSurface
        : (isOut
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary);
    final time = DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true)
        .toLocal();
    final timeLabel = DateFormat('MM-dd HH:mm').format(time);
    final db = ref.read(databaseProvider);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          isTransfer
              ? Icons.swap_horiz
              : (isOut ? Icons.arrow_upward : Icons.arrow_downward),
          size: 18,
        ),
      ),
      title: FutureBuilder<String>(
        future: _titleLabel(db),
        builder: (context, snap) => Text(snap.data ?? '\u2026'),
      ),
      subtitle: FutureBuilder<String>(
        future: _accountSubtitle(db),
        builder: (context, snap) {
          final accountPart = snap.data;
          if (accountPart == null || accountPart.isEmpty) {
            return Text(timeLabel);
          }
          return Text('$timeLabel \u00b7 $accountPart');
        },
      ),
      trailing: Builder(
        builder: (context) {
          final ledger = ref.watch(currentLedgerProvider).valueOrNull;
          final book = ref.watch(fxBookProvider).valueOrNull;
          final base = ledger?.baseCurrency;
          var unconverted = false;
          if (base != null &&
              book != null &&
              txn.currency != base &&
              txn.type != 'transfer') {
            final day = FxBook.dayFromHappenAtMs(txn.happenAt);
            unconverted = book.rate(
                  fromCcy: txn.currency,
                  toCcy: base,
                  onDay: day,
                ) ==
                null;
          }
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$prefix${formatMinor(txn.currency, txn.amountMinor, hide: hide)}',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
              Text(
                unconverted
                    ? '${txn.currency} \u00b7 \u672a\u6298\u7b97'
                    : txn.currency,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: unconverted
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          );
        },
      ),
      onTap: () => context.push('/ledger/${txn.id}'),
    );
  }

  /// Category · note/merchant. Left: category, or 转账/未分类. Right: note else merchant.
  Future<String> _titleLabel(CentliDatabase db) async {
    String left = '';
    if (txn.categoryId != null && txn.categoryId!.isNotEmpty) {
      final cat = await db.getCategory(txn.categoryId!);
      left = (cat?.name ?? '').trim();
    }
    if (left.isEmpty) {
      left = txn.type == 'transfer' ? '转账' : '未分类';
    }

    final note = (txn.note ?? '').trim();
    final merchant = (txn.merchant ?? '').trim();
    final right = note.isNotEmpty ? note : merchant;

    if (right.isEmpty) return left;
    return '$left · $right';
  }

  /// Account name, or from→to for transfers when both resolve.
  Future<String> _accountSubtitle(CentliDatabase db) async {
    final from = await db.getAccount(txn.accountId);
    final fromName = (from?.name ?? '').trim();

    if (txn.type == 'transfer') {
      final toId = txn.toAccountId;
      if (toId != null && toId.isNotEmpty) {
        final to = await db.getAccount(toId);
        final toName = (to?.name ?? '').trim();
        if (fromName.isNotEmpty && toName.isNotEmpty) {
          return '$fromName \u2192 $toName';
        }
        if (toName.isNotEmpty) return toName;
      }
    }

    if (fromName.isNotEmpty) return fromName;
    return txn.currency;
  }
}

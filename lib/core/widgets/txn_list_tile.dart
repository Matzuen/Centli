import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../constants/currencies.dart';
import '../utils/fx.dart';
import '../utils/money.dart';
import 'category_visuals.dart';

/// Expense / income accent colors (reference screenshot).
const Color kTxnExpenseRed = Color(0xFFE53935);
const Color kTxnIncomeGreen = Color(0xFF43A047);

/// Shared transaction row: category icon · name / 账户·备注 · amount+time.
/// Used by home, search, stats drill-down (and mirrored on account detail).
class TxnListTile extends ConsumerWidget {
  const TxnListTile({
    super.key,
    required this.txn,
    required this.hide,
    this.showSeparator = false,
  });

  final Transaction txn;
  final bool hide;

  /// Light divider above this row (indented past the icon).
  final bool showSeparator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = txn.type == 'out';
    final isTransfer = txn.type == 'transfer';
    final amountColor = isTransfer
        ? Theme.of(context).colorScheme.onSurface
        : (isOut ? kTxnExpenseRed : kTxnIncomeGreen);
    final time = DateTime.fromMillisecondsSinceEpoch(txn.happenAt, isUtc: true)
        .toLocal();
    final timeLabel = DateFormat('HH:mm').format(time);
    final db = ref.read(databaseProvider);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSeparator)
          const Divider(
            height: 1,
            thickness: 0.5,
            indent: 72,
            endIndent: 16,
            color: Color(0xFFEEEEEE),
          ),
        InkWell(
          onTap: () => context.push('/ledger/${txn.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FutureBuilder<_CatMeta>(
                  future: _catMeta(db),
                  builder: (context, snap) {
                    final meta = snap.data;
                    return CategoryCircleIcon(
                      name: meta?.name ?? '',
                      kind: isTransfer ? 'transfer' : txn.type,
                      iconKey: meta?.icon,
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String>(
                        future: _categoryTitle(db),
                        builder: (context, snap) => Text(
                          snap.data ?? '\u2026',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                                color: scheme.onSurface,
                              ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FutureBuilder<String>(
                        future: _subtitle(db),
                        builder: (context, snap) {
                          final text = snap.data ?? '';
                          if (text.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  height: 1.2,
                                ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Builder(
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _amountLabel(),
                          style: TextStyle(
                            color: amountColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          unconverted ? '$timeLabel \u00b7 \u672a\u6298\u7b97' : timeLabel,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: unconverted ? scheme.error : muted,
                                height: 1.2,
                              ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _amountLabel() {
    if (hide) return '****';
    final symbol = currencySymbols[txn.currency] ?? txn.currency;
    final decimals = currencyDecimals[txn.currency] ?? 2;
    final major = fromMinor(txn.currency, txn.amountMinor);
    final numStr = decimals == 0
        ? '${major.round()}'
        : major.toStringAsFixed(decimals);
    // Reference: "¥ 20" with a space after the symbol.
    return '$symbol $numStr';
  }

  Future<_CatMeta> _catMeta(CentliDatabase db) async {
    if (txn.categoryId == null || txn.categoryId!.isEmpty) {
      return const _CatMeta(name: '', icon: null);
    }
    final cat = await db.getCategory(txn.categoryId!);
    return _CatMeta(name: (cat?.name ?? '').trim(), icon: cat?.icon);
  }

  /// Bold title: category only (转账 / 未分类 fallback).
  Future<String> _categoryTitle(CentliDatabase db) async {
    if (txn.type == 'transfer') return '\u8f6c\u8d26';
    if (txn.categoryId != null && txn.categoryId!.isNotEmpty) {
      final cat = await db.getCategory(txn.categoryId!);
      final name = (cat?.name ?? '').trim();
      if (name.isNotEmpty) return name;
    }
    return '\u672a\u5206\u7c7b';
  }

  /// Subtitle: 账户 · 备注/商家 (account always preferred visible).
  Future<String> _subtitle(CentliDatabase db) async {
    final accountPart = await _accountPart(db);
    final note = (txn.note ?? '').trim();
    final merchant = (txn.merchant ?? '').trim();
    final right = note.isNotEmpty ? note : merchant;

    if (accountPart.isEmpty && right.isEmpty) return txn.currency;
    if (accountPart.isEmpty) return right;
    if (right.isEmpty) return accountPart;
    return '$accountPart \u00b7 $right';
  }

  Future<String> _accountPart(CentliDatabase db) async {
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
    return fromName;
  }
}

class _CatMeta {
  const _CatMeta({required this.name, required this.icon});
  final String name;
  final String? icon;
}

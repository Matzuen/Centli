import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/db/centli_database.dart';
import '../../data/db/txn_tags.dart';
import '../../data/db/database_provider.dart';
import '../constants/currencies.dart';
import '../utils/fx.dart';
import '../utils/money.dart';
import '../../app/theme.dart';
import 'category_visuals.dart';

/// Highlight colour for search keywords on transaction rows.
const Color kKeywordHighlight = Color(0xFF7C4DFF);

/// Expense / income accent colors (reference screenshot).
const Color kTxnExpenseRed = Color(0xFFE53935);
const Color kTxnIncomeGreen = Color(0xFF43A047);

/// Shared transaction row: category icon · name / 账户·备注 · amount+time.
/// Used by home, search, stats drill-down (and mirrored on account detail).
///
/// Pass [lookups] from the list level so category/account names resolve
/// synchronously (avoids N+1 FutureBuilders per row).
class TxnListTile extends ConsumerWidget {
  const TxnListTile({
    super.key,
    required this.txn,
    required this.hide,
    this.showSeparator = false,
    this.lookups = TxnListLookups.empty,
    this.highlight = const [],
  });

  final Transaction txn;
  final bool hide;

  /// Light divider above this row (indented past the icon).
  final bool showSeparator;

  /// Preloaded category/account maps for this ledger.
  final TxnListLookups lookups;

  /// Search keywords to mark in the title / subtitle (empty = no highlight).
  final List<String> highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = txn.type == 'out';
    final isTransfer = txn.type == 'transfer';
    final isBalanceAdjust = (txn.note ?? '').trim() == '余额校正';
    final amountColor = isBalanceAdjust
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isTransfer
        ? Theme.of(context).colorScheme.onSurface
        : (isOut ? kTxnExpenseRed : kTxnIncomeGreen); // refund → income green
    final time = DateTime.fromMillisecondsSinceEpoch(
      txn.happenAt,
      isUtc: true,
    ).toLocal();
    final timeLabel = DateFormat('HH:mm').format(time);
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final cat = (txn.categoryId == null || txn.categoryId!.isEmpty)
        ? null
        : lookups.categoriesById[txn.categoryId!];
    final title = isBalanceAdjust ? '余额校正' : _categoryTitle(cat);
    final subtitle = isBalanceAdjust ? '不计入统计／预算' : _subtitle();

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
            padding: const EdgeInsets.all(CentliSpacing.cardPad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CategoryCircleIcon(
                  name: (cat?.name ?? '').trim(),
                  kind: isTransfer ? 'transfer' : txn.type,
                  iconKey: cat?.icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _HighlightedText(
                        text: title,
                        keywords: highlight,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                              color: scheme.onSurface,
                            ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: CentliSpacing.dense),
                        _HighlightedText(
                          text: subtitle,
                          keywords: highlight,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: muted, height: 1.2),
                        ),
                      ],
                      if (decodeTxnTags(txn.tags).isNotEmpty) ...[
                        const SizedBox(height: CentliSpacing.dense),
                        _TxnTagChips(tags: decodeTxnTags(txn.tags)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Builder(
                    builder: (context) {
                      final ledger = ref
                          .watch(currentLedgerProvider)
                          .valueOrNull;
                      final book = ref.watch(fxBookProvider).valueOrNull;
                      final base = ledger?.baseCurrency;
                      var unconverted = false;
                      if (base != null &&
                          book != null &&
                          txn.currency != base &&
                          txn.type != 'transfer') {
                        final day = FxBook.dayFromHappenAtMs(txn.happenAt);
                        unconverted =
                            book.rate(
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
                          // 大金额（¥1,234,567.89）在窄屏上必须能省略，
                          // 否则整行 Row 溢出。
                          Text(
                            _amountLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: amountColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: CentliSpacing.dense),
                          Text(
                            [
                              timeLabel,
                              if (unconverted) '\u672a\u6298\u7b97',
                              if (txn.includeInStat == 0) '\u4e0d\u8ba1\u5165',
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: unconverted ? scheme.error : muted,
                                  height: 1.2,
                                ),
                          ),
                        ],
                      );
                    },
                  ),
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
    return '$symbol $numStr';
  }

  String _categoryTitle(Category? cat) {
    if (txn.type == 'transfer') return '\u8f6c\u8d26';
    var base = '\u672a\u5206\u7c7b';
    final name = (cat?.name ?? '').trim();
    if (name.isNotEmpty) base = name;
    if (txn.type == 'refund') return '\u9000\u6b3e · $base';
    return base;
  }

  String _subtitle() {
    final accountPart = _accountPart();
    final note = (txn.note ?? '').trim();
    final right = note;

    if (accountPart.isEmpty && right.isEmpty) return txn.currency;
    if (accountPart.isEmpty) return right;
    if (right.isEmpty) return accountPart;
    return '$accountPart · $right';
  }

  String _accountPart() {
    final from = lookups.accountsById[txn.accountId];
    final fromName = (from?.name ?? '').trim();

    if (txn.type == 'transfer') {
      final toId = txn.toAccountId;
      if (toId != null && toId.isNotEmpty) {
        final to = lookups.accountsById[toId];
        final toName = (to?.name ?? '').trim();
        if (fromName.isNotEmpty && toName.isNotEmpty) {
          return '$fromName → $toName';
        }
        if (toName.isNotEmpty) return toName;
      }
    }
    return fromName;
  }
}

/// Text with search keywords marked (accent colour + semibold).
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({
    required this.text,
    required this.keywords,
    required this.style,
    this.maxLines,
  });

  final String text;
  final List<String> keywords;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final spans = highlightSpans(
      text,
      keywords,
      style: style,
      highlightColor: kKeywordHighlight,
    );
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// Split [text] into plain / highlighted spans for each [keywords] hit
/// (case-insensitive, longest keyword first, overlaps merged).
@visibleForTesting
List<TextSpan> highlightSpans(
  String text,
  List<String> keywords, {
  TextStyle? style,
  required Color highlightColor,
}) {
  final raw =
      [for (final k in keywords) k.trim()]
          .where((k) => k.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  if (raw.isEmpty || text.isEmpty) return [TextSpan(text: text, style: style)];

  final lower = text.toLowerCase();
  final marked = List<bool>.filled(text.length, false);
  for (final k in raw) {
    final kl = k.toLowerCase();
    var from = 0;
    while (from <= lower.length - kl.length) {
      final i = lower.indexOf(kl, from);
      if (i < 0) break;
      for (var j = i; j < i + kl.length; j++) {
        marked[j] = true;
      }
      from = i + kl.length;
    }
  }
  final hot = (style ?? const TextStyle()).copyWith(
    color: highlightColor,
    fontWeight: FontWeight.w800,
  );
  final out = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    final m = marked[i];
    var j = i + 1;
    while (j < text.length && marked[j] == m) {
      j++;
    }
    out.add(TextSpan(text: text.substring(i, j), style: m ? hot : style));
    i = j;
  }
  return out;
}

class _TxnTagChips extends StatelessWidget {
  const _TxnTagChips({required this.tags});
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = tags.take(2).toList();
    final extra = tags.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final t in shown)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              t,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (extra > 0)
          Text(
            '+$extra',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

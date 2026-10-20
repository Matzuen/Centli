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
import 'category_visuals.dart';

/// Highlight colour for search keywords on transaction rows.
const Color kKeywordHighlight = Color(0xFF7C4DFF);

/// Expense / income accent colors (reference screenshot).
const Color kTxnExpenseRed = Color(0xFFE53935);
const Color kTxnIncomeGreen = Color(0xFF43A047);

/// Shared transaction row: category icon · name / 资产账户·备注 · amount+time.
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
    final subtitle = isBalanceAdjust ? '不计入统计／预算' : _detailLine();

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
            // 金额列按内容宽度贴右，但最多占 55%：大字号/大金额时省略，
            // 而不是把整行撑破（flex: 0 会让它拿到无界宽度）。
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CategoryCircleIcon(
                    name: (cat?.name ?? '').trim(),
                    kind: isTransfer ? 'transfer' : txn.type,
                    iconKey: cat?.icon,
                    size: 40,
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
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.2,
                          ).copyWith(color: scheme.onSurface),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          _HighlightedText(
                            text: subtitle,
                            keywords: highlight,
                            maxLines: 1,
                            style: TextStyle(
                              color: muted,
                              fontSize: 12,
                              height: 1.25,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 金额只占自身宽度并贴行尾；上限 55% 宽度，
                  // 超出时省略，避免大字号/大金额把行撞破。
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.55,
                    ),
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
                            _AmountText(
                              symbol: hide
                                  ? ''
                                  : (currencySymbols[txn.currency] ??
                                        txn.currency),
                              number: hide ? '****' : _amountNumber(),
                              color: amountColor,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                timeLabel,
                                if (unconverted) '\u672a\u6298\u7b97',
                                if (txn.includeInStat == 0)
                                  '\u4e0d\u8ba1\u5165',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: unconverted ? scheme.error : muted,
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w400,
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
        ),
      ],
    );
  }

  String _amountNumber() {
    final decimals = currencyDecimals[txn.currency] ?? 2;
    final major = fromMinor(txn.currency, txn.amountMinor);
    if (decimals == 0) return '${major.round()}';
    return major.toStringAsFixed(decimals);
  }

  String _categoryTitle(Category? cat) {
    if (txn.type == 'transfer') return '\u8f6c\u8d26';
    var base = '\u672a\u5206\u7c7b';
    final name = (cat?.name ?? '').trim();
    if (name.isNotEmpty) base = name;
    if (txn.type == 'refund') return '\u9000\u6b3e · $base';
    return base;
  }

  /// 资产账户、备注、标签同一行，样式一致，用「 · 」隔开。
  String _detailLine() {
    final parts = <String>[
      _accountPart(),
      (txn.note ?? '').trim(),
      ...decodeTxnTags(txn.tags),
    ].where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return txn.currency;
    return parts.join(' · ');
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

/// 金额：13 号加粗，右对齐。
class _AmountText extends StatelessWidget {
  const _AmountText({
    required this.symbol,
    required this.number,
    required this.color,
  });

  final String symbol;
  final String number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 13,
      height: 1.2,
    );
    return Text.rich(
      TextSpan(
        style: base.copyWith(color: color),
        children: [
          if (symbol.isNotEmpty) TextSpan(text: symbol),
          TextSpan(text: symbol.isEmpty ? number : ' $number'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
    );
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

import '../constants/currencies.dart';

/// One cached FX quote. Semantics: 1 [fromCcy] = [rate] [toCcy].
class FxQuote {
  const FxQuote({
    required this.day,
    required this.fromCcy,
    required this.toCcy,
    required this.rate,
  });

  final String day; // yyyy-MM-dd (local calendar day)
  final String fromCcy;
  final String toCcy;
  final double rate;
}

/// In-memory FX book for convert-to-base (home / stats / net worth).
///
/// Lookup order for (from->to on day D):
/// 1. identity when currencies match
/// 2. exact day forward quote
/// 3. exact day inverse (1/rate)
/// 4. nearest prior day forward, then inverse
class FxBook {
  FxBook(List<FxQuote> quotes) : _byPair = {} {
    for (final q in quotes) {
      if (q.rate <= 0) continue;
      final key = _pairKey(q.fromCcy, q.toCcy);
      _byPair.putIfAbsent(key, () => <FxQuote>[]).add(q);
    }
    for (final list in _byPair.values) {
      list.sort((a, b) => a.day.compareTo(b.day));
    }
  }

  final Map<String, List<FxQuote>> _byPair;

  static String _pairKey(String from, String to) => '$from|$to';

  /// Local calendar day yyyy-MM-dd from a UTC epoch ms.
  static String dayFromHappenAtMs(int happenAtUtcMs) {
    final local =
        DateTime.fromMillisecondsSinceEpoch(happenAtUtcMs, isUtc: true)
            .toLocal();
    return formatDay(local);
  }

  static String formatDay(DateTime local) {
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String todayLocal([DateTime? now]) => formatDay(now ?? DateTime.now());

  /// 1 [fromCcy] = returned [toCcy], or null if unknown.
  double? rate({
    required String fromCcy,
    required String toCcy,
    required String onDay,
  }) {
    if (fromCcy == toCcy) return 1.0;
    final forward = _rateOnOrBefore(fromCcy, toCcy, onDay);
    if (forward != null) return forward;
    final inverse = _rateOnOrBefore(toCcy, fromCcy, onDay);
    if (inverse != null && inverse > 0) return 1.0 / inverse;
    return null;
  }

  double? _rateOnOrBefore(String from, String to, String onDay) {
    final list = _byPair[_pairKey(from, to)];
    if (list == null || list.isEmpty) return null;
    FxQuote? best;
    for (final q in list) {
      if (q.day.compareTo(onDay) <= 0) {
        best = q;
      } else {
        break;
      }
    }
    return best?.rate;
  }

  /// Convert [amountMinor] in [fromCcy] to [toCcy] minor units.
  /// Returns null when no usable rate exists.
  int? convertMinor({
    required String fromCcy,
    required String toCcy,
    required int amountMinor,
    required String onDay,
  }) {
    final r = rate(fromCcy: fromCcy, toCcy: toCcy, onDay: onDay);
    if (r == null) return null;
    return applyRate(
      fromCcy: fromCcy,
      toCcy: toCcy,
      amountMinor: amountMinor,
      rate: r,
    );
  }

  /// Apply a known rate (1 from = rate to), respecting minor-unit decimals.
  static int applyRate({
    required String fromCcy,
    required String toCcy,
    required int amountMinor,
    required double rate,
  }) {
    final fromDec = currencyDecimals[fromCcy] ?? 2;
    final toDec = currencyDecimals[toCcy] ?? 2;
    final fromFactor = _pow10(fromDec);
    final toFactor = _pow10(toDec);
    final major = amountMinor / fromFactor;
    return (major * rate * toFactor).round();
  }

  static int _pow10(int n) {
    var r = 1;
    for (var i = 0; i < n; i++) {
      r *= 10;
    }
    return r;
  }
}

/// Range income/expense already in base minor units, plus leftovers.
class BaseRangeSummary {
  const BaseRangeSummary({
    required this.incomeMinor,
    required this.expenseMinor,
    required this.unconverted,
    required this.convertedCount,
    required this.unconvertedCount,
  });

  final int incomeMinor;
  final int expenseMinor;

  /// Original-currency totals that could not be converted.
  final Map<String, ({int income, int expense})> unconverted;
  final int convertedCount;
  final int unconvertedCount;

  bool get hasUnconverted => unconverted.isNotEmpty;
}

/// Net worth in base minor units (active accounts only).
class BaseNetWorth {
  const BaseNetWorth({
    required this.totalMinor,
    required this.unconvertedByCcy,
    required this.convertedAccountCount,
    required this.unconvertedAccountCount,
  });

  final int totalMinor;
  final Map<String, int> unconvertedByCcy;
  final int convertedAccountCount;
  final int unconvertedAccountCount;

  bool get hasUnconverted => unconvertedByCcy.isNotEmpty;
}


/// Asset / liability totals in base minor units (active accounts).
///
/// Same FX rules as [BaseNetWorth]: unconverted accounts are excluded from
/// the sums and listed in [unconvertedByCcy] (original-currency minor).
class BaseAssetLiability {
  const BaseAssetLiability({
    required this.assetMinor,
    required this.liabilityMinor,
    required this.unconvertedByCcy,
  });

  final int assetMinor;
  final int liabilityMinor;

  /// Original-currency balances that could not be converted.
  final Map<String, int> unconvertedByCcy;

  bool get hasUnconverted => unconvertedByCcy.isNotEmpty;
}

/// Convert each account balance to [baseCurrency] and split by sign.
BaseAssetLiability assetLiabilityInBase({
  required Iterable<({String currency, int balanceMinor})> accounts,
  required FxBook book,
  required String baseCurrency,
  required String onDay,
}) {
  var asset = 0;
  var liability = 0;
  final leftover = <String, int>{};
  for (final a in accounts) {
    final asBase = book.convertMinor(
      fromCcy: a.currency,
      toCcy: baseCurrency,
      amountMinor: a.balanceMinor,
      onDay: onDay,
    );
    if (asBase == null) {
      leftover[a.currency] = (leftover[a.currency] ?? 0) + a.balanceMinor;
    } else if (asBase >= 0) {
      asset += asBase;
    } else {
      liability += -asBase;
    }
  }
  return BaseAssetLiability(
    assetMinor: asset,
    liabilityMinor: liability,
    unconvertedByCcy: leftover,
  );
}

/// Convert one balance; null when no rate (caller should skip or show raw).
int? balanceInBase({
  required String currency,
  required int balanceMinor,
  required FxBook book,
  required String baseCurrency,
  required String onDay,
}) {
  return book.convertMinor(
    fromCcy: currency,
    toCcy: baseCurrency,
    amountMinor: balanceMinor,
    onDay: onDay,
  );
}

/// Rolling / month / custom windows for home & stats.
///
/// - [DateRangeKind.lastDays]: default home/stats — last N days (N=30).
/// - [DateRangeKind.month]: a calendar month.
/// - [DateRangeKind.custom]: arbitrary inclusive day range.
enum DateRangeKind { lastDays, month, custom }

class DateRangeWindow {
  const DateRangeWindow._({
    required this.kind,
    required this.startLocal,
    required this.endLocal,
    this.days,
  });

  final DateRangeKind kind;

  /// Inclusive start (local midnight of first day).
  final DateTime startLocal;

  /// Exclusive end (local midnight after last included day).
  final DateTime endLocal;

  /// Only set for [DateRangeKind.lastDays].
  final int? days;

  int get startMs => startLocal.toUtc().millisecondsSinceEpoch;
  int get endMs => endLocal.toUtc().millisecondsSinceEpoch;

  String get key => '${kind.name}_${startMs}_$endMs';

  /// Window ending at start of tomorrow (covers all of "today").
  factory DateRangeWindow.lastDays({int days = 30, DateTime? nowLocal}) {
    final now = nowLocal ?? DateTime.now();
    final end = DateTime(now.year, now.month, now.day + 1);
    final start = end.subtract(Duration(days: days));
    return DateRangeWindow._(
      kind: DateRangeKind.lastDays,
      startLocal: start,
      endLocal: end,
      days: days,
    );
  }

  factory DateRangeWindow.forMonth(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return DateRangeWindow._(
      kind: DateRangeKind.month,
      startLocal: start,
      endLocal: end,
    );
  }

  /// 本周（周一 00:00 ～ 下周一 00:00，本地）。
  factory DateRangeWindow.thisWeek({DateTime? nowLocal}) {
    final now = nowLocal ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: today.weekday - 1));
    final end = start.add(const Duration(days: 7));
    return DateRangeWindow._(
      kind: DateRangeKind.custom,
      startLocal: start,
      endLocal: end,
    );
  }

  /// 上个自然月。
  factory DateRangeWindow.lastMonth({DateTime? nowLocal}) {
    final now = nowLocal ?? DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final prev = DateTime(thisMonth.year, thisMonth.month - 1, 1);
    return DateRangeWindow.forMonth(prev.year, prev.month);
  }

  /// 本自然月。
  factory DateRangeWindow.thisMonth({DateTime? nowLocal}) {
    final now = nowLocal ?? DateTime.now();
    return DateRangeWindow.forMonth(now.year, now.month);
  }

  /// [startInclusive] / [endInclusive] are calendar days (time-of-day ignored).
  factory DateRangeWindow.custom({
    required DateTime startInclusive,
    required DateTime endInclusive,
  }) {
    var start = DateTime(
      startInclusive.year,
      startInclusive.month,
      startInclusive.day,
    );
    var endDay = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
    );
    if (endDay.isBefore(start)) {
      final tmp = start;
      start = endDay;
      endDay = tmp;
    }
    final end = endDay.add(const Duration(days: 1));
    return DateRangeWindow._(
      kind: DateRangeKind.custom,
      startLocal: start,
      endLocal: end,
    );
  }

  DateRangeWindow prev() {
    switch (kind) {
      case DateRangeKind.lastDays:
        final d = days ?? 30;
        return DateRangeWindow._(
          kind: kind,
          startLocal: startLocal.subtract(Duration(days: d)),
          endLocal: endLocal.subtract(Duration(days: d)),
          days: d,
        );
      case DateRangeKind.month:
        final p = DateTime(startLocal.year, startLocal.month - 1, 1);
        return DateRangeWindow.forMonth(p.year, p.month);
      case DateRangeKind.custom:
        final span = endLocal.difference(startLocal);
        return DateRangeWindow._(
          kind: kind,
          startLocal: startLocal.subtract(span),
          endLocal: endLocal.subtract(span),
        );
    }
  }

  DateRangeWindow next() {
    switch (kind) {
      case DateRangeKind.lastDays:
        final d = days ?? 30;
        final advanced = DateRangeWindow._(
          kind: kind,
          startLocal: startLocal.add(Duration(days: d)),
          endLocal: endLocal.add(Duration(days: d)),
          days: d,
        );
        final latest = DateRangeWindow.lastDays(days: d);
        if (advanced.endLocal.isAfter(latest.endLocal)) return latest;
        return advanced;
      case DateRangeKind.month:
        final n = DateTime(startLocal.year, startLocal.month + 1, 1);
        final now = DateTime.now();
        final thisMonth = DateTime(now.year, now.month, 1);
        if (n.isAfter(thisMonth)) {
          return DateRangeWindow.forMonth(thisMonth.year, thisMonth.month);
        }
        return DateRangeWindow.forMonth(n.year, n.month);
      case DateRangeKind.custom:
        final span = endLocal.difference(startLocal);
        final advanced = DateRangeWindow._(
          kind: kind,
          startLocal: startLocal.add(span),
          endLocal: endLocal.add(span),
        );
        final latestEnd = DateTime.now();
        final cap = DateTime(latestEnd.year, latestEnd.month, latestEnd.day + 1);
        if (advanced.endLocal.isAfter(cap)) {
          return DateRangeWindow.custom(
            startInclusive: cap.subtract(span),
            endInclusive: cap.subtract(const Duration(days: 1)),
          );
        }
        return advanced;
    }
  }

  /// Whether this window is the "current" one relative to [nowLocal].
  bool isLatestAt(DateTime nowLocal) {
    switch (kind) {
      case DateRangeKind.lastDays:
        final latest = DateRangeWindow.lastDays(
          days: days ?? 30,
          nowLocal: nowLocal,
        );
        return endLocal.year == latest.endLocal.year &&
            endLocal.month == latest.endLocal.month &&
            endLocal.day == latest.endLocal.day;
      case DateRangeKind.month:
        return startLocal.year == nowLocal.year &&
            startLocal.month == nowLocal.month;
      case DateRangeKind.custom:
        final todayEnd =
            DateTime(nowLocal.year, nowLocal.month, nowLocal.day + 1);
        return endLocal.year == todayEnd.year &&
            endLocal.month == todayEnd.month &&
            endLocal.day == todayEnd.day;
    }
  }

  bool get isLatest => isLatestAt(DateTime.now());

  /// Label relative to [nowLocal] (same rules as [label]).
  String labelAt(DateTime nowLocal) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final lastDay = endLocal.subtract(const Duration(days: 1));
    switch (kind) {
      case DateRangeKind.lastDays:
        if (isLatestAt(nowLocal)) return '近${days ?? 30}天';
        return '${fmt(startLocal)} ~ ${fmt(lastDay)}';
      case DateRangeKind.month:
        return '${startLocal.year}年${startLocal.month}月';
      case DateRangeKind.custom:
        if (startLocal.year == lastDay.year &&
            startLocal.month == lastDay.month &&
            startLocal.day == lastDay.day) {
          return fmt(startLocal);
        }
        return '${fmt(startLocal)} ~ ${fmt(lastDay)}';
    }
  }

  String get label => labelAt(DateTime.now());
}

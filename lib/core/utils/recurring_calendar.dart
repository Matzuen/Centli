/// Pure calendar helpers for recurring bookkeeping (no IO).
library;

/// Result of [dueOccurrences]: dates to generate plus how many were truncated.
class DueOccurrencesResult {
  const DueOccurrencesResult({
    required this.occurrences,
    required this.truncatedCount,
  });

  final List<DateTime> occurrences;
  final int truncatedCount;
}

/// Advance [from] by [interval] periods of [periodKind], with month-end clamp.
///
/// Anchor day is the day-of-month of the *original* start (passed as [anchorDay])
/// so Jan 31 → Feb 28 → Mar 31.
DateTime advancePeriod({
  required DateTime from,
  required String periodKind,
  required int periodInterval,
  required int anchorDay,
}) {
  final interval = periodInterval <= 0 ? 1 : periodInterval;
  switch (periodKind) {
    case 'day':
      return DateTime(from.year, from.month, from.day + interval);
    case 'week':
      return DateTime(from.year, from.month, from.day + 7 * interval);
    case 'month':
      return _addMonthsClamped(from, interval, anchorDay);
    case 'quarter':
      return _addMonthsClamped(from, 3 * interval, anchorDay);
    case 'year':
      return _addMonthsClamped(from, 12 * interval, anchorDay);
    default:
      return DateTime(from.year, from.month, from.day + interval);
  }
}

DateTime _addMonthsClamped(DateTime from, int months, int anchorDay) {
  final totalMonths = from.year * 12 + (from.month - 1) + months;
  final y = totalMonths ~/ 12;
  final m = totalMonths % 12 + 1;
  final dim = _daysInMonth(y, m);
  final d = anchorDay > dim ? dim : anchorDay;
  return DateTime(y, m, d, from.hour, from.minute, from.second, from.millisecond);
}

int _daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

/// Occurrences with [nextRunAt]..<=[now], starting cursor at max(nextRunAt, aligned).
DueOccurrencesResult dueOccurrences({
  required DateTime startAt,
  required String periodKind,
  required int periodInterval,
  required DateTime nextRunAt,
  required DateTime now,
  int maxOccurrences = 12,
}) {
  final anchorDay = startAt.day;
  // Normalize to local date (drop time drift for calendar kinds).
  var cursor = DateTime(
    nextRunAt.year,
    nextRunAt.month,
    nextRunAt.day,
    startAt.hour,
    startAt.minute,
  );
  final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
  final out = <DateTime>[];
  var truncated = 0;
  // Safety: never loop forever
  var guard = 0;
  while (!cursor.isAfter(end) && guard < 1000) {
    guard++;
    if (out.length >= maxOccurrences) {
      truncated++;
    } else {
      out.add(cursor);
    }
    cursor = advancePeriod(
      from: cursor,
      periodKind: periodKind,
      periodInterval: periodInterval,
      anchorDay: anchorDay,
    );
  }
  return DueOccurrencesResult(occurrences: out, truncatedCount: truncated);
}

/// Next run strictly after [from] (or equal if [from] is a valid slot and future).
DateTime nextRunAfter({
  required DateTime startAt,
  required String periodKind,
  required int periodInterval,
  required DateTime from,
}) {
  final anchorDay = startAt.day;
  var cursor = DateTime(
    startAt.year,
    startAt.month,
    startAt.day,
    startAt.hour,
    startAt.minute,
  );
  final target = DateTime(from.year, from.month, from.day, from.hour, from.minute);
  var guard = 0;
  while (!cursor.isAfter(target) && guard < 10000) {
    guard++;
    cursor = advancePeriod(
      from: cursor,
      periodKind: periodKind,
      periodInterval: periodInterval,
      anchorDay: anchorDay,
    );
  }
  return cursor;
}

/// Preview at least [count] future occurrences from [startAt] (inclusive if future).
List<DateTime> previewOccurrences({
  required DateTime startAt,
  required String periodKind,
  required int periodInterval,
  required DateTime now,
  int count = 3,
}) {
  final anchorDay = startAt.day;
  var cursor = DateTime(
    startAt.year,
    startAt.month,
    startAt.day,
    startAt.hour,
    startAt.minute,
  );
  final out = <DateTime>[];
  var guard = 0;
  // If start is in the past, still include it in catch-up preview via dueOccurrences;
  // for wizard preview of *future*, skip until > now-ish day start.
  final today = DateTime(now.year, now.month, now.day);
  while (cursor.isBefore(today) && guard < 10000) {
    guard++;
    cursor = advancePeriod(
      from: cursor,
      periodKind: periodKind,
      periodInterval: periodInterval,
      anchorDay: anchorDay,
    );
  }
  while (out.length < count && guard < 10000) {
    guard++;
    out.add(cursor);
    cursor = advancePeriod(
      from: cursor,
      periodKind: periodKind,
      periodInterval: periodInterval,
      anchorDay: anchorDay,
    );
  }
  return out;
}

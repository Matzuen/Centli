import 'package:centli/core/utils/recurring_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dueOccurrences', () {
    test('monthly 1st from Jan to Apr', () {
      final r = dueOccurrences(
        startAt: DateTime(2026, 1, 1),
        periodKind: 'month',
        periodInterval: 1,
        nextRunAt: DateTime(2026, 1, 1),
        now: DateTime(2026, 4, 1),
      );
      expect(
        r.occurrences.map((d) => '${d.year}-${d.month}-${d.day}').toList(),
        ['2026-1-1', '2026-2-1', '2026-3-1', '2026-4-1'],
      );
      expect(r.truncatedCount, 0);
    });

    test('month-end clamp Jan 31 restores Mar 31', () {
      final r = dueOccurrences(
        startAt: DateTime(2026, 1, 31),
        periodKind: 'month',
        periodInterval: 1,
        nextRunAt: DateTime(2026, 1, 31),
        now: DateTime(2026, 3, 31),
      );
      expect(
        r.occurrences.map((d) => '${d.month}-${d.day}').toList(),
        ['1-31', '2-28', '3-31'],
      );
    });

    test('leap year Feb 29 yearly clamps to Feb 28', () {
      final r = dueOccurrences(
        startAt: DateTime(2024, 2, 29),
        periodKind: 'year',
        periodInterval: 1,
        nextRunAt: DateTime(2024, 2, 29),
        now: DateTime(2025, 2, 28),
      );
      expect(r.occurrences.map((d) => '${d.year}-${d.month}-${d.day}').toList(), [
        '2024-2-29',
        '2025-2-28',
      ]);
    });

    test('every 2 weeks crosses months', () {
      final r = dueOccurrences(
        startAt: DateTime(2026, 1, 20),
        periodKind: 'week',
        periodInterval: 2,
        nextRunAt: DateTime(2026, 1, 20),
        now: DateTime(2026, 2, 20),
      );
      expect(r.occurrences.length, greaterThanOrEqualTo(3));
      expect(r.occurrences[0], DateTime(2026, 1, 20));
      expect(r.occurrences[1], DateTime(2026, 2, 3));
      expect(r.occurrences[2], DateTime(2026, 2, 17));
    });

    test('maxOccurrences truncates and reports remainder', () {
      final r = dueOccurrences(
        startAt: DateTime(2026, 1, 1),
        periodKind: 'day',
        periodInterval: 1,
        nextRunAt: DateTime(2026, 1, 1),
        now: DateTime(2026, 1, 20),
        maxOccurrences: 5,
      );
      expect(r.occurrences.length, 5);
      expect(r.truncatedCount, 15); // days 6..20
    });
  });
}

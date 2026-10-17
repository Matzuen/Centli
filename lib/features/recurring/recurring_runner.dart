import '../../data/db/centli_database.dart';
import '../../core/utils/recurring_calendar.dart';
import 'package:drift/drift.dart';

/// Catch-up runner for enabled recurring rules (idempotent via occurrenceKey).
class RecurringRunResult {
  const RecurringRunResult({
    this.generated = 0,
    this.skippedBroken = 0,
    this.truncatedTotal = 0,
  });

  final int generated;
  final int skippedBroken;
  final int truncatedTotal;
}

Future<RecurringRunResult> runDueRecurring(
  CentliDatabase db, {
  DateTime? now,
}) async {
  final n = now ?? DateTime.now();
  final nowMsVal = n.millisecondsSinceEpoch;
  final rules = await (db.select(db.recurringRules)
        ..where((t) => t.enabled.equals(1) & t.nextRunAt.isSmallerOrEqualValue(nowMsVal)))
      .get();
  if (rules.isEmpty) {
    return const RecurringRunResult();
  }

  var generated = 0;
  var skippedBroken = 0;
  var truncatedTotal = 0;

  for (final rule in rules) {
    try {
      final account = await db.getAccount(rule.accountId);
      if (account == null || account.archived == 1) {
        skippedBroken++;
        continue;
      }
      if (rule.categoryId != null) {
        final cat = await (db.select(db.categories)
              ..where((t) => t.id.equals(rule.categoryId!)))
            .getSingleOrNull();
        if (cat == null || cat.archived == 1) {
          skippedBroken++;
          continue;
        }
      }

      final startAt = DateTime.fromMillisecondsSinceEpoch(rule.startAt);
      final nextRun = DateTime.fromMillisecondsSinceEpoch(rule.nextRunAt);
      final due = dueOccurrences(
        startAt: startAt,
        periodKind: rule.periodKind,
        periodInterval: rule.periodInterval,
        nextRunAt: nextRun,
        now: n,
      );
      truncatedTotal += due.truncatedCount;

      await db.transaction(() async {
        for (final occ in due.occurrences) {
          final key =
              'rec:${rule.id}:${occ.millisecondsSinceEpoch}';
          final existing = await (db.select(db.transactions)
                ..where((t) => t.occurrenceKey.equals(key))
                ..limit(1))
              .get();
          if (existing.isNotEmpty) continue;

          final baseNote = rule.note?.trim();
          final note = baseNote == null || baseNote.isEmpty
              ? '[\u5468\u671f]'
              : '[\u5468\u671f] $baseNote';

          await db.insertManualTransaction(
            ledgerId: rule.ledgerId,
            type: rule.type,
            amountMinor: rule.amountMinor,
            currency: rule.currency,
            accountId: rule.accountId,
            categoryId: rule.categoryId,
            merchant: rule.merchant,
            note: note,
            tags: null,
            happenAt: occ,
            includeInStat: rule.includeInStat,
            includeInBudget: rule.includeInBudget,
            occurrenceKey: key,
          );
          generated++;
        }

        // Advance nextRunAt to first future slot after last generated (or now).
        final lastOcc = due.occurrences.isEmpty
            ? nextRun
            : due.occurrences.last;
        final advanced = nextRunAfter(
          startAt: startAt,
          periodKind: rule.periodKind,
          periodInterval: rule.periodInterval,
          from: lastOcc.isAfter(n) ? lastOcc : n,
        );
        // If we truncated, still advance past the generated ones.
        final nextMs = advanced.millisecondsSinceEpoch;
        await (db.update(db.recurringRules)..where((t) => t.id.equals(rule.id)))
            .write(
          RecurringRulesCompanion(
            nextRunAt: Value(nextMs),
            lastRunAt: Value(nowMsVal),
            skippedCount: Value(
              rule.skippedCount + due.truncatedCount,
            ),
            updatedAt: Value(nowMsVal),
          ),
        );
      });
    } catch (_) {
      skippedBroken++;
    }
  }

  return RecurringRunResult(
    generated: generated,
    skippedBroken: skippedBroken,
    truncatedTotal: truncatedTotal,
  );
}

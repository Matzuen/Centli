import 'package:drift/drift.dart';
import 'accounts.dart';
import 'categories.dart';
import 'ledgers.dart';

/// Periodic bookkeeping rules (schema v6). Types: in / out only (no transfer).
class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId =>
      text().named('ledger_id').references(Ledgers, #id)();
  /// 'in' | 'out'
  TextColumn get type => text()();
  IntColumn get amountMinor => integer().named('amount_minor')();
  TextColumn get currency => text()();
  TextColumn get accountId =>
      text().named('account_id').references(Accounts, #id)();
  TextColumn get categoryId =>
      text().named('category_id').nullable().references(Categories, #id)();
  TextColumn get merchant => text().nullable()();
  TextColumn get note => text().nullable()();
  /// JSON array string, same convention as transactions.tags.
  TextColumn get tags => text().nullable()();
  IntColumn get includeInStat =>
      integer().named('include_in_stat').withDefault(const Constant(1))();
  IntColumn get includeInBudget =>
      integer().named('include_in_budget').withDefault(const Constant(1))();
  /// day / week / month / quarter / year
  TextColumn get periodKind => text().named('period_kind')();
  IntColumn get periodInterval =>
      integer().named('period_interval').withDefault(const Constant(1))();
  IntColumn get startAt => integer().named('start_at')();
  IntColumn get nextRunAt => integer().named('next_run_at')();
  IntColumn get lastRunAt => integer().named('last_run_at').nullable()();
  IntColumn get enabled => integer().withDefault(const Constant(1))();
  /// Periods skipped due to maxOccurrences cap (for UI tip).
  IntColumn get skippedCount =>
      integer().named('skipped_count').withDefault(const Constant(0))();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

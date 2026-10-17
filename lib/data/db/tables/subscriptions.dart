import 'package:drift/drift.dart';
import 'ledgers.dart';
import 'categories.dart';

class Subscriptions extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId =>
      text().named('ledger_id').references(Ledgers, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  TextColumn get categoryId =>
      text().named('category_id').nullable().references(Categories, #id)();
  IntColumn get priceMinor => integer().named('price_minor')();
  TextColumn get currency => text()();
  /// week / month / quarter / year / lifetime
  TextColumn get periodKind => text().named('period_kind')();
  /// active / cancelled / trial / owned / free
  TextColumn get status => text()();
  IntColumn get startedAt => integer().named('started_at')();
  IntColumn get nextDueAt => integer().named('next_due_at').nullable()();
  IntColumn get remindDaysBefore => integer()
      .named('remind_days_before')
      .withDefault(const Constant(3))();
  TextColumn get note => text().nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

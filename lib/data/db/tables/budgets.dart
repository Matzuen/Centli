import 'package:drift/drift.dart';
import 'ledgers.dart';

/// Monthly expense budgets. [categoryId] empty string = ledger total for the month.
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId =>
      text().named('ledger_id').references(Ledgers, #id)();
  /// `yyyy-MM` in local calendar.
  TextColumn get yearMonth => text().named('year_month')();
  /// `''` = total monthly expense budget; otherwise a categories.id.
  TextColumn get categoryId =>
      text().named('category_id').withDefault(const Constant(''))();
  /// Limit in ledger base currency minor units.
  IntColumn get amountMinor => integer().named('amount_minor')();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {ledgerId, yearMonth, categoryId},
      ];
}

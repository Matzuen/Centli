import 'package:drift/drift.dart';

class Ledgers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get baseCurrency => text().named('base_currency')();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get archived => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
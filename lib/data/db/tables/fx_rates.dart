import 'package:drift/drift.dart';

/// FX cache [P2+]; empty in P0 seed.
class FxRates extends Table {
  TextColumn get day => text()(); // yyyy-MM-dd
  TextColumn get fromCcy => text().named('from_ccy')();
  TextColumn get toCcy => text().named('to_ccy')();
  RealColumn get rate => real()();
  TextColumn get source => text().nullable()();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {day, fromCcy, toCcy};
}
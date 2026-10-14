import 'package:drift/drift.dart';
import 'ledgers.dart';

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text().named('ledger_id').references(Ledgers, #id)();
  TextColumn get name => text()();
  TextColumn get parentId => text().named('parent_id').nullable()();
  TextColumn get kind => text()(); // out / in
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant(0))();
  IntColumn get archived => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().named('created_at')();

  @override
  Set<Column> get primaryKey => {id};
}
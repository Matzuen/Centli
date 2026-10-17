import 'package:drift/drift.dart';
import 'ledgers.dart';

/// Per-ledger custom asset categories (accounts.type stores asset_types.id).
class AssetTypes extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text().named('ledger_id').references(Ledgers, #id)();
  TextColumn get name => text()();
  TextColumn get icon => text().nullable()();
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant(0))();
  IntColumn get archived => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

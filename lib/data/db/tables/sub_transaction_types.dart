import 'package:drift/drift.dart';

/// Global templates for sub-transactions (AA / 退款 / 手续费 …).
///
/// [sign]: `1` = income-like (+), `-1` = expense-like (−).
class SubTransactionTypes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sign => integer()();
  TextColumn get iconKey => text().named('icon_key').nullable()();
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant(0))();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
  IntColumn get deletedAt => integer().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

import 'package:drift/drift.dart';

class MerchantRules extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text().named('ledger_id')();
  TextColumn get merchantKey => text().named('merchant_key')();
  TextColumn get categoryId => text().named('category_id').nullable()();
  TextColumn get accountId => text().named('account_id').nullable()();
  IntColumn get hitCount =>
      integer().named('hit_count').withDefault(const Constant(1))();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {ledgerId, merchantKey},
      ];
}
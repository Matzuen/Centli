import 'package:drift/drift.dart';

class PendingCaptures extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text().named('ledger_id')();
  TextColumn get sourcePkg => text().named('source_pkg')();
  TextColumn get rawTitle => text().named('raw_title').nullable()();
  TextColumn get rawText => text().named('raw_text')();
  IntColumn get amountMinor => integer().named('amount_minor').nullable()();
  TextColumn get currency => text().nullable()();
  TextColumn get merchant => text().nullable()();
  IntColumn get happenAt => integer().named('happen_at').nullable()();
  TextColumn get suggestedCategoryId =>
      text().named('suggested_category_id').nullable()();
  TextColumn get suggestedAccountId =>
      text().named('suggested_account_id').nullable()();
  TextColumn get status => text()(); // pending / confirmed / ignored
  TextColumn get dedupeKey => text().named('dedupe_key')();
  IntColumn get parseOk =>
      integer().named('parse_ok').withDefault(const Constant(0))();
  /// Persisted parse direction: in / out / refund / repay. Null = legacy, treat as out.
  TextColumn get direction => text().nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {dedupeKey},
      ];
}
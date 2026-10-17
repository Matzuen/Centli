import 'package:drift/drift.dart';
import 'accounts.dart';
import 'categories.dart';
import 'ledgers.dart';

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text().named('ledger_id').references(Ledgers, #id)();
  TextColumn get type => text()(); // in / out / transfer
  IntColumn get amountMinor => integer().named('amount_minor')();
  TextColumn get currency => text()();
  @ReferenceName('outgoingTransactions')
  TextColumn get accountId =>
      text().named('account_id').references(Accounts, #id)();
  @ReferenceName('incomingTransfers')
  TextColumn get toAccountId =>
      text().named('to_account_id').nullable().references(Accounts, #id)();
  TextColumn get categoryId =>
      text().named('category_id').nullable().references(Categories, #id)();
  TextColumn get merchant => text().nullable()();
  /// Optional household member label (free text; no member entity table).
  TextColumn get member => text().nullable()();
  TextColumn get note => text().nullable()();
  /// JSON array string, e.g. `["报销","旅行"]`. Null/empty = no tags.
  TextColumn get tags => text().nullable()();
  IntColumn get happenAt => integer().named('happen_at')();
  IntColumn get includeInStat =>
      integer().named('include_in_stat').withDefault(const Constant(1))();
  IntColumn get includeInBudget =>
      integer().named('include_in_budget').withDefault(const Constant(1))();
  TextColumn get transferGroupId =>
      text().named('transfer_group_id').nullable()();
  RealColumn get fxRate => real().named('fx_rate').nullable()();
  IntColumn get toAmountMinor =>
      integer().named('to_amount_minor').nullable()();
  TextColumn get source =>
      text().withDefault(const Constant('manual'))();
  TextColumn get pendingId => text().named('pending_id').nullable()();
  /// Idempotency key for recurring generations: `rec:ruleId:ms`.
  TextColumn get occurrenceKey =>
      text().named('occurrence_key').nullable()();
  IntColumn get createdAt => integer().named('created_at')();
  IntColumn get updatedAt => integer().named('updated_at')();
  IntColumn get deletedAt => integer().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
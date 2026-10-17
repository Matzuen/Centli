import 'dart:io';

import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

void _createV10DbWithMember(File file) {
  if (file.existsSync()) file.deleteSync();
  final db = raw_sqlite.sqlite3.open(file.path);
  db.execute('PRAGMA foreign_keys = OFF;');
  db.execute('''CREATE TABLE "ledgers" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "base_currency" TEXT NOT NULL, "created_at" INTEGER NOT NULL, "archived" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "accounts" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "name" TEXT NOT NULL, "currency" TEXT NOT NULL, "type" TEXT NOT NULL, "icon" TEXT NULL, "opening_balance_minor" INTEGER NOT NULL DEFAULT 0, "sort_order" INTEGER NOT NULL DEFAULT 0, "archived" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "asset_types" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "name" TEXT NOT NULL, "icon" TEXT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "archived" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "categories" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "name" TEXT NOT NULL, "parent_id" TEXT NULL, "kind" TEXT NOT NULL, "icon" TEXT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "archived" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "transactions" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "type" TEXT NOT NULL, "amount_minor" INTEGER NOT NULL, "currency" TEXT NOT NULL, "account_id" TEXT NOT NULL REFERENCES accounts (id), "to_account_id" TEXT NULL REFERENCES accounts (id), "category_id" TEXT NULL REFERENCES categories (id), "member" TEXT NULL, "note" TEXT NULL, "tags" TEXT NULL, "happen_at" INTEGER NOT NULL, "include_in_stat" INTEGER NOT NULL DEFAULT 1, "include_in_budget" INTEGER NOT NULL DEFAULT 1, "transfer_group_id" TEXT NULL, "fx_rate" REAL NULL, "to_amount_minor" INTEGER NULL, "source" TEXT NOT NULL DEFAULT 'manual', "pending_id" TEXT NULL, "occurrence_key" TEXT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "pending_captures" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL, "source_pkg" TEXT NOT NULL, "raw_title" TEXT NULL, "raw_text" TEXT NOT NULL, "amount_minor" INTEGER NULL, "currency" TEXT NULL, "note" TEXT NULL, "happen_at" INTEGER NULL, "suggested_category_id" TEXT NULL, "suggested_account_id" TEXT NULL, "status" TEXT NOT NULL, "dedupe_key" TEXT NOT NULL, "parse_ok" INTEGER NOT NULL DEFAULT 0, "direction" TEXT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("dedupe_key"));''');
  db.execute('''CREATE TABLE "merchant_rules" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL, "merchant_key" TEXT NOT NULL, "category_id" TEXT NULL, "account_id" TEXT NULL, "hit_count" INTEGER NOT NULL DEFAULT 1, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("ledger_id", "merchant_key"));''');
  db.execute('''CREATE TABLE "fx_rates" ("day" TEXT NOT NULL, "from_ccy" TEXT NOT NULL, "to_ccy" TEXT NOT NULL, "rate" REAL NOT NULL, "source" TEXT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("day", "from_ccy", "to_ccy"));''');
  db.execute('''CREATE TABLE "budgets" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "year_month" TEXT NOT NULL, "category_id" TEXT NOT NULL DEFAULT '', "amount_minor" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("ledger_id", "year_month", "category_id"));''');
  db.execute('''CREATE TABLE "app_settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"));''');
  db.execute('''CREATE TABLE "recurring_rules" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "type" TEXT NOT NULL, "amount_minor" INTEGER NOT NULL, "currency" TEXT NOT NULL, "account_id" TEXT NOT NULL REFERENCES accounts (id), "category_id" TEXT NULL REFERENCES categories (id), "merchant" TEXT NULL, "note" TEXT NULL, "tags" TEXT NULL, "include_in_stat" INTEGER NOT NULL DEFAULT 1, "include_in_budget" INTEGER NOT NULL DEFAULT 1, "period_kind" TEXT NOT NULL, "period_interval" INTEGER NOT NULL DEFAULT 1, "start_at" INTEGER NOT NULL, "next_run_at" INTEGER NOT NULL, "last_run_at" INTEGER NULL, "enabled" INTEGER NOT NULL DEFAULT 1, "skipped_count" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"));''');

  db.execute(
    "INSERT INTO ledgers(id, name, base_currency, created_at) "
    "VALUES ('L1','测试账本','CNY',1);",
  );
  db.execute(
    "INSERT INTO accounts(id, ledger_id, name, currency, type, opening_balance_minor, created_at, updated_at) "
    "VALUES ('A1','L1','现金','CNY','cash',0,1,1);",
  );
  db.execute(
    "INSERT INTO transactions(id, ledger_id, type, amount_minor, currency, account_id, member, note, happen_at, created_at, updated_at) VALUES "
    "('T1','L1','out',100,'CNY','A1','Alice','午餐',10,1,1),"
    "('T2','L1','out',200,'CNY','A1','Bob',NULL,20,1,1),"
    "('T3','L1','out',300,'CNY','A1',NULL,'仅备注',30,1,1),"
    "('T4','L1','out',400,'CNY','A1','','保留备注',40,1,1);",
  );
  db.execute('PRAGMA user_version = 10;');
  db.dispose();
}

void _createV4DbWithoutMember(File file) {
  if (file.existsSync()) file.deleteSync();
  final db = raw_sqlite.sqlite3.open(file.path);
  db.execute('PRAGMA foreign_keys = OFF;');
  db.execute('''CREATE TABLE "ledgers" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "base_currency" TEXT NOT NULL, "created_at" INTEGER NOT NULL, "archived" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "accounts" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "name" TEXT NOT NULL, "currency" TEXT NOT NULL, "type" TEXT NOT NULL, "icon" TEXT NULL, "opening_balance_minor" INTEGER NOT NULL DEFAULT 0, "sort_order" INTEGER NOT NULL DEFAULT 0, "archived" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "categories" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "name" TEXT NOT NULL, "parent_id" TEXT NULL, "kind" TEXT NOT NULL, "icon" TEXT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "archived" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "transactions" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "type" TEXT NOT NULL, "amount_minor" INTEGER NOT NULL, "currency" TEXT NOT NULL, "account_id" TEXT NOT NULL REFERENCES accounts (id), "to_account_id" TEXT NULL REFERENCES accounts (id), "category_id" TEXT NULL REFERENCES categories (id), "merchant" TEXT NULL, "note" TEXT NULL, "tags" TEXT NULL, "happen_at" INTEGER NOT NULL, "include_in_stat" INTEGER NOT NULL DEFAULT 1, "include_in_budget" INTEGER NOT NULL DEFAULT 1, "transfer_group_id" TEXT NULL, "fx_rate" REAL NULL, "to_amount_minor" INTEGER NULL, "source" TEXT NOT NULL DEFAULT 'manual', "pending_id" TEXT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, "deleted_at" INTEGER NULL, PRIMARY KEY ("id"));''');
  db.execute('''CREATE TABLE "pending_captures" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL, "source_pkg" TEXT NOT NULL, "raw_title" TEXT NULL, "raw_text" TEXT NOT NULL, "amount_minor" INTEGER NULL, "currency" TEXT NULL, "merchant" TEXT NULL, "happen_at" INTEGER NULL, "suggested_category_id" TEXT NULL, "suggested_account_id" TEXT NULL, "status" TEXT NOT NULL, "dedupe_key" TEXT NOT NULL, "parse_ok" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("dedupe_key"));''');
  db.execute('''CREATE TABLE "merchant_rules" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL, "merchant_key" TEXT NOT NULL, "category_id" TEXT NULL, "account_id" TEXT NULL, "hit_count" INTEGER NOT NULL DEFAULT 1, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("ledger_id", "merchant_key"));''');
  db.execute('''CREATE TABLE "fx_rates" ("day" TEXT NOT NULL, "from_ccy" TEXT NOT NULL, "to_ccy" TEXT NOT NULL, "rate" REAL NOT NULL, "source" TEXT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("day", "from_ccy", "to_ccy"));''');
  db.execute('''CREATE TABLE "budgets" ("id" TEXT NOT NULL, "ledger_id" TEXT NOT NULL REFERENCES ledgers (id), "year_month" TEXT NOT NULL, "category_id" TEXT NOT NULL DEFAULT '', "amount_minor" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, PRIMARY KEY ("id"), UNIQUE ("ledger_id", "year_month", "category_id"));''');
  db.execute('''CREATE TABLE "app_settings" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"));''');

  db.execute(
    "INSERT INTO ledgers(id, name, base_currency, created_at) "
    "VALUES ('L1','测试账本','CNY',1);",
  );
  db.execute(
    "INSERT INTO accounts(id, ledger_id, name, currency, type, icon, opening_balance_minor, created_at, updated_at) "
    "VALUES ('A1','L1','现金','CNY','cash','cash',0,1,1);",
  );
  db.execute(
    "INSERT INTO transactions(id, ledger_id, type, amount_minor, currency, account_id, merchant, note, happen_at, created_at, updated_at) VALUES "
    "('T1','L1','out',100,'CNY','A1','星巴克','原备注',10,1,1);",
  );
  db.execute('PRAGMA user_version = 4;');
  db.dispose();
}

void main() {
  test('v11 onCreate has no member column', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 11);
    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(cols.contains('member'), isFalse);
    expect(cols.contains('note'), isTrue);
  });

  test('v10→v11 merges 4 member rows into note and drops column', () async {
    final file = File(
      '${Directory.systemTemp.path}/centli_v10_member_merge.db',
    );
    _createV10DbWithMember(file);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final db = CentliDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 11);

    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(cols.contains('member'), isFalse);

    final rows = await db.customSelect(
      'SELECT id, note, amount_minor, currency, account_id FROM transactions ORDER BY id',
    ).get();
    expect(rows.length, 4);

    String? noteOf(String id) =>
        rows.firstWhere((r) => r.read<String>('id') == id).read<String?>('note');

    expect(noteOf('T1'), '午餐 · Alice');
    expect(noteOf('T2'), 'Bob');
    expect(noteOf('T3'), '仅备注');
    expect(noteOf('T4'), '保留备注');

    for (final r in rows) {
      expect(r.read<String>('currency'), 'CNY');
      expect(r.read<String>('account_id'), 'A1');
    }
    expect(
      rows.firstWhere((r) => r.read<String>('id') == 'T1').read<int>('amount_minor'),
      100,
    );
    expect(
      rows.firstWhere((r) => r.read<String>('id') == 'T2').read<int>('amount_minor'),
      200,
    );
  });

  test('v4→v11 cross-version ends without member', () async {
    final file = File(
      '${Directory.systemTemp.path}/centli_v4_to_v11.db',
    );
    _createV4DbWithoutMember(file);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });

    final db = CentliDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);

    final ver = await db.customSelect('PRAGMA user_version').getSingle();
    expect(ver.read<int>('user_version'), 11);

    final cols = {
      for (final r
          in await db.customSelect('PRAGMA table_info(transactions)').get())
        r.read<String>('name')
    };
    expect(cols.contains('member'), isFalse);
    expect(cols.contains('merchant'), isFalse);
    expect(cols.contains('occurrence_key'), isTrue);

    final row = await db.customSelect(
      "SELECT note, amount_minor FROM transactions WHERE id = 'T1'",
    ).getSingle();
    expect(row.read<String>('note'), '星巴克 · 原备注');
    expect(row.read<int>('amount_minor'), 100);
  });
}

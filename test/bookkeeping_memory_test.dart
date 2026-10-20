import 'package:centli/data/db/centli_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记账记忆：上次使用的资产账户 / 分类（last_bookkeeping）与「备注 → 分类」
/// （note_category_map）。都是 app_settings 里的 JSON，不进导出。
void main() {
  late CentliDatabase db;
  late String ledgerId;
  late List<Account> accounts;
  late List<Category> cats;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    ledgerId = ledger.id;
    accounts = await db.loadActiveAccounts(ledgerId);
    cats = await db.loadCategories(ledgerId, 'out');
  });

  tearDown(() async => db.close());

  group('last bookkeeping choice', () {
    test('nothing saved yet → null (fresh install keeps defaults)', () async {
      expect(await db.loadLastBookkeeping(), isNull);
    });

    test('round-trips type / account / category per direction', () async {
      await db.saveLastBookkeeping(
        LastBookkeepingChoice(
          type: 'out',
          accountId: accounts.first.id,
          categoryId: cats.first.id,
          categoryByType: {'out': cats.first.id, 'in': 'c-in'},
        ),
      );
      final got = await db.loadLastBookkeeping();
      expect(got, isNotNull);
      expect(got!.type, 'out');
      expect(got.accountId, accounts.first.id);
      expect(got.categoryId, cats.first.id);
      expect(got.categoryByType['out'], cats.first.id);
      expect(got.categoryByType['in'], 'c-in');
    });

    test('transfer is not remembered as the next 记一笔 type default', () async {
      // The sheet only saves out/in, so a transfer must not overwrite it.
      await db.saveLastBookkeeping(
        LastBookkeepingChoice(
          type: 'out',
          accountId: accounts.first.id,
          categoryId: cats.first.id,
        ),
      );
      final got = await db.loadLastBookkeeping();
      expect(got!.type, 'out');
    });
  });

  group('note → category memory', () {
    test('exact note recalls its category', () async {
      await db.rememberNoteCategories(['午饭'], cats[1].id);
      expect(await db.recallCategoryForNote('午饭'), cats[1].id);
    });

    test('whitespace / case / punctuation are normalised', () async {
      await db.rememberNoteCategories(['Lunch  Set'], cats[2].id);
      expect(await db.recallCategoryForNote('  lunch   set '), cats[2].id);
      expect(await db.recallCategoryForNote('lunch   set。'), cats[2].id);
    });

    test('a longer note containing a remembered fragment still matches',
        () async {
      await db.rememberNoteCategories(['午饭'], cats[1].id);
      expect(await db.recallCategoryForNote('午饭和同事'), cats[1].id, reason: 'fragment match');
    });

    test('the longest matching fragment wins', () async {
      await db.rememberNoteCategories(['咖啡'], cats[1].id);
      await db.rememberNoteCategories(['咖啡 星巴克'], cats[3].id);
      expect(await db.recallCategoryForNote('咖啡 星巴克 中杯'), cats[3].id);
    });

    test('1-character notes are ignored (too noisy)', () async {
      await db.rememberNoteCategories(['饭'], cats[1].id);
      expect(await db.recallCategoryForNote('饭'), isNull);
    });

    test('re-remembering updates the category', () async {
      await db.rememberNoteCategories(['午饭'], cats[1].id);
      await db.rememberNoteCategories(['午饭'], cats[4].id);
      expect(await db.recallCategoryForNote('午饭'), cats[4].id);
    });

    test('empty / null note recalls nothing', () async {
      await db.rememberNoteCategories(['午饭'], cats[1].id);
      expect(await db.recallCategoryForNote(null), isNull);
      expect(await db.recallCategoryForNote('   '), isNull);
    });

    test('map is capped and keeps the most recent entries', () async {
      for (var i = 0; i < CentliDatabase.noteCategoryMapLimit + 20; i++) {
        await db.rememberNoteCategories(['note$i'], cats[1].id);
      }
      final map = await db.loadNoteCategoryMap();
      expect(map.length, CentliDatabase.noteCategoryMapLimit);
      expect(map.containsKey('note0'), isFalse, reason: 'oldest evicted');
      final last = CentliDatabase.noteCategoryMapLimit + 19;
      expect(map.containsKey('note$last'), isTrue);
    });
  });
}

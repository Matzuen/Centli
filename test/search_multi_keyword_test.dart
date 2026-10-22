import 'package:centli/data/db/centli_database.dart';
import 'package:centli/core/widgets/txn_list_tile.dart';
import 'package:centli/features/ledger/search_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Search: space-separated OR keywords, keyword chips, row highlighting.
void main() {
  group('searchKeywords', () {
    test('splits on spaces and full-width spaces, dedupes', () {
      expect(searchKeywords('午餐 支付宝'), ['午餐', '支付宝']);
      expect(searchKeywords('午餐\u3000支付宝'), ['午餐', '支付宝']);
      expect(searchKeywords('  午餐   午餐  支付宝 '), ['午餐', '支付宝']);
      expect(searchKeywords(''), isEmpty);
      expect(searchKeywords('   '), isEmpty);
    });
  });

  group('highlightSpans', () {
    List<TextSpan> spans(String text, List<String> kw) =>
        highlightSpans(text, kw, highlightColor: kKeywordHighlight);

    test('marks every keyword occurrence', () {
      final out = spans('午餐 支付宝', ['午餐', '支付宝']);
      expect(out.map((s) => s.text).join(), '午餐 支付宝');
      expect(
        out.where((s) => s.style?.color == kKeywordHighlight).map((s) => s.text),
        ['午餐', '支付宝'],
        reason: 'the untouched space keeps the plain style',
      );
    });

    test('is case-insensitive and merges overlaps', () {
      final out = spans('Starbucks Coffee', ['star', 'Starbucks']);
      final marked = out
          .where((s) => s.style?.color == kKeywordHighlight)
          .map((s) => s.text)
          .join();
      expect(marked, 'Starbucks');
      expect(out.map((s) => s.text).join(), 'Starbucks Coffee');
    });

    test('no keywords / empty text → single plain span', () {
      expect(spans('午餐', []).single.text, '午餐');
      expect(spans('', ['午餐']).single.text, '');
    });
  });

  group('searchTransactions multi-keyword', () {
    late CentliDatabase db;
    late String ledgerId;
    late List<String> catsOut;

    setUp(() async {
      db = CentliDatabase.forTesting(NativeDatabase.memory());
      await db.seedDefaults();
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      ledgerId = ledger.id;
      final accounts = await db.loadActiveAccounts(ledgerId);
      final cats = await db.loadCategories(ledgerId, 'out');
      catsOut = cats.map((c) => c.id).toList();
      Future<void> add(String note, int minor, String catId) =>
          db.insertManualTransaction(
            ledgerId: ledgerId,
            type: 'out',
            amountMinor: minor,
            currency: 'CNY',
            accountId: accounts.first.id,
            categoryId: catId,
            note: note,
          );
      await add('午餐 公司楼下', 2500, catsOut.first);
      await add('午餐 支付宝', 1800, catsOut.first);
      await add('打车 支付宝', 3000, catsOut.first);
      await add('Shopee order', 9000, catsOut.last);
      await add('商飞出差', 12000, catsOut.first);
      await add('羽毛球馆', 2800, catsOut.first);
    });

    tearDown(() async => db.close());

    Future<List<String>> notes(String q) async {
      final rows = await db.searchTransactions(ledgerId, q);
      return [for (final r in rows) (r.note ?? '')];
    }

    test('single keyword matches note substrings', () async {
      expect((await notes('午餐')).length, 2);
    });

    test('space-separated keywords are ORed', () async {
      final hit = await notes('商飞 羽毛球');
      expect(hit.toSet(), {'商飞出差', '羽毛球馆'});
    });

    test('OR returns union of each keyword', () async {
      final hit = await notes('午餐 支付宝');
      expect(hit.toSet(), {
        '午餐 公司楼下',
        '午餐 支付宝',
        '打车 支付宝',
      });
    });

    test('full-width space separates keywords too', () async {
      final hit = await notes('商飞\u3000羽毛球');
      expect(hit.toSet(), {'商飞出差', '羽毛球馆'});
    });

    test('keyword is case-insensitive', () async {
      expect((await notes('shopee')).length, 1);
      expect((await notes('shopee order')).length, 1);
    });

    test('amount keyword matches exact amount among OR tokens', () async {
      final rows = await db.searchTransactions(ledgerId, '支付宝 18');
      expect(
        rows.map((r) => r.amountMinor).toSet(),
        {1800, 3000},
        reason: '18 → 1800 与「支付宝」两条都应命中',
      );
    });

    test('keyword plus category filter still applies', () async {
      final rows = await db.searchTransactions(
        ledgerId,
        '支付宝',
        categoryId: catsOut.last,
      );
      expect(rows, isEmpty);
    });

    test('category-name token does not leak onto other tokens', () async {
      final catId = catsOut.first;
      await (db.update(db.categories)..where((t) => t.id.equals(catId))).write(
        const CategoriesCompanion(name: Value('羽毛球')),
      );
      // 「商飞」 alone must not match every 羽毛球-category row via leaked catHits.
      final onlyShangfei = await notes('商飞');
      expect(onlyShangfei, ['商飞出差']);
    });
  });
}

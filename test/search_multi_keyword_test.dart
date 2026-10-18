import 'package:centli/data/db/centli_database.dart';
import 'package:centli/core/widgets/txn_list_tile.dart';
import 'package:centli/features/ledger/search_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Search: space-separated AND keywords, keyword chips, row highlighting.
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
      Future<void> add(String note, int minor, String catId) => db.insertManualTransaction(
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
    });

    tearDown(() async => db.close());

    Future<List<String>> notes(String q) async {
      final rows = await db.searchTransactions(ledgerId, q);
      return [for (final r in rows) (r.note ?? '')];
    }

    test('single keyword matches note substrings', () async {
      expect((await notes('午餐')).length, 2);
    });

    test('space-separated keywords are ANDed', () async {
      final hit = await notes('午餐 支付宝');
      expect(hit, ['午餐 支付宝']);
      // The AND must not degrade to OR.
      expect(hit.contains('打车 支付宝'), isFalse);
    });

    test('full-width space separates keywords too', () async {
      expect(await notes('午餐\u3000支付宝'), ['午餐 支付宝']);
    });

    test('three keywords all must hit', () async {
      expect(await notes('午餐 支付宝 楼下'), isEmpty);
      expect(await notes('午餐 公司 楼下'), ['午餐 公司楼下']);
    });

    test('keyword is case-insensitive', () async {
      expect((await notes('shopee')).length, 1);
      expect((await notes('shopee order')).length, 1);
    });

    test('amount keyword narrows by exact amount', () async {
      final rows = await db.searchTransactions(ledgerId, '支付宝 18');
      expect(rows.map((r) => r.amountMinor), [1800]);
    });

    test('keyword plus category filter still applies', () async {
      final rows = await db.searchTransactions(
        ledgerId,
        '支付宝',
        categoryId: catsOut.last,
      );
      expect(rows, isEmpty);
    });
  });
}

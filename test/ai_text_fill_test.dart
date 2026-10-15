import 'package:centli/features/ledger/ai_text_fill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cats = ['餐饮', '交通', '日用', '居住', '娱乐', '医疗', '教育', '其他', '工资', '红包', '理财'];
  const accounts = ['现金', '支付宝', '微信'];
  final now = DateTime(2026, 10, 14, 15, 30);

  group('parseBookkeepingText', () {
    test('lunch expense with amount and category', () {
      final r = parseBookkeepingText(
        '午餐花了28.5',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.type, 'out');
      expect(r.amount, 28.5);
      expect(r.categoryName, '餐饮');
      expect(r.hasConfidentCategory, isTrue);
      expect(r.hasUsefulFill, isTrue);
      // Must NOT dump whole input into note.
      expect(r.note, isNot('午餐花了28.5'));
    });

    test('metro with yuan unit', () {
      final r = parseBookkeepingText(
        '地铁 4元',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.type, 'out');
      expect(r.amount, 4);
      expect(r.categoryName, '交通');
      expect(r.note, isNull);
    });

    test('salary income', () {
      final r = parseBookkeepingText(
        '收到工资8000',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.type, 'in');
      expect(r.amount, 8000);
      expect(r.categoryName, '工资');
    });

    test('transfer between accounts', () {
      final r = parseBookkeepingText(
        '支付宝转到微信100',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.type, 'transfer');
      expect(r.amount, 100);
      expect(r.accountName, '支付宝');
      expect(r.toAccountName, '微信');
    });

    test('yesterday + alipay account', () {
      final r = parseBookkeepingText(
        '昨天支付宝买咖啡32',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.type, 'out');
      expect(r.amount, 32);
      expect(r.categoryName, '餐饮');
      expect(r.accountName, '支付宝');
      expect(r.happenAt?.year, 2026);
      expect(r.happenAt?.month, 10);
      expect(r.happenAt?.day, 13);
    });

    test('merchant via 在', () {
      final r = parseBookkeepingText(
        '在星巴克花了35元',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.amount, 35);
      expect(r.merchant, '星巴克');
      expect(r.categoryName, '餐饮');
      expect(r.note, isNot('在星巴克花了35元'));
    });

    test('empty input', () {
      final r = parseBookkeepingText('  ');
      expect(r.hasUsefulFill, isFalse);
    });

    test('currency symbol amount', () {
      final r = parseBookkeepingText(
        '超市购物￥56.8',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.amount, 56.8);
      expect(r.categoryName, '日用');
    });

    test('amount-only leaves category unset', () {
      final r = parseBookkeepingText(
        '花了88',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.amount, 88);
      expect(r.type, 'out');
      expect(r.hasConfidentCategory, isFalse);
      expect(r.categoryName, isNull);
      expect(r.note, isNull);
    });

    test('waimai maps to dining', () {
      final r = parseBookkeepingText(
        '美团外卖 42',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.amount, 42);
      expect(r.categoryName, '餐饮');
      expect(r.merchant, '美团');
    });

    test('rent maps to housing', () {
      final r = parseBookkeepingText(
        '房租3000',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.amount, 3000);
      expect(r.categoryName, '居住');
    });

    test('prefers leaf category when tree provided', () {
      final refs = [
        const CategoryRef(name: '餐饮', id: 'p1', kind: 'out'),
        const CategoryRef(name: '外卖', id: 'c1', parentId: 'p1', kind: 'out'),
        const CategoryRef(name: '交通', id: 'p2', kind: 'out'),
      ];
      final r = parseBookkeepingText(
        '外卖35',
        categories: refs,
        accountNames: accounts,
        now: now,
      );
      expect(r.categoryName, '外卖');
      expect(r.hasConfidentCategory, isTrue);
    });

    test('leftover remark kept as note', () {
      final r = parseBookkeepingText(
        '午餐花了28.5 和同事聚餐',
        categoryNames: cats,
        accountNames: accounts,
        now: now,
      );
      expect(r.amount, 28.5);
      expect(r.categoryName, '餐饮');
      expect(r.note, isNotNull);
      expect(r.note!.contains('同事'), isTrue);
      expect(r.note, isNot(contains('28.5')));
    });

    test('mapCategoryHintToLocal fuzzy', () {
      expect(
        mapCategoryHintToLocal('餐饮美食', categoryNames: cats),
        '餐饮',
      );
      expect(
        mapCategoryHintToLocal('地铁出行', categoryNames: cats),
        '交通',
      );
      expect(
        mapCategoryHintToLocal('完全没听说过的类', categoryNames: cats),
        isNull,
      );
    });
  });
}

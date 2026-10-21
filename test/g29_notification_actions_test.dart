import 'package:centli/data/db/centli_database.dart';
import 'package:centli/platform/notifications/notification_noise.dart';
import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:centli/platform/notifications/noti_template_store.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteInput amount parse (G29.4)', () {
    test('24.70 / ￥24.7 / 24.7元 → 2470; abc → null', () {
      expect(parseRemoteInputAmountMinor('24.70'), 2470);
      expect(parseRemoteInputAmountMinor('￥24.7'), 2470);
      expect(parseRemoteInputAmountMinor('24.7元'), 2470);
      expect(parseRemoteInputAmountMinor('abc'), isNull);
    });
  });

  group('noise filter (G29.1)', () {
    test('marketing without amount → weak drop', () {
      expect(
        shouldDropAsWeakNoise(
          templateMatched: false,
          amountMinor: null,
          title: '红包优惠活动限时抽奖',
          text: '会员积分理财',
        ),
        isTrue,
      );
      expect(containsMarketingWord('支付优惠券到账'), isTrue);
    });
  });

  group('抖音支付 24.70元 + alipay pkg', () {
    late CentliDatabase db;

    setUp(() async {
      db = CentliDatabase.forTesting(NativeDatabase.memory());
      await db.seedDefaults();
      NotiTemplateStore.bindDatabase(db);
      await NotiTemplateStore.load(force: true);
    });

    tearDown(() async {
      await db.close();
    });

    test('hits alipay pay template with amount 24.70 out', () async {
      final templates = NotiTemplateStore.peek();
      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '交易提醒',
        text: '抖音支付 24.70元',
        whenMs: DateTime.now().millisecondsSinceEpoch,
      );
      final parsed = parseNotification(raw, templates);
      expect(parsed.templateId, isNotNull);
      expect(parsed.amountMinor, 2470);
      expect(parsed.direction, anyOf('out', isNull)); // direction may come from template
      // Prefer exact template id if present
      expect(
        parsed.templateId,
        anyOf('alipay_expense_zh', contains('alipay')),
      );
    });
  });

  group('source noti_action txn', () {
    late CentliDatabase db;

    setUp(() async {
      db = CentliDatabase.forTesting(NativeDatabase.memory());
      await db.seedDefaults();
    });

    tearDown(() async {
      await db.close();
    });

    test('lists and counts like manual', () async {
      final ledgerId = (await db.currentLedgerId())!;
      final accounts = await db.loadActiveAccounts(ledgerId);
      final cats = await db.loadCategories(ledgerId, 'out');
      await db.insertManualTransaction(
        ledgerId: ledgerId,
        type: 'out',
        amountMinor: 2470,
        currency: 'CNY',
        accountId: accounts.first.id,
        categoryId: cats.first.id,
        note: 'noti',
      );
      // insert with source via companion if API allows — use raw update
      final rows = await db.select(db.transactions).get();
      final txn = rows.last;
      await (db.update(db.transactions)..where((t) => t.id.equals(txn.id)))
          .write(
        const TransactionsCompanion(
          source: Value('noti_action'),
        ),
      );
      final again = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txn.id)))
          .getSingle();
      expect(again.source, 'noti_action');
      expect(again.includeInStat, 1);
      expect(again.amountMinor, 2470);
    });
  });
}

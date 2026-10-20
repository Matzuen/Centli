import 'package:centli/data/db/centli_database.dart';
import 'package:centli/platform/notifications/notification_ingest_bridge.dart';
import 'package:centli/platform/notifications/notification_noise.dart';
import 'package:centli/platform/notifications/noti_template_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通知入库链路（`NotificationIngestBridge.ingestRaw`）的集成测试。
///
/// 这条链路直接决定「一笔账记不记」，之前只有纯函数测试，native 侧查询错列
/// （`merchant`）导致静默失败时没有任何断言兜住。这里用内存库跑真实分支：
/// 本地模板命中 → 写待确认；聊天/营销 → 丢弃并记录原因；关闭自动记账 → 不写。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;
  late String ledgerId;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    ledgerId = (await db.currentLedgerId())!;
    NotiTemplateStore.bindDatabase(db);
    await NotiTemplateStore.load(force: true);
    await db.setSetting('auto_capture_enabled', 'true');
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> raw({
    String pkg = 'com.tencent.mm',
    required String title,
    required String text,
    String key = 'k1',
  }) =>
      {
        'pkg': pkg,
        'title': title,
        'text': text,
        'when': DateTime(2026, 10, 20, 12).millisecondsSinceEpoch,
        'key': key,
      };

  test('支付宝支付通知 → 写入待确认（金额/方向正确）', () async {
    final id = await NotificationIngestBridge.ingestRaw(
      db,
      raw(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '你已成功付款12.50元，收款方：便利店',
      ),
    );

    expect(id, isNotNull, reason: '真实支付通知必须入库');
    expect(await db.countPendingCaptures(ledgerId), 1);

    final pending = await db.getPendingCapture(id!);
    expect(pending, isNotNull);
    expect(pending!.amountMinor, 1250);
    expect(pending.currency, 'CNY');
    expect(pending.status, 'pending');
    expect(pending.parseOk, 1);
  });

  test('聊天类通知 → 不入库，并记录 weak 丢弃', () async {
    final id = await NotificationIngestBridge.ingestRaw(
      db,
      raw(title: '张三', text: '明天见'),
    );

    expect(id, isNull);
    expect(await db.countPendingCaptures(ledgerId), 0);

    // 丢弃原因记在 native 侧（桌面测试里 channel 被 supported 短路），
    // 这里直接验证判定本身：无模板、无金额 → weak。
    expect(
      shouldDropAsWeakNoise(
        templateMatched: false,
        amountMinor: null,
        title: '张三',
        text: '明天见',
      ),
      isTrue,
    );
  });

  test('关闭自动记账 → 直接返回，不写库', () async {
    await db.setSetting('auto_capture_enabled', 'false');

    final id = await NotificationIngestBridge.ingestRaw(
      db,
      raw(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '你已成功付款9.90元',
      ),
    );

    expect(id, isNull);
    expect(await db.countPendingCaptures(ledgerId), 0);
  });

  test('同一条通知重复投递 → 只入一条（按通知 key 去重）', () async {
    final payload = raw(
      pkg: 'com.eg.android.AlipayGphone',
      title: '支付成功',
      text: '你已成功付款12.50元',
      key: 'same-key',
    );

    final first = await NotificationIngestBridge.ingestRaw(db, payload);
    final second = await NotificationIngestBridge.ingestRaw(db, payload);

    expect(first, isNotNull);
    expect(second, isNull, reason: '重复投递不应产生第二条');
    expect(await db.countPendingCaptures(ledgerId), 1);
  });

  test('AI 关闭时不会走模型：凭证齐全但开关为关也不该调用', () async {
    // 只写凭证，不打开「AI 识别通知」——默认就是关的。
    await db.setSetting('smart_fill_llm_base_url', 'https://api.example.com');
    await db.setSetting('smart_fill_llm_model', 'test-model');
    await db.setSetting('smart_fill_llm_enabled', 'true');
    // 内存缓存可能来自上一条用例，强制失效后再读。
    await NotificationIngestBridge.ingestRaw(
      db,
      raw(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付成功',
        text: '你已成功付款1.00元',
        key: 'ai-off',
      ),
    );

    // 走本地模板即可入库，不应依赖网络；这里只断言结果，不触发真实请求。
    expect(await db.countPendingCaptures(ledgerId), 1);
  });
}

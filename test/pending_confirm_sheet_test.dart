import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/pending/pending_confirm_sheet.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页「待确认」卡片 + 确认入账弹窗。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;
  late String ledgerId;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    ledgerId = ledger.id;
  });

  tearDown(() async => db.close());

  Future<PendingCapture> seedPending({
    String pkg = 'com.eg.android.AlipayGphone',
    String title = '支付成功',
    String text = '向 星巴克 付款 ¥28.50',
    int? amountMinor = 2850,
    String? direction = 'out',
  }) async {
    await db.ingestParsedNotification(
      ledgerId: ledgerId,
      sourcePkg: pkg,
      rawTitle: title,
      rawText: text,
      dedupeKey: 'k-${DateTime.now().microsecondsSinceEpoch}',
      amountMinor: amountMinor,
      merchant: '星巴克',
      parseOk: amountMinor != null,
      accountHint: pkg.contains('Alipay') ? 'alipay' : 'wechat',
      direction: direction ?? 'out',
    );
    final list = await db.loadPendingCapturesForExport(ledgerId);
    return list.firstWhere((p) => p.status == 'pending');
  }

  group('labels', () {
    test('direction labels', () {
      expect(pendingDirectionLabel('out'), '支出');
      expect(pendingDirectionLabel('in'), '收入');
      expect(pendingDirectionLabel('refund'), '退款');
      expect(pendingDirectionLabel('repay'), '还款');
      expect(pendingDirectionLabel(null), '支出');
    });

    test('source labels', () {
      expect(pendingSourceLabel('com.eg.android.AlipayGphone'), '支付宝');
      expect(pendingSourceLabel('com.tencent.mm'), '微信');
      expect(pendingSourceLabel('com.other'), 'com.other');
    });
  });

  Future<void> pumpDialog(
    WidgetTester tester,
    PendingCapture capture,
  ) async {
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(400 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CentliTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: Builder(
                  builder: (inner) => FilledButton(
                    onPressed: () =>
                        showPendingConfirmDialog(inner, ref, capture: capture),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('open'));
    // The dialog loads categories/accounts before opening.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('dialog prefills amount and submits a transaction',
      (tester) async {
    final capture = await seedPending();
    await pumpDialog(tester, capture);

    expect(find.text('确认入账'), findsOneWidget);
    final amountField =
        tester.widget<TextField>(find.byKey(const Key('confirm_pending_amount')));
    expect(amountField.controller!.text, '28.50');
    expect(find.text('支出'), findsWidgets);

    await tester.tap(find.byKey(const Key('confirm_pending_submit')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final rows = await db.loadTransactionsForExport(ledgerId);
    expect(rows, hasLength(1), reason: 'one booked transaction');
    expect(rows.single.amountMinor, 2850);
    expect(rows.single.type, 'out');
    // The capture is confirmed, so it leaves the pending list.
    final all = await db.loadPendingCapturesForExport(ledgerId);
    expect(
      all.firstWhere((p) => p.id == capture.id).status,
      'confirmed',
    );
  });

  testWidgets('typed amount overrides the parsed one', (tester) async {
    final capture = await seedPending();
    await pumpDialog(tester, capture);

    await tester.enterText(
      find.byKey(const Key('confirm_pending_amount')),
      '31.20',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm_pending_submit')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final rows = await db.loadTransactionsForExport(ledgerId);
    expect(rows.single.amountMinor, 3120);
  });

  testWidgets('income notice defaults to an income category', (tester) async {
    final capture = await seedPending(
      title: '收款到账',
      text: '收到一笔转账 ¥200.00',
      amountMinor: 20000,
      direction: 'in',
    );
    await pumpDialog(tester, capture);
    expect(find.text('收入'), findsWidgets);
    await tester.tap(find.byKey(const Key('confirm_pending_submit')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final rows = await db.loadTransactionsForExport(ledgerId);
    expect(rows.single.type, 'in');
    expect(rows.single.amountMinor, 20000);
  });

  testWidgets('invalid amount is rejected without booking', (tester) async {
    final capture = await seedPending();
    await pumpDialog(tester, capture);
    await tester.enterText(
      find.byKey(const Key('confirm_pending_amount')),
      '0',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm_pending_submit')));
    await tester.pump();
    final rows = await db.loadTransactionsForExport(ledgerId);
    expect(rows, isEmpty);
  });
}

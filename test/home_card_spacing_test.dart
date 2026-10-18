import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/home/home_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页概览区的卡片间距必须一致。
///
/// 曾经的 bug：待确认区块在空列表时渲染成 `SizedBox.shrink()`，但它两侧的
/// 两个 `SizedBox` 间距仍然存在，导致概览卡→图表是 16+16=32，而图表→账单
/// 只有 16，视觉上那张图表卡像被单独隔开了。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
  });

  tearDown(() async => db.close());

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: CentliTheme.light(),
          home: const HomePage(),
        ),
      ),
    );
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  List<double> cardGaps(WidgetTester tester) {
    final cards = find.byType(CentliSoftCard);
    final count = tester.widgetList(cards).length;
    final gaps = <double>[];
    for (var i = 1; i < count; i++) {
      gaps.add(
        tester.getRect(cards.at(i)).top -
            tester.getRect(cards.at(i - 1)).bottom,
      );
    }
    return gaps;
  }

  testWidgets('cards are evenly spaced when there is nothing pending',
      (tester) async {
    await pumpHome(tester);
    final gaps = cardGaps(tester);
    expect(gaps.length, greaterThanOrEqualTo(2), reason: 'need 3+ cards');
    for (final g in gaps) {
      expect(g, closeTo(gaps.first, 0.5), reason: 'gaps: $gaps');
    }
  });

  testWidgets('a pending item does not change the surrounding rhythm',
      (tester) async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await db.ingestParsedNotification(
      ledgerId: ledger.id,
      sourcePkg: 'com.eg.android.AlipayGphone',
      rawTitle: '支付成功',
      rawText: '向 星巴克 付款 ¥28.50',
      dedupeKey: 'pending-spacing',
      amountMinor: 2850,
      parseOk: true,
      direction: 'out',
    );
    await pumpHome(tester);
    // The carousel lives inside its own card; every card-to-card gap must
    // still be identical.
    final gaps = cardGaps(tester);
    expect(gaps.length, greaterThanOrEqualTo(2));
    for (final g in gaps) {
      expect(g, closeTo(gaps.first, 0.5), reason: 'gaps: $gaps');
    }
    // The pending card actually appeared.
    expect(find.byKey(const Key('home_pending_carousel')), findsOneWidget);
  });
}

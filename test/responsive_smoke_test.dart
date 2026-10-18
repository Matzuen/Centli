import 'package:centli/app/theme.dart';
import 'package:centli/data/db/centli_database.dart';
import 'package:centli/data/db/database_provider.dart';
import 'package:centli/features/assets/asset_types_page.dart';
import 'package:centli/features/assets/assets_page.dart';
import 'package:centli/features/home/home_page.dart';
import 'package:centli/features/ledger/ledger_detail_page.dart';
import 'package:centli/features/ledger/search_page.dart';
import 'package:centli/features/pending/pending_page.dart';
import 'package:centli/features/recurring/recurring_list_page.dart';
import 'package:centli/features/settings/about_page.dart';
import 'package:centli/features/settings/budget_page.dart';
import 'package:centli/features/settings/categories_page.dart';
import 'package:centli/features/settings/export_page.dart';
import 'package:centli/features/settings/fx_rates_page.dart';
import 'package:centli/features/settings/recycle_bin_page.dart';
import 'package:centli/features/stats/stats_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 窄屏冒烟：主要页面在 320dp 宽 + 大字号下渲染，不允许出现
/// RenderFlex overflow / RenderBox 断言。
///
/// 这类溢出在真机上表现为黄黑条纹，是最容易漏掉的展示问题。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CentliDatabase db;

  setUp(() async {
    db = CentliDatabase.forTesting(NativeDatabase.memory());
    await db.seedDefaults();
  });

  tearDown(() async => db.close());

  /// Seed one transaction with a long note so text-ellipsis paths are hit.
  Future<void> seedTxn(String ledgerId) async {
    final accounts = await db.loadActiveAccounts(ledgerId);
    final cats = await db.loadCategories(ledgerId, 'out');
    if (accounts.isEmpty || cats.isEmpty) return;
    await db.insertManualTransaction(
      ledgerId: ledgerId,
      type: 'out',
      amountMinor: 123456789, // ¥1,234,567.89 — very wide for a phone
      currency: 'CNY',
      accountId: accounts.first.id,
      categoryId: cats.first.id,
      note: '这是一条非常非常长的备注文字用来测试文本截断是否正常工作不会溢出',
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    double width = 320,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = Size(width * 3, 2400 * 3);
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    );
    // Drift streams settle over several frames; pumpAndSettle would hang.
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  final pages = <String, Widget Function(String ledgerId)>{
    'assets': (_) => const AssetsPage(),
    'asset types': (_) => const AssetTypesPage(),
    'search': (_) => const SearchPage(),
    'pending': (_) => const PendingPage(),
    'stats': (_) => const StatsPage(),
    'recycle bin': (_) => const RecycleBinPage(),
    'categories': (_) => const CategoriesPage(),
    'budget': (_) => const BudgetPage(),
    'recurring': (_) => const RecurringListPage(),
    'fx rates': (_) => const FxRatesPage(),
    'export': (_) => const ExportPage(),
    'about': (_) => const AboutPage(),
  };

  pages.forEach((label, build) {
    testWidgets('$label fits a 320dp wide screen', (tester) async {
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      await seedTxn(ledger.id);
      await pumpPage(tester, build(ledger.id));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('home fits a 320dp wide screen', (tester) async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await seedTxn(ledger.id);
    await pumpPage(tester, const HomePage());
    expect(tester.takeException(), isNull);
  });

  testWidgets('ledger detail fits a 320dp wide screen', (tester) async {
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    await seedTxn(ledger.id);
    final txns = await db.loadTransactionsForExport(ledger.id);
    await pumpPage(tester, LedgerDetailPage(transactionId: txns.first.id));
    expect(tester.takeException(), isNull);
  });

  group('200% text scale (accessibility)', () {
    testWidgets('home does not overflow', (tester) async {
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      await seedTxn(ledger.id);
      await pumpPage(tester, const HomePage(), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stats does not overflow', (tester) async {
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      await seedTxn(ledger.id);
      await pumpPage(tester, const StatsPage(), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('assets does not overflow', (tester) async {
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      await seedTxn(ledger.id);
      await pumpPage(tester, const AssetsPage(), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });
}

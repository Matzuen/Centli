import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/ledger/quick_bookkeeping_sheet.dart';
import 'package:centli/features/ledger/smart_bookkeeping_submit.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: QuickBookkeepingSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('text-only panel: title, no voice UI', (tester) async {
    await pumpSheet(tester);
    expect(find.text('快速记账'), findsOneWidget);
    expect(find.text('语音记账'), findsNothing);
    // Voice was removed: no hold-to-talk bar and no microphone affordance.
    expect(find.byKey(const ValueKey('hold_talk_bar')), findsNothing);
    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.textContaining('按住'), findsNothing);
  });

  testWidgets('typing shows submit actions', (tester) async {
    await pumpSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('quick_bk_text')),
      '午餐28.5',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('quick_bk_submit')), findsOneWidget);
    expect(find.text('记账并继续'), findsOneWidget);
  });

  testWidgets('empty submit shows a hint instead of inserting', (tester) async {
    await pumpSheet(tester);
    await tester.enterText(find.byKey(const ValueKey('quick_bk_text')), '  ');
    await tester.pump();
    // Nothing typed → no submit button offered.
    expect(find.byKey(const ValueKey('quick_bk_submit')), findsNothing);
  });

  test('typed text submits a transaction', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    final outcome = await submitSmartBookkeepingText(
      db: db,
      rawText: '午餐28.5',
      ledgerId: ledger.id,
      accounts: accounts,
    );
    expect(outcome.ok, isTrue, reason: outcome.errorMessage);
    final rows = await db.loadTransactionsForExport(ledger.id);
    expect(rows.any((txn) => txn.amountMinor == 2850), isTrue);
  });
}

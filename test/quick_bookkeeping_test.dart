import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/ledger/local_speech.dart';
import 'package:centli/features/ledger/quick_bookkeeping_sheet.dart';
import 'package:centli/features/ledger/smart_bookkeeping_submit.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSpeech implements VoiceSpeechBackend {
  var ensureReadyResult = true;
  String? friendlyErrorOverride;
  final starts = <DateTime>[];
  final stops = <DateTime>[];
  final cancels = <DateTime>[];
  void Function(LocalSpeechResult result)? _onResult;
  String? emitOnStart;
  var startCalls = 0;

  @override
  String? get friendlyError => friendlyErrorOverride;

  @override
  set onStatusChanged(void Function(String status)? cb) {}

  @override
  set onSoundLevel(void Function(double level)? cb) {}

  @override
  set onErrorMessage(void Function(String message)? cb) {}

  @override
  Future<bool> ensureReady({String localeId = 'zh_CN'}) async =>
      ensureReadyResult;

  @override
  Future<void> start({
    required void Function(LocalSpeechResult result) onResult,
    String? localeId,
  }) async {
    startCalls++;
    starts.add(DateTime.now());
    _onResult = onResult;
    final t = emitOnStart;
    if (t != null) {
      onResult(LocalSpeechResult(text: t, finalResult: false));
    }
  }

  @override
  Future<void> stop() async {
    stops.add(DateTime.now());
    final t = emitOnStart;
    if (t != null && _onResult != null) {
      _onResult!(LocalSpeechResult(text: t, finalResult: true));
    }
  }

  @override
  Future<void> cancel() async {
    cancels.add(DateTime.now());
  }
}

void main() {
  test('HoldTalkPhysics cancel zone and min hold', () {
    expect(
      HoldTalkPhysics.isCancelZone(startY: 400, currentY: 330),
      isTrue,
    );
    expect(
      HoldTalkPhysics.isCancelZone(startY: 400, currentY: 350),
      isFalse,
    );
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    expect(
      HoldTalkPhysics.isTooShort(t0, t0.add(const Duration(milliseconds: 400))),
      isTrue,
    );
    expect(
      HoldTalkPhysics.isTooShort(t0, t0.add(const Duration(milliseconds: 600))),
      isFalse,
    );
  });

  testWidgets('title is 快速记账', (tester) async {
    final fake = FakeSpeech();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QuickBookkeepingSheet(speech: fake),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('快速记账'), findsOneWidget);
    expect(find.text('语音记账'), findsNothing);
  });

  testWidgets('hold then release fills text; cancel discards', (tester) async {
    final fake = FakeSpeech()..emitOnStart = '午饭三十元';
    var clock = DateTime(2026, 6, 1, 12, 0, 0);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QuickBookkeepingSheet(
              speech: fake,
              now: () => clock,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byKey(const ValueKey('hold_talk_bar'));
    expect(bar, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(bar));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.startCalls, greaterThan(0));
    expect(find.text('松开 结束'), findsOneWidget);

    clock = clock.add(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(fake.stops, isNotEmpty);
    expect(find.text('午饭三十元'), findsWidgets);
    expect(fake.cancels, isEmpty);

    fake.emitOnStart = '应被丢弃';
    final g2 = await tester.startGesture(tester.getCenter(bar));
    await tester.pump();
    await g2.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(find.text('松开 取消'), findsOneWidget);
    clock = clock.add(const Duration(milliseconds: 800));
    await g2.up();
    await tester.pumpAndSettle();
    expect(fake.cancels, isNotEmpty);
    expect(find.text('应被丢弃'), findsNothing);
    expect(find.text('午饭三十元'), findsWidgets);
  });

  testWidgets('too-short hold shows tip and cancels', (tester) async {
    final fake = FakeSpeech()..emitOnStart = '短';
    var clock = DateTime(2026, 6, 1, 12, 0, 0);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QuickBookkeepingSheet(
              speech: fake,
              now: () => clock,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('hold_talk_bar'));
    final gesture = await tester.startGesture(tester.getCenter(bar));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.textContaining('太短'), findsOneWidget);
    expect(fake.cancels, isNotEmpty);
  });

  testWidgets('dispose cancels speech', (tester) async {
    final fake = FakeSpeech()..emitOnStart = 'x';
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QuickBookkeepingSheet(speech: fake),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = find.byKey(const ValueKey('hold_talk_bar'));
    await tester.startGesture(tester.getCenter(bar));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(fake.cancels, isNotEmpty);
  });

  testWidgets('type text shows submit actions', (tester) async {
    final fake = FakeSpeech();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QuickBookkeepingSheet(speech: fake),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('快速记账'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '午餐28.5');
    await tester.pump();
    expect(find.text('记账并关闭'), findsOneWidget);
    expect(find.text('记账并继续'), findsOneWidget);
  });

  testWidgets('recognize then edit text field', (tester) async {
    final fake = FakeSpeech()..emitOnStart = '咖啡15';
    var clock = DateTime(2026, 6, 1, 12, 0, 0);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: QuickBookkeepingSheet(
              speech: fake,
              now: () => clock,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bar = find.byKey(const ValueKey('hold_talk_bar'));
    final gesture = await tester.startGesture(tester.getCenter(bar));
    await tester.pump();
    clock = clock.add(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('咖啡15'), findsWidgets);

    await tester.enterText(find.byType(TextField), '咖啡25元');
    await tester.pump();
    expect(find.text('咖啡25元'), findsWidgets);
    expect(find.text('记账并继续'), findsOneWidget);
  });

  test('direct typed text submits transaction', () async {
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

  test('edited recognized text submits transaction', () async {
    final db = CentliDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.seedDefaults();
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
    final accounts = await db.loadActiveAccounts(ledger.id);
    // Simulate: recognized '咖啡15', user edits to '咖啡25.0' then submits.
    final outcome = await submitSmartBookkeepingText(
      db: db,
      rawText: '咖啡25.0',
      ledgerId: ledger.id,
      accounts: accounts,
    );
    expect(outcome.ok, isTrue, reason: outcome.errorMessage);
    final rows = await db.loadTransactionsForExport(ledger.id);
    expect(rows.any((txn) => txn.amountMinor == 2500), isTrue);
  });
}

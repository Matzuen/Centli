import 'package:centli/features/ledger/local_speech.dart';
import 'package:centli/features/ledger/voice_bookkeeping_sheet.dart';
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

  testWidgets('hold then release fills text; cancel discards', (tester) async {
    final fake = FakeSpeech()..emitOnStart = '午饭三十元';
    var clock = DateTime(2026, 6, 1, 12, 0, 0);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: VoiceBookkeepingSheet(
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
            body: VoiceBookkeepingSheet(
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
    // clock unchanged -> too short
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
            body: VoiceBookkeepingSheet(speech: fake),
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
}

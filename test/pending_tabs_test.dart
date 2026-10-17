import 'package:centli/data/db/centli_database.dart';
import 'package:centli/features/pending/pending_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pending tabs partition invariant', () {
    late CentliDatabase db;
    late String ledgerId;

    setUp(() async {
      db = CentliDatabase.forTesting(NativeDatabase.memory());
      await db.seedDefaults();
      final ledger = await (db.select(db.ledgers)..limit(1)).getSingle();
      ledgerId = ledger.id;
    });

    tearDown(() async {
      await db.close();
    });

    Future<String> insertCapture({
      required String status,
      required int parseOk,
      required String dedupeSuffix,
    }) async {
      final id = await db.ingestParsedNotification(
        ledgerId: ledgerId,
        sourcePkg: 'manual:test',
        rawText: 'body $dedupeSuffix',
        dedupeKey: 't0a-part-$dedupeSuffix',
        amountMinor: parseOk == 1 ? 100 : null,
        currency: 'CNY',
        merchant: 'm',
        parseOk: parseOk == 1,
      );
      expect(id, isNotNull);
      if (status != 'pending') {
        await (db.update(db.pendingCaptures)
              ..where((t) => t.id.equals(id!)))
            .write(
          PendingCapturesCompanion(
            status: Value(status),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
      }
      return id!;
    }

    test('four tabs disjoint and union equals all rows', () async {
      final okId = await insertCapture(
        status: 'pending',
        parseOk: 1,
        dedupeSuffix: 'ok',
      );
      final failId = await insertCapture(
        status: 'pending',
        parseOk: 0,
        dedupeSuffix: 'fail',
      );
      final ignoredId = await insertCapture(
        status: 'ignored',
        parseOk: 1,
        dedupeSuffix: 'ign',
      );
      final confirmedId = await insertCapture(
        status: 'confirmed',
        parseOk: 0, // badge would have been wrong before T0A-2
        dedupeSuffix: 'conf',
      );
      // Unknown status must land in confirmed tab (NOT IN pending/ignored).
      final weirdId = await insertCapture(
        status: 'weird',
        parseOk: 1,
        dedupeSuffix: 'weird',
      );

      final pending = await db.watchPendingOkCaptures(ledgerId).first;
      final failed = await db.watchParseFailedCaptures(ledgerId).first;
      final ignored = await db.watchPendingCaptures(ledgerId, status: 'ignored').first;
      final confirmed = await db.watchConfirmedCaptures(ledgerId).first;
      final all = await (db.select(db.pendingCaptures)
            ..where((t) => t.ledgerId.equals(ledgerId)))
          .get();

      final pendingIds = pending.map((e) => e.id).toSet();
      final failedIds = failed.map((e) => e.id).toSet();
      final ignoredIds = ignored.map((e) => e.id).toSet();
      final confirmedIds = confirmed.map((e) => e.id).toSet();
      final allIds = all.map((e) => e.id).toSet();

      expect(pendingIds, {okId});
      expect(failedIds, {failId});
      expect(ignoredIds, {ignoredId});
      expect(confirmedIds, {confirmedId, weirdId});

      // Pairwise disjoint.
      final sets = [pendingIds, failedIds, ignoredIds, confirmedIds];
      for (var i = 0; i < sets.length; i++) {
        for (var j = i + 1; j < sets.length; j++) {
          expect(
            sets[i].intersection(sets[j]),
            isEmpty,
            reason: 'tabs $i and $j must be disjoint',
          );
        }
      }

      // Union == all.
      final union = pendingIds
          .union(failedIds)
          .union(ignoredIds)
          .union(confirmedIds);
      expect(union, allIds);
      expect(union.length, allIds.length);
    });
  });

  group('pending badge status priority', () {
    test('confirmed + parseOk=0 shows 已入账', () {
      expect(
        pendingCaptureBadgeLabel(status: 'confirmed', parseOk: 0),
        '\u5df2\u5165\u8d26',
      );
    });

    test('pending + parseOk=0 shows 解析失败', () {
      expect(
        pendingCaptureBadgeLabel(status: 'pending', parseOk: 0),
        '\u89e3\u6790\u5931\u8d25',
      );
    });

    test('ignored shows 已忽略 even if parseOk=0', () {
      expect(
        pendingCaptureBadgeLabel(status: 'ignored', parseOk: 0),
        '\u5df2\u5ffd\u7565',
      );
    });

    test('pending + parseOk=1 has no badge', () {
      expect(
        pendingCaptureBadgeLabel(status: 'pending', parseOk: 1),
        isNull,
      );
    });
  });

  group('pending segmented control 320dp', () {
    testWidgets('four labels fit without overflow; width stable across tabs',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selected = 'pending';

      Future<void> pumpAt(String tab) async {
        selected = tab;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 320 - 32, // pageH padding approx both sides
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      return SegmentedButton<String>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 'pending',
                            label: Text('\u5f85\u786e\u8ba4'),
                          ),
                          ButtonSegment(
                            value: 'parse_failed',
                            label: Text('\u89e3\u6790\u5931\u8d25'),
                          ),
                          ButtonSegment(
                            value: 'ignored',
                            label: Text('\u5df2\u5ffd\u7565'),
                          ),
                          ButtonSegment(
                            value: 'confirmed',
                            label: Text('\u5df2\u5165\u8d26'),
                          ),
                        ],
                        selected: {selected},
                        onSelectionChanged: (s) {
                          setState(() => selected = s.first);
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpAt('pending');
      expect(tester.takeException(), isNull);
      for (final label in [
        '\u5f85\u786e\u8ba4',
        '\u89e3\u6790\u5931\u8d25',
        '\u5df2\u5ffd\u7565',
        '\u5df2\u5165\u8d26',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      final sizePending = tester.getSize(find.byType(SegmentedButton<String>));

      await pumpAt('parse_failed');
      expect(tester.takeException(), isNull);
      final sizeFailed = tester.getSize(find.byType(SegmentedButton<String>));

      await pumpAt('ignored');
      expect(tester.takeException(), isNull);
      final sizeIgnored = tester.getSize(find.byType(SegmentedButton<String>));

      await pumpAt('confirmed');
      expect(tester.takeException(), isNull);
      final sizeConfirmed = tester.getSize(find.byType(SegmentedButton<String>));

      expect(sizePending.width, sizeFailed.width);
      expect(sizePending.width, sizeIgnored.width);
      expect(sizePending.width, sizeConfirmed.width);
      // Measured: Size(288.0, 40.0) at 320dp viewport with ~32dp page padding.
      expect(sizePending.width, 288.0);
    });
  });
}

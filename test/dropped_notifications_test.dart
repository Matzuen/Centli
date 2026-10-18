import 'dart:convert';

import 'package:centli/platform/notifications/dropped_notification.dart';
import 'package:centli/platform/notifications/noti_template_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DroppedNotification.fromMap / parse JSON', () {
    test('dirty data and long title truncate to 80 without throw', () {
      final d = DroppedNotification.fromMap({
        'pkg': 'com.example.bank',
        'title': 'A' * 120,
        'when': 'not-a-number',
        'reason': 'not_watched',
        'body': 'MUST_NOT_APPEAR',
      });
      expect(d.title.length, 80);
      expect(d.whenMs, 0);
      expect(d.reason, 'not_watched');
    });

    test('over 20 keeps newest 20; same pkg+title keeps newest', () {
      final entries = <Map<String, Object>>[];
      for (var i = 0; i < 25; i++) {
        entries.add({
          'pkg': 'pkg.$i',
          'title': 't$i',
          'when': i * 1000,
          'reason': 'not_watched',
        });
      }
      entries.add({
        'pkg': 'pkg.dup',
        'title': 'same',
        'when': 1,
        'reason': 'not_watched',
      });
      entries.add({
        'pkg': 'pkg.dup',
        'title': 'same',
        'when': 99999,
        'reason': 'disabled',
      });
      final list = parseDroppedNotificationsJson(jsonEncode(entries));
      expect(list.length, 20);
      expect(list.first.whenMs, greaterThan(list.last.whenMs));
      final dup = list.where((e) => e.pkg == 'pkg.dup').toList();
      expect(dup.length, 1);
      expect(dup.single.whenMs, 99999);
      expect(dup.single.reason, 'disabled');
    });

    test('newest first by when', () {
      final list = parseDroppedNotificationsJson(jsonEncode([
        {'pkg': 'a', 'title': '1', 'when': 10, 'reason': 'blank'},
        {'pkg': 'b', 'title': '2', 'when': 30, 'reason': 'blank'},
        {'pkg': 'c', 'title': '3', 'when': 20, 'reason': 'blank'},
      ]));
      expect(list.map((e) => e.pkg).toList(), ['b', 'c', 'a']);
    });
  });

  group('extra_watched_packages union', () {
    test('extras empty → whitelist == template set', () {
      final templates = {'com.eg.android.AlipayGphone', 'com.tencent.mm'};
      expect(
        NotiTemplateStore.unionWatchedPackages(templates, const []),
        templates,
      );
    });

    test('extras with 2 → union deduped', () {
      final templates = {'com.eg.android.AlipayGphone', 'com.tencent.mm'};
      final extras = ['com.bank.a', 'com.tencent.mm', 'com.bank.b'];
      expect(
        NotiTemplateStore.unionWatchedPackages(templates, extras),
        {
          'com.eg.android.AlipayGphone',
          'com.tencent.mm',
          'com.bank.a',
          'com.bank.b',
        },
      );
    });
  });
}

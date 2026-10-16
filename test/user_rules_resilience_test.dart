import 'package:centli/platform/notifications/notification_parse.dart';
import 'package:centli/platform/notifications/noti_template_store.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _goodMap({
  required String id,
  String amountRegex = r'¥\s*([0-9]+(?:\.[0-9]{1,2})?)',
  String mustContain = '付款成功',
}) =>
    {
      'id': id,
      'name': id,
      'packages': ['com.eg.android.AlipayGphone'],
      'defaultCurrency': 'CNY',
      'mustContainRegex': mustContain,
      'amountRegex': amountRegex,
      'merchantRegex': r'(?:向|给)\s*(.+?)(?:\s|$)',
    };

void main() {
  group('NotiTemplate.tryParse', () {
    test('bad entries do not affect good ones', () {
      final good1 = _goodMap(id: 'good1');
      final good2 = _goodMap(id: 'good2', mustContain: '支付成功');
      final bad = Map<String, dynamic>.from(good1)
        ..remove('amountRegex')
        ..['id'] = 'bad_missing_amount';

      final parsed = [
        NotiTemplate.tryParse(good1),
        NotiTemplate.tryParse(bad),
        NotiTemplate.tryParse(good2),
      ];
      expect(parsed[0], isNotNull);
      expect(parsed[0]!.id, 'good1');
      expect(parsed[1], isNull);
      expect(parsed[2], isNotNull);
      expect(parsed[2]!.id, 'good2');
    });

    test('invalid amountRegex "(" returns null', () {
      final bad = _goodMap(id: 'bad_re', amountRegex: '(');
      expect(NotiTemplate.tryParse(bad), isNull);
    });
  });


  group('NotiTemplate.direction', () {
    test('missing direction defaults to out', () {
      final t = NotiTemplate.tryParse(_goodMap(id: 'd_missing'));
      expect(t, isNotNull);
      expect(t!.direction, 'out');
    });

    test('illegal direction falls back to out', () {
      final m = _goodMap(id: 'd_bad')..['direction'] = 'transfer';
      final t = NotiTemplate.tryParse(m);
      expect(t, isNotNull);
      expect(t!.direction, 'out');
    });

    test('in / out / refund round-trip via toJson', () {
      for (final d in ['in', 'out', 'refund']) {
        final m = _goodMap(id: 'd_$d')..['direction'] = d;
        final t = NotiTemplate.tryParse(m);
        expect(t, isNotNull);
        expect(t!.direction, d);
        final again = NotiTemplate.tryParse(t.toJson());
        expect(again, isNotNull);
        expect(again!.direction, d);
      }
    });

    test('normalizeDirection helper', () {
      expect(NotiTemplate.normalizeDirection(null), 'out');
      expect(NotiTemplate.normalizeDirection(''), 'out');
      expect(NotiTemplate.normalizeDirection('IN'), 'out');
      expect(NotiTemplate.normalizeDirection('in'), 'in');
      expect(NotiTemplate.normalizeDirection('refund'), 'refund');
    });
  });

  group('parseNotification resilience', () {
    test('bad rule does not drop notification or throw', () {
      final bad = NotiTemplate(
        id: 'bad_first',
        packages: const ['com.eg.android.AlipayGphone'],
        mustContainRegex: '付款成功',
        amountRegex: '(', // invalid — must be skipped
      );
      final good = NotiTemplate(
        id: 'good_second',
        packages: const ['com.eg.android.AlipayGphone'],
        mustContainRegex: '付款成功',
        amountRegex: r'¥\s*([0-9]+(?:\.[0-9]{1,2})?)',
        merchantRegex: r'(?:向|给)\s*(.+?)(?:\s|$)',
      );

      final raw = RawNotification(
        pkg: 'com.eg.android.AlipayGphone',
        title: '支付',
        text: '向 星巴克 付款成功 ¥28.50',
        whenMs: 1,
      );

      late ParseResult r;
      expect(() {
        r = parseNotification(raw, [bad, good]);
      }, returnsNormally);
      expect(r.templateId, 'good_second');
      expect(r.ok, isTrue);
      expect(r.amountMinor, 2850);
    });
  });

  group('merge order', () {
    test('user first then non-disabled official', () {
      final user = [
        NotiTemplate(
          id: 'u1',
          packages: const ['com.example'],
          amountRegex: r'(\d+)',
        ),
      ];
      final official = [
        NotiTemplate(
          id: 'o1',
          packages: const ['com.example'],
          amountRegex: r'(\d+)',
        ),
        NotiTemplate(
          id: 'o2',
          packages: const ['com.example'],
          amountRegex: r'(\d+)',
        ),
      ];
      final merged = NotiTemplateStore.mergeForTesting(
        user,
        official,
        {'o1'},
      );
      expect(merged.map((t) => t.id).toList(), ['u1', 'o2']);
    });
  });
}

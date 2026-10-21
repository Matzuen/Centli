import 'dart:convert';
import 'dart:io';

import 'package:centli/platform/notifications/noti_template_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Map<String, dynamic> _bundle({
  required int version,
  String must = '付款成功',
  String id = 'alipay_expense_zh',
}) =>
    {
      'version': version,
      'updated_at': '2026-10-17',
      'templates': [
        {
          'id': id,
          'name': id,
          'packages': ['com.eg.android.AlipayGphone'],
          'defaultCurrency': 'CNY',
          'mustContainRegex': must,
          'excludeTextRegex': '验证码',
          'amountRegex': r'¥\s*([0-9]+(?:\.[0-9]{1,2})?)',
          'direction': 'out',
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('centli_official_');
    // Point path_provider to tmp via binding — store uses getApplicationDocumentsDirectory.
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return tmp.path;
      }
      return tmp.path;
    });
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('higher version official import accepted', () async {
    // Seed documents with v1
    final doc = File(p.join(tmp.path, 'noti_templates.json'));
    await doc.writeAsString(jsonEncode(_bundle(version: 1)));
    await NotiTemplateStore.load(force: true);

    final r = await NotiTemplateStore.importOfficialRulesJson(
      jsonEncode(_bundle(version: 2, must: '支付成功|付款成功')),
    );
    expect(r.updated, isTrue, reason: r.message);
    expect(NotiTemplateStore.version, 2);
  });

  test('same version official import is no-op', () async {
    final doc = File(p.join(tmp.path, 'noti_templates.json'));
    await doc.writeAsString(jsonEncode(_bundle(version: 3)));
    await NotiTemplateStore.load(force: true);
    final r = await NotiTemplateStore.importOfficialRulesJson(
      jsonEncode(_bundle(version: 3)),
    );
    expect(r.updated, isFalse);
    expect(r.message, contains('相同'));
  });

  test('lower version rejected', () async {
    final doc = File(p.join(tmp.path, 'noti_templates.json'));
    await doc.writeAsString(jsonEncode(_bundle(version: 5)));
    await NotiTemplateStore.load(force: true);
    final r = await NotiTemplateStore.importOfficialRulesJson(
      jsonEncode(_bundle(version: 2)),
    );
    expect(r.updated, isFalse);
    expect(NotiTemplateStore.version, 5);
  });

  test('bad rules rejected and file unchanged', () async {
    final doc = File(p.join(tmp.path, 'noti_templates.json'));
    final good = jsonEncode(_bundle(version: 4));
    await doc.writeAsString(good);
    await NotiTemplateStore.load(force: true);
    final r = await NotiTemplateStore.importOfficialRulesJson('{"version":9,"templates":[]}');
    expect(r.updated, isFalse);
    expect(await doc.readAsString(), good);
  });
}

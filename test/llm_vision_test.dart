import 'dart:convert';
import 'dart:typed_data';

import 'package:centli/core/utils/image_for_llm.dart';
import 'package:centli/features/ledger/llm_text_fill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

void main() {
  test('prepareImageForLlm shrinks long edge and stays jpeg under 2MB', () {
    final big = img.Image(width: 1080, height: 2400);
    img.fill(big, color: img.ColorRgb8(255, 255, 255));
    final raw = Uint8List.fromList(img.encodePng(big));
    final out = prepareImageForLlm(raw);
    expect(out.width <= 1600, isTrue);
    expect(out.height <= 1600, isTrue);
    final ratioIn = 1080 / 2400;
    final ratioOut = out.width / out.height;
    expect((ratioIn - ratioOut).abs() < 0.01, isTrue);
    expect(base64Encode(out.bytes).length <= 2 * 1024 * 1024, isTrue);
  });

  test('vision request puts image_url in user message with detail original', () async {
    http.Request? seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'amount': 12.5,
                  'type': 'out',
                  'merchant': '测试店',
                }),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final cfg = SmartFillLlmConfig(
      enabled: true,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      apiKey: 'sk-test',
    );
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 32, height: 32), quality: 80),
    );
    final result = await parseBookkeepingImageWithLlm(
      jpeg,
      config: cfg,
      client: client,
    );
    expect(result, isNotNull);
    expect(result!.source, 'llm-vision');
    expect(result.amount, 12.5);
    expect(seen, isNotNull);
    final body = jsonDecode(seen!.body) as Map<String, dynamic>;
    expect(body['model'], 'deepseek-flash');
    final messages = body['messages'] as List;
    final system = messages.first as Map;
    expect(system['role'], 'system');
    expect(system['content'], isA<String>());
    final user = messages[1] as Map;
    expect(user['role'], 'user');
    expect(user['content'], isA<List>());
    final parts = user['content'] as List;
    final imagePart = parts.cast<Map>().firstWhere((p) => p['type'] == 'image_url');
    expect(imagePart['image_url']['detail'], 'original');
    expect(
      (imagePart['image_url']['url'] as String).startsWith('data:image/jpeg;base64,'),
      isTrue,
    );
  });

  test('vision 400 with image keyword → readable model error', () async {
    final client = MockClient((request) async {
      return http.Response('{"error":"image not supported"}', 400);
    });
    final cfg = SmartFillLlmConfig(
      enabled: true,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      apiKey: 'sk-test',
    );
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8), quality: 80),
    );
    expect(
      () => parseBookkeepingImageWithLlm(jpeg, config: cfg, client: client),
      throwsA(
        isA<LlmVisionException>().having(
          (e) => e.message,
          'message',
          contains('不支持图片'),
        ),
      ),
    );
  });

  test('defaults are DeepSeek', () {
    expect(kDefaultLlmBaseUrl, 'https://api.deepseek.com');
    expect(kDefaultLlmModel, 'deepseek-flash');
  });
}

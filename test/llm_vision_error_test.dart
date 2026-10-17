import 'dart:convert';
import 'dart:typed_data';

import 'package:centli/features/ledger/llm_text_fill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

Uint8List _tinyJpeg() => Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8), quality: 80),
    );

SmartFillLlmConfig _cfg({String apiKey = 'sk-test-secret-key'}) =>
    SmartFillLlmConfig(
      enabled: true,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      apiKey: apiKey,
    );

void main() {
  test('describeLlmHttpError extracts error.message', () {
    final s = describeLlmHttpError(
      400,
      jsonEncode({
        'error': {'message': 'Model Not Exist'},
      }),
    );
    expect(s, contains('HTTP 400'));
    expect(s, contains('Model Not Exist'));
  });

  test('400 Model Not Exist surfaces in exception', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'Model Not Exist'},
        }),
        400,
      );
    });
    expect(
      () => parseBookkeepingImageWithLlm(
            _tinyJpeg(),
            config: _cfg(),
            client: client,
          ),
      throwsA(
        isA<LlmVisionException>().having(
          (e) => e.message,
          'message',
          allOf(contains('Model Not Exist'), contains('400')),
        ),
      ),
    );
  });

  test('400 unknown field detail triggers one retry without detail', () async {
    var calls = 0;
    String? secondBody;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'unknown field detail'},
          }),
          400,
        );
      }
      secondBody = request.body;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({'amount': 1.0, 'type': 'out'}),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final result = await parseBookkeepingImageWithLlm(
      _tinyJpeg(),
      config: _cfg(),
      client: client,
    );
    expect(result, isNotNull);
    expect(calls, 2);
    final body = jsonDecode(secondBody!) as Map<String, dynamic>;
    final messages = body['messages'] as List;
    final user = messages[1] as Map;
    final parts = user['content'] as List;
    final imagePart =
        parts.cast<Map>().firstWhere((p) => p['type'] == 'image_url');
    expect(imagePart['image_url'].containsKey('detail'), isFalse);
  });

  test('400 image not supported keeps friendly and original', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'image not supported'},
        }),
        400,
      );
    });
    expect(
      () => parseBookkeepingImageWithLlm(
            _tinyJpeg(),
            config: _cfg(),
            client: client,
          ),
      throwsA(
        isA<LlmVisionException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('image not supported'),
            contains('\u4e0d\u652f\u6301\u56fe\u7247'),
          ),
        ),
      ),
    );
  });

  test('401 contains status and never apiKey', () async {
    const key = 'sk-super-secret-should-not-leak';
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'Unauthorized'},
        }),
        401,
      );
    });
    try {
      await parseBookkeepingImageWithLlm(
        _tinyJpeg(),
        config: _cfg(apiKey: key),
        client: client,
      );
      fail('expected exception');
    } on LlmVisionException catch (e) {
      expect(e.message, contains('401'));
      expect(e.message.contains(key), isFalse);
    }
  });

  test('500 non-JSON body does not throw FormatException', () async {
    final client = MockClient((request) async {
      return http.Response('internal boom', 500);
    });
    expect(
      () => parseBookkeepingImageWithLlm(
            _tinyJpeg(),
            config: _cfg(),
            client: client,
          ),
      throwsA(
        isA<LlmVisionException>().having(
          (e) => e.message,
          'message',
          contains('HTTP 500'),
        ),
      ),
    );
  });

  test('200 normal JSON parses', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': jsonEncode({
                  'amount': 9.9,
                  'type': 'out',
                  'merchant': 'Cafe',
                }),
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final result = await parseBookkeepingImageWithLlm(
      _tinyJpeg(),
      config: _cfg(),
      client: client,
    );
    expect(result, isNotNull);
    expect(result!.amount, 9.9);
    expect(result.source, 'llm-vision');
  });
}

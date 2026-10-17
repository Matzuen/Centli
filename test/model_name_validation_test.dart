import 'package:centli/features/settings/model_name_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const deepseekBase = 'https://api.deepseek.com';

  test('deekseek-flash vs deepseek-flash distance=1 -> typo hint', () {
    expect(levenshteinDistance('deekseek-flash', 'deepseek-flash'), 1);
    final hint = evaluateDeepSeekModelHint(
      'deekseek-flash',
      baseUrl: deepseekBase,
    );
    expect(hint.kind, DeepSeekModelHintKind.typo);
    expect(hint.suggestion, 'deepseek-flash');
    expect(hint.message, contains('deepseek-flash'));
  });

  test('known models deepseek-flash / deepseek-v4-pro -> no hint', () {
    for (final m in ['deepseek-flash', 'deepseek-v4-pro']) {
      final hint = evaluateDeepSeekModelHint(m, baseUrl: deepseekBase);
      expect(hint.kind, DeepSeekModelHintKind.none, reason: m);
      expect(suggestDeepSeekModelTypo(m, baseUrl: deepseekBase), isNull);
    }
  });

  test('my-local-model distance>2 -> generic vision warning only', () {
    final dFlash = levenshteinDistance('my-local-model', 'deepseek-flash');
    final dPro = levenshteinDistance('my-local-model', 'deepseek-v4-pro');
    expect(dFlash, greaterThan(kDeepSeekTypoMaxDistance));
    expect(dPro, greaterThan(kDeepSeekTypoMaxDistance));
    final hint = evaluateDeepSeekModelHint(
      'my-local-model',
      baseUrl: deepseekBase,
    );
    expect(hint.kind, DeepSeekModelHintKind.unsupportedVision);
    expect(hint.suggestion, isNull);
    expect(hint.message, '该模型可能不支持图片识别');
  });

  test('one-tap fix suggestion equals deepseek-flash', () {
    final suggestion = suggestDeepSeekModelTypo(
      'deekseek-flash',
      baseUrl: deepseekBase,
    );
    expect(suggestion, 'deepseek-flash');
    final after = evaluateDeepSeekModelHint(
      suggestion!,
      baseUrl: deepseekBase,
    );
    expect(after.kind, DeepSeekModelHintKind.none);
    expect(suggestion, 'deepseek-flash');
  });

  test('non-deepseek host skips approximate check', () {
    final hint = evaluateDeepSeekModelHint(
      'deekseek-flash',
      baseUrl: 'https://api.openai.com/v1',
    );
    expect(hint.kind, DeepSeekModelHintKind.none);
  });

  test('connectionTestTypoHintLine on failure', () {
    final line = connectionTestTypoHintLine(
      'deekseek-flash',
      baseUrl: deepseekBase,
    );
    expect(line, '提示：你可能想用 deepseek-flash');
  });
}

import 'package:centli/features/ledger/llm_text_fill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SmartFillLlmConfig cfg({
    bool enabled = false,
    bool notifyAi = false,
    bool assetAi = false,
    String apiKey = 'sk-test',
  }) =>
      SmartFillLlmConfig(
        enabled: enabled,
        notifyAiEnabled: notifyAi,
        assetAiEnabled: assetAi,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        apiKey: apiKey,
      );

  test('feature switches are independent', () {
    final textOnly = cfg(enabled: true);
    expect(textOnly.isReady, isTrue);
    expect(textOnly.isNotifyAiReady, isFalse);
    expect(textOnly.isAssetAiReady, isFalse);

    final notifyOnly = cfg(notifyAi: true);
    expect(notifyOnly.isReady, isFalse);
    expect(notifyOnly.isNotifyAiReady, isTrue);
    expect(notifyOnly.isAssetAiReady, isFalse);

    final assetOnly = cfg(assetAi: true);
    expect(assetOnly.isReady, isFalse);
    expect(assetOnly.isNotifyAiReady, isFalse);
    expect(assetOnly.isAssetAiReady, isTrue);
  });

  test('credentials required for all gates', () {
    final bare = cfg(enabled: true, notifyAi: true, assetAi: true, apiKey: '');
    expect(bare.hasCredentials, isFalse);
    expect(bare.isReady, isFalse);
    expect(bare.isNotifyAiReady, isFalse);
    expect(bare.isAssetAiReady, isFalse);
  });
}

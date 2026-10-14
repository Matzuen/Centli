/// Local speech-to-text facade for bookkeeping voice fill.
///
/// Uses the OS on-device / system speech engine via `speech_to_text`.
/// No Centli cloud / API key. Availability and offline behavior depend on
/// the platform language pack (Android offline STT, iOS on-device, etc.).
library;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class LocalSpeechResult {
  const LocalSpeechResult({
    required this.text,
    this.finalResult = true,
  });

  final String text;
  final bool finalResult;
}

/// Thin wrapper so the bookkeeping UI stays free of plugin details.
class LocalSpeechService {
  LocalSpeechService({SpeechToText? plugin}) : _plugin = plugin ?? SpeechToText();

  final SpeechToText _plugin;
  var _ready = false;
  var _listening = false;

  bool get isAvailable => _ready;
  bool get isListening => _listening;

  Future<bool> ensureReady({String localeId = 'zh_CN'}) async {
    if (kIsWeb) return false;
    if (_ready) return true;
    try {
      _ready = await _plugin.initialize(
        onError: (e) => debugPrint('LocalSpeech error: $e'),
        onStatus: (s) {
          _listening = s == 'listening';
        },
      );
    } catch (e) {
      debugPrint('LocalSpeech init failed: $e');
      _ready = false;
    }
    return _ready;
  }

  /// Prefer a Chinese locale when the OS lists one.
  Future<String> resolveLocale({String preferred = 'zh_CN'}) async {
    if (!_ready) return preferred;
    try {
      final locales = await _plugin.locales();
      for (final l in locales) {
        final id = l.localeId.replaceAll('-', '_');
        if (id.toLowerCase().startsWith('zh')) return l.localeId;
      }
    } catch (_) {}
    return preferred;
  }

  Future<void> start({
    required void Function(LocalSpeechResult result) onResult,
    String? localeId,
  }) async {
    final ok = await ensureReady();
    if (!ok) {
      throw StateError('speech_unavailable');
    }
    final locale = localeId ?? await resolveLocale();
    _listening = true;
    await _plugin.listen(
      onResult: (r) {
        onResult(
          LocalSpeechResult(
            text: r.recognizedWords,
            finalResult: r.finalResult,
          ),
        );
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.confirmation,
        cancelOnError: true,
        partialResults: true,
        // Prefer on-device recognition; fails if the OS has no offline pack.
        onDevice: true,
        localeId: locale,
      ),
    );
  }

  Future<void> stop() async {
    if (!_ready) return;
    await _plugin.stop();
    _listening = false;
  }

  Future<void> cancel() async {
    if (!_ready) return;
    await _plugin.cancel();
    _listening = false;
  }
}

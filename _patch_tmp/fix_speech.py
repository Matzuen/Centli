from pathlib import Path

root = Path(r"D:\Resource\Codebase\studyProject\Centli")

# ========== Bug 1: local_speech.dart ==========
speech = r'''/// Local speech-to-text facade for bookkeeping voice fill.
///
/// Uses the OS speech engine via `speech_to_text`.
/// No Centli cloud / API key. Prefers network+on-device (onDevice: false)
/// so Chinese recognition works without an offline language pack; falls
/// back with a clear error if the engine still fails.
library;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
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
  String? _lastError;

  bool get isAvailable => _ready;
  bool get isListening => _listening;
  String? get lastError => _lastError;

  Future<bool> ensureReady({String localeId = 'zh_CN'}) async {
    if (kIsWeb) return false;
    if (_ready) return true;
    _lastError = null;
    try {
      _ready = await _plugin.initialize(
        onError: (SpeechRecognitionError e) {
          _lastError = '${e.errorMsg} (permanent=${e.permanent})';
          debugPrint('LocalSpeech error: $_lastError');
          if (e.permanent) {
            _listening = false;
          }
        },
        onStatus: (s) {
          _listening = s == 'listening';
          debugPrint('LocalSpeech status: $s');
        },
      );
      if (!_ready) {
        _lastError = _lastError ?? 'speech_init_false';
      }
    } catch (e) {
      debugPrint('LocalSpeech init failed: $e');
      _lastError = '$e';
      _ready = false;
    }
    return _ready;
  }

  /// Prefer a Chinese locale when the OS lists one.
  Future<String> resolveLocale({String preferred = 'zh_CN'}) async {
    if (!_ready) return preferred;
    try {
      final locales = await _plugin.locales();
      // Exact / close match first.
      for (final want in [preferred, 'zh_CN', 'zh_Hans_CN', 'zh_CN_#Hans', 'zh']) {
        final wantNorm = want.replaceAll('-', '_').toLowerCase();
        for (final l in locales) {
          final id = l.localeId.replaceAll('-', '_');
          if (id.toLowerCase() == wantNorm ||
              id.toLowerCase().startsWith('zh_cn') ||
              id.toLowerCase().startsWith('zh_hans')) {
            return l.localeId;
          }
        }
      }
      for (final l in locales) {
        final id = l.localeId.replaceAll('-', '_');
        if (id.toLowerCase().startsWith('zh')) return l.localeId;
      }
    } catch (_) {}
    return preferred;
  }

  Future<void> _listenOnce({
    required void Function(LocalSpeechResult result) onResult,
    required String locale,
    required bool onDevice,
  }) async {
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
        // false = allow network STT when offline Chinese pack is missing.
        onDevice: onDevice,
        localeId: locale,
      ),
    );
  }

  Future<void> start({
    required void Function(LocalSpeechResult result) onResult,
    String? localeId,
  }) async {
    final ok = await ensureReady();
    if (!ok) {
      throw StateError(
        _lastError == null
            ? 'speech_unavailable'
            : 'speech_unavailable: $_lastError',
      );
    }
    final locale = localeId ?? await resolveLocale();
    _lastError = null;
    _listening = true;

    // 1) Allow online/system engine (works on most CN Android phones).
    try {
      await _listenOnce(onResult: onResult, locale: locale, onDevice: false);
      return;
    } catch (e) {
      debugPrint('LocalSpeech listen(onDevice:false) failed: $e');
      _lastError = '$e';
    }

    // 2) Fall back to strict on-device if online path threw synchronously.
    try {
      await _listenOnce(onResult: onResult, locale: locale, onDevice: true);
      return;
    } catch (e) {
      debugPrint('LocalSpeech listen(onDevice:true) failed: $e');
      _listening = false;
      _lastError = '$e';
      throw StateError(
        'speech_listen_failed: $_lastError。'
        '请检查麦克风权限，或在系统设置中下载中文语音识别包 / 保持网络可用。',
      );
    }
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
'''
(root / "lib/features/ledger/local_speech.dart").write_text(speech, encoding="utf-8", newline="\n")
print("wrote local_speech.dart")

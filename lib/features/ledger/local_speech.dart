/// Local speech-to-text facade for bookkeeping voice fill.
///
/// Uses the OS speech engine via `speech_to_text`.
/// No Centli cloud / API key. Prefers network+on-device (onDevice: false)
/// so Chinese recognition works without an offline language pack.
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

/// Injectable speech backend used by QuickBookkeepingSheet (tests can fake it).
abstract class VoiceSpeechBackend {
  Future<bool> ensureReady({String localeId = 'zh_CN'});
  String? get friendlyError;
  set onStatusChanged(void Function(String status)? cb);
  set onSoundLevel(void Function(double level)? cb);
  set onErrorMessage(void Function(String message)? cb);
  Future<void> start({
    required void Function(LocalSpeechResult result) onResult,
    String? localeId,
  });
  Future<void> stop();
  Future<void> cancel();
}

/// Thin wrapper so the bookkeeping UI stays free of plugin details.
class LocalSpeechService implements VoiceSpeechBackend {
  LocalSpeechService({SpeechToText? plugin}) : _plugin = plugin ?? SpeechToText();

  final SpeechToText _plugin;
  var _ready = false;
  var _listening = false;
  String? _lastError;
  String _lastStatus = 'idle';

  void Function(String status)? onStatusChanged;
  void Function(double level)? onSoundLevel;
  void Function(String message)? onErrorMessage;

  bool get isAvailable => _ready;
  bool get isListening => _listening;
  String? get lastError => _lastError;
  String get lastStatus => _lastStatus;

  /// Human-readable Chinese hint for the last error (or null).
  @override
  String? get friendlyError {
    final e = _lastError;
    if (e == null || e.isEmpty) return null;
    final lower = e.toLowerCase();
    if (lower.contains('permission') ||
        lower.contains('denied') ||
        lower.contains('not_allowed') ||
        lower.contains('authoriz')) {
      return '未获得麦克风权限，请在系统设置中允许 Centli 使用麦克风后重试';
    }
    if (lower.contains('network') || lower.contains('offline')) {
      return '语音识别需要网络（或已下载的中文离线包），请检查网络后重试';
    }
    if (lower.contains('language') ||
        lower.contains('locale') ||
        lower.contains('recognizer_busy') ||
        lower.contains('not_available') ||
        lower.contains('speech_init_false') ||
        lower.contains('speech_unavailable')) {
      return '当前设备语音识别不可用。请确认已开启麦克风权限，并在系统语音设置中启用中文识别 / 保持网络畅通';
    }
    if (lower.contains('error_speech_timeout') ||
        lower.contains('timeout') ||
        lower.contains('no_match') ||
        lower.contains('error_no_match')) {
      return '没有听清，请靠近麦克风再说一次，或改用文字话术';
    }
    if (lower.contains('error_audio') || lower.contains('audio')) {
      return '麦克风被占用或无法录音，请关闭其他录音应用后重试';
    }
    return '语音识别失败：$e';
  }

  @override
  Future<bool> ensureReady({String localeId = 'zh_CN'}) async {
    if (kIsWeb) {
      _lastError = 'web_unsupported';
      return false;
    }
    if (_ready) return true;
    _lastError = null;
    try {
      _ready = await _plugin.initialize(
        onError: (SpeechRecognitionError e) {
          _lastError = '${e.errorMsg} (permanent=${e.permanent})';
          debugPrint('LocalSpeech error: $_lastError');
          _setStatus(e.permanent ? 'error' : _lastStatus);
          if (e.permanent) {
            _listening = false;
            _setStatus('error');
          }
          final msg = friendlyError;
          if (msg != null) onErrorMessage?.call(msg);
        },
        onStatus: (s) {
          debugPrint('LocalSpeech status: $s');
          _listening = s == 'listening';
          _setStatus(s);
        },
        // Deliver last partial as final if engine is slow (common on CN OEM ROMs).
        finalTimeout: const Duration(seconds: 3),
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

  void _setStatus(String s) {
    _lastStatus = s;
    onStatusChanged?.call(s);
  }

  /// Prefer a Chinese locale when the OS lists one.
  Future<String> resolveLocale({String preferred = 'zh_CN'}) async {
    if (!_ready) return preferred;
    try {
      final locales = await _plugin.locales();
      for (final want in [
        preferred,
        'zh_CN',
        'zh_Hans_CN',
        'zh_CN_#Hans',
        'zh',
      ]) {
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
      onSoundLevelChange: (level) {
        onSoundLevel?.call(level);
      },
      listenOptions: SpeechListenOptions(
        // Dictation suits multi-word bookkeeping phrases better than confirmation.
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        partialResults: true,
        onDevice: onDevice,
        localeId: locale,
        // Give users time to think / speak; avoid silent early stop.
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 45),
      ),
    );
  }

  @override
  Future<void> start({
    required void Function(LocalSpeechResult result) onResult,
    String? localeId,
  }) async {
    final ok = await ensureReady();
    if (!ok) {
      throw StateError(
        friendlyError ??
            (_lastError == null
                ? '当前设备语音识别不可用'
                : '当前设备语音识别不可用: $_lastError'),
      );
    }
    // Ensure previous session is fully stopped before starting again.
    try {
      if (_plugin.isListening) {
        await _plugin.stop();
      }
    } catch (_) {}

    final locale = localeId ?? await resolveLocale();
    _lastError = null;
    _listening = true;
    _setStatus('listening');

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
      _setStatus('error');
      throw StateError(
        friendlyError ??
            '语音识别启动失败: $_lastError。'
                '请检查麦克风权限，或在系统设置中下载中文语音识别包 / 保持网络可用。',
      );
    }
  }

  @override
  Future<void> stop() async {
    if (!_ready) {
      _listening = false;
      _setStatus('notListening');
      return;
    }
    try {
      await _plugin.stop();
    } finally {
      _listening = false;
      _setStatus('notListening');
    }
  }

  @override
  Future<void> cancel() async {
    if (!_ready) {
      _listening = false;
      _setStatus('notListening');
      return;
    }
    try {
      await _plugin.cancel();
    } finally {
      _listening = false;
      _setStatus('notListening');
    }
  }
}

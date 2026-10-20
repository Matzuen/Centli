import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Allowed PIN lengths for 资产锁.
const Set<int> kAppLockPinLengths = {4, 6};

/// Default when creating a new PIN (user can switch to 4 in the dialog).
const int kDefaultAppLockPinLength = 6;

/// Secure PIN hashing + biometric helpers. Never stores plaintext PIN in Drift.
class AppLockService {
  AppLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  static const _keySalt = 'centli_pin_salt';
  static const _keyHash = 'centli_pin_hash';
  static const _keyLength = 'centli_pin_length';
  static const _keyFailCount = 'centli_pin_fail_count';
  static const _keyLockUntil = 'centli_pin_lock_until_ms';
  static const _maxFails = 5;
  static const _lockoutMs = 60 * 1000; // 1 minute

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _keyHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Digits required for the currently saved PIN (defaults to 6 for older installs).
  Future<int> pinLength() async {
    final raw = await _storage.read(key: _keyLength);
    final n = int.tryParse(raw ?? '');
    if (n != null && kAppLockPinLengths.contains(n)) return n;
    return kDefaultAppLockPinLength;
  }

  Future<void> setPin(String pin) async {
    _assertPinFormat(pin);
    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);
    await _storage.write(key: _keySalt, value: salt);
    await _storage.write(key: _keyHash, value: hash);
    await _storage.write(key: _keyLength, value: '${pin.length}');
  }

  Future<Duration?> lockoutRemaining() async {
    final untilRaw = await _storage.read(key: _keyLockUntil);
    final until = int.tryParse(untilRaw ?? '');
    if (until == null) return null;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) {
      await _storage.delete(key: _keyLockUntil);
      return null;
    }
    return Duration(milliseconds: left);
  }

  Future<bool> verifyPin(String pin) async {
    final len = await pinLength();
    if (!_looksLikePin(pin, length: len)) return false;
    final remaining = await lockoutRemaining();
    if (remaining != null) return false;
    final salt = await _storage.read(key: _keySalt);
    final expected = await _storage.read(key: _keyHash);
    if (salt == null || expected == null) return false;
    final ok = _hashPin(pin, salt) == expected;
    if (ok) {
      await _storage.delete(key: _keyFailCount);
      await _storage.delete(key: _keyLockUntil);
      return true;
    }
    final prev = int.tryParse(await _storage.read(key: _keyFailCount) ?? '0') ?? 0;
    final next = prev + 1;
    await _storage.write(key: _keyFailCount, value: '$next');
    if (next >= _maxFails) {
      final until = DateTime.now().millisecondsSinceEpoch + _lockoutMs;
      await _storage.write(key: _keyLockUntil, value: '$until');
      await _storage.write(key: _keyFailCount, value: '0');
    }
    return false;
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyHash);
    await _storage.delete(key: _keyLength);
    await _storage.delete(key: _keyFailCount);
    await _storage.delete(key: _keyLockUntil);
  }

  /// Device supports some form of local auth (biometrics / device credentials).
  Future<bool> isBiometricHardwareAvailable() async {
    if (kIsWeb) return false;
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (canCheck) return true;
      // Some desktops report device-supported without enrolled biometrics.
      final types = await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric({
    String reason = '解锁 Centli',
  }) async {
    if (kIsWeb) return false;
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static void _assertPinFormat(String pin) {
    if (!_looksLikePin(pin)) {
      throw ArgumentError('PIN 须为 4 或 6 位数字');
    }
  }

  static bool _looksLikePin(String pin, {int? length}) {
    if (length != null) {
      return RegExp('^\\d{$length}\$').hasMatch(pin);
    }
    return RegExp(r'^\d{4}$').hasMatch(pin) || RegExp(r'^\d{6}$').hasMatch(pin);
  }

  static String _randomSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}

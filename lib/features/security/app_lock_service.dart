import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// PIN length for app lock (6 digits).
const int kAppLockPinLength = 6;

/// Secure PIN hashing + biometric helpers. Never stores plaintext PIN in Drift.
class AppLockService {
  AppLockService({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  static const _keySalt = 'centli_pin_salt';
  static const _keyHash = 'centli_pin_hash';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _keyHash);
    return hash != null && hash.isNotEmpty;
  }

  Future<void> setPin(String pin) async {
    _assertPinFormat(pin);
    final salt = _randomSalt();
    final hash = _hashPin(pin, salt);
    await _storage.write(key: _keySalt, value: salt);
    await _storage.write(key: _keyHash, value: hash);
  }

  Future<bool> verifyPin(String pin) async {
    if (!_looksLikePin(pin)) return false;
    final salt = await _storage.read(key: _keySalt);
    final expected = await _storage.read(key: _keyHash);
    if (salt == null || expected == null) return false;
    return _hashPin(pin, salt) == expected;
  }

  Future<void> clearPin() async {
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyHash);
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
      throw ArgumentError('PIN must be $kAppLockPinLength digits');
    }
  }

  static bool _looksLikePin(String pin) =>
      RegExp(r'^\d{6}$').hasMatch(pin);

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

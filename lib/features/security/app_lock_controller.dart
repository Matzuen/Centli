import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import 'app_lock_service.dart';
import 'pin_pad.dart';

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService();
});

final appLockEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(databaseProvider).watchAppLockEnabled();
});

final appLockBiometricProvider = StreamProvider<bool>((ref) {
  return ref.watch(databaseProvider).watchAppLockBiometric();
});

/// Session-only: whether amounts are temporarily revealed while 资产锁 is on.
/// Defaults to concealed; resets when the app re-locks.
final amountsRevealedProvider =
    NotifierProvider<AmountsRevealedNotifier, bool>(AmountsRevealedNotifier.new);

class AmountsRevealedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void reveal() => state = true;

  void conceal() => state = false;
}

/// Hide amounts when 资产锁 is on and the user has not revealed them this session.
final hideAmountProvider = Provider<bool>((ref) {
  final lockOn = ref.watch(appLockEnabledProvider).valueOrNull ?? false;
  if (!lockOn) return false;
  return !ref.watch(amountsRevealedProvider);
});

/// Prompt biometric (if enabled) then PIN. Used to reveal amounts / change settings.
Future<bool> authenticateSensitiveAction(
  BuildContext context,
  WidgetRef ref, {
  String reason = '验证身份以查看金额',
  String pinTitle = '输入 PIN 以查看金额',
}) async {
  final svc = ref.read(appLockServiceProvider);
  final bioOn = ref.read(appLockBiometricProvider).valueOrNull ?? false;
  if (bioOn) {
    final hw = await svc.isBiometricHardwareAvailable();
    if (hw) {
      final ok = await svc.authenticateBiometric(reason: reason);
      if (ok) return true;
    }
  }
  if (!context.mounted) return false;
  return showVerifyPinDialog(
    context,
    verify: svc.verifyPin,
    resolvePinLength: svc.pinLength,
    title: pinTitle,
  );
}

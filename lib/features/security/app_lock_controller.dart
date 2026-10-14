import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import 'app_lock_service.dart';

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService();
});

final appLockEnabledProvider = StreamProvider<bool>((ref) {
  return ref.watch(databaseProvider).watchAppLockEnabled();
});

final appLockBiometricProvider = StreamProvider<bool>((ref) {
  return ref.watch(databaseProvider).watchAppLockBiometric();
});

/// Session unlock flag — resets on process kill. Not persisted.
final appLockUnlockedProvider =
    NotifierProvider<AppLockUnlockedNotifier, bool>(AppLockUnlockedNotifier.new);

class AppLockUnlockedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() => state = false;
}

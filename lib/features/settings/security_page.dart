import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/db/database_provider.dart';
import '../security/app_lock_controller.dart';
import '../security/pin_pad.dart';

/// Security settings: app lock, biometric, hide-amount default.
class SecurityPage extends ConsumerStatefulWidget {
  const SecurityPage({super.key});

  @override
  ConsumerState<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends ConsumerState<SecurityPage> {
  bool? _bioHw;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final hw =
          await ref.read(appLockServiceProvider).isBiometricHardwareAvailable();
      if (mounted) setState(() => _bioHw = hw);
    });
  }

  Future<bool> _authToChange() async {
    final svc = ref.read(appLockServiceProvider);
    final bioOn =
        ref.read(appLockBiometricProvider).valueOrNull ?? false;
    if (bioOn && (_bioHw ?? false)) {
      final ok = await svc.authenticateBiometric(reason: '验证身份以更改安全设置');
      if (ok) return true;
    }
    if (!mounted) return false;
    return showVerifyPinDialog(
      context,
      verify: svc.verifyPin,
      title: '输入当前 PIN',
    );
  }

  Future<void> _onLockChanged(bool enable) async {
    final db = ref.read(databaseProvider);
    final svc = ref.read(appLockServiceProvider);
    if (enable) {
      final pin = await showSetPinDialog(context);
      if (pin == null || !mounted) return;
      await svc.setPin(pin);
      await db.setAppLockEnabled(true);
      ref.read(appLockUnlockedProvider.notifier).unlock();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('应用锁已开启')),
        );
      }
    } else {
      final ok = await _authToChange();
      if (!ok || !mounted) return;
      await svc.clearPin();
      await db.setAppLockEnabled(false);
      await db.setAppLockBiometric(false);
      ref.read(appLockUnlockedProvider.notifier).unlock();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('应用锁已关闭')),
        );
      }
    }
  }

  Future<void> _changePin() async {
    final ok = await _authToChange();
    if (!ok || !mounted) return;
    final pin = await showSetPinDialog(context);
    if (pin == null || !mounted) return;
    await ref.read(appLockServiceProvider).setPin(pin);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN 已更新')),
      );
    }
  }

  Future<void> _onBiometricChanged(bool enable) async {
    if (enable && !(_bioHw ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此设备不支持生物识别')),
      );
      return;
    }
    final ok = await _authToChange();
    if (!ok || !mounted) return;
    await ref.read(databaseProvider).setAppLockBiometric(enable);
  }

  @override
  Widget build(BuildContext context) {
    final lockAsync = ref.watch(appLockEnabledProvider);
    final bioAsync = ref.watch(appLockBiometricProvider);
    final hideAsync = ref.watch(hideAmountProvider);
    final lockOn = lockAsync.valueOrNull ?? false;
    final bioOn = bioAsync.valueOrNull ?? false;
    final hideOn = hideAsync.valueOrNull ?? false;

    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('安全')),
      body: ListView(
        padding: CentliSpacing.pagePadding,
        children: [
          CentliSoftCard(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.lock_outline),
                  title: const Text('应用锁'),
                  subtitle: const Text('冷启动与回到前台时需解锁'),
                  value: lockOn,
                  onChanged: lockAsync.isLoading ? null : _onLockChanged,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('修改 PIN'),
                  subtitle: const Text('6 位数字'),
                  enabled: lockOn,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: lockOn ? _changePin : null,
                ),
                const Divider(height: 1, indent: 56),
                SwitchListTile(
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('生物识别'),
                  subtitle: Text(
                    _bioHw == null
                        ? '检测中…'
                        : (_bioHw!
                            ? '解锁时优先使用指纹 / Face ID'
                            : '当前设备不可用，将仅使用 PIN'),
                  ),
                  value: bioOn && lockOn && (_bioHw ?? false),
                  onChanged: (!lockOn || _bioHw != true)
                      ? null
                      : _onBiometricChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: CentliSpacing.section),
          CentliSoftCard(
            child: SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: const Text('隐藏金额默认'),
              subtitle: const Text('与首页眼睛按钮同步'),
              value: hideOn,
              onChanged: hideAsync.isLoading
                  ? null
                  : (_) => ref.read(databaseProvider).toggleHideAmount(),
            ),
          ),
        ],
      ),
    );
  }
}

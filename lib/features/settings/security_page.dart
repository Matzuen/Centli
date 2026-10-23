import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/db/database_provider.dart';
import '../security/app_lock_controller.dart';
import '../security/pin_pad.dart';
import '../../core/widgets/glass.dart';

/// Security settings: 资产锁, biometric, PIN.
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
    if (!mounted) return false;
    return authenticateSensitiveAction(
      context,
      ref,
      reason: '验证身份以更改安全设置',
      pinTitle: '输入当前 PIN',
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
      ref.read(amountsRevealedProvider.notifier).conceal();
      if (mounted) {
        showGlassSnackBar(context, '资产锁已开启，金额默认隐藏');
      }
    } else {
      final ok = await _authToChange();
      if (!ok || !mounted) return;
      await svc.clearPin();
      await db.setAppLockEnabled(false);
      await db.setAppLockBiometric(false);
      ref.read(amountsRevealedProvider.notifier).conceal();
      if (mounted) {
        showGlassSnackBar(context, '资产锁已关闭');
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
      showGlassSnackBar(context, 'PIN 已更新');
    }
  }

  Future<void> _onBiometricChanged(bool enable) async {
    if (enable && !(_bioHw ?? false)) {
      showGlassSnackBar(context, '此设备不支持生物识别');
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
    final lockOn = lockAsync.valueOrNull ?? false;
    final bioOn = bioAsync.valueOrNull ?? false;

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
                  title: const Text('资产锁'),
                  subtitle: const Text(
                    '开启后隐藏全部金额。首页概览卡点眼睛可临时查看（需验证 PIN / 生物识别）；'
                    '关掉眼睛不用验证。回到前台会重新隐藏。',
                  ),
                  value: lockOn,
                  onChanged: lockAsync.isLoading ? null : _onLockChanged,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.pin_outlined),
                  title: const Text('修改 PIN'),
                  subtitle: const Text('可选 4 位或 6 位'),
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
                            ? '查看金额时优先使用指纹 / Face ID'
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
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';


import '../../app/deep_link.dart';

import 'app_lock_controller.dart';
import 'app_lock_service.dart';
import 'pin_pad.dart';
import '../../app/theme.dart';

/// Full-screen unlock gate at `/lock`.
class AppLockPage extends ConsumerStatefulWidget {
  const AppLockPage({super.key});

  @override
  ConsumerState<AppLockPage> createState() => _AppLockPageState();
}

class _AppLockPageState extends ConsumerState<AppLockPage> {
  String _pin = '';
  String? _error;
  bool _busy = false;
  bool _usePin = false;
  bool _bioAvailable = false;
  bool _bioPreferred = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final svc = ref.read(appLockServiceProvider);
    final bioHw = await svc.isBiometricHardwareAvailable();
    final bioPref =
        ref.read(appLockBiometricProvider).valueOrNull ?? false;
    if (!mounted) return;
    setState(() {
      _bioAvailable = bioHw;
      _bioPreferred = bioPref;
      _usePin = !(bioHw && bioPref);
    });
    if (bioHw && bioPref) {
      await _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref.read(appLockServiceProvider).authenticateBiometric();
    if (!mounted) return;
    if (ok) {
      _finishUnlock();
      return;
    }
    setState(() {
      _busy = false;
      _usePin = true;
      _error = '生物识别未通过，请使用 PIN';
    });
  }

  Future<void> _onPinChanged(String v) async {
    setState(() {
      _pin = v;
      _error = null;
    });
    if (v.length != kAppLockPinLength || _busy) return;
    setState(() => _busy = true);
    final svc = ref.read(appLockServiceProvider);
      final locked = await svc.lockoutRemaining();
      if (locked != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('请 ${locked.inSeconds + 1} 秒后再试')),
          );
        }
        return;
      }
      final ok = await svc.verifyPin(v);
    if (!mounted) return;
    if (ok) {
      _finishUnlock();
    } else {
      setState(() {
        _busy = false;
        _pin = '';
        _error = 'PIN 错误';
      });
    }
  }

  void _finishUnlock() {
    ref.read(appLockUnlockedProvider.notifier).unlock();
    if (!mounted) return;
    context.go(PendingDeepLink.take() ?? '/home');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      size: 36,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                  Text(
                    'Centli 已锁定',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  Text(
                    _usePin ? '请输入 6 位 PIN' : '使用生物识别解锁',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 28),
                  if (!_usePin) ...[
                    FilledButton.icon(
                      onPressed: _busy ? null : _tryBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('生物识别解锁'),
                    ),
                    const SizedBox(height: CentliSpacing.section),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _usePin = true;
                                _error = null;
                              }),
                      child: const Text('用 PIN'),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: CentliSpacing.section),
                      Text(_error!, style: TextStyle(color: scheme.error)),
                    ],
                  ] else ...[
                    PinPad(
                      value: _pin,
                      onChanged: _onPinChanged,
                      enabled: !_busy,
                      errorText: _error,
                    ),
                    if (_bioAvailable && _bioPreferred) ...[
                      const SizedBox(height: CentliSpacing.item),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _usePin = false;
                                  _pin = '';
                                  _error = null;
                                });
                                _tryBiometric();
                              },
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('改用生物识别'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

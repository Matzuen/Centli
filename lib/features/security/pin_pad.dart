import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import 'app_lock_service.dart';
import '../../app/theme.dart';

/// Dot display + numeric keypad for [kAppLockPinLength]-digit PIN.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.errorText,
    this.subtitle,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final String? errorText;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subtitle != null) ...[
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CentliSpacing.sectionLoose),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(kAppLockPinLength, (i) {
            final filled = i < value.length;
            return Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? scheme.primary : Colors.transparent,
                border: Border.all(
                  color: filled ? scheme.primary : scheme.outline,
                  width: 1.5,
                ),
              ),
            );
          }),
        ),
        if (errorText != null) ...[
          const SizedBox(height: CentliSpacing.section),
          Text(
            errorText!,
            style: TextStyle(color: scheme.error, fontSize: 13),
          ),
        ],
        const SizedBox(height: 28),
        _Keypad(
          enabled: enabled,
          onDigit: (d) {
            if (!enabled) return;
            if (value.length >= kAppLockPinLength) return;
            HapticFeedback.selectionClick();
            onChanged('$value$d');
          },
          onBackspace: () {
            if (!enabled || value.isEmpty) return;
            HapticFeedback.selectionClick();
            onChanged(value.substring(0, value.length - 1));
          },
        ),
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.enabled,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, IconData? icon}) {
      return SizedBox(
        width: 84,
        height: 64,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(40),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 28)
                : Text(
                    label,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in row) key(d, onTap: () => onDigit(d)),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 84, height: 64),
            key('0', onTap: () => onDigit('0')),
            key('', icon: Icons.backspace_outlined, onTap: onBackspace),
          ],
        ),
      ],
    );
  }
}

/// Full-screen dialog flow: enter PIN → confirm PIN. Returns PIN or null.
Future<String?> showSetPinDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _SetPinDialog(),
  );
}

class _SetPinDialog extends StatefulWidget {
  const _SetPinDialog();

  @override
  State<_SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<_SetPinDialog> {
  String _first = '';
  String _second = '';
  bool _confirming = false;
  String? _error;

  void _onChanged(String v) {
    setState(() {
      _error = null;
      if (!_confirming) {
        _first = v;
        if (v.length == kAppLockPinLength) {
          _confirming = true;
        }
      } else {
        _second = v;
        if (v.length == kAppLockPinLength) {
          if (v == _first) {
            Navigator.pop(context, v);
          } else {
            _error = '两次 PIN 不一致，请重试';
            _first = '';
            _second = '';
            _confirming = false;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_confirming ? '确认 PIN' : '设置 6 位 PIN'),
      content: SizedBox(
        width: 320,
        child: PinPad(
          value: _confirming ? _second : _first,
          onChanged: _onChanged,
          errorText: _error,
          subtitle: _confirming ? '请再输入一次' : '用于解锁应用',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// Ask current PIN; returns true if verified.
Future<bool> showVerifyPinDialog(
  BuildContext context, {
  required Future<bool> Function(String pin) verify,
  String title = '输入 PIN',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _VerifyPinDialog(title: title, verify: verify),
  );
  return ok == true;
}

class _VerifyPinDialog extends StatefulWidget {
  const _VerifyPinDialog({required this.title, required this.verify});

  final String title;
  final Future<bool> Function(String pin) verify;

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _onChanged(String v) async {
    setState(() {
      _pin = v;
      _error = null;
    });
    if (v.length != kAppLockPinLength || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.verify(v);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _pin = '';
        _error = 'PIN 错误';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: PinPad(
          value: _pin,
          onChanged: _onChanged,
          enabled: !_busy,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

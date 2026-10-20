import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock_service.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

/// Dot display + numeric keypad for a [pinLength]-digit PIN (4 or 6).
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.value,
    required this.onChanged,
    this.pinLength = kDefaultAppLockPinLength,
    this.enabled = true,
    this.errorText,
    this.subtitle,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final int pinLength;
  final bool enabled;
  final String? errorText;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final len = kAppLockPinLengths.contains(pinLength)
        ? pinLength
        : kDefaultAppLockPinLength;
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
          children: List.generate(len, (i) {
            final filled = i < value.length;
            return Container(
              width: 14,
              height: 14,
              margin: EdgeInsets.symmetric(horizontal: len == 4 ? 10 : 8),
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
            if (value.length >= len) return;
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
      return Expanded(
        child: SizedBox(
          height: 56,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(40),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 26)
                  : Text(
                      label,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
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
            children: [
              for (final d in row) key(d, onTap: () => onDigit(d)),
            ],
          ),
        Row(
          children: [
            const Expanded(child: SizedBox(height: 56)),
            key('0', onTap: () => onDigit('0')),
            key('', icon: Icons.backspace_outlined, onTap: onBackspace),
          ],
        ),
      ],
    );
  }
}

/// Enter PIN → confirm PIN. Returns PIN or null. User picks 4 or 6 digits.
Future<String?> showSetPinDialog(BuildContext context) async {
  return showGlassDialog<String>(
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
  int _pinLength = kDefaultAppLockPinLength;
  String _first = '';
  String _second = '';
  bool _confirming = false;
  String? _error;

  void _onLengthChanged(int length) {
    if (_confirming || length == _pinLength) return;
    setState(() {
      _pinLength = length;
      _first = '';
      _second = '';
      _error = null;
    });
  }

  void _onChanged(String v) {
    setState(() {
      _error = null;
      if (!_confirming) {
        _first = v;
        if (v.length == _pinLength) {
          _confirming = true;
        }
      } else {
        _second = v;
        if (v.length == _pinLength) {
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(_confirming ? '确认 PIN' : '设置 $_pinLength 位 PIN'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_confirming) ...[
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 4, label: Text('4 位')),
                  ButtonSegment(value: 6, label: Text('6 位')),
                ],
                selected: {_pinLength},
                onSelectionChanged: (s) => _onLengthChanged(s.first),
              ),
              const SizedBox(height: CentliSpacing.section),
            ],
            PinPad(
              value: _confirming ? _second : _first,
              pinLength: _pinLength,
              onChanged: _onChanged,
              errorText: _error,
              subtitle: _confirming ? '请再输入一次' : '用于查看金额时验证',
            ),
          ],
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
  required Future<int> Function() resolvePinLength,
  String title = '输入 PIN',
}) async {
  final ok = await showGlassDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _VerifyPinDialog(
      title: title,
      verify: verify,
      resolvePinLength: resolvePinLength,
    ),
  );
  return ok == true;
}

class _VerifyPinDialog extends StatefulWidget {
  const _VerifyPinDialog({
    required this.title,
    required this.verify,
    required this.resolvePinLength,
  });

  final String title;
  final Future<bool> Function(String pin) verify;
  final Future<int> Function() resolvePinLength;

  @override
  State<_VerifyPinDialog> createState() => _VerifyPinDialogState();
}

class _VerifyPinDialogState extends State<_VerifyPinDialog> {
  String _pin = '';
  String? _error;
  bool _busy = false;
  int? _pinLength;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final len = await widget.resolvePinLength();
      if (!mounted) return;
      setState(() => _pinLength = len);
    });
  }

  Future<void> _onChanged(String v) async {
    final len = _pinLength;
    if (len == null) return;
    setState(() {
      _pin = v;
      _error = null;
    });
    if (v.length != len || _busy) return;
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
    final len = _pinLength;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Text(widget.title),
      content: SizedBox(
        width: 280,
        child: len == null
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : PinPad(
                value: _pin,
                pinLength: len,
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

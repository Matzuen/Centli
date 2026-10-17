import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/db/database_provider.dart';
import 'local_speech.dart';
import 'smart_bookkeeping_submit.dart';
import '../capture/capture_intake_actions.dart';

Future<void> showQuickBookkeepingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const QuickBookkeepingSheet(),
  );
}

/// WeChat-style hold-to-talk voice bookkeeping panel.
class QuickBookkeepingSheet extends ConsumerStatefulWidget {
  const QuickBookkeepingSheet({super.key, this.speech, this.now});

  /// Injected for tests; production uses [LocalSpeechService].
  final VoiceSpeechBackend? speech;

  /// Clock for hold-duration checks (tests inject a controllable clock).
  final DateTime Function()? now;

  @override
  ConsumerState<QuickBookkeepingSheet> createState() =>
      _QuickBookkeepingSheetState();
}

/// Pure helpers for hold-to-talk (unit-tested).
@visibleForTesting
class HoldTalkPhysics {
  static const cancelThresholdDp = 60.0;
  static const minHold = Duration(milliseconds: 500);

  static bool isCancelZone({
    required double startY,
    required double currentY,
  }) =>
      startY - currentY > cancelThresholdDp;

  static bool isTooShort(DateTime start, DateTime end) =>
      end.difference(start) < minHold;
}

class _QuickBookkeepingSheetState extends ConsumerState<QuickBookkeepingSheet> {
  late final VoiceSpeechBackend _speech =
      widget.speech ?? LocalSpeechService();
  DateTime _now() => widget.now?.call() ?? DateTime.now();
  final _textCtrl = TextEditingController();

  /// idle | starting | listening | canceling | recognizing | done | error
  String _phase = 'idle';
  double _level = 0;
  String? _error;
  var _busy = false;
  var _submitting = false;
  var _gotText = false;

  /// Hold-session state (WeChat-style).
  var _holding = false;
  var _willCancel = false;
  double? _pointerStartY;
  DateTime? _holdStartedAt;
  String _textBeforeHold = '';
  String _sessionText = '';

  @override
  void dispose() {
    _textCtrl.dispose();
    _speech.cancel();
    super.dispose();
  }

  void _bindSpeechCallbacks() {
    _speech.onStatusChanged = (status) {
      if (!mounted || !_holding) return;
      if (status == 'listening') {
        setState(() {
          _phase = _willCancel ? 'canceling' : 'listening';
          _error = null;
        });
      } else if (status == 'error') {
        setState(() {
          _phase = 'error';
          _level = 0;
          _holding = false;
          _error ??= _speech.friendlyError ?? '语音识别失败';
        });
      }
    };
    _speech.onSoundLevel = (level) {
      if (!mounted || !_holding) return;
      setState(() => _level = level);
    };
    _speech.onErrorMessage = (msg) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        _level = 0;
        _holding = false;
        _error = msg;
      });
    };
  }

  Future<void> _beginHold(Offset globalPosition) async {
    if (_busy || _submitting || _holding) return;
    _bindSpeechCallbacks();
    setState(() {
      _holding = true;
      _willCancel = false;
      _pointerStartY = globalPosition.dy;
      _holdStartedAt = _now();
      _busy = true;
      _phase = 'starting';
      _error = null;
      _gotText = false;
      _level = 0;
      _textBeforeHold = _textCtrl.text;
      _sessionText = '';
    });
    try {
      final ok = await _speech.ensureReady();
      if (!mounted) return;
      if (!_holding) return; // released during ensureReady
      if (!ok) {
        setState(() {
          _holding = false;
          _phase = 'error';
          _error = _speech.friendlyError ?? '当前设备不支持语音识别，请或直接输入文字';
        });
        return;
      }
      setState(() => _phase = _willCancel ? 'canceling' : 'listening');
      await _speech.start(
        onResult: (r) {
          if (!mounted || !_holding) return;
          final text = r.text.trim();
          if (text.isNotEmpty) {
            _gotText = true;
            _sessionText = r.text;
            setState(() {});
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _holding = false;
        _phase = 'error';
        _level = 0;
        _error = _speech.friendlyError ?? '语音识别失败：';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onHoldMove(Offset globalPosition) {
    if (!_holding || _pointerStartY == null) return;
    final cancel = HoldTalkPhysics.isCancelZone(
      startY: _pointerStartY!,
      currentY: globalPosition.dy,
    );
    if (cancel != _willCancel) {
      setState(() {
        _willCancel = cancel;
        if (_phase == 'listening' || _phase == 'canceling' || _phase == 'starting') {
          _phase = cancel ? 'canceling' : 'listening';
        }
      });
    }
  }

  Future<void> _endHold() async {
    if (!_holding) return;
    final started = _holdStartedAt;
    final willCancel = _willCancel;
    final session = _sessionText;
    final before = _textBeforeHold;
    setState(() {
      _holding = false;
      _willCancel = false;
      _pointerStartY = null;
      _level = 0;
    });

    if (willCancel) {
      try {
        await _speech.cancel();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _textCtrl.text = before;
        _sessionText = '';
        _phase = before.trim().isEmpty ? 'idle' : 'done';
        _error = null;
      });
      return;
    }

    if (started != null &&
        HoldTalkPhysics.isTooShort(started, _now())) {
      try {
        await _speech.cancel();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _textCtrl.text = before;
        _sessionText = '';
        _phase = before.trim().isEmpty ? 'idle' : 'done';
        _error = '说话时间太短';
      });
      return;
    }

    try {
      await _speech.stop();
    } catch (_) {}
    if (!mounted) return;

    final text = session.trim().isNotEmpty ? session : _sessionText;
    if (text.trim().isEmpty && !_gotText) {
      setState(() {
        _textCtrl.text = before;
        _phase = 'error';
        _error = '没有听清，请靠近麦克风再说，或直接输入文字';
      });
      return;
    }

    setState(() {
      if (text.trim().isNotEmpty) {
        _textCtrl.text = text;
        _textCtrl.selection = TextSelection.collapsed(
          offset: _textCtrl.text.length,
        );
      }
      _phase = _textCtrl.text.trim().isEmpty ? 'error' : 'done';
      if (_textCtrl.text.trim().isEmpty) {
        _error = '没有听清，请靠近麦克风再说，或直接输入文字';
      } else {
        _error = null;
      }
    });
  }

  Future<void> _submit({required bool keepOpen}) async {
    if (_submitting) return;
    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _phase = 'error';
        _error = '请先按住说话，或直接输入文字';
      });
      return;
    }
    final db = ref.read(databaseProvider);
    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择账本')),
      );
      return;
    }
    final accounts = await db.loadActiveAccounts(ledgerId);
    setState(() => _submitting = true);
    try {
      final outcome = await submitSmartBookkeepingText(
        db: db,
        rawText: raw,
        ledgerId: ledgerId,
        accounts: accounts,
      );
      if (!mounted) return;
      if (!outcome.ok) {
        setState(() {
          _phase = 'error';
          _error = outcome.errorMessage ?? '记账失败';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outcome.errorMessage ?? '记账失败')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.summary ?? '已记账')),
      );
      if (keepOpen) {
        _textCtrl.clear();
        setState(() {
          _phase = 'idle';
          _error = null;
        });
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildDots(ColorScheme scheme) {
    final active = _holding && (_phase == 'listening' || _phase == 'canceling');
    final intensity = active
        ? ((_level + 2) / 12).clamp(0.2, 1.0)
        : (_phase == 'starting' ? 0.45 : 0.25);
    final color = _willCancel ? scheme.error : scheme.onSurfaceVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 12; i++)
          Container(
            width: 8,
            height: 8 + (active ? (i % 3) * 6.0 * intensity : 0),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25 + 0.45 * intensity),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  String get _holdLabel {
    if (_phase == 'starting') return '正在打开麦克风…';
    if (_willCancel) return '松开 取消';
    if (_holding) return '松开 结束';
    return '按住 说话';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final showError = _error != null && _error!.isNotEmpty && !_holding;
    final holdColor = _willCancel
        ? scheme.error
        : (_holding ? scheme.primary : scheme.onSurface);
    final holdFg = _willCancel
        ? scheme.onError
        : (_holding ? scheme.onPrimary : scheme.surface);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '快速记账',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  IconButton(
                    tooltip: '智能填单设置',
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/me/smart-fill');
                    },
                    icon: Icon(
                      Icons.settings_outlined,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CentliSpacing.item),
              if (_holding)
                SizedBox(height: 56, child: Center(child: _buildDots(scheme))),
              if (_holding && _sessionText.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _sessionText,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              if (showError)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                  ),
                ),
              TextField(
                controller: _textCtrl,
                minLines: 1,
                maxLines: 3,
                enabled: !_holding && !_submitting,
                decoration: InputDecoration(
                  hintText: '说一句或打一句，如「午餐20元 支付宝」',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  if (_textCtrl.text.trim().isNotEmpty && _phase != 'done') {
                    setState(() {
                      _phase = 'done';
                      _error = null;
                    });
                  }
                },
              ),
              const SizedBox(height: CentliSpacing.sectionLoose),
              // Full-width hold bar — Listener for immediate press (no long-press delay).
              Listener(
                key: const ValueKey('hold_talk_bar'),
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) {
                  if (_busy || _submitting) return;
                  _beginHold(e.position);
                },
                onPointerMove: (e) => _onHoldMove(e.position),
                onPointerUp: (_) => _endHold(),
                onPointerCancel: (_) async {
                  _willCancel = true;
                  await _endHold();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: holdColor,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Text(
                    _holdLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: holdFg,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              if (!_holding && !_submitting) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final nav = Navigator.of(context);
                          nav.pop();
                          final overlayCtx = nav.overlay?.context;
                          if (overlayCtx != null && overlayCtx.mounted) {
                            importCaptureFromScreenshot(overlayCtx, ref);
                          }
                        },
                        icon: const Icon(Icons.document_scanner_outlined),
                        label: const Text('截图识别'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          final nav = Navigator.of(context);
                          nav.pop();
                          final overlayCtx = nav.overlay?.context;
                          if (overlayCtx != null && overlayCtx.mounted) {
                            importCaptureFromClipboard(overlayCtx, ref);
                          }
                        },
                        icon: const Icon(Icons.content_paste_outlined),
                        label: const Text('剪贴板'),
                      ),
                    ),
                  ],
                ),
              ],
              if (!_holding &&
                  _textCtrl.text.trim().isNotEmpty &&
                  !_submitting) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _submit(keepOpen: false),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                  ),
                  child: const Text('记账并关闭'),
                ),
                TextButton(
                  onPressed: () => _submit(keepOpen: true),
                  child: const Text('记账并继续'),
                ),
              ],
              if (_submitting)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

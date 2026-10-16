import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/db/database_provider.dart';
import 'local_speech.dart';
import 'smart_bookkeeping_submit.dart';

Future<void> showVoiceBookkeepingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const VoiceBookkeepingSheet(),
  );
}

/// Independent voice bookkeeping panel (Finch-style).
///
/// Long-recording mode entry is hidden for now (no separate long-recording
/// engine); see docs/grokbot/audit_input/notes.md.
class VoiceBookkeepingSheet extends ConsumerStatefulWidget {
  const VoiceBookkeepingSheet({super.key});

  @override
  ConsumerState<VoiceBookkeepingSheet> createState() =>
      _VoiceBookkeepingSheetState();
}

class _VoiceBookkeepingSheetState extends ConsumerState<VoiceBookkeepingSheet> {
  final _speech = LocalSpeechService();
  final _textCtrl = TextEditingController();

  /// idle | starting | listening | recognizing | done | error
  String _phase = 'idle';
  double _level = 0;
  String? _error;
  var _busy = false;
  var _submitting = false;
  var _gotText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startRecording();
    });
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _speech.cancel();
    super.dispose();
  }

  void _bindSpeechCallbacks() {
    _speech.onStatusChanged = (status) {
      if (!mounted) return;
      if (status == 'listening') {
        setState(() {
          _phase = 'listening';
          _error = null;
        });
      } else if (status == 'notListening') {
        if (_phase == 'listening') {
          setState(() => _phase = 'recognizing');
          Future<void>.delayed(const Duration(milliseconds: 1600), () {
            if (!mounted) return;
            if (_phase == 'recognizing' &&
                !_gotText &&
                _textCtrl.text.trim().isEmpty) {
              setState(() {
                _phase = 'error';
                _level = 0;
                _error = '没有听清，请靠近麦克风再说，或改用文字记账';
              });
            }
          });
        }
      } else if (status == 'done') {
        setState(() {
          if (_phase != 'done' && _phase != 'error') {
            _phase = _textCtrl.text.trim().isEmpty ? 'error' : 'done';
          }
          _level = 0;
        });
      } else if (status == 'error') {
        setState(() {
          _phase = 'error';
          _level = 0;
          _error ??= _speech.friendlyError ?? '语音识别失败';
        });
      }
    };
    _speech.onSoundLevel = (level) {
      if (!mounted || _phase != 'listening') return;
      setState(() => _level = level);
    };
    _speech.onErrorMessage = (msg) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        _level = 0;
        _error = msg;
      });
    };
  }

  Future<void> _startRecording() async {
    if (_busy || _submitting) return;
    _bindSpeechCallbacks();
    setState(() {
      _busy = true;
      _phase = 'starting';
      _error = null;
      _gotText = false;
      _level = 0;
      _textCtrl.clear();
    });
    try {
      final ok = await _speech.ensureReady();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _phase = 'error';
          _error = _speech.friendlyError ?? '当前设备不支持语音识别，请改用文字记账';
        });
        return;
      }
      setState(() => _phase = 'listening');
      await _speech.start(
        onResult: (r) {
          if (!mounted) return;
          final text = r.text.trim();
          if (text.isNotEmpty) {
            _gotText = true;
            setState(() {
              _textCtrl.text = r.text;
              _textCtrl.selection = TextSelection.collapsed(
                offset: _textCtrl.text.length,
              );
              _phase = r.finalResult ? 'recognizing' : 'listening';
            });
          }
          if (r.finalResult) {
            _stopSpeech(userInitiated: false).then((_) async {
              if (!mounted) return;
              if (text.isEmpty) {
                setState(() {
                  _phase = 'error';
                  _error = '没有听清，请靠近麦克风再说，或改用文字记账';
                });
                return;
              }
              setState(() => _phase = 'done');
              await _submit(keepOpen: false);
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = 'error';
        _level = 0;
        _error = _speech.friendlyError ?? '语音识别失败：$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopSpeech({bool userInitiated = false}) async {
    try {
      if (userInitiated) {
        await _speech.cancel();
      } else {
        await _speech.stop();
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _level = 0);
    }
  }

  Future<void> _submit({required bool keepOpen}) async {
    if (_submitting) return;
    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _phase = 'error';
        _error = '没有听清，请重新录音或改用文字记账';
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
        await _startRecording();
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _buildDots(ColorScheme scheme) {
    final listening = _phase == 'listening';
    final intensity = listening
        ? ((_level + 2) / 12).clamp(0.2, 1.0)
        : (_phase == 'recognizing' || _phase == 'starting' ? 0.45 : 0.25);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 12; i++)
          Container(
            width: 8,
            height: 8 + (listening ? (i % 3) * 6.0 * intensity : 0),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(
                alpha: 0.25 + 0.45 * intensity,
              ),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final showError = _phase == 'error' && (_error?.isNotEmpty ?? false);
    final showResult = _textCtrl.text.trim().isNotEmpty &&
        (_phase == 'done' || _phase == 'error' || _phase == 'recognizing');

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
                      '语音记账',
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
              SizedBox(height: 56, child: Center(child: _buildDots(scheme))),
              const SizedBox(height: 12),
              if (_phase == 'starting' || _phase == 'listening')
                Text(
                  _phase == 'starting' ? '正在打开麦克风…' : '正在听，请说…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (_phase == 'recognizing')
                Text(
                  '识别中…',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
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
              if (showResult) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _textCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.55,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: CentliSpacing.sectionLoose),
              if (_phase == 'done' && !_submitting) ...[
                FilledButton(
                  onPressed: () => _submit(keepOpen: false),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                  ),
                  child: const Text('记账并关闭'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _submit(keepOpen: true),
                  child: const Text('记账并继续'),
                ),
              ] else if (_phase == 'listening' || _phase == 'starting') ...[
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _stopSpeech(userInitiated: true).then((_) {
                            if (mounted) {
                              setState(() {
                                _phase = 'error';
                                _error = '已取消，可重新录音';
                              });
                            }
                          }),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  child: const Text('停止'),
                ),
              ] else ...[
                FilledButton.icon(
                  onPressed: (_busy || _submitting) ? null : _startRecording,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(26),
                    ),
                    backgroundColor: scheme.onSurface,
                    foregroundColor: scheme.surface,
                  ),
                  icon: const Icon(Icons.mic),
                  label: Text(_submitting ? '记账中…' : '重新录音'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

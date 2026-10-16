import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../core/utils/money.dart';
import '../../core/utils/amount_expr.dart';
import '../../core/widgets/centli_icon.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/txn_tags.dart';
import '../../data/db/database_provider.dart';
import 'ai_text_fill.dart';
import 'llm_text_fill.dart';
import 'local_speech.dart';
import 'category_picker_sheet.dart';

Future<void> showBookkeepingSheet(
  BuildContext context, {
  Transaction? existing,
  bool expandAi = false,
  bool startVoice = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => BookkeepingSheet(
      existing: existing,
      expandAi: expandAi,
      startVoice: startVoice,
    ),
  );
}

class BookkeepingSheet extends ConsumerStatefulWidget {
  const BookkeepingSheet({
    super.key,
    this.existing,
    this.expandAi = false,
    this.startVoice = false,
  });

  final Transaction? existing;
  final bool expandAi;
  final bool startVoice;

  @override
  ConsumerState<BookkeepingSheet> createState() => _BookkeepingSheetState();
}

class _BookkeepingSheetState extends ConsumerState<BookkeepingSheet> {
  String _type = 'out';
  String _amountText = '0';
  String _toAmountText = '0';
  String? _fxRateText;

  /// When cross-ccy: user enters to_amount (true) or fx_rate (false).
  bool _useToAmount = true;
  String? _accountId;
  String? _toAccountId;
  String? _categoryId;
  String? _merchant;
  final _noteCtrl = TextEditingController();
  List<String> _tags = [];
  final _aiTextCtrl = TextEditingController();
  bool _aiExpanded = false;
  final _speech = LocalSpeechService();
  var _speechListening = false;
  var _speechBusy = false;
  var _aiFilling = false;

  /// idle | starting | listening | recognizing
  String _speechPhase = 'idle';
  double _speechLevel = 0;
  var _gotSpeechText = false;
  List<Account> _accounts = [];
  List<Category> _categories = [];
  String? _ledgerId;
  bool _loading = true;
  bool _saving = false;
  DateTime _happenAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.expandAi || widget.startVoice) {
      _aiExpanded = true;
    }
    _load();
    if (widget.startVoice) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bootAiMode();
      });
    }
  }

  Future<void> _bootAiMode() async {
    if (!mounted) return;
    await _toggleVoiceFill();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _aiTextCtrl.dispose();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null) {
      setState(() => _loading = false);
      return;
    }
    var accounts = await db.loadActiveAccounts(ledgerId);
    final existing = widget.existing;
    if (existing != null) {
      final need = <String>{
        existing.accountId,
        if (existing.toAccountId != null) existing.toAccountId!,
      };
      final have = {for (final a in accounts) a.id};
      for (final id in need) {
        if (!have.contains(id)) {
          final a = await db.getAccount(id);
          if (a != null) accounts = [...accounts, a];
        }
      }
    }
    final cats = await db.loadCategories(
      ledgerId,
      _type == 'in' ? 'in' : 'out',
    );
    if (!mounted) return;
    setState(() {
      _ledgerId = ledgerId;
      _accounts = accounts;
      if (existing != null) {
        _type = existing.type;
        _amountText = fromMinor(
          existing.currency,
          existing.amountMinor,
        ).toStringAsFixed(currencyDecimals[existing.currency] ?? 2);
        // trim trailing zeros from whole amounts
        if (_amountText.contains('.')) {
          _amountText = _amountText.replaceFirst(RegExp(r'\.?0+$'), '');
          if (_amountText.isEmpty) _amountText = '0';
        }
        _accountId = existing.accountId;
        _toAccountId = existing.toAccountId;
        _categoryId = existing.categoryId;
        _merchant = existing.merchant;
        _noteCtrl.text = existing.note ?? '';
        _tags = List<String>.from(decodeTxnTags(existing.tags));
        _happenAt = DateTime.fromMillisecondsSinceEpoch(
          existing.happenAt,
          isUtc: true,
        ).toLocal();
        if (existing.toAmountMinor != null) {
          final toAcc = accounts.where((a) => a.id == existing.toAccountId);
          final toCcy = toAcc.isNotEmpty
              ? toAcc.first.currency
              : existing.currency;
          _toAmountText = fromMinor(
            toCcy,
            existing.toAmountMinor!,
          ).toStringAsFixed(currencyDecimals[toCcy] ?? 2);
        }
        if (existing.fxRate != null) {
          _fxRateText = existing.fxRate.toString();
        }
      } else {
        _accountId = accounts.isNotEmpty ? accounts.first.id : null;
        _toAccountId = accounts.length > 1 ? accounts[1].id : null;
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
      _categories = cats;
      // reload cats for existing type (may differ from default out)
      _loading = false;
    });
    if (existing != null && existing.type != 'out') {
      await _reloadCategories();
      if (existing.categoryId != null) {
        setState(() => _categoryId = existing.categoryId);
      }
    }
  }

  Future<void> _reloadCategories({bool resetSelection = false}) async {
    if (_ledgerId == null || _type == 'transfer') return;
    final db = ref.read(databaseProvider);
    final cats = await db.loadCategories(
      _ledgerId!,
      _type == 'in' ? 'in' : 'out',
    );
    setState(() {
      _categories = cats;
      if (resetSelection ||
          _categoryId == null ||
          !cats.any((c) => c.id == _categoryId)) {
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
    });
  }

  Account? _accountById(String? id) {
    if (id == null || _accounts.isEmpty) return null;
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  String get _currency {
    return _accountById(_accountId)?.currency ?? 'CNY';
  }

  String get _toCurrency {
    return _accountById(_toAccountId)?.currency ?? _currency;
  }

  bool get _isCrossCurrency {
    if (_type != 'transfer') return false;
    final from = _accountById(_accountId);
    final to = _accountById(_toAccountId);
    if (from == null || to == null) return false;
    return from.currency != to.currency;
  }

  int get _maxDecimals => currencyDecimals[_currency] ?? 2;

  void _onKey(String key) {
    setState(() {
      if (key == 'AC') {
        _amountText = '0';
      } else if (key == '+' ||
          key == '-' ||
          key == '\u00d7' ||
          key == '\u00f7' ||
          key == '*' ||
          key == '/') {
        _amountText = applyAmountOperator(_amountText, key);
      } else {
        _amountText = applyAmountKey(_amountText, key, _maxDecimals);
      }
    });
  }

  double? _evalAmount(String expr) => evalAmountExpr(expr);

  bool get _amountHasOperator => amountExprHasOperator(_amountText);

    Future<void> _promptCrossCurrency({bool keepOpen = false}) async {
    final fromCcy = _currency;
    final toCcy = _toCurrency;
    final major = _evalAmount(_amountText) ?? 0;
    final toCtrl = TextEditingController(
      text: _toAmountText == '0' ? '' : _toAmountText,
    );
    final rateCtrl = TextEditingController(text: _fxRateText ?? '');
    var useTo = _useToAmount;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: Text('\u8de8\u5e01\u8f6c\u8d26 ($fromCcy \u2192 $toCcy)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '\u8f6c\u51fa ${formatMinor(fromCcy, toMinor(fromCcy, major))}',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('\u5bf9\u65b9\u91d1\u989d'),
                      ),
                      ButtonSegment(value: false, label: Text('\u6c47\u7387')),
                    ],
                    selected: {useTo},
                    onSelectionChanged: (s) => setLocal(() => useTo = s.first),
                  ),
                  const SizedBox(height: 12),
                  if (useTo)
                    TextField(
                      controller: toCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '\u8f6c\u5165\u91d1\u989d ($toCcy)',
                        border: const OutlineInputBorder(),
                      ),
                    )
                  else
                    TextField(
                      controller: rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '1 $fromCcy = ? $toCcy',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('\u53d6\u6d88'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('\u786e\u5b9a'),
                ),
              ],
            );
          },
        );
      },
    );

    try {
      if (ok != true) return;
      setState(() {
        _useToAmount = useTo;
        if (useTo) {
          _toAmountText = toCtrl.text.trim().isEmpty ? '0' : toCtrl.text.trim();
          _fxRateText = null;
        } else {
          _fxRateText = rateCtrl.text.trim();
          _toAmountText = '0';
        }
      });
      await _save(skipCrossPrompt: true, keepOpen: keepOpen);
    } finally {
      toCtrl.dispose();
      rateCtrl.dispose();
    }
  }

  Future<void> _save({
    bool skipCrossPrompt = false,
    bool keepOpen = false,
  }) async {
    final major = _evalAmount(_amountText);
    if (major == null || major <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u8f93\u5165\u91d1\u989d')),
      );
      return;
    }
    // Collapse expression to evaluated major so subsequent FX math uses a plain number.
    if (_amountHasOperator) {
      final decimals = _maxDecimals;
      var collapsed = major.toStringAsFixed(decimals);
      if (decimals > 0) {
        collapsed = collapsed.replaceFirst(RegExp(r'\.?0+$'), '');
        if (collapsed.isEmpty) collapsed = '0';
      }
      _amountText = collapsed;
    }
    if (_ledgerId == null || _accountId == null) return;

    if (_type == 'transfer') {
      if (_toAccountId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('\u8bf7\u9009\u62e9\u8f6c\u5165\u8d26\u6237'),
          ),
        );
        return;
      }
      if (_toAccountId == _accountId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u8f6c\u51fa\u4e0e\u8f6c\u5165\u8d26\u6237\u4e0d\u80fd\u76f8\u540c',
            ),
          ),
        );
        return;
      }
      if (_isCrossCurrency && !skipCrossPrompt) {
        final hasTo = (double.tryParse(_toAmountText) ?? 0) > 0;
        final hasRate = (double.tryParse(_fxRateText ?? '') ?? 0) > 0;
        if (!hasTo && !hasRate) {
          await _promptCrossCurrency(keepOpen: keepOpen);
          return;
        }
      }
    } else if (_categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('\u8bf7\u9009\u62e9\u5206\u7c7b')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final amountMinor = toMinor(_currency, major);
      double? fxRate;
      int? toAmountMinor;

      if (_type == 'transfer' && _isCrossCurrency) {
        if (_useToAmount || (double.tryParse(_toAmountText) ?? 0) > 0) {
          final toMajor = double.tryParse(_toAmountText) ?? 0;
          if (toMajor <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('\u8bf7\u8f93\u5165\u5bf9\u65b9\u91d1\u989d'),
              ),
            );
            return;
          }
          toAmountMinor = toMinor(_toCurrency, toMajor);
          fxRate = toMajor / major; // 1 from = rate to
        } else {
          fxRate = double.tryParse(_fxRateText ?? '');
          if (fxRate == null || fxRate <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('\u8bf7\u8f93\u5165\u6709\u6548\u6c47\u7387'),
              ),
            );
            return;
          }
          toAmountMinor = toMinor(_toCurrency, major * fxRate);
        }
      } else if (_type == 'transfer') {
        toAmountMinor = amountMinor;
      }

      final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
      final merchant = (_merchant ?? '').trim().isEmpty
          ? null
          : _merchant!.trim();
      final toAcc = _type == 'transfer' ? _toAccountId : null;
      final cat = _type == 'transfer' ? null : _categoryId;
      if (widget.existing != null) {
        await db.updateManualTransaction(
          id: widget.existing!.id,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
          merchant: merchant,
          note: note,
          tags: _tags,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      } else {
        await db.insertManualTransaction(
          ledgerId: _ledgerId!,
          type: _type,
          amountMinor: amountMinor,
          currency: _currency,
          accountId: _accountId!,
          toAccountId: toAcc,
          categoryId: cat,
          merchant: merchant,
          note: note,
          tags: _tags,
          happenAt: _happenAt,
          fxRate: fxRate,
          toAmountMinor: toAmountMinor,
        );
      }
      if (!mounted) return;
      if (keepOpen && widget.existing == null) {
        // 再记一笔：落库后保留面板，清空金额/备注，时间刷新为现在。
        setState(() {
          _amountText = '0';
          _toAmountText = '0';
          _fxRateText = null;
          _noteCtrl.clear();
          _merchant = null;
          _happenAt = DateTime.now();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存，可继续记账')));
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _happenAtLabel {
    final now = DateTime.now();
    final sameDay =
        _happenAt.year == now.year &&
        _happenAt.month == now.month &&
        _happenAt.day == now.day;
    if (sameDay) {
      return DateFormat('HH:mm').format(_happenAt);
    }
    return DateFormat('yyyy-MM-dd HH:mm').format(_happenAt);
  }

  Future<void> _pickHappenAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _happenAt,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('zh', 'CN'),
      helpText: '选择日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_happenAt),
      helpText: '选择时间',
      builder: (context, child) {
        return Localizations.override(
          context: context,
          locale: const Locale('zh', 'CN'),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (time == null || !mounted) return;
    setState(() {
      _happenAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _bindSpeechCallbacks() {
    _speech.onStatusChanged = (status) {
      if (!mounted) return;
      if (status == 'listening') {
        setState(() {
          _speechListening = true;
          _speechPhase = 'listening';
        });
      } else if (status == 'notListening') {
        // Engine paused; may still deliver final result shortly.
        if (_speechPhase == 'listening') {
          setState(() => _speechPhase = 'recognizing');
          // If no final callback arrives, surface a clear tip after a beat.
          Future<void>.delayed(const Duration(milliseconds: 1600), () {
            if (!mounted) return;
            if (_speechPhase == 'recognizing' &&
                !_gotSpeechText &&
                _aiTextCtrl.text.trim().isEmpty) {
              setState(() {
                _speechListening = false;
                _speechPhase = 'idle';
                _speechLevel = 0;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('没有听清，请点麦克风重试，或改用文字'),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          });
        }
      } else if (status == 'done') {
        // UI reset only — empty/error snackbars are shown from onResult / onError.
        setState(() {
          _speechListening = false;
          if (_speechPhase != 'idle') {
            _speechPhase = 'idle';
          }
          _speechLevel = 0;
        });
      } else if (status == 'error') {
        setState(() {
          _speechListening = false;
          _speechPhase = 'idle';
          _speechLevel = 0;
        });
      }
    };
    _speech.onSoundLevel = (level) {
      if (!mounted || !_speechListening) return;
      setState(() => _speechLevel = level);
    };
    _speech.onErrorMessage = (msg) {
      if (!mounted) return;
      setState(() {
        _speechListening = false;
        _speechPhase = 'idle';
        _speechLevel = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
    };
  }

  Future<void> _toggleVoiceFill() async {
    if (_speechListening || _speechPhase == 'recognizing') {
      await _stopSpeech(userInitiated: true);
      return;
    }
    if (_speechBusy || _aiFilling) return;
    _bindSpeechCallbacks();
    setState(() {
      _speechBusy = true;
      _speechPhase = 'starting';
      _aiExpanded = true;
      _gotSpeechText = false;
      _speechLevel = 0;
    });
    try {
      final ok = await _speech.ensureReady();
      if (!mounted) return;
      if (!ok) {
        setState(() => _speechPhase = 'idle');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_speech.friendlyError ?? '当前设备不支持语音识别，请改用文字话术'),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
      setState(() {
        _speechListening = true;
        _speechPhase = 'listening';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在听… 请说出记账内容，说完稍等识别'),
          duration: Duration(seconds: 2),
        ),
      );
      await _speech.start(
        onResult: (r) {
          if (!mounted) return;
          final text = r.text.trim();
          if (text.isNotEmpty) {
            _gotSpeechText = true;
            setState(() {
              _aiTextCtrl.text = r.text;
              _aiTextCtrl.selection = TextSelection.collapsed(
                offset: _aiTextCtrl.text.length,
              );
              if (!r.finalResult) {
                _speechPhase = 'listening';
              } else {
                _speechPhase = 'recognizing';
              }
            });
          }
          if (r.finalResult && text.isNotEmpty) {
            _stopSpeech(userInitiated: false).then((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('识别完成，正在填入…'),
                  duration: Duration(seconds: 1),
                ),
              );
              _applyAiTextFill();
            });
          } else if (r.finalResult && text.isEmpty) {
            _stopSpeech(userInitiated: false).then((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('没有听清，请重试或改用文字'),
                  duration: Duration(seconds: 3),
                ),
              );
            });
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _speechListening = false;
        _speechPhase = 'idle';
        _speechLevel = 0;
      });
      final msg = _speech.friendlyError ?? '语音识别失败: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
    } finally {
      if (mounted) setState(() => _speechBusy = false);
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
      setState(() {
        _speechListening = false;
        if (_speechPhase != 'recognizing' || userInitiated) {
          _speechPhase = 'idle';
        }
        _speechLevel = 0;
      });
    } else {
      _speechListening = false;
      _speechPhase = 'idle';
    }
  }

  String get _speechStatusLabel {
    switch (_speechPhase) {
      case 'starting':
        return '正在启动麦克风…';
      case 'listening':
        return '正在听… 请说话';
      case 'recognizing':
        return '识别中…';
      default:
        return '';
    }
  }

  Future<void> _applyAiTextFill() async {
    final raw = _aiTextCtrl.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请先输入记账话术')));
      return;
    }
    if (_ledgerId == null) return;
    if (_aiFilling) return;

    setState(() => _aiFilling = true);
    try {
      final db = ref.read(databaseProvider);
      final outCats = await db.loadCategories(_ledgerId!, 'out');
      final inCats = await db.loadCategories(_ledgerId!, 'in');
      final catRefs = <CategoryRef>[
        for (final c in outCats)
          CategoryRef(
            name: c.name,
            id: c.id,
            parentId: c.parentId,
            kind: c.kind,
          ),
        for (final c in inCats)
          CategoryRef(
            name: c.name,
            id: c.id,
            parentId: c.parentId,
            kind: c.kind,
          ),
      ];
      final allCatNames = catRefs.map((c) => c.name).toList();
      final accountNames = _accounts.map((a) => a.name).toList();

      // Local parse first (always available as fallback).
      var parsed = parseBookkeepingText(
        raw,
        categoryNames: allCatNames,
        categories: catRefs,
        accountNames: accountNames,
      );

      // Optional LLM enhancement when configured.
      try {
        final llmSettings = SmartFillLlmSettings();
        final cfg = await llmSettings.load(db);
        if (cfg.isReady) {
          final llm = await parseBookkeepingTextWithLlm(
            raw,
            config: cfg,
            categoryNames: allCatNames,
            categories: catRefs,
            accountNames: accountNames,
          );
          if (llm != null && llm.hasUsefulFill) {
            parsed = llm;
          }
        }
      } catch (_) {
        // Keep local parse; never block fill/save on LLM errors.
      }

      if (!parsed.hasUsefulFill) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('未能识别，请换种说法或手动填写')));
        return;
      }

      final nextType = parsed.type ?? _type;
      List<Category> cats = _categories;
      if (nextType != 'transfer') {
        cats = await db.loadCategories(
          _ledgerId!,
          nextType == 'in' ? 'in' : 'out',
        );
      }

      // Only set category when confident; otherwise leave unset (do NOT guess first).
      String? categoryId;
      var categoryResolved = false;
      if (parsed.hasConfidentCategory && nextType != 'transfer') {
        Category? hit;
        for (final c in cats) {
          if (c.name == parsed.categoryName) {
            hit = c;
            break;
          }
        }
        hit ??= () {
          for (final c in cats) {
            if (c.name.contains(parsed.categoryName!) ||
                parsed.categoryName!.contains(c.name)) {
              return c;
            }
          }
          return null;
        }();
        if (hit != null) {
          categoryId = hit.id;
          categoryResolved = true;
        }
      }

      // Merchant rule may override category for expense/income.
      if (parsed.merchant != null &&
          parsed.merchant!.trim().isNotEmpty &&
          nextType != 'transfer') {
        final key = parsed.merchant!.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        final rule = await db.findMerchantRule(_ledgerId!, key);
        if (rule?.categoryId != null) {
          final id = rule!.categoryId!;
          if (cats.any((c) => c.id == id)) {
            categoryId = id;
            categoryResolved = true;
          }
        }
      }

      String? accountId = _accountId;
      String? toAccountId = _toAccountId;
      if (parsed.accountName != null) {
        for (final a in _accounts) {
          if (a.name == parsed.accountName) {
            accountId = a.id;
            break;
          }
        }
      }
      if (parsed.toAccountName != null) {
        for (final a in _accounts) {
          if (a.name == parsed.toAccountName) {
            toAccountId = a.id;
            break;
          }
        }
      }
      // Merchant-rule account if still default and rule has one.
      if (parsed.merchant != null && parsed.merchant!.trim().isNotEmpty) {
        final key = parsed.merchant!.trim().toLowerCase().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        final rule = await db.findMerchantRule(_ledgerId!, key);
        if (rule?.accountId != null &&
            _accounts.any((a) => a.id == rule!.accountId)) {
          if (parsed.accountName == null) {
            accountId = rule!.accountId;
          }
        }
      }

      String amountText = _amountText;
      if (parsed.amount != null) {
        var s = parsed.amount!.toStringAsFixed(2);
        s = s.replaceFirst(RegExp(r'\.?0+$'), '');
        if (s.isEmpty) s = '0';
        amountText = s;
      }

      // Note = leftover remark only. Merchant is stored on its own column.
      final leftover = parsed.note?.trim();
      final noteText = (leftover != null && leftover.isNotEmpty)
          ? leftover
          : '';
      final merchantText = parsed.merchant?.trim();

      if (!mounted) return;
      setState(() {
        _type = nextType;
        _categories = cats;
        if (nextType == 'transfer') {
          _categoryId = null;
        } else if (categoryResolved) {
          _categoryId = categoryId;
        } else {
          // Unset rather than wrong guess.
          _categoryId = null;
        }
        _accountId = accountId;
        _toAccountId = toAccountId;
        _amountText = amountText;
        _merchant = (merchantText != null && merchantText.isNotEmpty)
            ? merchantText
            : null;
        _noteCtrl.text = noteText;
        if (parsed.happenAt != null) {
          _happenAt = parsed.happenAt!;
        }
        _aiExpanded = false;
      });

      final summary = parsed.hits.isEmpty
          ? '已预填'
          : '已预填：${parsed.hits.join(' · ')}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(summary)));
    } finally {
      if (mounted) setState(() => _aiFilling = false);
    }
  }

  Category? _categoryById(String? id) {
    if (id == null || _categories.isEmpty) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _pickCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories: _categories,
      selectedId: _categoryId,
    );
    if (!mounted) return;
    if (id != null) {
      setState(() => _categoryId = id);
      return;
    }
    // Dismiss or 管理: refresh tree, keep selection when still valid.
    await _reloadCategories();
  }

  Future<void> _pickAccount({required bool toAccount}) async {
    final current = toAccount ? _toAccountId : _accountId;
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _AccountPickerSheet(
          accounts: _accounts,
          selectedId: current,
          title: toAccount
              ? '\u9009\u62e9\u8f6c\u5165\u8d26\u6237'
              : '\u9009\u62e9\u8d26\u6237',
        );
      },
    );
    if (id == null || !mounted) return;
    setState(() {
      if (toAccount) {
        _toAccountId = id;
      } else {
        _accountId = id;
      }
    });
  }

  bool get _isDirty {
    final amt = _evalAmount(_amountText) ?? 0;
    return amt > 0 || _noteCtrl.text.trim().isNotEmpty || _tags.isNotEmpty;
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_isDirty) return true;
    final major = _evalAmount(_amountText) ?? 0;
    final label = major > 0
        ? formatMinor(_currency, toMinor(_currency, major))
        : (_noteCtrl.text.trim().isNotEmpty ? '备注' : '标签');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃这笔记账？'),
        content: Text('已输入 $label，确定放弃？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续记账'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _editSheetTags() async {
    final current = List<String>.from(_tags);
    final ctrl = TextEditingController();
    final suggestions = _ledgerId == null
        ? <String>[]
        : await ref.read(databaseProvider).listDistinctTags(_ledgerId!);
    if (!mounted) return;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void addTag(String raw) {
              var t = raw.trim();
              if (t.isEmpty) return;
              if (t.length > 12) t = t.substring(0, 12);
              if (current.contains(t) || current.length >= 5) return;
              setLocal(() => current.add(t));
              ctrl.clear();
            }

            return AlertDialog(
              title: const Text('标签'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final t in current)
                          InputChip(
                            label: Text(t),
                            onDeleted: () => setLocal(() => current.remove(t)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(
                        labelText: '新标签',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: addTag,
                    ),
                    if (suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final s in suggestions.take(12))
                            ActionChip(
                              label: Text(s),
                              onPressed: () => addTag(s),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, List<String>.from(current)),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
    if (result != null) setState(() => _tags = result);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.92;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardIfNeeded() && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _loading
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: CentliSpacing.item),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: scheme.outlineVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '记一笔 · ${ref.watch(currentLedgerProvider).valueOrNull?.name ?? ''}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      for (final entry in [
                                        ('out', '支出'),
                                        ('in', '收入'),
                                        ('transfer', '转账'),
                                      ])
                                        Expanded(
                                          child: InkWell(
                                            onTap: () {
                                              setState(() => _type = entry.$1);
                                              _reloadCategories(resetSelection: true);
                                            },
                                            child: Column(
                                              children: [
                                                Text(
                                                  entry.$2,
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                        fontWeight: _type == entry.$1
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                        color: _type == entry.$1
                                                            ? scheme.primary
                                                            : scheme.onSurfaceVariant,
                                                      ),
                                                ),
                                                const SizedBox(height: 6),
                                                Container(
                                                  height: 2,
                                                  color: _type == entry.$1
                                                      ? scheme.primary
                                                      : Colors.transparent,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Finch rhythm: compact amount (right), chips flush under.
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_amountHasOperator)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Text(
                                      _amountText,
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            height: 1.0,
                                          ),
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      formatMinor(
                                        _currency,
                                        toMinor(
                                          _currency,
                                          _evalAmount(_amountText) ?? 0,
                                        ),
                                      ),
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -0.8,
                                            height: 1.0,
                                            fontSize: 36,
                                          ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _currency,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: CentliSpacing.dense),
                                const Divider(height: 1, thickness: 0.5),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
                            // Finch chip row: time + category + account (or transfer legs)
                            child: _ChipScrollRow(
                              children: [
                                _MetaChip(
                                  icon: Icons.schedule_rounded,
                                  label: _happenAtLabel,
                                  onTap: _pickHappenAt,
                                ),
                                if (_type != 'transfer') ...[
                                  Builder(
                                    builder: (context) {
                                      final cat = _categoryById(_categoryId);
                                      return _MetaChip(
                                        leading: cat == null
                                            ? null
                                            : CentliIconChip(
                                                name: cat.name,
                                                kind: cat.kind,
                                                iconKey: cat.icon,
                                                size: 22,
                                              ),
                                        icon: cat == null
                                            ? Icons.category_outlined
                                            : null,
                                        label: cat?.name ?? '\u5206\u7c7b',
                                        onTap: _pickCategory,
                                      );
                                    },
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final acc = _accountById(_accountId);
                                      return _MetaChip(
                                        leading: acc == null
                                            ? null
                                            : CentliIconChip(
                                                name: acc.name,
                                                kind: 'account',
                                                iconKey: acc.icon,
                                                size: 22,
                                              ),
                                        icon: acc == null
                                            ? Icons
                                                  .account_balance_wallet_outlined
                                            : null,
                                        label: acc == null
                                            ? '\u8d26\u6237'
                                            : '${acc.name} \u00b7 ${acc.currency}',
                                        onTap: () =>
                                            _pickAccount(toAccount: false),
                                      );
                                    },
                                  ),
                                ] else ...[
                                  Builder(
                                    builder: (context) {
                                      final acc = _accountById(_accountId);
                                      return _MetaChip(
                                        leading: acc == null
                                            ? null
                                            : CentliIconChip(
                                                name: acc.name,
                                                kind: 'account',
                                                iconKey: acc.icon,
                                                size: 22,
                                              ),
                                        icon: Icons.south_west_rounded,
                                        label: acc == null
                                            ? '\u8f6c\u51fa'
                                            : '\u8f6c\u51fa \u00b7 ${acc.name}',
                                        onTap: () =>
                                            _pickAccount(toAccount: false),
                                      );
                                    },
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final acc = _accountById(_toAccountId);
                                      return _MetaChip(
                                        leading: acc == null
                                            ? null
                                            : CentliIconChip(
                                                name: acc.name,
                                                kind: 'account',
                                                iconKey: acc.icon,
                                                size: 22,
                                              ),
                                        icon: Icons.north_east_rounded,
                                        label: acc == null
                                            ? '\u8f6c\u5165'
                                            : '\u8f6c\u5165 \u00b7 ${acc.name}',
                                        onTap: () =>
                                            _pickAccount(toAccount: true),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_type == 'transfer' && _isCrossCurrency)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Text(
                                '\u8de8\u5e01\uff1a\u4fdd\u5b58\u65f6\u4f1a\u8be2\u95ee\u5bf9\u65b9\u91d1\u989d/\u6c47\u7387',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                            child: TextField(
                              controller: _noteCtrl,
                              decoration: InputDecoration(
                                hintText: '\u5907\u6ce8',
                                isDense: true,
                                prefixIcon: Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: scheme.onSurfaceVariant,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: '\u6807\u7b7e',
                                  icon: Icon(
                                    _tags.isEmpty
                                        ? Icons.sell_outlined
                                        : Icons.sell,
                                    size: 20,
                                  ),
                                  onPressed: _editSheetTags,
                                ),
                                filled: true,
                                fillColor: scheme.surfaceContainerHighest,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // L7: voice/text above keypad
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  onTap: () => setState(
                                    () => _aiExpanded = !_aiExpanded,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome,
                                          size: 18,
                                          color: scheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '文字记账',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  color: scheme.primary,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          '\u8bed\u97f3\u00b7\u6587\u5b57',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: scheme.onSurfaceVariant,
                                              ),
                                        ),
                                        Icon(
                                          _aiExpanded
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_aiExpanded) ...[
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _aiTextCtrl,
                                          minLines: 1,
                                          maxLines: 3,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) =>
                                              _applyAiTextFill(),
                                          decoration: InputDecoration(
                                            hintText:
                                                _speechPhase == 'listening'
                                                ? '正在听，请说出记账内容…'
                                                : _speechPhase == 'recognizing'
                                                ? '识别中…'
                                                : '例：午餐花了28.5 / 昨天支付宝地铁4元',
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton.filledTonal(
                                        tooltip:
                                            (_speechListening ||
                                                _speechPhase == 'recognizing')
                                            ? '停止'
                                            : '语音填单',
                                        onPressed: (_saving || _speechBusy)
                                            ? null
                                            : _toggleVoiceFill,
                                        style: _speechPhase == 'listening'
                                            ? IconButton.styleFrom(
                                                foregroundColor: Theme.of(
                                                  context,
                                                ).colorScheme.error,
                                              )
                                            : null,
                                        icon: _speechPhase == 'starting'
                                            ? const SizedBox(
                                                width: 22,
                                                height: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : Icon(
                                                _speechPhase == 'listening'
                                                    ? Icons.mic
                                                    : _speechPhase ==
                                                          'recognizing'
                                                    ? Icons.hearing
                                                    : Icons.mic_none,
                                              ),
                                      ),
                                      const SizedBox(width: 4),
                                      FilledButton(
                                        onPressed:
                                            (_saving ||
                                                _aiFilling ||
                                                _speechPhase == 'listening')
                                            ? null
                                            : _applyAiTextFill,
                                        child: Text(_aiFilling ? '…' : '填入'),
                                      ),
                                    ],
                                  ),
                                  if (_speechPhase != 'idle') ...[
                                    const SizedBox(height: 8),
                                    _SpeechStatusBanner(
                                      label: _speechStatusLabel,
                                      phase: _speechPhase,
                                      level: _speechLevel,
                                      onStop: (_speechBusy)
                                          ? null
                                          : () => _stopSpeech(
                                              userInitiated: true,
                                            ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),

                  SizedBox(height: CentliSpacing.sheetGap),
                  _Keypad(
                    onKey: _onKey,
                    onSubmit: _saving ? null : () => _save(),
                    onLongSubmit: (_saving || widget.existing != null)
                        ? null
                        : () => _save(keepOpen: true),
                  ),
                  SizedBox(
                    height: safeBottom > 0 ? safeBottom : CentliSpacing.dense,
                  ),
                ],
              ),
      ),
    ),
    );
  }
}

/// Two-column form select: label (labelMedium) + tappable value (bodyLarge) with ▾.

/// One Finch-style chip row: left-aligned, horizontal drag when overflowing.
class _ChipScrollRow extends StatelessWidget {
  const _ChipScrollRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(right: 16),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: CentliSpacing.item),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.onTap,
    this.icon,
    this.leading,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6B7A99).withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: 6),
              ] else if (icon != null) ...[
                Icon(icon, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPickerSheet extends StatelessWidget {
  const _AccountPickerSheet({
    required this.accounts,
    required this.title,
    this.selectedId,
  });

  final List<Account> accounts;
  final String title;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.55;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: accounts.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (context, i) {
                final a = accounts[i];
                final selected = a.id == selectedId;
                return ListTile(
                  leading: CentliIconChip(
                    name: a.name,
                    kind: 'account',
                    iconKey: a.icon,
                    size: 40,
                  ),
                  title: Text(
                    a.name,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(currencyLabel(a.currency)),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: CentliTheme.softBlue)
                      : null,
                  onTap: () => Navigator.pop(context, a.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onKey,
    required this.onSubmit,
    this.onLongSubmit,
  });

  final void Function(String key) onKey;
  final VoidCallback? onSubmit;

  /// Long-press on check: save and keep sheet open (再记一笔).
  final VoidCallback? onLongSubmit;

    static const _keys = [
    ['1', '2', '3', '+', '×'],
    ['4', '5', '6', '-', '÷'],
    ['7', '8', '9', '⌫', 'AC'],
    ['.', '0', '00', '✓'],
  ];

  Color _bg(BuildContext context, String k) {
    if (k == '\u2713') return CentliTheme.keypadConfirm(context);
    if (k == 'AC' || k == '\u232b') return CentliTheme.keypadAcBg(context);
    if (k == '+' || k == '-' || k == '×' || k == '÷') {
      return CentliTheme.keypadOpBg(context);
    }
    return CentliTheme.keypadNumBg(context);
  }

  Color _fg(BuildContext context, String k) {
    final scheme = Theme.of(context).colorScheme;
    if (k == '\u2713') return Colors.white;
    if (k == 'AC' || k == '\u232b') return CentliTheme.keypadAcFg(context);
    if (k == '+' || k == '-' || k == '×' || k == '÷') {
      return CentliTheme.softBlue;
    }
    return scheme.onSurface;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in _keys)
            Row(
              children: [
                for (final k in row)
                  Expanded(
                    flex: (row.length == 4 && k == '✓') ? 2 : 1,
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: SizedBox(
                        height: 52,
                        child: Tooltip(
                          message: k == '\u2713' ? '\u957f\u6309\u518d\u8bb0\u4e00\u7b14' : '',
                          child: Material(
                          color: _bg(context, k),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              if (k == '\u2713') {
                                onSubmit?.call();
                              } else {
                                onKey(k);
                              }
                            },
                            onLongPress: k == '\u2713' ? onLongSubmit : null,
                            child: Center(
                              child: Text(
                                k == '\u2713' ? '\u2713' : k,
                                style: TextStyle(
                                  fontSize: k == 'AC' ? 16 : 20,
                                  fontWeight: FontWeight.w700,
                                  color: _fg(context, k),
                                ),
                              ),
                            ),
                          ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SpeechStatusBanner extends StatelessWidget {
  const _SpeechStatusBanner({
    required this.label,
    required this.phase,
    required this.level,
    this.onStop,
  });

  final String label;
  final String phase;
  final double level;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = phase == 'listening';
    // Map mic level (~ -2..10 typical) into 0..1 for the bar.
    final intensity = listening
        ? ((level + 2) / 12).clamp(0.15, 1.0)
        : (phase == 'recognizing' ? 0.45 : 0.25);

    return Material(
      color: listening
          ? scheme.errorContainer.withValues(alpha: 0.85)
          : scheme.secondaryContainer.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              listening
                  ? Icons.graphic_eq
                  : phase == 'recognizing'
                  ? Icons.hourglass_top
                  : Icons.mic_none,
              color: listening ? scheme.error : scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: listening
                          ? scheme.onErrorContainer
                          : scheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: phase == 'recognizing' || phase == 'starting'
                          ? null
                          : intensity,
                      minHeight: 4,
                      backgroundColor: scheme.surface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            if (onStop != null) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: onStop, child: const Text('停止')),
            ],
          ],
        ),
      ),
    );
  }
}

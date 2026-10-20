import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/db/database_provider.dart';
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

/// Text quick-bookkeeping panel (long-press the center 「记一笔」 tab).
///
/// Type a sentence such as 「午餐20元 支付宝」; [submitSmartBookkeepingText]
/// parses amount / category / account locally (optional LLM enhancement) and
/// inserts the transaction. Voice dictation was removed — text only.
class QuickBookkeepingSheet extends ConsumerStatefulWidget {
  const QuickBookkeepingSheet({super.key});

  @override
  ConsumerState<QuickBookkeepingSheet> createState() =>
      _QuickBookkeepingSheetState();
}

class _QuickBookkeepingSheetState extends ConsumerState<QuickBookkeepingSheet> {
  final _textCtrl = TextEditingController();

  String? _error;
  var _submitting = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool keepOpen}) async {
    if (_submitting) return;
    final raw = _textCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请先输入一句话，例如「午餐20元 支付宝」');
      return;
    }
    final db = ref.read(databaseProvider);
    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择记账本')),
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
        setState(() => _error = outcome.errorMessage ?? '记账失败');
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
        setState(() => _error = null);
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final hasText = _textCtrl.text.trim().isNotEmpty;

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
                    tooltip: 'AI 增强设置',
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
              if (_error != null)
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
                key: const ValueKey('quick_bk_text'),
                autofocus: true,
                minLines: 1,
                maxLines: 3,
                enabled: !_submitting,
                decoration: InputDecoration(
                  hintText: '打一句，如「午餐20元 支付宝」',
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
                  if (_error != null || _textCtrl.text.trim().isNotEmpty) {
                    setState(() => _error = null);
                  }
                },
                onSubmitted: (_) => _submit(keepOpen: false),
              ),
              const SizedBox(height: CentliSpacing.sectionLoose),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting
                          ? null
                          : () {
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
                      onPressed: _submitting
                          ? null
                          : () {
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
              if (hasText && !_submitting) ...[
                const SizedBox(height: CentliSpacing.section),
                FilledButton(
                  key: const ValueKey('quick_bk_submit'),
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

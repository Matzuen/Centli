import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../data/db/database_provider.dart';
import 'smart_bookkeeping_submit.dart';

Future<void> showTextBookkeepingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const TextBookkeepingSheet(),
  );
}

/// Independent text bookkeeping panel (Finch-style).
///
/// Title uses 「文字记账」— local rule parse is primary; optional LLM is only
/// an enhancement behind settings.
class TextBookkeepingSheet extends ConsumerStatefulWidget {
  const TextBookkeepingSheet({super.key});

  @override
  ConsumerState<TextBookkeepingSheet> createState() =>
      _TextBookkeepingSheetState();
}

class _TextBookkeepingSheetState extends ConsumerState<TextBookkeepingSheet> {
  final _ctrl = TextEditingController();
  var _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool keepOpen}) async {
    if (_submitting) return;
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
        rawText: _ctrl.text,
        ledgerId: ledgerId,
        accounts: accounts,
      );
      if (!mounted) return;
      if (!outcome.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(outcome.errorMessage ?? '记账失败')),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.summary ?? '已记账')),
      );
      if (keepOpen) {
        _ctrl.clear();
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
                      '文字记账',
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
              const SizedBox(height: 4),
              Text(
                '直接输入一句话，帮你完成记账。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: CentliSpacing.item),
              TextField(
                controller: _ctrl,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(keepOpen: false),
                decoration: InputDecoration(
                  hintText: '例如：午餐20元 支付宝',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(
                    alpha: 0.55,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
              const SizedBox(height: CentliSpacing.sectionLoose),
              FilledButton(
                onPressed: _submitting ? null : () => _submit(keepOpen: false),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  backgroundColor: scheme.onSurface,
                  foregroundColor: scheme.surface,
                ),
                child: Text(_submitting ? '记账中…' : '记账并关闭'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _submitting ? null : () => _submit(keepOpen: true),
                child: const Text('记账并继续'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

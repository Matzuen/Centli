import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/widgets/glass.dart';
import '../../platform/notifications/ai_noti_trace.dart';
import '../../platform/notifications/notification_llm_parse.dart';
import '../../platform/notifications/recognition_rule_distill.dart';
import 'pending_confirm_sheet.dart';

/// After 待确认「忽略」, offer a snackbar action to open [showQuickExcludeFilterSheet].
void offerQuickExcludeFilterAfterIgnore(
  BuildContext context, {
  required String pkg,
  String? title,
  String? body,
  String? matchedKeywords,
}) {
  if (!context.mounted) return;
  final p = pkg.trim();
  if (p.isEmpty) return;
  showGlassSnackBar(
    context,
    '已忽略',
    duration: const Duration(seconds: 5),
    actionLabel: '写入过滤',
    onAction: () {
      // Defer so the snackbar close animation does not fight the sheet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showQuickExcludeFilterSheet(
          context,
          pkg: p,
          title: title,
          body: body,
          matchedKeywords: matchedKeywords,
        );
      });
    },
  );
}

/// Soft sheet: keyword chips +「仅当前 App」+ 加入过滤 → user exclude rule.
Future<void> showQuickExcludeFilterSheet(
  BuildContext context, {
  required String pkg,
  String? title,
  String? body,
  String? matchedKeywords,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final titleText = (title ?? '').trim();
  final bodyText = body;
  final initial = distillExcludeKeywordChips(
    title: titleText,
    body: bodyText,
    matchedKeywords: matchedKeywords,
  );
  final chips = List<String>.from(initial);
  if (chips.isEmpty && titleText.length >= 2) {
    chips.add(titleText.length > 16 ? titleText.substring(0, 16) : titleText);
  }
  if (chips.isEmpty) {
    showGlassSnackBar(context, '这条通知没有可写入的关键词');
    return;
  }

  final selected = {for (final c in chips) c};
  final scopeAppOnly = ValueNotifier<bool>(true);
  final result = await showGlassSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: CentliSpacing.pageH,
          right: CentliSpacing.pageH,
          top: CentliSpacing.item,
          bottom: MediaQuery.viewInsetsOf(ctx).bottom + CentliSpacing.pageBottom,
        ),
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '快速加入过滤',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: CentliSpacing.item),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in chips)
                      FilterChip(
                        label: Text(c),
                        selected: selected.contains(c),
                        onSelected: (v) {
                          setLocal(() {
                            if (v) {
                              selected.add(c);
                            } else {
                              selected.remove(c);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: CentliSpacing.item),
                Text(
                  '之后同类通知将自动忽略',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: CentliSpacing.section),
                ValueListenableBuilder<bool>(
                  valueListenable: scopeAppOnly,
                  builder: (ctx, onlyApp, _) {
                    return InkWell(
                      onTap: () => scopeAppOnly.value = !onlyApp,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              onlyApp
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              size: 20,
                              color: onlyApp
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '仅${pendingSourceLabel(pkg)}',
                                style: Theme.of(ctx).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: CentliSpacing.section),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () => Navigator.pop(ctx, true),
                        child: const Text('加入过滤'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
  scopeAppOnly.dispose();
  if (result != true || !context.mounted) return;
  if (selected.isEmpty) return;

  try {
    final id = await upsertUserExcludeFilterFromKeywords(
      pkg: pkg,
      keywords: selected.toList(),
      title: titleText,
      body: bodyText,
    );
    if (!context.mounted) return;
    if (id == null) {
      showGlassSnackBar(context, '未能写入过滤（关键词可能不安全）');
      return;
    }
    await AiNotiTrace.record(
      pkg: pkg,
      title: titleText.isEmpty ? selected.first : titleText,
      body: bodyText,
      kind: AiNotiTraceKinds.distillExclude,
      ruleName: distilledExcludeRuleDisplayName(pkg),
      matchedKeywords: selected.join('|'),
      detail: '待确认忽略后一键写入过滤',
    );
    if (!context.mounted) return;
    showGlassSnackBar(
      context,
      '已加入「${distilledExcludeRuleDisplayName(pkg)}」过滤',
    );
  } catch (err) {
    if (!context.mounted) return;
    showGlassSnackBar(context, '写入失败: $err');
  }
}

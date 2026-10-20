import 'package:flutter/material.dart';


import '../utils/date_range.dart';
import '../../app/theme.dart';
import 'glass.dart';

/// Chevron bar + tappable label that opens month / custom / last-30 picker.
class DateRangeControl extends StatelessWidget {
  const DateRangeControl({
    super.key,
    required this.range,
    required this.onChanged,
  });

  final DateRangeWindow range;
  final ValueChanged<DateRangeWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '上一段',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
          onPressed: () => onChanged(range.prev()),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final next = await showCentliDateRangeSheet(
                context,
                current: range,
              );
              if (next != null) onChanged(next);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      range.label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '下一段',
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          padding: EdgeInsets.zero,
          onPressed: range.isLatest ? null : () => onChanged(range.next()),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Bottom sheet: 近30天 / 选择月份 / 自定义区间.
Future<DateRangeWindow?> showCentliDateRangeSheet(
  BuildContext context, {
  required DateRangeWindow current,
}) {
  return showGlassSheet<DateRangeWindow>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '选择时间范围',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.timelapse_outlined),
              title: const Text('近 30 天'),
              subtitle: const Text('默认滚动窗口'),
              trailing: current.kind == DateRangeKind.lastDays && current.isLatest
                  ? Icon(Icons.check, color: Theme.of(ctx).colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx, DateRangeWindow.lastDays(days: 30));
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('选择月份'),
              subtitle: Text(
                current.kind == DateRangeKind.month
                    ? current.label
                    : '按自然月查看',
              ),
              onTap: () async {
                final month = await _pickMonth(ctx, current);
                if (month != null && ctx.mounted) {
                  Navigator.pop(ctx, month);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: const Text('自定义区间'),
              subtitle: Text(
                current.kind == DateRangeKind.custom
                    ? current.label
                    : '自选起止日期',
              ),
              onTap: () async {
                final custom = await _pickCustom(ctx, current);
                if (custom != null && ctx.mounted) {
                  Navigator.pop(ctx, custom);
                }
              },
            ),
            const SizedBox(height: CentliSpacing.item),
          ],
        ),
      );
    },
  );
}

Future<DateRangeWindow?> _pickMonth(
  BuildContext context,
  DateRangeWindow current,
) async {
  final now = DateTime.now();
  final initial = current.kind == DateRangeKind.month
      ? current.startLocal
      : DateTime(now.year, now.month, 1);

  final picked = await showDatePicker(
    context: context,
    initialDate: initial.isAfter(now) ? now : initial,
    firstDate: DateTime(2020, 1, 1),
    lastDate: now,
    locale: const Locale('zh', 'CN'),
    helpText: '选择月份（点该月任意一天）',
    initialDatePickerMode: DatePickerMode.year,
  );
  if (picked == null) return null;
  return DateRangeWindow.forMonth(picked.year, picked.month);
}

Future<DateRangeWindow?> _pickCustom(
  BuildContext context,
  DateRangeWindow current,
) async {
  final now = DateTime.now();
  final lastDay = current.endLocal.subtract(const Duration(days: 1));
  final initial = DateTimeRange(
    start: current.startLocal.isAfter(now) ? now : current.startLocal,
    end: lastDay.isAfter(now) ? now : lastDay,
  );

  final picked = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020, 1, 1),
    lastDate: now,
    initialDateRange: initial,
    locale: const Locale('zh', 'CN'),
    helpText: '选择自定义区间',
    saveText: '确定',
  );
  if (picked == null) return null;
  return DateRangeWindow.custom(
    startInclusive: picked.start,
    endInclusive: picked.end,
  );
}

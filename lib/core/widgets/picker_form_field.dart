import 'package:flutter/material.dart';

/// 表单里点开选择器的字段：外观接近 [InputDecoration]，不走系统下拉列表。
class CentliPickerFormField extends StatelessWidget {
  const CentliPickerFormField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.leading,
    this.enabled = true,
    this.error = false,
    this.isDense = true,
    this.outlined = false,
    this.contentPadding,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? leading;
  final bool enabled;
  final bool error;
  final bool isDense;
  final bool outlined;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = const BorderRadius.all(Radius.circular(14));
    final baseBorder = outlined
        ? OutlineInputBorder(borderRadius: borderRadius)
        : null;
    final errorBorder = error
        ? OutlineInputBorder(
            borderRadius: borderRadius,
            borderSide: BorderSide(color: scheme.error, width: 1.2),
          )
        : null;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: borderRadius,
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          isDense: isDense,
          contentPadding: contentPadding,
          border: baseBorder,
          enabledBorder: errorBorder ?? baseBorder,
          suffixIcon: Icon(
            Icons.chevron_right_rounded,
            color: scheme.onSurfaceVariant,
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: enabled
                          ? scheme.onSurface
                          : scheme.onSurface.withValues(alpha: 0.38),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

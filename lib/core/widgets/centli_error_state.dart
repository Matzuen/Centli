import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../../app/theme.dart';

/// What kind of failure the user is facing, so the hint can be actionable.
enum CentliErrorKind { network, database, permission, unknown }

/// Normalise an exception / async error into [CentliErrorKind].
CentliErrorKind classifyError(Object? error) {
  if (error == null) return CentliErrorKind.unknown;
  if (error is TimeoutException || error is SocketException) {
    return CentliErrorKind.network;
  }
  if (error is HttpException) return CentliErrorKind.network;
  if (error is SqliteException) return CentliErrorKind.database;
  if (error is PlatformException) {
    final code = (error.code).toLowerCase();
    if (code.contains('permission') ||
        code.contains('denied') ||
        code.contains('auth')) {
      return CentliErrorKind.permission;
    }
    if (code.contains('network') || code.contains('socket')) {
      return CentliErrorKind.network;
    }
  }
  final text = '$error'.toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('timeout') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('network is unreachable') ||
      text.contains('clientexception')) {
    return CentliErrorKind.network;
  }
  if (text.contains('sqlexception') ||
      text.contains('databaseexception') ||
      text.contains('database is locked') ||
      text.contains('no such table')) {
    return CentliErrorKind.database;
  }
  if (text.contains('permission') ||
      text.contains('denied') ||
      text.contains('not allowed')) {
    return CentliErrorKind.permission;
  }
  return CentliErrorKind.unknown;
}

/// Short Chinese title for a failure, e.g. 网络连接失败 / 数据读取失败.
String errorTitle(Object? error) {
  switch (classifyError(error)) {
    case CentliErrorKind.network:
      return '网络连接失败';
    case CentliErrorKind.database:
      return '数据读取失败';
    case CentliErrorKind.permission:
      return '权限不足';
    case CentliErrorKind.unknown:
      return '加载失败';
  }
}

/// Actionable hint for a failure.
String errorHint(Object? error) {
  switch (classifyError(error)) {
    case CentliErrorKind.network:
      return '请检查网络连接后重试。如果是汇率 / AI 增强相关，网络恢复后会自动重新获取。';
    case CentliErrorKind.database:
      return '读取本地数据时出错。可以点「重试」；若一直失败，请重启应用。';
    case CentliErrorKind.permission:
      return '相关权限未开启。请到系统设置中允许 Centli 使用对应权限后重试。';
    case CentliErrorKind.unknown:
      return '可以点「重试」。若反复出现，请把下面的详情反馈给我们。';
  }
}

/// Consistent failure block with a retry button (never shows a bare toString
/// unless the user expands 「详情」).
class CentliErrorState extends StatefulWidget {
  const CentliErrorState({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object? error;
  final VoidCallback? onRetry;

  /// Inline (for a card) vs. full-page centred layout.
  final bool compact;

  @override
  State<CentliErrorState> createState() => _CentliErrorStateState();
}

class _CentliErrorStateState extends State<CentliErrorState> {
  var _showDetail = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = classifyError(widget.error);
    final icon = switch (kind) {
      CentliErrorKind.network => Icons.wifi_off_rounded,
      CentliErrorKind.database => Icons.storage_rounded,
      CentliErrorKind.permission => Icons.lock_outline_rounded,
      CentliErrorKind.unknown => Icons.error_outline_rounded,
    };
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: widget.compact ? 32 : 48, color: scheme.error),
        SizedBox(height: widget.compact ? 8 : 12),
        Text(
          errorTitle(widget.error),
          style: widget.compact
              ? Theme.of(context).textTheme.titleSmall
              : Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CentliSpacing.item),
        Text(
          errorHint(widget.error),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
        ),
        if (_showDetail) ...[
          const SizedBox(height: CentliSpacing.item),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              '${widget.error}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        const SizedBox(height: CentliSpacing.section),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (widget.onRetry != null)
              FilledButton.tonalIcon(
                key: const Key('centli_error_retry'),
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
              ),
            TextButton(
              onPressed: () => setState(() => _showDetail = !_showDetail),
              child: Text(_showDetail ? '收起详情' : '详情'),
            ),
          ],
        ),
      ],
    );
    return Padding(
      padding: EdgeInsets.all(widget.compact ? 12 : 28),
      child: Center(child: content),
    );
  }
}

/// One-line error for snackbars: 「网络连接失败：详情」.
String errorSnack(Object? error) => '${errorTitle(error)}。${errorHint(error)}';

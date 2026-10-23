/// Shared screenshot / clipboard intake actions for home, pending, quick sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/db/database_provider.dart';
import '../../platform/pending/pending_capture_intake.dart';
import '../../core/widgets/glass.dart';

void _showResultSnackBar(BuildContext context, ManualIngestResult result) {
  showGlassSnackBar(context, result.snackbarText());
}

/// Pick a screenshot (gallery/camera), confirm AI consent once, then ingest.
Future<void> importCaptureFromScreenshot(
  BuildContext context,
  WidgetRef ref,
) async {
  final source = await showGlassSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选择'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('拍照'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return;
  final picker = ImagePicker();
  final file = await picker.pickImage(source: source, imageQuality: 92);
  if (file == null || !context.mounted) return;
  final db = ref.read(databaseProvider);
  var consented = await PendingCaptureIntake.hasImageAiConsent(db);
  if (!consented) {
    if (!context.mounted) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('截图识别说明'),
        content: const Text(
          '截图识别会把图片发送到 DeepSeek（或你配置的大模型服务），是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('同意'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await PendingCaptureIntake.setImageAiConsent(db, true);
    consented = true;
  }
  if (!context.mounted) return;
  showGlassSnackBar(context, '正在识别截图…');
  final result = await PendingCaptureIntake.ingestImagePath(
    db,
    file.path,
    sourceKind: 'screenshot',
    consentAlreadyGranted: consented,
  );
  if (!context.mounted) return;
  _showResultSnackBar(context, result);
}

/// Ingest an image from the system clipboard (if any).
Future<void> importCaptureFromClipboard(
  BuildContext context,
  WidgetRef ref,
) async {
  final db = ref.read(databaseProvider);
  final result = await PendingCaptureIntake.ingestClipboard(db);
  if (!context.mounted) return;
  _showResultSnackBar(context, result);
}

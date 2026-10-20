/// Pick a screenshot and recognize asset balances via the configured LLM.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/image_for_llm.dart';
import '../../data/db/database_provider.dart';
import '../../platform/pending/pending_capture_intake.dart';
import '../ledger/llm_text_fill.dart';
import 'asset_balance_recognize_sheet.dart';
import 'asset_balance_vision.dart';

Future<void> importAssetBalancesFromScreenshot(
  BuildContext context,
  WidgetRef ref, {
  required String ledgerId,
  required String baseCurrency,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
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

  final file = await ImagePicker().pickImage(source: source, imageQuality: 92);
  if (file == null || !context.mounted) return;

  final db = ref.read(databaseProvider);
  var consented = await PendingCaptureIntake.hasImageAiConsent(db);
  if (!consented) {
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('截图识别说明'),
        content: const Text(
          '资产截图识别会把图片发送到 DeepSeek（或你配置的大模型服务），是否继续？',
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
  }

  final llm = SmartFillLlmSettings();
  final config = await llm.load(db);
  if (!config.isReady) {
    if (!context.mounted) return;
    final message = !config.enabled
        ? '请先在「我的 · AI 增强」启用大模型并保存'
        : config.apiKey.trim().isEmpty
            ? '请先在「我的 · AI 增强」填写并保存 API Key'
            : '请先在「我的 · AI 增强」填写服务地址';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: '去设置',
          onPressed: () {
            if (context.mounted) context.push('/me/smart-fill');
          },
        ),
      ),
    );
    return;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('正在识别资产截图…')),
  );

  try {
    final raw = await File(file.path).readAsBytes();
    final prepared = prepareImageForLlm(raw);
    final accounts = await db.loadActiveAccounts(ledgerId);
    final types = await db.loadAssetTypes(ledgerId);
    final balances = await db.accountBalances(ledgerId);
    final result = await parseAssetBalancesImageWithLlm(
      prepared.bytes,
      config: config,
      accountNames: [for (final a in accounts) a.name],
      typeNames: [for (final t in types) t.name],
      baseCurrency: baseCurrency,
      settingsDb: db,
    );
    if (!context.mounted) return;
    await showAssetBalanceRecognizeSheet(
      context,
      ref,
      ledgerId: ledgerId,
      result: result,
      accounts: accounts,
      balances: balances,
      types: types,
    );
  } on LlmVisionException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.message)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('识别失败：$e')),
    );
  }
}

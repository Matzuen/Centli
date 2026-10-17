import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../notifications/notification_listener_stub.dart';
import '../notifications/notification_parse.dart';
import 'dart:io';
import '../../core/utils/image_for_llm.dart';
import '../../core/utils/note_compose.dart';
import '../../features/ledger/llm_text_fill.dart';

/// Result of a manual pending ingest (share / 截图视觉 / clipboard / URL).
class ManualIngestResult {
  const ManualIngestResult({
    required this.ok,
    this.pendingId,
    this.parseOk = false,
    this.amountMinor,
    this.currency,
    this.merchant,
    this.message,
    this.navigateToPending = false,
  });

  final bool ok;
  final String? pendingId;
  final bool parseOk;
  final int? amountMinor;
  final String? currency;
  final String? merchant;
  final String? message;
  final bool navigateToPending;

  String snackbarText() {
    if (message != null && message!.isNotEmpty) return message!;
    if (!ok) return '未能识别为账单，请确认包含金额或转账/红包关键词';
    final amt = amountMinor == null
        ? ''
        : ' ${formatMinor(currency ?? 'CNY', amountMinor!)}';
    final m = (merchant != null && merchant!.trim().isNotEmpty)
        ? ' · ${merchant!.trim()}'
        : '';
    if (parseOk) return '已加入待确认$amt$m';
    return '已加入待确认（需补全金额）$m';
  }
}

/// Shared pipeline for share / 截图视觉 / clipboard / URL → pending_captures.
///
/// Does **not** require [auto_capture_enabled] — user explicitly chose content.
/// Reuses [CentliDatabase.ingestParsedNotification] (same queue as notifications).
abstract final class PendingCaptureIntake {
  static CentliDatabase? _db;
  static void Function(String route)? onNavigate;

  /// Optional: last cold-start payload already delivered once.
  static bool _started = false;

  static Future<void> start(
    CentliDatabase db, {
    required void Function(String route) navigate,
  }) async {
    _db = db;
    onNavigate = navigate;
    if (_started) return;
    _started = true;
    await NotificationCaptureStub.bindPendingIntake(_onNativeIntake);
  }

  static Future<void> _onNativeIntake(Map<String, dynamic> payload) async {
    final db = _db;
    if (db == null) return;
    final kind = payload['kind'] as String? ?? '';
    ManualIngestResult result;
    if (kind == 'text') {
      final text = payload['text'] as String? ?? '';
      result = await ingestText(
        db,
        text: text,
        title: payload['title'] as String?,
        sourceKind: 'share',
        navigate: true,
      );
    } else if (kind == 'image') {
      final path = payload['imagePath'] as String? ?? '';
      result = await ingestImagePath(
        db,
        path,
        sourceKind: 'share_image',
        navigate: true,
      );
    } else if (kind == 'uri') {
      final uriStr = payload['uri'] as String? ?? '';
      result = await ingestUri(
        db,
        Uri.tryParse(uriStr),
        navigate: true,
      );
    } else {
      return;
    }
    debugPrint('PendingCaptureIntake native: ${result.snackbarText()}');
  }

  static Future<ManualIngestResult> ingestText(
    CentliDatabase db, {
    required String text,
    String? title,
    required String sourceKind,
    bool navigate = false,
    String? pkgHint,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && (title ?? '').trim().isEmpty) {
      return const ManualIngestResult(
        ok: false,
        message: '内容为空',
      );
    }

    final ledgerId = await db.currentLedgerId();
    if (ledgerId == null || ledgerId.isEmpty) {
      return const ManualIngestResult(
        ok: false,
        message: '尚未初始化账本',
      );
    }

    final parsed = parseManualCaptureText(
      trimmed,
      title: title,
      pkgHint: pkgHint,
    );
    if (parsed.templateId == null && !parsed.ok) {
      // Rejected: no keyword and no usable amount.
      return const ManualIngestResult(
        ok: false,
        message: '未能识别为账单，请确认包含金额或转账/红包/支付关键词',
      );
    }
    // Accept if template matched OR ok with amount.
    if (parsed.templateId == null) {
      return const ManualIngestResult(
        ok: false,
        message: '未能识别为账单',
      );
    }

    final pkg = (pkgHint != null && pkgHint.isNotEmpty)
        ? pkgHint
        : guessPkgFromText('$title\n$trimmed');
    final sourcePkg = pkg == 'manual' ? 'manual:$sourceKind' : pkg;
    final whenMs =
        parsed.happenAt?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
    final key = manualDedupeKey(
      sourceKind: sourceKind,
      body: '${title ?? ''}\n$trimmed',
      parsed: parsed,
      whenMs: whenMs,
    );

    String? id;
    try {
      id = await db.ingestParsedNotification(
        ledgerId: ledgerId,
        sourcePkg: sourcePkg,
        rawTitle: title ?? _titleForSource(sourceKind),
        rawText: trimmed.isEmpty ? (title ?? '') : trimmed,
        dedupeKey: key,
        amountMinor: parsed.amountMinor,
        currency: parsed.currency ?? 'CNY',
        merchant: parsed.merchant,
        happenAt: whenMs,
        parseOk: parsed.ok,
        accountHint: parsed.accountHint,
        direction: parsed.direction,
      );
    } catch (e) {
      return ManualIngestResult(
        ok: false,
        message: '写入失败: $e',
      );
    }

    if (id == null) {
      return const ManualIngestResult(
        ok: false,
        message: '已存在相同待确认（去重）',
      );
    }

    final currency = parsed.currency ?? 'CNY';
    await NotificationCaptureStub.showPendingConfirm(
      pendingId: id,
      title: parsed.amountMinor != null
          ? '待确认 ${formatMinor(currency, parsed.amountMinor!)}'
          : '待确认',
      body: parsed.merchant,
    );

    if (navigate) {
      onNavigate?.call('/home/pending');
    }

    return ManualIngestResult(
      ok: true,
      pendingId: id,
      parseOk: parsed.ok,
      amountMinor: parsed.amountMinor,
      currency: currency,
      merchant: parsed.merchant,
      navigateToPending: navigate,
    );
  }

  static String _titleForSource(String sourceKind) {
    switch (sourceKind) {
      case 'share':
        return '分享导入';
      case 'share_image':
        return '分享图片';
      case 'clipboard':
        return '剪贴板导入';
      case 'ocr':
        return '截图识别';
      case 'url':
        return '快捷指令';
      default:
        return '手动导入';
    }
  }

  static Future<ManualIngestResult> ingestClipboard(
    CentliDatabase db, {
    bool navigate = false,
  }) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      return const ManualIngestResult(
        ok: false,
        message: '剪贴板没有文字',
      );
    }
    return ingestText(
      db,
      text: text,
      sourceKind: 'clipboard',
      navigate: navigate,
    );
  }

  static const imageAiConsentKey = 'image_ai_consent';

  /// Returns false if user has not consented to uploading images to the LLM.
  static Future<bool> hasImageAiConsent(CentliDatabase db) async {
    final v = await db.getSetting(imageAiConsentKey);
    return v == 'true' || v == '1';
  }

  static Future<void> setImageAiConsent(CentliDatabase db, bool yes) async {
    await db.setSetting(imageAiConsentKey, yes ? 'true' : 'false');
  }

  static Future<ManualIngestResult> ingestImagePath(
    CentliDatabase db,
    String path, {
    required String sourceKind,
    bool navigate = false,
    bool consentAlreadyGranted = false,
  }) async {
    if (path.trim().isEmpty) {
      return const ManualIngestResult(ok: false, message: '未选择图片');
    }
    if (!consentAlreadyGranted && !await hasImageAiConsent(db)) {
      return const ManualIngestResult(
        ok: false,
        message: '截图识别会把图片发送到已配置的大模型服务，请先在确认对话框中同意',
      );
    }
    try {
      final raw = await File(path).readAsBytes();
      final prepared = prepareImageForLlm(raw);
      final cfg = await SmartFillLlmSettings().load(db);
      if (!cfg.isReady) {
        return const ManualIngestResult(
          ok: false,
          message: '请先在智能填单里启用大模型并配置 API Key',
        );
      }
      final filled = await parseBookkeepingImageWithLlm(
        prepared.bytes,
        config: cfg,
      );
      if (filled == null) {
        return const ManualIngestResult(
          ok: false,
          message: '图片识别未返回结果',
        );
      }
      final ledgerId = await db.currentLedgerId();
      if (ledgerId == null || ledgerId.isEmpty) {
        return const ManualIngestResult(ok: false, message: '尚未初始化账本');
      }
      final amountMinor = filled.amount == null
          ? null
          : toMinor('CNY', filled.amount!);
      final composedNote = composeNote(merchant: filled.merchant, note: filled.note);
      final whenMs = filled.happenAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
      final rawText = [
        if (filled.merchant != null) '商户 ${filled.merchant}',
        if (filled.amount != null) '金额 ${filled.amount}',
        ?composedNote,
        '来源:截图视觉识别',
      ].join('\n');
      final key = 'vision:$sourceKind:${path.hashCode}:$whenMs:$amountMinor';
      final id = await db.ingestParsedNotification(
        ledgerId: ledgerId,
        sourcePkg: 'manual:$sourceKind',
        rawTitle: '截图识别',
        rawText: rawText.isEmpty ? '截图识别' : rawText,
        dedupeKey: key,
        amountMinor: amountMinor,
        currency: 'CNY',
        merchant: filled.merchant,
        happenAt: whenMs,
        parseOk: amountMinor != null,
        direction: filled.type == 'in'
            ? 'in'
            : filled.type == 'transfer'
                ? 'out'
                : 'out',
      );
      if (id == null) {
        return const ManualIngestResult(
          ok: false,
          message: '已存在相同待确认（去重）',
        );
      }
      if (navigate) {
        onNavigate?.call('/home/pending');
      }
      return ManualIngestResult(
        ok: true,
        pendingId: id,
        parseOk: amountMinor != null,
        amountMinor: amountMinor,
        currency: 'CNY',
        merchant: filled.merchant,
        navigateToPending: navigate,
      );
    } on LlmVisionException catch (e) {
      return ManualIngestResult(ok: false, message: e.message);
    } catch (e) {
      return ManualIngestResult(ok: false, message: '截图识别失败: $e');
    }
  }

  /// Handle `centli://pending?text=...` or `?amount=&merchant=&note=`.
  static Future<ManualIngestResult> ingestUri(
    CentliDatabase db,
    Uri? uri, {
    bool navigate = true,
  }) async {
    if (uri == null) {
      return const ManualIngestResult(ok: false, message: '无效链接');
    }
    if (uri.scheme != 'centli') {
      return const ManualIngestResult(ok: false, message: '非 Centli 链接');
    }
    // centli://pending?...  or centli:///pending?...
    final host = uri.host;
    final path = uri.path;
    final isPending = host == 'pending' ||
        path == '/pending' ||
        path == 'pending' ||
        host.isEmpty && path.contains('pending');
    if (!isPending) {
      return ManualIngestResult(
        ok: false,
        message: '未知路径: ${uri.toString()}',
      );
    }

    final q = uri.queryParameters;
    final textParam = q['text'];
    if (textParam != null && textParam.trim().isNotEmpty) {
      return ingestText(
        db,
        text: textParam,
        sourceKind: 'url',
        navigate: navigate,
      );
    }

    final amountStr = q['amount'];
    final merchant = q['merchant'];
    final note = q['note'] ?? q['title'];
    if (amountStr == null || amountStr.trim().isEmpty) {
      return const ManualIngestResult(
        ok: false,
        message: '链接缺少文本或金额参数',
      );
    }

    final major = double.tryParse(amountStr.trim().replaceAll(',', ''));
    if (major == null || major <= 0) {
      return const ManualIngestResult(ok: false, message: '金额无效');
    }

    final buf = StringBuffer();
    buf.writeln('转账成功');
    if (merchant != null && merchant.trim().isNotEmpty) {
      buf.writeln('向 ${merchant.trim()} 转账');
    }
    buf.writeln('¥${major.toStringAsFixed(2)}');
    if (note != null && note.trim().isNotEmpty) {
      buf.writeln(note.trim());
    }

    // Force amount via structured path after building bill-like text.
    final result = await ingestText(
      db,
      text: buf.toString(),
      title: note,
      sourceKind: 'url',
      navigate: navigate,
      pkgHint: guessPkgFromText(buf.toString()),
    );
    return result;
  }

  /// Debug helper: describe URI without ingesting.
  static Map<String, String> previewUri(Uri uri) {
    return Map<String, String>.from(uri.queryParameters);
  }
}

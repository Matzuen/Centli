import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/money.dart';
import '../../platform/notifications/ai_noti_trace.dart';
import '../../platform/notifications/notification_llm_parse.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../../platform/notifications/recognition_rule_distill.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

/// Settings → 自动记账 → 识别规则.
class RecognitionRulesPage extends StatefulWidget {
  const RecognitionRulesPage({super.key});

  @override
  State<RecognitionRulesPage> createState() => _RecognitionRulesPageState();
}

class _RecognitionRulesPageState extends State<RecognitionRulesPage> {
  bool _loading = true;
  List<NotiTemplate> _official = const [];
  List<NotiTemplate> _user = const [];
  Set<String> _disabled = {};
  int _version = kNotiTemplateFallbackVersion;
  String _source = 'builtin';

  String _tryAppChoice = 'alipay';
  final _tryPkgCtrl = TextEditingController(
    text: 'com.eg.android.AlipayGphone',
  );
  final _tryTitle = TextEditingController();
  final _tryBody = TextEditingController(text: '向 星巴克 付款成功 ¥28.50');
  ParseExplainResult? _tryResult;
  bool _busy = false;
  bool _loadWarnDismissed = false;
  bool _staleWarnDismissed = false;
  int _skippedCount = 0;
  String? _loadError;
  List<NotiTemplate> _staleDistill = const [];
  int _mergePruned = 0;
  List<AiNotiTraceEvent> _aiTrace = const [];
  bool _officialExpanded = false;
  bool _aiRulesExpanded = true;
  bool _manualExpanded = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Widget _collapsibleRuleSection({
    required String title,
    required String subtitle,
    required bool expanded,
    required ValueChanged<bool> onExpanded,
    required List<Widget> children,
    Widget? trailing,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // 不挂 PageStorageKey：展开状态已经由 _xxxExpanded 单一持有，
          // 再让 PageStorage 恢复一次会出现「平铺已展开、图标却是收起」。
          initiallyExpanded: expanded,
          maintainState: true,
          // 卡片本身是磨砂面，展开/收起都不要额外描边。
          shape: const Border(),
          collapsedShape: const Border(),
          onExpansionChanged: onExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          trailing: trailing == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    trailing,
                    Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                  ],
                ),
          children: children,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tryPkgCtrl.dispose();
    _tryTitle.dispose();
    _tryBody.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    await NotiTemplateStore.load(force: true);
    final merged = await autoMergeDistillCaptureRulesIfNeeded();
    await NotiTemplateStore.load(force: true);
    if (!mounted) return;
    final stale = listStaleDistillRules(
      userRules: NotiTemplateStore.peekUser(),
      meta: NotiTemplateStore.peekDistillMeta(),
    );
    final trace = await AiNotiTrace.load(force: true);
    if (!mounted) return;
    setState(() {
      _official = NotiTemplateStore.peekOfficial();
      _user = NotiTemplateStore.peekUser();
      _disabled = NotiTemplateStore.peekDisabledOfficialIds();
      _version = NotiTemplateStore.version;
      _source = NotiTemplateStore.source;
      _skippedCount = NotiTemplateStore.lastSkippedCount;
      _loadError = NotiTemplateStore.lastLoadError;
      _staleDistill = stale;
      _mergePruned = merged;
      _aiTrace = trace;
      _loading = false;
    });
  }

  List<NotiTemplate> get _aiRules =>
      [for (final t in _user) if (isDistillRuleId(t.id)) t];

  List<NotiTemplate> get _manualRules =>
      [for (final t in _user) if (!isDistillRuleId(t.id)) t];

  String _relTrace(int whenMs) {
    if (whenMs <= 0) return '';
    final diff = DateTime.now().millisecondsSinceEpoch - whenMs;
    if (diff < 60 * 1000) return '刚刚';
    if (diff < 60 * 60 * 1000) return '${diff ~/ (60 * 1000)} 分钟前';
    if (diff < 24 * 60 * 60 * 1000) {
      return '${diff ~/ (60 * 60 * 1000)} 小时前';
    }
    return '${diff ~/ (24 * 60 * 60 * 1000)} 天前';
  }

  Future<void> _clearAiTrace() async {
    await AiNotiTrace.clear();
    if (!mounted) return;
    setState(() => _aiTrace = const []);
  }

  Future<void> _showAiTraceDetail(AiNotiTraceEvent e) async {
    final scheme = Theme.of(context).colorScheme;
    await showGlassDialog<void>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: Text(e.kindLabel),
        content: SingleChildScrollView(
          child: SelectableText(
            [
              '应用: ${_pkgLabel(e.pkg)}',
              if (e.ruleName != null && e.ruleName!.isNotEmpty)
                '规则: ${e.ruleName}',
              if (e.matchedKeywords != null &&
                  e.matchedKeywords!.trim().isNotEmpty)
                '匹配关键词: ${e.matchedKeywords}',
              '去向: ${e.destinationLabel}',
              if (e.detail != null && e.detail!.isNotEmpty) '备注: ${e.detail}',
              if (_relTrace(e.atMs).isNotEmpty) _relTrace(e.atMs),
              '',
              '—— 原通知 ——',
              e.originalNotification,
              '',
              '—— AI / 本地识别 ——',
              (e.recognition != null && e.recognition!.trim().isNotEmpty)
                  ? e.recognition!.trim()
                  : '（无识别详情，请用新版再测一条通知）',
            ].join('\n'),
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  color: scheme.onSurface,
                ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _userRuleTile(NotiTemplate t, ColorScheme scheme) {
    return CentliSoftCard(
      child: ListTile(
        leading: Icon(
          isDistillExcludeRuleId(t.id)
              ? Icons.block_outlined
              : isDistillCaptureRuleId(t.id)
                  ? Icons.auto_awesome_outlined
                  : Icons.edit_note,
          color: scheme.primary,
        ),
        title: Text(t.displayName),
        subtitle: Text(
          [
            t.packages.map(_pkgLabel).join('、'),
            if (isDistillRuleId(t.id)) _distillActivityLabel(t),
            if (t.mustContainRegex != null && t.mustContainRegex!.isNotEmpty)
              '关键词 ${t.mustContainRegex}',
          ].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: CentliGlassPopupButton<String>(
          onSelected: (v) async {
            if (v == 'edit') {
              final changed = await context.push<bool>(
                '/me/auto/rules/edit?id=${Uri.encodeComponent(t.id)}',
              );
              if (changed == true) await _reload();
            } else if (v == 'delete') {
              await _deleteUser(t);
            }
          },
          items: const [
            CentliMenuItem(value: 'edit', label: '编辑'),
            CentliMenuItem(value: 'delete', label: '删除', destructive: true),
          ],
        ),
        onTap: () async {
          final changed = await context.push<bool>(
            '/me/auto/rules/edit?id=${Uri.encodeComponent(t.id)}',
          );
          if (changed == true) await _reload();
        },
      ),
    );
  }

  Future<void> _purgeStaleDistill() async {
    if (_staleDistill.isEmpty) return;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('清理过期 AI 规则'),
        content: Text(
          '将删除 ${_staleDistill.length} 条超过 $kDistillStaleDays 天未命中的 AI 蒸馏规则。'
          '手写规则不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: centliDangerFilledStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      for (final t in List<NotiTemplate>.from(_staleDistill)) {
        await NotiTemplateStore.deleteUserTemplate(t.id);
      }
      await _reload();
      if (!mounted) return;
      showGlassSnackBar(context, '已清理过期 AI 规则');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _distillActivityLabel(NotiTemplate t) {
    if (!isDistillRuleId(t.id)) return '';
    final m = NotiTemplateStore.peekDistillMetaFor(t.id);
    if (m == null) return 'AI 规则';
    final hit = m.lastHitAtMs;
    if (hit == null) {
      final days = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(m.createdAtMs))
          .inDays;
      if (days <= 0) return 'AI 规则 · 今日学成 · 尚未命中';
      return 'AI 规则 · 学成 $days 天 · 尚未命中';
    }
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(hit))
        .inDays;
    if (days <= 0) return 'AI 规则 · 今日命中';
    return 'AI 规则 · $days 天前命中';
  }

  String _pkgLabel(String pkg) {
    if (pkg.contains('Alipay') || pkg.contains('alipay')) return '支付宝';
    if (pkg.contains('tencent.mm')) return '微信';
    return pkg;
  }

  Future<void> _toggleOfficial(NotiTemplate t, bool enabled) async {
    setState(() => _busy = true);
    try {
      await NotiTemplateStore.setOfficialDisabled(t.id, !enabled);
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteUser(NotiTemplate t) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('删除规则'),
        content: Text('确定删除「${t.displayName}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: centliDangerFilledStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await NotiTemplateStore.deleteUserTemplate(t.id);
      await _reload();
      if (!mounted) return;
      showGlassSnackBar(context, '已删除');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _runTry() {
    final pkg = _tryPkgCtrl.text.trim().isEmpty
        ? 'com.eg.android.AlipayGphone'
        : _tryPkgCtrl.text.trim();
    final raw = RawNotification(
      pkg: pkg,
      title: _tryTitle.text,
      text: _tryBody.text,
      whenMs: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      final explained = explainNotificationParse(raw, NotiTemplateStore.peek());
      setState(() => _tryResult = explained);
    } catch (e) {
      showGlassSnackBar(context, '试跑失败: $e');
    }
  }

  Future<void> _exportUser() async {
    setState(() => _busy = true);
    try {
      final json = await NotiTemplateStore.exportUserRulesJson();
      await Clipboard.setData(ClipboardData(text: json));
      if (!mounted) return;
      showGlassSnackBar(context, '已复制我的规则 JSON 到剪贴板');
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, '导出失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  Future<void> _importOfficialFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) return;
        showGlassSnackBar(context, '无法读取文件内容，请重试');
        return;
      }
      setState(() => _busy = true);
      final r = await NotiTemplateStore.importOfficialRulesJson(utf8.decode(bytes));
      await _reload();
      if (!mounted) return;
      showGlassSnackBar(context, r.message);
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, '导入内置规则失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importOfficialFromUrl() async {
    final urlCtrl = TextEditingController(
      text: NotiTemplateStore.kDefaultOfficialRulesUrl,
    );
    final url = await showGlassDialog<String>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('从网络导入内置规则'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '粘贴 HTTPS 地址下载内置规则 JSON。'
              '仅当 version 更高时覆盖；失败则保留原规则。'
              '默认地址留空，请使用自建 Raw/Gist。',
            ),
            const SizedBox(height: CentliSpacing.section),
            TextField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'HTTPS JSON 地址',
                hintText: 'https://example.com/noti_templates.json',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, urlCtrl.text.trim()),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    try {
      setState(() => _busy = true);
      final r = await NotiTemplateStore.importOfficialRulesFromUrl(url);
      await _reload();
      if (!mounted) return;
      showGlassSnackBar(context, r.message);
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, '网络导入失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rollbackOfficial() async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('恢复内置规则'),
        content: const Text(
          '将用 App 打包的内置模板覆盖本地规则包，包括你改过的内置规则（不影响「我的规则」）。确定？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      setState(() => _busy = true);
      final r = await NotiTemplateStore.rollbackOfficialToAsset();
      await _reload();
      if (!mounted) return;
      showGlassSnackBar(context, r.message);
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, '恢复失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importUser() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (files.isEmpty) return;
      final f = files.first;
      final bytes = await f.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) return;
        showGlassSnackBar(context, '无法读取文件内容，请重试');
        return;
      }
      final fileText = utf8.decode(bytes);
      if (!mounted) return;

      final merge = await showGlassDialog<bool>(
        context: context,
        builder: (ctx) => CentliGlassDialog(
          title: const Text('导入我的规则'),
          content: const Text('合并到现有规则，还是完全替换？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('替换'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('合并'),
            ),
          ],
        ),
      );
      if (merge == null) return;

      setState(() => _busy = true);
      final n = await NotiTemplateStore.importUserRulesJson(
        fileText,
        merge: merge,
      );
      await _reload();
      if (!mounted) return;
      showGlassSnackBar(context, '已导入 $n 条规则');
    } catch (e) {
      if (!mounted) return;
      showGlassSnackBar(context, '导入失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importUserFromUrl() async {
    final urlCtrl = TextEditingController();
    final url = await showGlassDialog<String>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('从网络导入我的规则'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '粘贴 HTTPS 地址，下载 JSON 后按与本地导入相同的格式校验。'
              '仅更新「我的规则」，不会改动内置规则。不会在启动时自动拉取。',
            ),
            const SizedBox(height: CentliSpacing.section),
            TextField(
              controller: urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'HTTPS JSON 地址',
                hintText: 'https://example.com/user_rules.json',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, urlCtrl.text.trim()),
            child: const Text('下一步'),
          ),
        ],
      ),
    );
    final pasted = url?.trim() ?? '';
    urlCtrl.dispose();
    if (pasted.isEmpty) return;
    if (!mounted) return;

    final merge = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('导入方式'),
        content: Text('从\n$pasted\n下载后，合并到现有规则，还是完全替换？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('替换'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('合并'),
          ),
        ],
      ),
    );
    if (merge == null) return;

    setState(() => _busy = true);
    try {
      final n = await NotiTemplateStore.importUserRulesFromUrl(
        pasted,
        merge: merge,
      );
      await _reload();
      if (!mounted) return;
      showGlassSnackBar(context, '已从网络导入 $n 条规则');
    } catch (e) {
      if (!mounted) return;
      final msg = e is FormatException ? (e.message) : '$e';
      showGlassSnackBar(context, '网络导入失败: $msg');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showOfficialDetail(NotiTemplate t) {
    final disabled = _disabled.contains(t.id);
    showGlassSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.paddingOf(ctx).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.displayName, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  disabled ? '已禁用 · 内置规则' : '内置规则 · 可编辑',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '修改会写入本机覆盖；右上角「恢复内置规则」可一键还原。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: CentliSpacing.section),
                _kv('ID', t.id),
                _kv('包名', t.packages.map(_pkgLabel).join('、')),
                _kv(
                  '匹配位置',
                  t.matchOn == 'title' ? '仅标题（门控）' : '标题+正文',
                ),
                _kv(
                  '收支',
                  t.matchOn == 'title'
                      ? '正文判定（默认${t.direction == 'in' ? '收入' : '支出'}）'
                      : (t.direction == 'in' ? '收入' : '支出'),
                ),
                _kv('必须包含', t.mustContainRegex ?? '—'),
                _kv('排除', t.excludeTextRegex ?? '—'),
                _kv('标题正则', t.titleRegex ?? '—'),
                _kv('金额正则', t.amountRegex),
                _kv('商户正则', t.merchantRegex ?? '—'),
                _kv('商户取自标题', t.merchantFromTitle ? '是' : '否'),
                _kv('资产账户提示', t.defaultAccountHint ?? '—'),
                _kv('默认币种', t.defaultCurrency),
                const SizedBox(height: CentliSpacing.sectionLoose),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用此内置规则'),
                  subtitle: const Text('关闭后解析时跳过（不修改规则内容）'),
                  value: !disabled,
                  onChanged: _busy
                      ? null
                      : (v) async {
                          Navigator.pop(ctx);
                          await _toggleOfficial(t, v);
                        },
                ),
                const SizedBox(height: CentliSpacing.item),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          final changed = await context.push<bool>(
                            '/me/auto/rules/edit?id=${Uri.encodeComponent(t.id)}',
                          );
                          if (changed == true) await _reload();
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('编辑此规则'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CentliSpacing.item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(v)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('识别规则'),
        actions: [
          CentliGlassPopupButton<String>(
            tooltip: '更多',
            maxWidth: 260,
            onSelected: (v) {
              if (v == 'export') _exportUser();
              if (v == 'import') _importUser();
              if (v == 'import_url') _importUserFromUrl();
              if (v == 'import_official') _importOfficialFile();
              if (v == 'import_official_url') _importOfficialFromUrl();
              if (v == 'rollback_official') _rollbackOfficial();
            },
            items: const [
              CentliMenuItem(value: 'export', label: '导出我的规则'),
              CentliMenuItem(value: 'import', label: '从文件导入我的规则'),
              CentliMenuItem(value: 'import_url', label: '从网络导入我的规则'),
              CentliMenuItem(value: 'import_official', label: '从文件导入内置规则'),
              CentliMenuItem(
                value: 'import_official_url',
                label: '从网络导入内置规则',
              ),
              CentliMenuItem(value: 'rollback_official', label: '恢复内置规则'),
            ],
          ),
          IconButton(
            tooltip: '添加规则',
            icon: const Icon(Icons.add),
            onPressed: _busy
                ? null
                : () async {
                    final changed =
                        await context.push<bool>('/me/auto/rules/edit');
                    if (changed == true) await _reload();
                  },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                CentliSpacing.pageH,
                CentliSpacing.pageTop,
                CentliSpacing.pageH,
                CentliSpacing.pageBottom,
              ),
              children: [
                if (!_loadWarnDismissed &&
                    (_skippedCount > 0 || _loadError != null)) ...[
                  CentliSoftCard(
                    color: scheme.errorContainer,
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _loadError != null
                                ? (_skippedCount > 0
                                    ? '$_loadError。另有 $_skippedCount 条规则格式有误已跳过，其余规则正常。建议导出备份后检查。'
                                    : '$_loadError。建议导出备份后检查。')
                                : '有 $_skippedCount 条规则格式有误已跳过，其余规则正常。建议导出备份后检查。',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: scheme.onErrorContainer,
                                  height: 1.35,
                                ),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setState(() => _loadWarnDismissed = true),
                          child: Text(
                            '关闭',
                            style: TextStyle(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                ],
                Text(
                  '内置 / AI / 我的规则可点标题展开或收起。'
                  '右上角导入导出；右上角添加手写规则；底部「试一试」验证样例。',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: CentliSpacing.sectionLoose),
                _collapsibleRuleSection(
                  title: '内置规则',
                  subtitle:
                      'v$_version · $_source · ${_official.length} 条 · 可编辑 / 启停 / 一键恢复',
                  expanded: _officialExpanded,
                  onExpanded: (v) => setState(() => _officialExpanded = v),
                  children: [
                    if (_official.isEmpty)
                      CentliEmptyState(
                        icon: Icons.rule_folder_outlined,
                        title: '暂无内置规则',
                        message: '内置模板未加载时会出现这里；可从右上角导入规则包。',
                        padding: EdgeInsets.zero,
                      )
                    else
                      for (final t in _official) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            _disabled.contains(t.id)
                                ? Icons.rule_folder_outlined
                                : Icons.verified_outlined,
                            color: _disabled.contains(t.id)
                                ? scheme.outline
                                : scheme.primary,
                          ),
                          title: Text(t.displayName),
                          subtitle: Text(
                            [
                              t.packages.map(_pkgLabel).join('、'),
                              if (_disabled.contains(t.id)) '已禁用',
                            ].join(' · '),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showOfficialDetail(t),
                        ),
                      ],
                  ],
                ),
                const SizedBox(height: CentliSpacing.section),
                Text(
                  '最近处理',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '本地规则与 AI 识别的最近最多 50 条决策。'
                  '点某条可看匹配关键词、去向（待确认 / 排除等），以及原通知与识别详情。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: CentliSpacing.item),
                CentliSoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                          _aiTrace.isEmpty
                              ? '尚无记录'
                              : '最近 ${_aiTrace.length} 条',
                        ),
                        trailing: _aiTrace.isEmpty
                            ? null
                            : TextButton(
                                onPressed: _clearAiTrace,
                                child: const Text('清空'),
                              ),
                      ),
                      if (_aiTrace.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Text(
                            '还没有处理记录。请确认：① 自动记账已开；②「AI 识别通知」已开并保存；'
                            '③ 用真实支付/聊天通知测一次，再点 AI 规则旁的刷新。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        )
                      else
                        SizedBox(
                          height: 168,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: _aiTrace.take(50).length,
                            itemBuilder: (context, i) {
                              final e = _aiTrace[i];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  e.kind.contains('distill')
                                      ? Icons.auto_awesome
                                      : e.kind.contains('exclude')
                                          ? Icons.block_outlined
                                          : e.kind.contains('local') ||
                                                  e.kind.contains('reuse')
                                              ? Icons.rule_outlined
                                              : Icons.smart_toy_outlined,
                                  size: 20,
                                  color: scheme.primary,
                                ),
                                title: Text(
                                  e.kindLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  [
                                    e.destinationLabel,
                                    _pkgLabel(e.pkg),
                                    e.titleShort,
                                    if (e.matchedKeywords != null &&
                                        e.matchedKeywords!.trim().isNotEmpty)
                                      '关键词 ${e.matchedKeywords}',
                                    if (e.recognition != null &&
                                        e.recognition!.contains('金额:'))
                                      e.recognition!
                                          .split('\n')
                                          .firstWhere(
                                            (l) => l.startsWith('金额:'),
                                            orElse: () => '',
                                          ),
                                    if (e.ruleName != null &&
                                        e.ruleName!.isNotEmpty)
                                      e.ruleName!,
                                    _relTrace(e.atMs),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: scheme.onSurfaceVariant,
                                ),
                                onTap: () => _showAiTraceDetail(e),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                if (_mergePruned > 0) ...[
                  Text(
                    'AI 捕获规则已超过 $kDistillCaptureMaxRules 条上限，刚才自动合并了 $_mergePruned 条。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: CentliSpacing.item),
                ],
                if (!_staleWarnDismissed && _staleDistill.isNotEmpty) ...[
                  CentliSoftCard(
                    color: scheme.secondaryContainer,
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.hourglass_empty,
                              color: scheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '有 ${_staleDistill.length} 条 AI 规则超过 $kDistillStaleDays 天未命中，可一键清理。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSecondaryContainer,
                                      height: 1.35,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 4,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(
                                          () => _staleWarnDismissed = true,
                                        ),
                                child: Text(
                                  '稍后',
                                  style: TextStyle(
                                    color: scheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              FilledButton.tonal(
                                onPressed: _busy ? null : _purgeStaleDistill,
                                child: const Text('一键清理'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                ],
                _collapsibleRuleSection(
                  title: 'AI 规则',
                  subtitle:
                      '${_aiRules.length} 条 · 如「微信-支出-支付成功」「微信-排除」',
                  expanded: _aiRulesExpanded,
                  onExpanded: (v) => setState(() => _aiRulesExpanded = v),
                  trailing: IconButton(
                    tooltip: '刷新',
                    onPressed: _busy ? null : _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                  children: [
                    if (_aiRules.isEmpty)
                      CentliEmptyState(
                        icon: Icons.auto_awesome_outlined,
                        title: '还没有 AI 反写规则',
                        message:
                            '看上方「最近处理」：若只有「本地模板已识别」而没有「已反写」，'
                            '多半是未开「AI 识别通知」或后台调用失败；若有「已反写」却列表为空，点刷新。',
                        padding: EdgeInsets.zero,
                      )
                    else
                      for (final t in _aiRules) ...[
                        _userRuleTile(t, scheme),
                        const SizedBox(height: CentliSpacing.item),
                      ],
                  ],
                ),
                const SizedBox(height: CentliSpacing.section),
                _collapsibleRuleSection(
                  title: '我的规则',
                  subtitle: '${_manualRules.length} 条 · 手写 / 导入，解析时优先匹配',
                  expanded: _manualExpanded,
                  onExpanded: (v) => setState(() => _manualExpanded = v),
                  children: [
                    if (_manualRules.isEmpty)
                      CentliEmptyState(
                        icon: Icons.playlist_add,
                        title: '还没有手写规则',
                        message: '点右上角 + 添加，或从「更多」导入文件/网络规则。',
                        padding: EdgeInsets.zero,
                      )
                    else
                      for (final t in _manualRules) ...[
                        _userRuleTile(t, scheme),
                        const SizedBox(height: CentliSpacing.item),
                      ],
                  ],
                ),
                const SizedBox(height: CentliSpacing.sectionLoose),
                Text('试一试', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: CentliSpacing.dense),
                Text(
                  '粘贴一条通知样例，用当前合并规则试解析（不入库）。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: CentliSpacing.item),
                CentliSoftCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _tryAppChoice,
                          decoration: const InputDecoration(
                            labelText: '来源应用',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'alipay',
                              child: Text('支付宝'),
                            ),
                            DropdownMenuItem(
                              value: 'wechat',
                              child: Text('微信'),
                            ),
                            DropdownMenuItem(value: 'other', child: Text('其它')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _tryAppChoice = v;
                              if (v == 'alipay') {
                                _tryPkgCtrl.text =
                                    'com.eg.android.AlipayGphone';
                              } else if (v == 'wechat') {
                                _tryPkgCtrl.text = 'com.tencent.mm';
                              }
                            });
                          },
                        ),
                        if (_tryAppChoice == 'other') ...[
                          const SizedBox(height: CentliSpacing.item),
                          TextField(
                            controller: _tryPkgCtrl,
                            decoration: const InputDecoration(
                              labelText: '包名',
                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                              isDense: true,
                              hintText: '例如 com.xxx.pay',
                            ),
                          ),
                        ],
                        const SizedBox(height: CentliSpacing.item),
                        TextField(
                          controller: _tryTitle,
                          decoration: const InputDecoration(
                            labelText: '标题（可选）',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: CentliSpacing.item),
                        TextField(
                          controller: _tryBody,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: '通知正文',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: CentliSpacing.section),
                        FilledButton.tonalIcon(
                          onPressed: _runTry,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('试解析'),
                        ),
                        if (_tryResult != null) ...[
                          const SizedBox(height: CentliSpacing.section),
                          _TryResultCard(result: _tryResult!),
                        ],
                      ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _TryResultCard extends StatelessWidget {
  const _TryResultCard({required this.result});

  final ParseExplainResult result;

  @override
  Widget build(BuildContext context) {
    final r = result.result;
    final scheme = Theme.of(context).colorScheme;
    final okColor = r.ok ? scheme.primary : scheme.error;
    String amountText = '—';
    if (r.amountMinor != null) {
      amountText = formatMinor(r.currency ?? 'CNY', r.amountMinor!);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.reason,
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(color: okColor),
          ),
          const SizedBox(height: CentliSpacing.item),
          Text('金额：$amountText'),
          Text('商户：${r.merchant ?? '—'}'),
          Text('规则：${r.templateId ?? '—'}'),
          Text('币种：${r.currency ?? '—'}'),
          if (result.steps.isNotEmpty) ...[
            const SizedBox(height: CentliSpacing.item),
            Text('步骤', style: Theme.of(context).textTheme.labelLarge),
            for (final s in result.steps) Text('· $s'),
          ],
        ],
      ),
    );
  }
}

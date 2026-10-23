import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../ledger/llm_text_fill.dart';
import 'model_name_validation.dart';
import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

/// AI 增强 / 大模型配置（OpenAI 兼容接口）。
class SmartFillSettingsPage extends ConsumerStatefulWidget {
  const SmartFillSettingsPage({super.key});

  @override
  ConsumerState<SmartFillSettingsPage> createState() =>
      _SmartFillSettingsPageState();
}

class _SmartFillSettingsPageState extends ConsumerState<SmartFillSettingsPage> {
  final _settings = SmartFillLlmSettings();
  final _baseCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  bool _notifyAiEnabled = false;
  bool _assetAiEnabled = false;
  bool _hasKey = false;
  bool _obscureKey = true;
  bool _testing = false;
  String? _effectiveBase;
  String? _effectiveModel;
  String? _keyTail;
  String? _modelWarning;
  String? _testResult;
  String? _detailCompat;

  @override
  void initState() {
    super.initState();
    _baseCtrl.addListener(_onModelInputsChanged);
    _modelCtrl.addListener(_onModelInputsChanged);
    _load();
  }

  void _onModelInputsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _baseCtrl.removeListener(_onModelInputsChanged);
    _modelCtrl.removeListener(_onModelInputsChanged);
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final cfg = await _settings.load(db);
    final hasKey = await _settings.hasApiKey();
    final key = cfg.apiKey.trim();
    final tail = key.length >= 4 ? key.substring(key.length - 4) : key;
    final compat = await db.getSetting(kLlmDetailCompatKey);
    if (!mounted) return;
    setState(() {
      _enabled = cfg.enabled;
      _notifyAiEnabled = cfg.notifyAiEnabled;
      _assetAiEnabled = cfg.assetAiEnabled;
      _baseCtrl.text = cfg.baseUrl;
      _modelCtrl.text = cfg.model;
      _hasKey = hasKey;
      _keyCtrl.text = '';
      _effectiveBase = cfg.baseUrl;
      _effectiveModel = cfg.model;
      _keyTail = hasKey ? tail : null;
      _modelWarning = _settings.lastModelWarning;
      _detailCompat = compat;
      _loading = false;
    });
    final notice = _settings.lastMigrationNotice;
    if (notice != null && mounted) {
      showGlassSnackBar(context, notice);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final keyText = _keyCtrl.text.trim();
      await _settings.save(
        db: db,
        enabled: _enabled,
        notifyAiEnabled: _notifyAiEnabled,
        assetAiEnabled: _assetAiEnabled,
        baseUrl: _baseCtrl.text.trim().isEmpty
            ? kDefaultLlmBaseUrl
            : _baseCtrl.text.trim(),
        model: _modelCtrl.text.trim().isEmpty
            ? kDefaultLlmModel
            : _modelCtrl.text.trim(),
        apiKey: keyText.isEmpty ? null : keyText,
      );
      final hasKey = await _settings.hasApiKey();
      if (!mounted) return;
      setState(() {
        _hasKey = hasKey;
        if (keyText.isNotEmpty) _keyCtrl.clear();
      });
      showGlassSnackBar(context, '已保存 AI 增强设置');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearKey() async {
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => CentliGlassDialog(
        title: const Text('清除接口密钥？'),
        content: const Text('清除后将无法调用大模型，AI 增强会回退到本地解析。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: centliDangerFilledStyle(ctx),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(databaseProvider);
    await _settings.save(
      db: db,
      enabled: _enabled,
      notifyAiEnabled: _notifyAiEnabled,
      assetAiEnabled: _assetAiEnabled,
      baseUrl: _baseCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      clearApiKey: true,
    );
    if (!mounted) return;
    setState(() {
      _hasKey = false;
      _keyCtrl.clear();
    });
    showGlassSnackBar(context, '已清除接口密钥');
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    final keyText = _keyCtrl.text.trim();
    final hasKeyNow = _hasKey || keyText.isNotEmpty;
    if (!hasKeyNow) {
      setState(() => _testResult = '❌ 请先配置 API Key');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final db = ref.read(databaseProvider);
      var cfg = await _settings.load(db);
      final base = _baseCtrl.text.trim().isEmpty
          ? kDefaultLlmBaseUrl
          : _baseCtrl.text.trim();
      final model = _modelCtrl.text.trim().isEmpty
          ? kDefaultLlmModel
          : _modelCtrl.text.trim();
      final apiKey = keyText.isNotEmpty ? keyText : cfg.apiKey;
      cfg = SmartFillLlmConfig(
        enabled: true,
        baseUrl: base,
        model: model,
        apiKey: apiKey,
      );
      final result = await testLlmConnection(config: cfg);
      if (!mounted) return;
      var msg = result.message;
      if (!result.ok) {
        final tip = connectionTestTypoHintLine(model, baseUrl: base);
        if (tip != null) {
          msg = '$msg\n$tip';
        }
      }
      setState(() => _testResult = msg);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CentliGradientScaffold(
      appBar: AppBar(
        title: const Text('AI 增强'),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: CentliSpacing.pagePadding,
              children: [
                CentliSoftCard(
                  key: const Key('bk_effective_llm_config'),
                  padding: const EdgeInsets.all(CentliSpacing.cardPad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '默认使用 deepseek-flash（支持图片）。接口配置共用；文字填单、通知解析、资产识别各自独立开关，互不影响。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: CentliSpacing.section),
                      Text(
                        '当前生效配置',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: CentliSpacing.item),
                      SelectableText(
                        '接口地址：${_effectiveBase ?? _baseCtrl.text}\n'
                        '模型：${_effectiveModel ?? _modelCtrl.text}\n'
                        'Key：${_hasKey ? "已保存（sk-…${_keyTail ?? ""}）" : "未配置"}',
                      ),
                      if (_modelWarning != null) ...[
                        const SizedBox(height: CentliSpacing.item),
                        Text(
                          _modelWarning!,
                          style: TextStyle(
                            color: Colors.amber.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (_detailCompat == 'true') ...[
                        const SizedBox(height: CentliSpacing.item),
                        Text(
                          '已自动兼容：服务端不接受 detail 字段',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: CentliSpacing.section),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.tonalIcon(
                          onPressed: _loading || _saving || _testing
                              ? null
                              : _testConnection,
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: Text(_testing ? '测试中…' : '测试连接'),
                        ),
                      ),
                      if (_testResult != null) ...[
                        const SizedBox(height: CentliSpacing.item),
                        GestureDetector(
                          onLongPress: () async {
                            await Clipboard.setData(
                              ClipboardData(text: _testResult!),
                            );
                            if (!context.mounted) return;
                            showGlassSnackBar(context, '已复制');
                          },
                          child: Text(
                            '$_testResult\n(长按可复制)',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('启用大模型增强'),
                        subtitle: const Text(
                          '文字填单与记账截图识别。失败时回退本地解析，不阻塞保存。',
                        ),
                        value: _enabled,
                        onChanged: (v) => setState(() => _enabled = v),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('AI 识别通知'),
                        subtitle: const Text(
                          '开启后，监听应用的通知标题与正文会发送到你配置的模型判断是否为收付款。'
                          '默认关闭；关闭时通知仅在本机解析，不会外发。',
                        ),
                        value: _notifyAiEnabled,
                        onChanged: (v) => setState(() => _notifyAiEnabled = v),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('AI 资产识别'),
                        subtitle: const Text(
                          '开启后，资产页「截图识别余额」才会把图片发给大模型。默认关闭。',
                        ),
                        value: _assetAiEnabled,
                        onChanged: (v) => setState(() => _assetAiEnabled = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                Text(
                  '三项开关彼此独立：开文字填单不会自动外发通知或资产截图。'
                  '均需先配置并保存 API Key。\n'
                  '开启「AI 识别通知」后，顺序为「本地排除规则 → AI → 本地解析」：'
                  '非收付款会学成「软件名-排除」规则；收付款会蒸馏「软件名-支出/收入」供后台复用。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: CentliSpacing.item),
                CentliSoftCard(
                  padding: const EdgeInsets.all(CentliSpacing.cardPad),
                  child: Column(
                    children: [
                TextField(
                  controller: _baseCtrl,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: '接口基础地址',
                    hintText: kDefaultLlmBaseUrl,
                    helperText: '通常无需 /v1，例如 https://api.deepseek.com。实际请求为「基础地址/chat/completions」',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: CentliSpacing.section),
                Builder(
                  builder: (context) {
                    final baseForHint = _baseCtrl.text.trim().isEmpty
                        ? kDefaultLlmBaseUrl
                        : _baseCtrl.text.trim();
                    final modelForHint = _modelCtrl.text.trim().isEmpty
                        ? kDefaultLlmModel
                        : _modelCtrl.text.trim();
                    final hint = evaluateDeepSeekModelHint(
                      modelForHint,
                      baseUrl: baseForHint,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _modelCtrl,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: '模型名',
                            hintText: kDefaultLlmModel,
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                          ),
                          autocorrect: false,
                        ),
                        if (hint.kind == DeepSeekModelHintKind.typo &&
                            hint.suggestion != null) ...[
                          const SizedBox(height: CentliSpacing.item),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  hint.message ?? '',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _saving
                                    ? null
                                    : () {
                                        _modelCtrl.text = hint.suggestion!;
                                        _modelCtrl.selection =
                                            TextSelection.collapsed(
                                          offset: _modelCtrl.text.length,
                                        );
                                        setState(() {});
                                      },
                                child: const Text('一键修正'),
                              ),
                            ],
                          ),
                        ] else if (hint.kind ==
                            DeepSeekModelHintKind.unsupportedVision) ...[
                          const SizedBox(height: CentliSpacing.item),
                          Text(
                            hint.message ?? '',
                            style: TextStyle(
                              color: Colors.amber.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: CentliSpacing.section),
                TextField(
                  controller: _keyCtrl,
                  enabled: !_saving,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: _hasKey ? '接口密钥（已保存，留空则不修改）' : '接口密钥',
                    hintText: _hasKey ? '••••••••' : '粘贴密钥',
                    helperText: '仅保存在本机安全存储，不会上传到厘记服务器',
                    border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    suffixIcon: IconButton(
                      tooltip: _obscureKey ? '显示' : '隐藏',
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                if (_hasKey) ...[
                  const SizedBox(height: CentliSpacing.item),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _clearKey,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('清除已保存的接口密钥'),
                    ),
                  ),
                ],
                    ],
                  ),
                ),
                const SizedBox(height: CentliSpacing.section),
                CentliSoftCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '使用说明',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: CentliSpacing.item),
                        const Text(
                          '1. 在记账页展开「AI 增强」，输入话术后点「填入」（需打开「启用大模型增强」）。\n'
                          '2. 支付通知默认只走本地规则；需要 AI 时再单独打开「AI 识别通知」。\n'
                          '3. 资产页截图识别余额需单独打开「AI 资产识别」，且模型需支持视觉。\n'
                          '4. 分类不确定时不会强行猜错类；备注只保留结构化抽取后的剩余文字。',
                        ),
                      ],
                    ),
                ),
              ],
            ),
    );
  }
}

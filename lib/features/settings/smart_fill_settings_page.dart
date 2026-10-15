import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/database_provider.dart';
import '../ledger/llm_text_fill.dart';

/// 智能填单 / 大模型增强配置（OpenAI 兼容接口）。
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
  bool _hasKey = false;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final cfg = await _settings.load(db);
    final hasKey = await _settings.hasApiKey();
    if (!mounted) return;
    setState(() {
      _enabled = cfg.enabled;
      _baseCtrl.text = cfg.baseUrl;
      _modelCtrl.text = cfg.model;
      _hasKey = hasKey;
      _keyCtrl.text = '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final keyText = _keyCtrl.text.trim();
      await _settings.save(
        db: db,
        enabled: _enabled,
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存智能填单设置')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearKey() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除 API Key？'),
        content: const Text('清除后将无法调用大模型，智能填单会回退到本地解析。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
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
      baseUrl: _baseCtrl.text.trim(),
      model: _modelCtrl.text.trim(),
      clearApiKey: true,
    );
    if (!mounted) return;
    setState(() {
      _hasKey = false;
      _keyCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除 API Key')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能填单'),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('用大模型增强文字填单'),
                  subtitle: const Text(
                    '开启后，记账页「智能填单」会优先调用你配置的 OpenAI 兼容接口；失败时自动回退本地解析，不阻塞保存。',
                  ),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const Divider(height: 24),
                Text(
                  '本地解析始终可用；大模型为可选增强。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _baseCtrl,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: kDefaultLlmBaseUrl,
                    helperText: '需包含 /v1；将请求 {base}/chat/completions',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _modelCtrl,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: '模型名',
                    hintText: kDefaultLlmModel,
                    border: OutlineInputBorder(),
                  ),
                  autocorrect: false,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyCtrl,
                  enabled: !_saving,
                  obscureText: _obscureKey,
                  decoration: InputDecoration(
                    labelText: _hasKey ? 'API Key（已保存，留空则不修改）' : 'API Key',
                    hintText: _hasKey ? '••••••••' : 'sk-...',
                    helperText: '仅保存在本机安全存储（flutter_secure_storage）',
                    border: const OutlineInputBorder(),
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
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _clearKey,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('清除已保存的 API Key'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '使用说明',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '1. 在记账页展开「智能填单」，输入话术后点「填入」。\n'
                          '2. 未开启或未配置 Key 时，仅用本地关键词/分类匹配。\n'
                          '3. 兼容任意 OpenAI Chat Completions 接口（含代理）。\n'
                          '4. 分类不确定时不会强行猜错类；备注只保留结构化抽取后的剩余文字。',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

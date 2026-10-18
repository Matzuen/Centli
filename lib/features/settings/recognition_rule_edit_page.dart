import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';


import '../../core/utils/id_gen.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../../app/theme.dart';

/// Add / edit a user recognition rule.
class RecognitionRuleEditPage extends StatefulWidget {
  const RecognitionRuleEditPage({super.key, this.ruleId});

  final String? ruleId;

  @override
  State<RecognitionRuleEditPage> createState() =>
      _RecognitionRuleEditPageState();
}

class _RecognitionRuleEditPageState extends State<RecognitionRuleEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _pkgOtherCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _mustCtrl = TextEditingController();
  final _excludeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: kAmountRegex);
  final _merchantCtrl = TextEditingController();

  String _appChoice = 'alipay';
  String? _accountHint = 'alipay';
  bool _merchantFromTitle = false;
  bool _loading = true;
  bool _saving = false;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pkgOtherCtrl.dispose();
    _titleCtrl.dispose();
    _mustCtrl.dispose();
    _excludeCtrl.dispose();
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await NotiTemplateStore.load();
    final id = widget.ruleId;
    if (id != null && id.isNotEmpty) {
      NotiTemplate? found;
      for (final t in NotiTemplateStore.peekUser()) {
        if (t.id == id) {
          found = t;
          break;
        }
      }
      if (found != null) {
        _editingId = found.id;
        _nameCtrl.text = found.displayName;
        final pkg = found.packages.isNotEmpty ? found.packages.first : '';
        if (pkg == 'com.eg.android.AlipayGphone') {
          _appChoice = 'alipay';
        } else if (pkg == 'com.tencent.mm') {
          _appChoice = 'wechat';
        } else {
          _appChoice = 'other';
          _pkgOtherCtrl.text = pkg;
        }
        _titleCtrl.text = found.titleRegex ?? '';
        _mustCtrl.text = found.mustContainRegex ?? '';
        _excludeCtrl.text = found.excludeTextRegex ?? '';
        _amountCtrl.text = found.amountRegex;
        _merchantCtrl.text = found.merchantRegex ?? '';
        _merchantFromTitle = found.merchantFromTitle;
        _accountHint = found.defaultAccountHint;
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<String> _packagesForChoice() {
    switch (_appChoice) {
      case 'wechat':
        return const ['com.tencent.mm'];
      case 'other':
        final p = _pkgOtherCtrl.text.trim();
        return p.isEmpty ? const <String>[] : [p];
      case 'alipay':
      default:
        return const ['com.eg.android.AlipayGphone'];
    }
  }

  String? _hintForChoice() {
    if (_accountHint != null) return _accountHint;
    switch (_appChoice) {
      case 'wechat':
        return 'wechat';
      case 'alipay':
        return 'alipay';
      default:
        return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final packages = _packagesForChoice();
    if (packages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写包名')),
      );
      return;
    }

    // Validate regex fields lightly.
    for (final entry in [
      ('标题', _titleCtrl.text),
      ('必须包含', _mustCtrl.text),
      ('排除', _excludeCtrl.text),
      ('金额', _amountCtrl.text),
      ('商户', _merchantCtrl.text),
    ]) {
      final raw = entry.$2.trim();
      if (raw.isEmpty) continue;
      try {
        RegExp(raw);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${entry.$1}正则无效: $e')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final id = _editingId ?? 'user_${newId()}';
      final amount = _amountCtrl.text.trim().isEmpty
          ? kAmountRegex
          : _amountCtrl.text.trim();
      final template = NotiTemplate(
        id: id,
        name: _nameCtrl.text.trim(),
        packages: packages,
        titleRegex: _nullIfEmpty(_titleCtrl.text),
        mustContainRegex: _nullIfEmpty(_mustCtrl.text),
        excludeTextRegex: _nullIfEmpty(_excludeCtrl.text),
        amountRegex: amount,
        merchantRegex: _nullIfEmpty(_merchantCtrl.text),
        merchantFromTitle: _merchantFromTitle,
        defaultAccountHint: _hintForChoice(),
      );
      await NotiTemplateStore.upsertUserTemplate(template);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nullIfEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = _editingId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '编辑规则' : '添加规则'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
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
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '名称',
                      border: OutlineInputBorder(),
                      hintText: '例如：银行借记通知',
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请填写名称' : null,
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: _appChoice,
                    decoration: const InputDecoration(
                      labelText: '应用',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'alipay', child: Text('支付宝')),
                      DropdownMenuItem(value: 'wechat', child: Text('微信')),
                      DropdownMenuItem(value: 'other', child: Text('其它')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _appChoice = v;
                        if (v == 'alipay') {
                          _accountHint ??= 'alipay';
                          if (_accountHint == 'wechat') _accountHint = 'alipay';
                        } else if (v == 'wechat') {
                          if (_accountHint == 'alipay') _accountHint = 'wechat';
                        }
                      });
                    },
                  ),
                  if (_appChoice == 'other') ...[
                    const SizedBox(height: CentliSpacing.section),
                    TextFormField(
                      controller: _pkgOtherCtrl,
                      decoration: const InputDecoration(
                        labelText: '包名',
                        border: OutlineInputBorder(),
                        hintText: 'com.xxx.app',
                      ),
                      validator: (v) {
                        if (_appChoice != 'other') return null;
                        if (v == null || v.trim().isEmpty) return '请填写包名';
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String?>(
                    initialValue: _accountHint,
                    decoration: const InputDecoration(
                      labelText: '建议账户提示',
                      border: OutlineInputBorder(),
                      helperText: '用于映射到「应用 → 默认账户」',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'alipay', child: Text('支付宝')),
                      DropdownMenuItem(value: 'wechat', child: Text('微信')),
                      DropdownMenuItem(value: null, child: Text('无')),
                    ],
                    onChanged: (v) => setState(() => _accountHint = v),
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                  Text(
                    '匹配条件（正则，普通关键词用 | 分隔）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  TextFormField(
                    controller: _mustCtrl,
                    decoration: const InputDecoration(
                      labelText: '正文必须包含',
                      border: OutlineInputBorder(),
                      hintText: '支付成功|付款成功',
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextFormField(
                    controller: _excludeCtrl,
                    decoration: const InputDecoration(
                      labelText: '排除词',
                      border: OutlineInputBorder(),
                      hintText: '验证码|登录',
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '标题正则（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                  Text(
                    '提取',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: '金额正则',
                      border: OutlineInputBorder(),
                      helperText: '第 1 捕获组为数字；留空则用内置默认',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextFormField(
                    controller: _merchantCtrl,
                    decoration: const InputDecoration(
                      labelText: '商户正则（可选）',
                      border: OutlineInputBorder(),
                      hintText: r'(?:向|给|商户)\s*(.+?)(?:\s|$)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('商户优先取自标题'),
                    subtitle: const Text('适合微信「商户名-微信支付」类标题'),
                    value: _merchantFromTitle,
                    onChanged: (v) => setState(() => _merchantFromTitle = v),
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose + CentliSpacing.item),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
    );
  }
}

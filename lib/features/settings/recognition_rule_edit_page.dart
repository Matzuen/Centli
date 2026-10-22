import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/id_gen.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../platform/notifications/notification_parse.dart';
import '../../platform/notifications/noti_template_store.dart';
import '../../platform/notifications/watched_package_resolve.dart';
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
  String _direction = 'out';
  String _matchOn = 'body';
  String _defaultCurrency = 'CNY';
  /// Extra packages beyond the primary app choice (preserved on edit).
  List<String> _extraPackages = const [];
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
        final pkgs = found.packages;
        final pkg = pkgs.isNotEmpty ? pkgs.first : '';
        if (pkg == 'com.eg.android.AlipayGphone') {
          _appChoice = 'alipay';
        } else if (pkg == 'com.tencent.mm') {
          _appChoice = 'wechat';
        } else {
          _appChoice = 'other';
          _pkgOtherCtrl.text = pkg;
        }
        _extraPackages = pkgs.length > 1 ? pkgs.sublist(1) : const [];
        _titleCtrl.text = found.titleRegex ?? '';
        _mustCtrl.text = found.mustContainRegex ?? '';
        _excludeCtrl.text = found.excludeTextRegex ?? '';
        _amountCtrl.text = found.amountRegex;
        _merchantCtrl.text = found.merchantRegex ?? '';
        _merchantFromTitle = found.merchantFromTitle;
        _accountHint = found.defaultAccountHint;
        _direction = NotiTemplate.normalizeDirection(found.direction);
        _matchOn = found.matchOn == 'title' ? 'title' : 'body';
        _defaultCurrency = found.defaultCurrency.trim().isEmpty
            ? 'CNY'
            : found.defaultCurrency.trim().toUpperCase();
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<String> _packagesForChoice() {
    late final List<String> primary;
    switch (_appChoice) {
      case 'wechat':
        primary = const ['com.tencent.mm'];
      case 'other':
        primary = resolvePackageInput(_pkgOtherCtrl.text);
      case 'alipay':
      default:
        primary = const ['com.eg.android.AlipayGphone'];
    }
    if (primary.isEmpty) return primary;
    final seen = <String>{primary.first};
    final extras = <String>[];
    for (final p in _extraPackages) {
      final t = p.trim();
      if (t.isEmpty || !seen.add(t)) continue;
      extras.add(t);
    }
    // Alias 展开时 primary 可能已有多个包名。
    for (final p in primary.skip(1)) {
      if (seen.add(p)) extras.add(p);
    }
    return [primary.first, ...extras];
  }

  Future<void> _pickInstalledApp() async {
    final apps = await NotificationCaptureStub.listLaunchableApps();
    if (!mounted) return;
    if (apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能读取已安装应用，请手动填写包名')),
      );
      return;
    }
    final selected = await showModalBottomSheet<LaunchableAppInfo>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var filter = '';
        return StatefulBuilder(
          builder: (ctx, setModal) {
            final q = filter.trim().toLowerCase();
            final filtered = q.isEmpty
                ? apps
                : apps
                    .where(
                      (a) =>
                          a.label.toLowerCase().contains(q) ||
                          a.packageName.toLowerCase().contains(q),
                    )
                    .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.72,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '搜索应用名或包名',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(14)),
                          ),
                        ),
                        onChanged: (v) => setModal(() => filter = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final a = filtered[i];
                          return ListTile(
                            title: Text(a.label),
                            subtitle: Text(
                              a.packageName,
                              style: Theme.of(ctx).textTheme.bodySmall,
                            ),
                            onTap: () => Navigator.pop(ctx, a),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _pkgOtherCtrl.text = selected.packageName;
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = selected.label;
      }
    });
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
    if (_appChoice == 'other') {
      final err = packageInputError(_pkgOtherCtrl.text);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }
    }
    final packages = _packagesForChoice();
    if (packages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写包名或从已安装应用选择')),
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
        defaultCurrency: _defaultCurrency,
        titleRegex: _nullIfEmpty(_titleCtrl.text),
        mustContainRegex: _nullIfEmpty(_mustCtrl.text),
        excludeTextRegex: _nullIfEmpty(_excludeCtrl.text),
        amountRegex: amount,
        merchantRegex: _nullIfEmpty(_merchantCtrl.text),
        merchantFromTitle: _merchantFromTitle,
        defaultAccountHint: _hintForChoice(),
        direction: _direction,
        matchOn: _matchOn,
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
    return CentliGradientScaffold(
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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
                        _extraPackages = const [];
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
                        labelText: '包名或应用名',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14)),
                        ),
                        hintText: 'com.android.bankabc 或 中国农业银行',
                        helperText: '应用名会自动映射到常见银行包名；不确定请点下方选择',
                      ),
                      validator: (v) {
                        if (_appChoice != 'other') return null;
                        return packageInputError(v ?? '');
                      },
                    ),
                    const SizedBox(height: CentliSpacing.item),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickInstalledApp,
                      icon: const Icon(Icons.apps_outlined),
                      label: const Text('从已安装应用选择'),
                    ),
                  ],
                  if (_extraPackages.isNotEmpty) ...[
                    const SizedBox(height: CentliSpacing.dense),
                    Text(
                      '另含包名：${_extraPackages.join('、')}（保存时保留）',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String?>(
                    initialValue: _accountHint,
                    decoration: const InputDecoration(
                      labelText: '建议资产账户提示',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                      helperText: '用于映射到「应用 → 默认资产账户」',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'alipay', child: Text('支付宝')),
                      DropdownMenuItem(value: 'wechat', child: Text('微信')),
                      DropdownMenuItem(value: null, child: Text('无')),
                    ],
                    onChanged: (v) => setState(() => _accountHint = v),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: _defaultCurrency,
                    decoration: const InputDecoration(
                      labelText: '默认币种',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'CNY', child: Text('CNY 人民币')),
                      DropdownMenuItem(value: 'USD', child: Text('USD 美元')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR 欧元')),
                      DropdownMenuItem(value: 'HKD', child: Text('HKD 港币')),
                      DropdownMenuItem(value: 'JPY', child: Text('JPY 日元')),
                      DropdownMenuItem(value: 'TWD', child: Text('TWD 新台币')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _defaultCurrency = v);
                    },
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                  Text(
                    '匹配范围与收支',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  DropdownButtonFormField<String>(
                    initialValue: _matchOn,
                    decoration: const InputDecoration(
                      labelText: '关键词匹配位置',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                      helperText: '「仅标题」= 标题门控是否抓取；收支再由正文判定',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'body', child: Text('标题+正文（传统）')),
                      DropdownMenuItem(value: 'title', child: Text('仅标题（门控）')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _matchOn = v);
                    },
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: _direction,
                    decoration: InputDecoration(
                      labelText: '默认收支方向',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      helperText: _matchOn == 'title'
                          ? '仅标题门控时：正文有收/支词则覆盖此默认'
                          : '匹配成功后的记账方向',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'out', child: Text('支出')),
                      DropdownMenuItem(value: 'in', child: Text('收入')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _direction = v);
                    },
                  ),
                  const SizedBox(height: CentliSpacing.sectionLoose),
                  Text(
                    '匹配条件（正则，普通关键词用 | 分隔）',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: CentliSpacing.item),
                  TextFormField(
                    controller: _mustCtrl,
                    decoration: InputDecoration(
                      labelText: _matchOn == 'title' ? '标题必须包含' : '正文必须包含',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      hintText: '支付成功|付款成功',
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextFormField(
                    controller: _excludeCtrl,
                    decoration: InputDecoration(
                      labelText: _matchOn == 'title' ? '标题排除词' : '排除词',
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                      hintText: '验证码|登录|还款提醒',
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '标题正则（可选，额外约束）',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
                      helperText: '第 1 捕获组为数字；留空则用内置默认',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  TextFormField(
                    controller: _merchantCtrl,
                    decoration: const InputDecoration(
                      labelText: '商户正则（可选）',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
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

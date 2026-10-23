import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../core/utils/id_gen.dart';
import '../../core/utils/money.dart';
import '../../core/utils/recurring_calendar.dart';
import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/picker_form_field.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import '../ledger/account_picker_sheet.dart';
import '../ledger/category_picker_sheet.dart';
import 'recurring_runner.dart';

class RecurringWizardArgs {
  const RecurringWizardArgs({
    this.amountMinor,
    this.currency,
    this.periodKind,
    this.categoryId,
    this.accountId,
    this.note,
    this.type = 'out',
  });

  final int? amountMinor;
  final String? currency;
  final String? periodKind;
  final String? categoryId;
  final String? accountId;
  final String? note;
  final String type;
}

class RecurringWizardPage extends ConsumerStatefulWidget {
  const RecurringWizardPage({super.key, this.args});

  final RecurringWizardArgs? args;

  @override
  ConsumerState<RecurringWizardPage> createState() =>
      _RecurringWizardPageState();
}

class _RecurringWizardPageState extends ConsumerState<RecurringWizardPage> {
  int _step = 0;
  String _type = 'out';
  String _periodKind = 'month';
  int _interval = 1;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _accountId;
  String? _categoryId;
  DateTime _startAt = DateTime.now();
  List<Account> _accounts = [];
  List<Category> _categories = [];
  List<AssetType> _assetTypes = [];
  String? _ledgerId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.args;
    if (a != null) {
      _type = a.type;
      if (a.periodKind != null) _periodKind = a.periodKind!;
      if (a.amountMinor != null) {
        _amountCtrl.text = fromMinor(a.currency ?? 'CNY', a.amountMinor!)
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.?0+$'), '');
      }
      if (a.note != null) _noteCtrl.text = a.note!;
      _accountId = a.accountId;
      _categoryId = a.categoryId;
    }
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final ledger = await (db.select(db.ledgers)..limit(1)).getSingleOrNull();
    if (ledger == null) {
      setState(() => _loading = false);
      return;
    }
    final accounts = await db.loadActiveAccounts(ledger.id);
    final cats = await db.loadCategories(ledger.id, _type == 'in' ? 'in' : 'out');
    final assetTypes = await db.loadAssetTypes(ledger.id);
    setState(() {
      _ledgerId = ledger.id;
      _accounts = accounts;
      _categories = cats;
      _assetTypes = assetTypes;
      _accountId ??= accounts.isNotEmpty ? accounts.first.id : null;
      _categoryId ??= cats.isNotEmpty ? cats.first.id : null;
      _loading = false;
    });
  }

  Category? _categoryById(String? id) {
    if (id == null) return null;
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  Account? _accountById(String? id) {
    if (id == null) return null;
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _pickCategory() async {
    final id = await showCategoryPickerSheet(
      context,
      categories: _categories,
      selectedId: _categoryId,
    );
    if (id == null || !mounted) return;
    setState(() => _categoryId = id);
  }

  Future<void> _pickAccount() async {
    final id = await showAccountPickerSheet(
      context,
      accounts: _accounts,
      assetTypes: _assetTypes,
      selectedId: _accountId,
    );
    if (id == null || !mounted) return;
    setState(() => _accountId = id);
  }

  Future<void> _reloadCats() async {
    if (_ledgerId == null) return;
    final db = ref.read(databaseProvider);
    final cats =
        await db.loadCategories(_ledgerId!, _type == 'in' ? 'in' : 'out');
    setState(() {
      _categories = cats;
      if (_categoryId == null || !cats.any((c) => c.id == _categoryId)) {
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
    });
  }

  List<DateTime> get _preview {
    return previewOccurrences(
      startAt: _startAt,
      periodKind: _periodKind,
      periodInterval: _interval,
      now: DateTime.now(),
      count: 3,
    );
  }

  int get _catchUpCount {
    final due = dueOccurrences(
      startAt: _startAt,
      periodKind: _periodKind,
      periodInterval: _interval,
      nextRunAt: _startAt,
      now: DateTime.now(),
    );
    return due.occurrences.length;
  }

  Future<void> _save() async {
    final major = double.tryParse(_amountCtrl.text.trim());
    if (major == null || major <= 0) {
      showGlassSnackBar(context, '请输入金额');
      return;
    }
    if (_accountId == null || _categoryId == null || _ledgerId == null) {
      showGlassSnackBar(context, '请选择资产账户和分类');
      return;
    }
    final n = _catchUpCount;
    if (n > 1) {
      final ok = await showGlassDialog<bool>(
        context: context,
        builder: (ctx) => CentliGlassDialog(
          title: const Text('将补记多期'),
          content: Text('起始日较早，保存后约会补记 $n 笔。确认？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      final acc = _accounts.firstWhere((a) => a.id == _accountId);
      final ccy = acc.currency;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final startMs = DateTime(
        _startAt.year,
        _startAt.month,
        _startAt.day,
      ).millisecondsSinceEpoch;
      await db.into(db.recurringRules).insert(
            RecurringRulesCompanion.insert(
              id: newId(),
              ledgerId: _ledgerId!,
              type: _type,
              amountMinor: toMinor(ccy, major),
              currency: ccy,
              accountId: _accountId!,
              categoryId: Value(_categoryId),
              note: Value(
                _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
              ),
              periodKind: _periodKind,
              periodInterval: Value(_interval),
              startAt: startMs,
              nextRunAt: startMs,
              createdAt: ts,
              updatedAt: ts,
            ),
          );
      await runDueRecurring(db);
      if (!mounted) return;
      context.pop();
      showGlassSnackBar(context, '已创建；下次启动将自动补记到期项');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const CentliGradientScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return CentliGradientScaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? '新建周期 · 类型与周期' : '新建周期 · 详情'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: _step == 0 ? _step1() : _step2(),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CentliSpacing.cardPad),
          child: Row(
            children: [
              if (_step > 0)
                TextButton(
                  onPressed: () => setState(() => _step = 0),
                  child: const Text('上一步'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (_step == 0) {
                          setState(() => _step = 1);
                        } else {
                          _save();
                        }
                      },
                child: Text(_step == 0 ? '下一步' : '确定'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _step1() {
    return ListView(
      children: [
        Text('类型', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: CentliSpacing.item),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'out', label: Text('支出')),
            ButtonSegment(value: 'in', label: Text('收入')),
          ],
          selected: {_type},
          onSelectionChanged: (s) async {
            setState(() => _type = s.first);
            await _reloadCats();
          },
        ),
        const SizedBox(height: CentliSpacing.sectionLoose + CentliSpacing.item),
        Text('周期', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: CentliSpacing.item),
        Wrap(
          spacing: 8,
          children: [
            for (final e in [
              ('day', '天'),
              ('week', '周'),
              ('month', '月'),
              ('quarter', '季'),
              ('year', '年'),
            ])
              ChoiceChip(
                label: Text(e.$2),
                selected: _periodKind == e.$1,
                onSelected: (_) => setState(() => _periodKind = e.$1),
              ),
          ],
        ),
        const SizedBox(height: CentliSpacing.sectionLoose),
        Row(
          children: [
            const Text('间隔'),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: TextFormField(
                initialValue: '$_interval',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)))),
                onChanged: (v) {
                  final n = int.tryParse(v) ?? 1;
                  setState(() => _interval = n < 1 ? 1 : n);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _step2() {
    final prev = _preview;
    return ListView(
      children: [
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '金额',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
          ),
        ),
        const SizedBox(height: CentliSpacing.section),
        Builder(
          builder: (context) {
            final acc = _accountById(_accountId);
            return CentliPickerFormField(
              key: ValueKey('acc-$_accountId'),
              label: '资产账户',
              value: acc?.name ?? '选择资产账户',
              outlined: true,
              isDense: false,
              leading: acc == null
                  ? null
                  : CentliIconChip(
                      name: acc.name,
                      kind: 'account',
                      iconKey: acc.icon,
                      size: 22,
                    ),
              onTap: _pickAccount,
            );
          },
        ),
        const SizedBox(height: CentliSpacing.section),
        Builder(
          builder: (context) {
            final cat = _categoryById(_categoryId);
            return CentliPickerFormField(
              key: ValueKey('cat-$_categoryId'),
              label: '分类',
              value: cat?.name ?? '选择分类',
              outlined: true,
              isDense: false,
              leading: cat == null
                  ? null
                  : CentliIconChip(
                      name: cat.name,
                      kind: cat.kind,
                      iconKey: cat.icon,
                      size: 22,
                    ),
              onTap: _pickCategory,
            );
          },
        ),
        const SizedBox(height: CentliSpacing.section),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(
            labelText: '备注',
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
          ),
        ),
        const SizedBox(height: CentliSpacing.section),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('起始日期'),
          subtitle: Text(DateFormat('yyyy-MM-dd').format(_startAt)),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _startAt,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              locale: const Locale('zh', 'CN'),
            );
            if (d != null) setState(() => _startAt = d);
          },
        ),
        const SizedBox(height: CentliSpacing.section),
        Text('将生成', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: CentliSpacing.item),
        for (final d in prev)
          Text('· ${DateFormat('yyyy年M月d日').format(d)}'),
        if (_catchUpCount > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '提示：起始日较早，保存后约补记 $_catchUpCount 笔',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

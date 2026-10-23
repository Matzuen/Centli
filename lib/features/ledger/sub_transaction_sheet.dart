import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../core/utils/money.dart';
import '../../core/widgets/centli_icon.dart';
import '../../core/widgets/glass.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'account_picker_sheet.dart';

/// Draft used by 记一笔「附加」before the parent bill is saved.
class DraftSubTxn {
  const DraftSubTxn({
    required this.subTypeId,
    required this.subTypeName,
    required this.sign,
    required this.accountId,
    required this.currency,
    required this.amountMinor,
    this.includeInStat = 1,
    this.includeInBudget = 1,
  });

  final String subTypeId;
  final String subTypeName;
  final int sign;
  final String accountId;
  final String currency;
  final int amountMinor;
  final int includeInStat;
  final int includeInBudget;

  String get type => sign >= 0 ? 'in' : 'out';
}

/// Add / edit a sub-transaction under [parentId], or return a [DraftSubTxn]
/// when [parentId] is null (记一笔 draft mode).
Future<DraftSubTxn?> showSubTransactionSheet(
  BuildContext context, {
  required SubTransactionType subType,
  String? parentId,
  String? ledgerId,
  String? initialAccountId,
  DateTime? happenAt,
  Transaction? existing,
  DraftSubTxn? initialDraft,
}) {
  return showGlassSheet<DraftSubTxn>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _SubTxnBody(
      subType: subType,
      parentId: parentId,
      ledgerId: ledgerId,
      initialAccountId: initialAccountId,
      happenAt: happenAt,
      existing: existing,
      initialDraft: initialDraft,
    ),
  );
}

class _SubTxnBody extends ConsumerStatefulWidget {
  const _SubTxnBody({
    required this.subType,
    this.parentId,
    this.ledgerId,
    this.initialAccountId,
    this.happenAt,
    this.existing,
    this.initialDraft,
  });

  final SubTransactionType subType;
  final String? parentId;
  final String? ledgerId;
  final String? initialAccountId;
  final DateTime? happenAt;
  final Transaction? existing;
  final DraftSubTxn? initialDraft;

  @override
  ConsumerState<_SubTxnBody> createState() => _SubTxnBodyState();
}

class _SubTxnBodyState extends ConsumerState<_SubTxnBody> {
  late SubTransactionType _type;
  String? _accountId;
  String _currency = 'CNY';
  late final TextEditingController _amountCtrl;
  bool _includeInStat = true;
  bool _includeInBudget = true;
  bool _saving = false;

  List<Account> _accounts = const [];
  List<AssetType> _assetTypes = const [];
  List<SubTransactionType> _allTypes = const [];

  @override
  void initState() {
    super.initState();
    _type = widget.subType;
    final existing = widget.existing;
    final draft = widget.initialDraft;
    if (existing != null) {
      _accountId = existing.accountId;
      _currency = existing.currency;
      _includeInStat = existing.includeInStat == 1;
      _includeInBudget = existing.includeInBudget == 1;
      _amountCtrl = TextEditingController(
        text: _formatMajor(existing.currency, existing.amountMinor),
      );
    } else if (draft != null) {
      _accountId = draft.accountId;
      _currency = draft.currency;
      _includeInStat = draft.includeInStat == 1;
      _includeInBudget = draft.includeInBudget == 1;
      _amountCtrl = TextEditingController(
        text: _formatMajor(draft.currency, draft.amountMinor),
      );
    } else {
      _accountId = widget.initialAccountId;
      _amountCtrl = TextEditingController();
    }
    _load();
  }

  String _formatMajor(String ccy, int minor) {
    final major = fromMinor(ccy, minor);
    final decimals = currencyDecimals[ccy] ?? 2;
    var s = major.toStringAsFixed(decimals);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'\.?0+$'), '');
      if (s.isEmpty) s = '0';
    }
    return s;
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final ledgerId = widget.ledgerId ??
        widget.existing?.ledgerId ??
        await ref.read(currentLedgerIdProvider.future);
    if (ledgerId == null) return;
    final accounts = await db.loadActiveAccounts(ledgerId);
    final types = await db.loadAssetTypes(ledgerId);
    final subTypes = await db.loadSubTransactionTypes();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _assetTypes = types;
      _allTypes = subTypes;
      if (_accountId == null && accounts.isNotEmpty) {
        _accountId = accounts.first.id;
      }
      final acc = _accounts.cast<Account?>().firstWhere(
            (a) => a?.id == _accountId,
            orElse: () => null,
          );
      if (acc != null) _currency = acc.currency;
    });
  }

  Account? get _account {
    for (final a in _accounts) {
      if (a.id == _accountId) return a;
    }
    return null;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positive = _type.sign >= 0;
    final signColor =
        positive ? CentliTheme.incomeGreen : CentliTheme.expenseRed;
    final acc = _account;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: signColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                positive ? Icons.add : Icons.remove,
                color: signColor,
              ),
            ),
            title: Text(
              _type.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(positive ? '增加' : '减少'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickType,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: acc == null
                ? Icon(Icons.account_balance_wallet_outlined,
                    color: scheme.onSurfaceVariant)
                : CentliIconChip(
                    name: acc.name,
                    kind: 'account',
                    iconKey: acc.icon,
                    size: 28,
                  ),
            title: Text(acc?.name ?? '选择账户'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickAccount,
          ),
          const Divider(height: 1),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Text(currencyFlag(_currency), style: const TextStyle(fontSize: 22)),
            title: Text('币种: $_currency'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickCurrency,
          ),
          const Divider(height: 1),
          const SizedBox(height: 8),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              labelText: '账户金额',
              suffixText: _currency,
            ),
            autofocus: widget.existing == null && widget.initialDraft == null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('计入统计'),
            value: _includeInStat,
            onChanged: (v) => setState(() => _includeInStat = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('计入预算'),
            value: _includeInBudget,
            onChanged: (v) => setState(() => _includeInBudget = v),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _confirm,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickType() async {
    final types = _allTypes.isEmpty
        ? await ref.read(databaseProvider).loadSubTransactionTypes()
        : _allTypes;
    if (!mounted) return;
    final picked = await showGlassSheet<SubTransactionType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '选择类型',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final t in types)
              ListTile(
                leading: Icon(
                  t.sign >= 0 ? Icons.add : Icons.remove,
                  color: t.sign >= 0
                      ? CentliTheme.incomeGreen
                      : CentliTheme.expenseRed,
                ),
                title: Text(t.name),
                selected: t.id == _type.id,
                onTap: () => Navigator.pop(ctx, t),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _type = picked);
  }

  Future<void> _pickAccount() async {
    final id = await showAccountPickerSheet(
      context,
      accounts: _accounts,
      assetTypes: _assetTypes,
      selectedId: _accountId,
      title: '选择账户',
    );
    if (id == null) return;
    final acc = _accounts.cast<Account?>().firstWhere(
          (a) => a?.id == id,
          orElse: () => null,
        );
    setState(() {
      _accountId = id;
      if (acc != null) _currency = acc.currency;
    });
  }

  Future<void> _pickCurrency() async {
    final picked = await showGlassSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '选择币种',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            for (final c in supportedCurrencies)
              ListTile(
                title: Text(currencyLabel(c)),
                selected: c == _currency,
                onTap: () => Navigator.pop(ctx, c),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _currency = picked);
  }

  Future<void> _confirm() async {
    final accountId = _accountId;
    if (accountId == null) {
      showGlassSnackBar(context, '请选择账户');
      return;
    }
    final major = double.tryParse(_amountCtrl.text.trim());
    if (major == null || major <= 0) {
      showGlassSnackBar(context, '请输入有效金额');
      return;
    }
    final amountMinor = toMinor(_currency, major);
    final draft = DraftSubTxn(
      subTypeId: _type.id,
      subTypeName: _type.name,
      sign: _type.sign,
      accountId: accountId,
      currency: _currency,
      amountMinor: amountMinor,
      includeInStat: _includeInStat ? 1 : 0,
      includeInBudget: _includeInBudget ? 1 : 0,
    );

    final parentId = widget.parentId;
    if (parentId == null && widget.existing == null) {
      // Draft mode for 记一笔.
      Navigator.pop(context, draft);
      return;
    }

    setState(() => _saving = true);
    try {
      final db = ref.read(databaseProvider);
      if (widget.existing != null) {
        await db.updateTransactionFields(
          id: widget.existing!.id,
          type: draft.type,
          amountMinor: draft.amountMinor,
          currency: draft.currency,
          accountId: draft.accountId,
          includeInStat: draft.includeInStat,
          includeInBudget: draft.includeInBudget,
          subTypeId: draft.subTypeId,
          note: draft.subTypeName,
        );
      } else {
        final ledgerId = widget.ledgerId ??
            await ref.read(currentLedgerIdProvider.future);
        if (ledgerId == null) {
          if (mounted) showGlassSnackBar(context, '未找到记账本');
          return;
        }
        await db.insertManualTransaction(
          ledgerId: ledgerId,
          type: draft.type,
          amountMinor: draft.amountMinor,
          currency: draft.currency,
          accountId: draft.accountId,
          note: draft.subTypeName,
          happenAt: widget.happenAt,
          includeInStat: draft.includeInStat,
          includeInBudget: draft.includeInBudget,
          parentId: parentId,
          subTypeId: draft.subTypeId,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, draft);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Pick a sub-transaction type first (for 记一笔「附加」entry).
Future<SubTransactionType?> showSubTransactionTypePicker(
  BuildContext context,
  WidgetRef ref,
) async {
  final types = await ref.read(databaseProvider).loadSubTransactionTypes();
  if (!context.mounted) return null;
  if (types.isEmpty) {
    showGlassSnackBar(context, '请先在「我的 · 子交易管理」添加类型');
    return null;
  }
  return showGlassSheet<SubTransactionType>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '添加子交易',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          for (final t in types)
            ListTile(
              leading: Icon(
                t.sign >= 0 ? Icons.add : Icons.remove,
                color: t.sign >= 0
                    ? CentliTheme.incomeGreen
                    : CentliTheme.expenseRed,
              ),
              title: Text(t.name),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, t),
            ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

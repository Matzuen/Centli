import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/db/centli_database.dart';
import 'glass.dart';

/// 级联选择结果：`accountId == null` 表示「自动（按资产账户名）」。
class AccountCascadeResult {

  const AccountCascadeResult.auto({
    this.label = '自动（按资产账户名）',
  }) : accountId = null;

  const AccountCascadeResult.account({
    required String this.accountId,
    required this.label,
  });

  final String? accountId;
  final String label;

  bool get isAuto => accountId == null;
}

/// 严格三层级联：账本 → 资产分类 → 资产账户。
///
/// [includeAuto] 时第一层顶部保留「自动（按资产账户名）」快捷项。
Future<AccountCascadeResult?> showGlassAccountCascadePicker({
  required BuildContext context,
  required List<Ledger> ledgers,
  required List<AssetType> assetTypes,
  required List<Account> accounts,
  String? selectedAccountId,
  bool includeAuto = true,
  String title = '选择默认资产账户',
  String autoLabel = '自动（按资产账户名）',
}) {
  return showGlassSheet<AccountCascadeResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _AccountCascadeBody(
      ledgers: ledgers,
      assetTypes: assetTypes,
      accounts: accounts,
      selectedAccountId: selectedAccountId,
      includeAuto: includeAuto,
      title: title,
      autoLabel: autoLabel,
    ),
  );
}

enum _CascadeLevel { ledger, assetType, account }

class _AccountCascadeBody extends StatefulWidget {
  const _AccountCascadeBody({
    required this.ledgers,
    required this.assetTypes,
    required this.accounts,
    required this.includeAuto,
    required this.title,
    required this.autoLabel,
    this.selectedAccountId,
  });

  final List<Ledger> ledgers;
  final List<AssetType> assetTypes;
  final List<Account> accounts;
  final String? selectedAccountId;
  final bool includeAuto;
  final String title;
  final String autoLabel;

  @override
  State<_AccountCascadeBody> createState() => _AccountCascadeBodyState();
}

class _AccountCascadeBodyState extends State<_AccountCascadeBody> {
  _CascadeLevel _level = _CascadeLevel.ledger;
  Ledger? _ledger;
  AssetType? _assetType;

  Map<String, String> get _ledgerNames => {
        for (final l in widget.ledgers) l.id: l.name,
      };

  List<AssetType> get _typesForLedger {
    final lid = _ledger?.id;
    if (lid == null) return const [];
    final used = <String>{
      for (final a in widget.accounts)
        if (a.ledgerId == lid && a.type.trim().isNotEmpty) a.type.trim(),
    };
    final ordered = <AssetType>[
      for (final t in widget.assetTypes)
        if (t.ledgerId == lid && used.contains(t.id)) t,
    ];
    final known = {for (final t in ordered) t.id};
    final orphans = used.difference(known).toList()..sort();
    for (final id in orphans) {
      ordered.add(
        AssetType(
          id: id,
          ledgerId: lid,
          name: '其他',
          icon: null,
          sortOrder: 9999,
          archived: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
      );
    }
    return ordered;
  }

  List<Account> get _accountsForType {
    final lid = _ledger?.id;
    final tid = _assetType?.id;
    if (lid == null || tid == null) return const [];
    return [
      for (final a in widget.accounts)
        if (a.ledgerId == lid && a.type.trim() == tid) a,
    ];
  }

  String get _headerSubtitle {
    switch (_level) {
      case _CascadeLevel.ledger:
        return '账本';
      case _CascadeLevel.assetType:
        return _ledger?.name ?? '资产分类';
      case _CascadeLevel.account:
        final parts = <String>[
          if (_ledger != null) _ledger!.name,
          if (_assetType != null) _assetType!.name,
        ];
        return parts.join(' › ');
    }
  }

  void _goBack() {
    setState(() {
      switch (_level) {
        case _CascadeLevel.ledger:
          break;
        case _CascadeLevel.assetType:
          _level = _CascadeLevel.ledger;
          _ledger = null;
          _assetType = null;
        case _CascadeLevel.account:
          _level = _CascadeLevel.assetType;
          _assetType = null;
      }
    });
  }

  void _pickLedger(Ledger ledger) {
    setState(() {
      _ledger = ledger;
      _assetType = null;
      _level = _CascadeLevel.assetType;
    });
  }

  void _pickType(AssetType type) {
    setState(() {
      _assetType = type;
      _level = _CascadeLevel.account;
    });
  }

  void _pickAccount(Account account) {
    final ledgerName = _ledgerNames[account.ledgerId] ?? '';
    final typeName = _assetType?.name ?? '';
    final label = [
      if (ledgerName.isNotEmpty) ledgerName,
      if (typeName.isNotEmpty) typeName,
      account.name,
    ].join(' › ');
    Navigator.pop(
      context,
      AccountCascadeResult.account(accountId: account.id, label: label),
    );
  }

  void _pickAuto() {
    Navigator.pop(
      context,
      AccountCascadeResult.auto(label: widget.autoLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.55;
    final canBack = _level != _CascadeLevel.ledger;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const SizedBox(height: CentliSpacing.item),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                if (canBack)
                  IconButton(
                    tooltip: '返回',
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                else
                  const SizedBox(width: 48),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        _headerSubtitle,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildList(scheme)),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme scheme) {
    switch (_level) {
      case _CascadeLevel.ledger:
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (widget.includeAuto)
              _tile(
                label: widget.autoLabel,
                selected: widget.selectedAccountId == null,
                icon: Icons.auto_awesome_rounded,
                onTap: _pickAuto,
              ),
            if (widget.ledgers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '暂无记账本',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              for (final ledger in widget.ledgers)
                _tile(
                  label: ledger.name,
                  submenu: true,
                  selected: false,
                  onTap: () => _pickLedger(ledger),
                ),
          ],
        );
      case _CascadeLevel.assetType:
        final types = _typesForLedger;
        if (types.isEmpty) {
          return Center(
            child: Text(
              '该账本下暂无资产分类',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final t in types)
              _tile(
                label: t.name,
                submenu: true,
                selected: false,
                onTap: () => _pickType(t),
              ),
          ],
        );
      case _CascadeLevel.account:
        final accs = _accountsForType;
        if (accs.isEmpty) {
          return Center(
            child: Text(
              '该分类下暂无资产账户',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final a in accs)
              _tile(
                label: '${a.name} · ${a.currency}',
                selected: a.id == widget.selectedAccountId,
                onTap: () => _pickAccount(a),
              ),
          ],
        );
    }
  }

  Widget _tile({
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    bool submenu = false,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: selected
                  ? Icon(Icons.check_rounded, size: 20, color: color)
                  : icon != null
                      ? Icon(icon, size: 20, color: color)
                      : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            if (submenu)
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: scheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import '../../data/db/database_provider.dart';
import 'asset_balance_vision.dart';
import '../../core/widgets/glass.dart';

enum _RowAction { create, update, skip }

class _RowState {
  _RowState({
    required this.hit,
    required this.action,
    this.matched,
    this.currencyMismatch = false,
  });

  final AssetBalanceVisionHit hit;
  _RowAction action;
  Account? matched;
  bool selected = true;

  /// Recognised currency differs from the matched account's currency.
  ///
  /// [adjustAccountBalance] moves the balance within the account's own
  /// currency, so applying a CNY-shaped number to a USD account (or the
  /// reverse) would silently write the wrong amount. Such rows are left for
  /// the user to handle by hand instead of being applied.
  final bool currencyMismatch;
}

/// Confirm LLM-recognized balances before creating / adjusting accounts.
Future<bool> showAssetBalanceRecognizeSheet(
  BuildContext context,
  WidgetRef ref, {
  required String ledgerId,
  required AssetBalanceVisionResult result,
  required List<Account> accounts,
  required Map<String, int> balances,
  required List<AssetType> types,
}) async {
  final applied = await showGlassSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _AssetBalanceRecognizeSheet(
      ledgerId: ledgerId,
      result: result,
      accounts: accounts,
      balances: balances,
      types: types,
    ),
  );
  return applied == true;
}

class _AssetBalanceRecognizeSheet extends ConsumerStatefulWidget {
  const _AssetBalanceRecognizeSheet({
    required this.ledgerId,
    required this.result,
    required this.accounts,
    required this.balances,
    required this.types,
  });

  final String ledgerId;
  final AssetBalanceVisionResult result;
  final List<Account> accounts;
  final Map<String, int> balances;
  final List<AssetType> types;

  @override
  ConsumerState<_AssetBalanceRecognizeSheet> createState() =>
      _AssetBalanceRecognizeSheetState();
}

class _AssetBalanceRecognizeSheetState
    extends ConsumerState<_AssetBalanceRecognizeSheet> {
  late final List<_RowState> _rows;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final hit in widget.result.accounts) _buildRow(hit),
    ];
  }

  _RowState _buildRow(AssetBalanceVisionHit hit) {
    final matched = matchAccountByName(hit.name, widget.accounts);
    final mismatch =
        matched != null && matched.currency.toUpperCase() != hit.currency;
    final current = matched == null
        ? null
        : widget.balances[matched.id] ?? matched.openingBalanceMinor;
    final target = toMinor(hit.currency, hit.balance);
    final action = mismatch
        ? _RowAction.skip
        : (matched == null
            ? _RowAction.create
            : (current == target ? _RowAction.skip : _RowAction.update));
    return _RowState(
      hit: hit,
      action: action,
      matched: matched,
      currencyMismatch: mismatch,
    )..selected = action != _RowAction.skip;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final selectedCount = _rows.where((r) => r.selected).length;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '确认识别结果',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '勾选要写入的资产账户：新建期初余额，或校正已有资产账户当前余额。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                    if (widget.result.warnings.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.result.warnings.join('；'),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: CentliSpacing.dense),
                  itemBuilder: (context, i) => _rowTile(_rows[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  onPressed: _busy || selectedCount == 0 ? null : _apply,
                  child: Text(
                    _busy ? '写入中…' : '应用所选（$selectedCount）',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowTile(_RowState row) {
    final hit = row.hit;
    final money = formatMinor(hit.currency, toMinor(hit.currency, hit.balance));
    final actionLabel = row.currencyMismatch
        ? '币种不一致，请手动处理'
        : switch (row.action) {
            _RowAction.create => '新建',
            _RowAction.update => '校正余额',
            _RowAction.skip => '已一致',
          };
    final matchLabel = row.currencyMismatch
        ? '${row.matched!.name}（${row.matched!.currency}）'
        : (row.matched?.name ?? '（将新建）');
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
      borderRadius: BorderRadius.circular(12),
      child: CheckboxListTile(
        value: row.selected,
        onChanged: row.action == _RowAction.skip
            ? null
            : (v) => setState(() => row.selected = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          hit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$money · ${hit.typeHint} · $actionLabel → $matchLabel',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final db = ref.read(databaseProvider);
    var created = 0;
    var updated = 0;
    try {
      for (final row in _rows) {
        if (!row.selected || row.action == _RowAction.skip) continue;
        final hit = row.hit;
        final target = toMinor(hit.currency, hit.balance);
        if (row.action == _RowAction.create || row.matched == null) {
          await db.createAccount(
            ledgerId: widget.ledgerId,
            name: hit.name,
            currency: hit.currency,
            type: hit.typeHint,
            openingBalanceMinor: target,
          );
          created++;
        } else {
          final acc = row.matched!;
          final current =
              widget.balances[acc.id] ?? acc.openingBalanceMinor;
          await db.adjustAccountBalance(
            account: acc,
            targetBalanceMinor: target,
            currentBalanceMinor: current,
          );
          updated++;
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      showGlassSnackBar(context, [
              if (created > 0) '新建 $created 个资产账户',
              if (updated > 0) '校正 $updated 个余额',
              if (created == 0 && updated == 0) '没有需要写入的项',
            ].join('，'),);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showGlassSnackBar(context, '写入失败：$e');
    }
  }
}

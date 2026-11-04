import 'package:flutter/material.dart';

import '../../core/widgets/glass.dart';

/// v1 支付悬浮窗的 Flutter 仿制品：供 Windows / 桌面 debug 调布局，
/// 以及 Android 上 MethodChannel 失败时的兜底。不写真实账本。
Future<void> showPaymentOverlayDesktopPreview(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => const _PaymentOverlayDesktopDialog(),
  );
}

class _PaymentOverlayDesktopDialog extends StatefulWidget {
  const _PaymentOverlayDesktopDialog();

  @override
  State<_PaymentOverlayDesktopDialog> createState() =>
      _PaymentOverlayDesktopDialogState();
}

class _PaymentOverlayDesktopDialogState
    extends State<_PaymentOverlayDesktopDialog> {
  static const _purple = Color(0xFF5B4B8A);
  static const _cardBg = Color(0xFFF5F2FA);
  static const _teal = Color(0xFF00897B);
  static const _incomeGreen = Color(0xFF43A047);
  static const _ink = Color(0xFF1A1A1A);

  static const _demoLedgers = ['日常账本', '旅行账本', '家庭账本'];
  static const _demoCategories = ['餐饮', '交通', '购物', '娱乐', '其他'];
  static const _demoAccounts = ['微信', '支付宝', '现金', '银行卡'];

  String _ledger = _demoLedgers.first;
  String _direction = 'out'; // out | in | transfer
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  String? _category = '餐饮';
  String? _account = '微信';
  String? _toAccount;
  bool _categoriesExpanded = false;
  bool _accountsExpanded = false;
  bool _toAccountsExpanded = false;
  bool _showSuccess = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: '12.80');
    _noteCtrl = TextEditingController(text: '调试预览 · 咖啡');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_direction == 'transfer') {
      return _account != null &&
          _toAccount != null &&
          _account != _toAccount &&
          _category != null;
    }
    return _category != null && _account != null;
  }

  void _pickLedger() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '选择账本',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final name in _demoLedgers)
              ListTile(
                title: Text(name),
                trailing: name == _ledger
                    ? const Icon(Icons.check, color: _purple)
                    : null,
                onTap: () => Navigator.pop(ctx, name),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _ledger = picked;
        _category = _demoCategories.first;
        _account = _demoAccounts.first;
        _toAccount = null;
      });
    }
  }

  void _setDirection(String dir) {
    setState(() {
      _direction = dir;
      _categoriesExpanded = false;
      _accountsExpanded = false;
      _toAccountsExpanded = false;
      if (dir == 'transfer') {
        _category ??= '转账';
        _toAccount ??= _demoAccounts.length > 1 ? _demoAccounts[1] : null;
      } else {
        _category ??= _demoCategories.first;
        _toAccount = null;
      }
    });
  }

  void _onConfirm() {
    if (!_canConfirm) return;
    // 桌面预览：不写 Android / Drift 账。
    showGlassSnackBar(context, '桌面预览，未写入');
    setState(() => _showSuccess = true);
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width.clamp(280.0, 420.0);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: Material(
          color: _cardBg,
          elevation: 12,
          shadowColor: _purple.withValues(alpha: 0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: _purple.withValues(alpha: 0.25)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: _showSuccess ? _buildSuccess() : _buildMain(),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '已入账（预览）',
              style: TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '¥${_amountCtrl.text}',
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '桌面预览，未写入真实账本',
              style: TextStyle(color: Color(0xFF999999), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMain() {
    final cats = _direction == 'transfer'
        ? const ['转账', '还款', '其他']
        : _demoCategories;
    return SingleChildScrollView(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶栏：账本 ▾ + 关闭
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _pickLedger,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '$_ledger ▾',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 20),
              tooltip: '关闭',
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 2. 支出｜收入｜转账
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(child: _dirChip('out', '支出')),
              const SizedBox(width: 8),
              Expanded(child: _dirChip('in', '收入')),
              const SizedBox(width: 8),
              Expanded(child: _dirChip('transfer', '转账')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // 3. 大号金额
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              '¥',
              style: TextStyle(
                color: _ink,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 4),
            IntrinsicWidth(
              child: TextField(
                controller: _amountCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '0.00',
                  hintStyle: TextStyle(color: Color(0xFFBBBBBB)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '微信支付 · 刚刚',
          textAlign: TextAlign.center,
          style: TextStyle(color: _teal, fontSize: 12),
        ),
        const SizedBox(height: 10),
        // 4. 备注
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          style: const TextStyle(color: _ink, fontSize: 13),
          decoration: InputDecoration(
            hintText: '备注（可选）',
            hintStyle: const TextStyle(color: Color(0xFF999999)),
            filled: true,
            fillColor: const Color(0xCCFFFFFF),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _purple.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _purple.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _purple),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 5. 分类摘要
        _summaryRow(
          label: '分类',
          value: _category ?? '未选择',
          onTap: () => setState(() {
            _categoriesExpanded = !_categoriesExpanded;
            if (_categoriesExpanded) {
              _accountsExpanded = false;
              _toAccountsExpanded = false;
            }
          }),
        ),
        if (_categoriesExpanded) ...[
          const SizedBox(height: 8),
          _simpleChipWrap(
            items: cats,
            selected: _category,
            onPick: (v) => setState(() {
              _category = v;
              _categoriesExpanded = false;
            }),
          ),
        ],
        const SizedBox(height: 8),
        // 6. 账户摘要
        _summaryRow(
          label: _direction == 'transfer' ? '转出' : '账户',
          value: _account ?? '未选择',
          onTap: () => setState(() {
            _accountsExpanded = !_accountsExpanded;
            if (_accountsExpanded) {
              _categoriesExpanded = false;
              _toAccountsExpanded = false;
            }
          }),
        ),
        if (_accountsExpanded) ...[
          const SizedBox(height: 8),
          _simpleChipWrap(
            items: _demoAccounts,
            selected: _account,
            onPick: (v) => setState(() {
              _account = v;
              _accountsExpanded = false;
            }),
          ),
        ],
        if (_direction == 'transfer') ...[
          const SizedBox(height: 8),
          _summaryRow(
            label: '转入',
            value: _toAccount ?? '未选择',
            onTap: () => setState(() {
              _toAccountsExpanded = !_toAccountsExpanded;
              if (_toAccountsExpanded) {
                _categoriesExpanded = false;
                _accountsExpanded = false;
              }
            }),
          ),
          if (_toAccountsExpanded) ...[
            const SizedBox(height: 8),
            _simpleChipWrap(
              items: _demoAccounts,
              selected: _toAccount,
              onPick: (v) => setState(() {
                _toAccount = v;
                _toAccountsExpanded = false;
              }),
            ),
          ],
        ],
        const SizedBox(height: 16),
        // 7. 忽略｜稍后｜入账
        Row(
          children: [
            Expanded(
              flex: 5,
              child: _outlineBtn('忽略', () => Navigator.of(context).pop()),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: _outlineBtn('稍后', () {
                showGlassSnackBar(context, '桌面预览：稍后（未写入）');
                Navigator.of(context).pop();
              }),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Opacity(
                opacity: _canConfirm ? 1 : 0.5,
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _canConfirm ? _onConfirm : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _incomeGreen,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _incomeGreen,
                      disabledForegroundColor: Colors.white70,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '入账',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 8. 打开详情
        TextButton(
          onPressed: () {
            showGlassSnackBar(context, '桌面预览：打开详情（无跳转）');
          },
          child: const Text(
            '打开 App 详细确认',
            style: TextStyle(color: _purple, fontSize: 13),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '桌面为界面预览 · 真机 debug 为系统悬浮窗',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF999999), fontSize: 11),
        ),
      ],
    ),
    );
  }

  Widget _dirChip(String key, String label) {
    final selected = _direction == key;
    return Material(
      color: selected ? _purple : const Color(0xCCFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? _purple : _purple.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: () => _setDirection(key),
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xCCFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _purple.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  '›',
                  style: TextStyle(
                    color: _purple,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _simpleChipWrap({
    required List<String> items,
    required String? selected,
    required ValueChanged<String> onPick,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          ChoiceChip(
            label: Text(item),
            selected: selected == item,
            onSelected: (_) => onPick(item),
            selectedColor: _purple,
            labelStyle: TextStyle(
              color: selected == item ? Colors.white : _ink,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            backgroundColor: const Color(0xCCFFFFFF),
            side: BorderSide(color: _purple.withValues(alpha: 0.2)),
            showCheckmark: false,
          ),
      ],
    );
  }

  Widget _outlineBtn(String label, VoidCallback onTap) {
    return SizedBox(
      height: 48,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _purple,
          side: BorderSide(color: _purple.withValues(alpha: 0.2), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.white,
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}

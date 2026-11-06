import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/widgets/glass.dart';

/// 支付悬浮窗桌面预览：确认卡 + 主题绿紫；分类 chip / 账户常显网格。
/// 不写真实账本；真机走 Android 系统悬浮窗。
Future<void> showPaymentOverlayDesktopPreview(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x66000000),
    builder: (ctx) => const _PaymentOverlayDesktopDialog(),
  );
}

class _CatNode {
  const _CatNode(this.name, [this.children = const []]);
  final String name;
  final List<_CatNode> children;
  bool get isGroup => children.isNotEmpty;
}

class _PaymentOverlayDesktopDialog extends StatefulWidget {
  const _PaymentOverlayDesktopDialog();

  @override
  State<_PaymentOverlayDesktopDialog> createState() =>
      _PaymentOverlayDesktopDialogState();
}

class _PaymentOverlayDesktopDialogState
    extends State<_PaymentOverlayDesktopDialog> {
  static const _ink = Color(0xFF1A1A1A);
  static const _muted = Color(0xFF666666);
  static const _hint = Color(0xFF888888);
  static const _purple = CentliTheme.brandPrimary;
  static const _mint = CentliTheme.brandGreen;

  static const _demoCategoryTree = <_CatNode>[
    _CatNode('餐饮', [_CatNode('外卖'), _CatNode('堂食'), _CatNode('咖啡')]),
    _CatNode('交通', [_CatNode('地铁'), _CatNode('打车'), _CatNode('加油')]),
    _CatNode('购物'),
    _CatNode('娱乐'),
    _CatNode('其他'),
  ];

  static const _demoAccounts = ['招商银行信用卡', '微信零钱', '支付宝余额', '农业银行'];

  late final TextEditingController _amountCtrl;
  String _category = '餐饮';
  String _account = '招商银行信用卡';
  String? _toAccount;
  static const bool _transfer = false;
  bool _masked = false;
  bool _showSuccess = false;
  bool _catMore = false;
  String? _browseParent;

  List<String> get _chips {
    final pool = <String>[_category, '咖啡', '其他', '外卖', '交通', '购物'];
    final out = <String>[];
    for (final n in pool) {
      if (out.contains(n)) continue;
      out.add(n);
      if (out.length >= 3) break;
    }
    return out;
  }

  List<_CatNode> get _catLevelItems {
    if (_browseParent == null) return _demoCategoryTree;
    return _demoCategoryTree
            .firstWhere(
              (n) => n.name == _browseParent,
              orElse: () => const _CatNode(''),
            )
            .children;
  }

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: '18.00');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    final amountOk = (double.tryParse(_amountCtrl.text.trim()) ?? 0) > 0;
    final transferOk = !_transfer ||
        (_toAccount != null &&
            _toAccount!.isNotEmpty &&
            _toAccount != _account);
    return _category.isNotEmpty && _account.isNotEmpty && amountOk && transferOk;
  }

  void _pickCatChip(String name) {
    setState(() {
      _category = name;
      _catMore = false;
      _browseParent = null;
    });
  }

  void _toggleCatMore() {
    setState(() {
      _catMore = !_catMore;
      if (_catMore) {
        _browseParent = null;
      }
    });
  }

  void _onCatGridTap(_CatNode node) {
    if (_browseParent == null && node.isGroup) {
      setState(() => _browseParent = node.name);
      return;
    }
    setState(() {
      _category = node.name;
      _catMore = false;
      _browseParent = null;
    });
  }

  void _onConfirm() {
    if (!_canConfirm) return;
    showGlassSnackBar(context, '桌面预览，未写入');
    setState(() => _showSuccess = true);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width.clamp(280.0, 332.0);
    const radius = BorderRadius.all(Radius.circular(24));
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Color(0x338B84D6),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xE8F3EFFA),
                  borderRadius: radius,
                  border: Border.all(color: _purple.withValues(alpha: 0.28)),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
                    child: _showSuccess ? _buildSuccess() : _buildPending(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    final accLabel = _transfer && _toAccount != null
        ? '$_account → $_toAccount'
        : _account;
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '已入账',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '¥${_amountCtrl.text} · $_category · $accLabel',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPending() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '微信支付 · 刚刚',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 11.5),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '来自通知',
                style: TextStyle(color: _mint, fontSize: 10),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: _masked ? '显示金额' : '隐藏金额',
              onPressed: () => setState(() => _masked = !_masked),
              icon: Icon(
                _masked
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: _muted,
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: '收起',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18, color: _muted),
            ),
          ],
        ),
        Text.rich(
          TextSpan(
            style: const TextStyle(
              color: _ink,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
            children: [
              const TextSpan(text: '瑞幸咖啡'),
              TextSpan(
                text: ' · $_account',
                style: const TextStyle(
                  color: _hint,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (_masked)
          const Text(
            '¥ •••',
            style: TextStyle(
              color: _hint,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                '¥',
                style: TextStyle(
                  color: _muted,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              IntrinsicWidth(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                    height: 1.15,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(
              width: 28,
              child: Text('分类', style: TextStyle(color: _muted, fontSize: 11.5)),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final name in _chips) ...[
                      _chip(
                        label: name,
                        selected: name == _category,
                        onTap: () => _pickCatChip(name),
                      ),
                      const SizedBox(width: 6),
                    ],
                    _chip(
                      label: '更多',
                      selected: _catMore,
                      muted: !_catMore,
                      onTap: _toggleCatMore,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_catMore) ...[
          const SizedBox(height: 6),
          if (_browseParent != null)
            InkWell(
              onTap: () => setState(() => _browseParent = null),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '‹ 返回',
                  style: TextStyle(
                    color: _purple,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Text(
            _browseParent == null
                ? '选择一级分类'
                : '选择「$_browseParent」二级分类',
            style: const TextStyle(color: _hint, fontSize: 11),
          ),
          const SizedBox(height: 4),
          _grid(
            items: [
              for (final n in _catLevelItems)
                _GridItem(
                  label: n.name,
                  selected: n.name == _category,
                  onTap: () => _onCatGridTap(n),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _transfer ? '转出' : '账户',
          style: const TextStyle(color: _muted, fontSize: 11.5),
        ),
        const SizedBox(height: 6),
        _grid(
          items: [
            for (final a in _demoAccounts)
              _GridItem(
                label: a,
                selected: a == _account,
                onTap: () => setState(() {
                  _account = a;
                  if (_toAccount == a) {
                    _toAccount =
                        _demoAccounts.firstWhere((x) => x != a, orElse: () => a);
                  }
                }),
              ),
          ],
        ),
        if (_transfer) ...[
          const SizedBox(height: 8),
          const Text('转入', style: TextStyle(color: _muted, fontSize: 11.5)),
          const SizedBox(height: 6),
          _grid(
            items: [
              for (final a in _demoAccounts.where((x) => x != _account))
                _GridItem(
                  label: a,
                  selected: a == _toAccount,
                  onTap: () => setState(() => _toAccount = a),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          '已按历史记录预填，直接确认即可',
          style: TextStyle(color: _hint, fontSize: 10.5),
        ),
        const SizedBox(height: 10),
        Opacity(
          opacity: _canConfirm ? 1 : 0.45,
          child: SizedBox(
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: CentliTheme.brandGradient,
                boxShadow: [
                  BoxShadow(
                    color: _purple.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: _canConfirm ? _onConfirm : null,
                  borderRadius: BorderRadius.circular(16),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text(
                        '入账',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: _purple,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                minimumSize: const Size(0, 40),
              ),
              child: const Text('忽略', style: TextStyle(fontSize: 12)),
            ),
            Text('·', style: TextStyle(color: _purple.withValues(alpha: 0.4))),
            TextButton(
              onPressed: () {
                showGlassSnackBar(context, '桌面预览：稍后（未写入）');
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: _purple,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                minimumSize: const Size(0, 40),
              ),
              child: const Text('稍后', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _grid({required List<_GridItem> items}) {
    if (items.isEmpty) {
      return const Text(
        '暂无选项',
        style: TextStyle(color: _hint, fontSize: 12),
      );
    }
    final rows = <List<_GridItem>>[];
    for (var i = 0; i < items.length; i += 3) {
      rows.add(items.sublist(i, (i + 3).clamp(0, items.length)));
    }
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var c = 0; c < 3; c++) ...[
                if (c > 0) const SizedBox(width: 6),
                Expanded(
                  child: c < rows[r].length
                      ? _gridChip(rows[r][c])
                      : const SizedBox(height: 40),
                ),
              ],
            ],
          ),
        ],
      ],
    );
    if (rows.length <= 2) return body;
    return SizedBox(
      height: 40 * 2 + 8,
      child: SingleChildScrollView(child: body),
    );
  }

  Widget _gridChip(_GridItem item) {
    return Material(
      color: item.selected
          ? _mint.withValues(alpha: 0.12)
          : const Color(0xCCFFFFFF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: item.selected
              ? _mint.withValues(alpha: 0.28)
              : _purple.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: item.selected ? _mint : _ink,
                  fontSize: 12,
                  fontWeight:
                      item.selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool muted = false,
  }) {
    return Material(
      color: selected ? _mint.withValues(alpha: 0.12) : const Color(0xCCFFFFFF),
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? _mint.withValues(alpha: 0.28)
              : _purple.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: muted ? 8 : 13),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? _mint
                      : (muted ? _hint : _muted),
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridItem {
  const _GridItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
}

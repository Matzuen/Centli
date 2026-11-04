import 'package:flutter/material.dart';

import '../../core/widgets/glass.dart';

/// v1 支付悬浮窗的 Flutter 仿制品：供 Windows / 桌面 debug 调布局，
/// 以及 Android 上 MethodChannel 失败时的兜底。不写真实账本。
///
/// 分类 / 账户与真机一致：摘要行旁弹出级联菜单（有子项再展一级），
/// 不要独立大底栏 sheet。
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
  static const _purple = Color(0xFF5B4B8A);
  static const _cardBg = Color(0xFFF5F2FA);
  static const _teal = Color(0xFF00897B);
  static const _incomeGreen = Color(0xFF43A047);
  static const _ink = Color(0xFF1A1A1A);

  static const _demoLedgers = ['日常账本', '旅行账本', '家庭账本'];

  /// 分类树：餐饮 › 外卖/堂食 …
  static const _demoCategoryTree = <_CatNode>[
    _CatNode('餐饮', [_CatNode('外卖'), _CatNode('堂食'), _CatNode('咖啡')]),
    _CatNode('交通', [_CatNode('地铁'), _CatNode('打车'), _CatNode('加油')]),
    _CatNode('购物'),
    _CatNode('娱乐'),
    _CatNode('其他'),
  ];

  /// 资产分类 › 账户；跨账本时先账本。
  static const _demoAccountsByLedger = <String, Map<String, List<String>>>{
    '日常账本': {
      '现金账户': ['现金'],
      '信用账户': ['微信', '支付宝'],
      '银行账户': ['银行卡'],
    },
    '旅行账本': {
      '现金账户': ['旅行现金'],
      '信用账户': ['旅行信用卡'],
    },
    '家庭账本': {
      '银行账户': ['家庭储蓄卡'],
      '信用账户': ['家庭支付宝'],
    },
  };

  String _ledger = _demoLedgers.first;
  String _direction = 'out'; // out | in | transfer
  late final TextEditingController _amountCtrl;
  late final TextEditingController _noteCtrl;
  String? _category = '外卖';
  String? _account = '微信';
  String? _toAccount;
  bool _showSuccess = false;

  final GlobalKey _catKey = GlobalKey();
  final GlobalKey _accKey = GlobalKey();
  final GlobalKey _toAccKey = GlobalKey();

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

  List<_CatNode> get _categoryRoots {
    if (_direction == 'transfer') {
      return const [
        _CatNode('转账'),
        _CatNode('还款'),
        _CatNode('其他'),
      ];
    }
    return _demoCategoryTree;
  }

  Future<void> _pickLedgerNearTitle(BuildContext titleContext) async {
    final picked = await _showCascadeMenu(
      anchorContext: titleContext,
      roots: [
        for (final name in _demoLedgers)
          _CascadeNode(
            id: name,
            label: name,
            selected: name == _ledger,
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() {
        _ledger = picked.id;
        _category = _direction == 'transfer' ? '转账' : '外卖';
        _account = (_demoAccountsByLedger[_ledger]?.values.expand((e) => e).firstOrNull) ??
            '微信';
        _toAccount = null;
      });
    }
  }

  Future<void> _pickCategory() async {
    final roots = [
      for (final n in _categoryRoots)
        _CascadeNode(
          id: n.name,
          label: n.name,
          selected: n.name == _category,
          children: [
            for (final c in n.children)
              _CascadeNode(
                id: c.name,
                label: c.name,
                selected: c.name == _category,
              ),
          ],
        ),
    ];
    final picked = await _showCascadeMenu(
      anchorContext: _catKey.currentContext!,
      roots: roots,
    );
    if (picked != null && mounted) {
      setState(() => _category = picked.id);
    }
  }

  List<_CascadeNode> _accountCascadeRoots({String? exclude, String? selectedId}) {
    // 当前账本：资产分类 › 账户；并附「其他账本」入口（跨账本）。
    final current = _demoAccountsByLedger[_ledger] ?? const {};
    final nodes = <_CascadeNode>[];
    for (final entry in current.entries) {
      final leaves = [
        for (final name in entry.value)
          if (name != exclude)
            _CascadeNode(
              id: name,
              label: name,
              selected: name == selectedId,
            ),
      ];
      if (leaves.isEmpty) continue;
      if (current.length <= 1) {
        nodes.addAll(leaves);
      } else {
        nodes.add(
          _CascadeNode(
            id: 'type:${entry.key}',
            label: entry.key,
            children: leaves,
          ),
        );
      }
    }
    final otherLedgers = _demoLedgers.where((l) => l != _ledger).toList();
    if (otherLedgers.isNotEmpty) {
      nodes.add(
        _CascadeNode(
          id: '_other_ledgers',
          label: '其他账本',
          children: [
            for (final l in otherLedgers)
              _CascadeNode(
                id: 'ledger:$l',
                label: l,
                children: [
                  for (final e
                      in (_demoAccountsByLedger[l] ?? const {}).entries)
                    _CascadeNode(
                      id: 'type:$l/${e.key}',
                      label: e.key,
                      children: [
                        for (final name in e.value)
                          if (name != exclude)
                            _CascadeNode(
                              id: name,
                              label: name,
                              selected: name == selectedId,
                            ),
                      ],
                    ),
                ],
              ),
          ],
        ),
      );
    }
    return nodes;
  }

  Future<void> _pickAccount({required bool toAccount}) async {
    final key = toAccount ? _toAccKey : _accKey;
    final ctx = key.currentContext;
    if (ctx == null) return;
    final picked = await _showCascadeMenu(
      anchorContext: ctx,
      roots: _accountCascadeRoots(
        exclude: toAccount ? _account : null,
        selectedId: toAccount ? _toAccount : _account,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (toAccount) {
          _toAccount = picked.id;
        } else {
          _account = picked.id;
          if (_toAccount == _account) {
            _toAccount = null;
          }
        }
      });
    }
  }

  void _setDirection(String dir) {
    setState(() {
      _direction = dir;
      if (dir == 'transfer') {
        _category = '转账';
        _toAccount ??= (_demoAccountsByLedger[_ledger]
                ?.values
                .expand((e) => e)
                .where((a) => a != _account)
                .firstOrNull) ??
            null;
      } else {
        _category ??= '外卖';
        _toAccount = null;
      }
    });
  }

  void _onConfirm() {
    if (!_canConfirm) return;
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
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶栏：账本 ▾ + 关闭
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (titleCtx) => InkWell(
                    onTap: () => _pickLedgerNearTitle(titleCtx),
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
          // 5. 分类摘要 → 级联弹出菜单
          KeyedSubtree(
            key: _catKey,
            child: _summaryRow(
              label: '分类',
              value: _category ?? '未选择',
              onTap: _pickCategory,
            ),
          ),
          const SizedBox(height: 8),
          // 6. 账户摘要 → 级联弹出菜单
          KeyedSubtree(
            key: _accKey,
            child: _summaryRow(
              label: _direction == 'transfer' ? '转出' : '账户',
              value: _account ?? '未选择',
              onTap: () => _pickAccount(toAccount: false),
            ),
          ),
          if (_direction == 'transfer') ...[
            const SizedBox(height: 8),
            KeyedSubtree(
              key: _toAccKey,
              child: _summaryRow(
                label: '转入',
                value: _toAccount ?? '未选择',
                onTap: () => _pickAccount(toAccount: true),
              ),
            ),
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

class _CascadeNode {
  const _CascadeNode({
    required this.id,
    required this.label,
    this.selected = false,
    this.children = const [],
  });
  final String id;
  final String label;
  final bool selected;
  final List<_CascadeNode> children;
  bool get isGroup => children.isNotEmpty;
}

class _CascadePick {
  const _CascadePick(this.id, this.label);
  final String id;
  final String label;
}

Future<_CascadePick?> _showCascadeMenu({
  required BuildContext anchorContext,
  required List<_CascadeNode> roots,
}) {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) {
    return _showCascadeDialog(anchorContext, roots);
  }
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final rect = Rect.fromLTWH(
    topLeft.dx,
    topLeft.dy,
    box.size.width,
    box.size.height,
  );
  return showGeneralDialog<_CascadePick>(
    context: anchorContext,
    barrierDismissible: true,
    barrierLabel: 'dismiss',
    barrierColor: Colors.transparent,
    pageBuilder: (ctx, anim, secondary) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: rect.left.clamp(12.0, overlay.size.width - 220),
            top: (rect.bottom + 4).clamp(12.0, overlay.size.height - 120),
            width: 220,
            child: _CascadePopupCard(
              roots: roots,
              onPick: (p) => Navigator.pop(ctx, p),
            ),
          ),
        ],
      );
    },
  );
}

Future<_CascadePick?> _showCascadeDialog(
  BuildContext context,
  List<_CascadeNode> roots,
) {
  return showDialog<_CascadePick>(
    context: context,
    barrierColor: const Color(0x33000000),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      alignment: Alignment.center,
      child: SizedBox(
        width: 240,
        child: _CascadePopupCard(
          roots: roots,
          onPick: (p) => Navigator.pop(ctx, p),
        ),
      ),
    ),
  );
}

class _CascadePopupCard extends StatefulWidget {
  const _CascadePopupCard({required this.roots, required this.onPick});
  final List<_CascadeNode> roots;
  final ValueChanged<_CascadePick> onPick;

  @override
  State<_CascadePopupCard> createState() => _CascadePopupCardState();
}

class _CascadePopupCardState extends State<_CascadePopupCard> {
  static const _purple = Color(0xFF5B4B8A);
  static const _cardBg = Color(0xFFF5F2FA);
  static const _ink = Color(0xFF1A1A1A);

  final List<({String? title, List<_CascadeNode> items})> _stack = [];

  @override
  void initState() {
    super.initState();
    _stack.add((title: null, items: widget.roots));
  }

  @override
  Widget build(BuildContext context) {
    final level = _stack.last;
    return Material(
      color: _cardBg,
      elevation: 10,
      shadowColor: _purple.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _purple.withValues(alpha: 0.25)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          shrinkWrap: true,
          children: [
            if (_stack.length > 1)
              ListTile(
                dense: true,
                title: Text(
                  '‹ ${level.title ?? '返回'}',
                  style: const TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                onTap: () => setState(() => _stack.removeLast()),
              ),
            for (final item in level.items)
              ListTile(
                dense: true,
                title: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: item.selected ? _purple : _ink,
                    fontWeight:
                        item.selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                trailing: item.isGroup
                    ? const Text(
                        '›',
                        style: TextStyle(
                          color: _purple,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : (item.selected
                        ? const Icon(Icons.check, color: _purple, size: 18)
                        : null),
                onTap: () {
                  if (item.isGroup) {
                    setState(() {
                      _stack.add((title: item.label, items: item.children));
                    });
                  } else {
                    widget.onPick(_CascadePick(item.id, item.label));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

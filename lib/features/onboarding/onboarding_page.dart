import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/deep_link.dart';
import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../data/db/database_provider.dart';
import '../../core/widgets/glass.dart';

/// First-launch guide. Leads with 记账本 → 资产账户 → 记一笔.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _pageCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({String route = '/assets'}) async {
    await ref.read(databaseProvider).setSetting('onboarding_done', 'true');
    if (!mounted) return;
    context.go(PendingDeepLink.take() ?? route);
  }

  Future<void> _setupLedger() async {
    final db = ref.read(databaseProvider);
    final ledgerId = await db.currentLedgerId();
    final ledger =
        ledgerId == null ? null : await db.getLedger(ledgerId);
    if (!mounted) return;
    final nameCtrl = TextEditingController(text: ledger?.name ?? '');
    var base = ledger?.baseCurrency ?? 'CNY';
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return CentliGlassDialog(
              title: const Text('设置我的记账本'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '记账本名称',
                      hintText: '例如：个人、家庭、出差',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: CentliSpacing.section),
                  DropdownButtonFormField<String>(
                    initialValue: base,
                    items: [
                      for (final c in supportedCurrencies)
                        DropdownMenuItem(
                          value: c,
                          child: Text(currencyLabel(c)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => base = v);
                    },
                    decoration: const InputDecoration(
                      labelText: '本位币',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || !mounted) return;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入记账本名称')),
      );
      return;
    }
    if (ledger != null) {
      await db.updateLedger(id: ledger.id, name: name, baseCurrency: base);
    } else {
      await db.createLedgerWithDefaults(
        name: name,
        baseCurrency: base,
        switchTo: true,
      );
    }
    ref.invalidate(currentLedgerIdProvider);
    ref.invalidate(currentLedgerProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('记账本已设为「$name」')),
    );
    _next();
  }

  void _next() {
    if (_index >= _pageCount - 1) return;
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLast = _index == _pageCount - 1;

    return CentliGradientScaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => _finish(),
            child: const Text('跳过'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _OnboardSlide(
                    icon: Icons.menu_book_outlined,
                    title: '先建记账本',
                    body: '记账本把个人 / 家庭 / 出差的账分开。'
                        '起个名字、选好本位币，之后的资产账户和流水都归在这里。',
                    sketch: _LedgerSketch(onSetup: _setupLedger),
                  ),
                  const _OnboardSlide(
                    icon: Icons.account_balance_wallet_outlined,
                    title: '再建资产账户',
                    body: '到「资产」页点右上角 +「新建资产账户」，'
                        '添加现金、银行卡、电子钱包等，也可截图识别余额。'
                        '资产账户清楚了，收支才知道钱从哪来、到哪去。',
                    sketch: _AssetsSketch(),
                  ),
                  const _OnboardSlide(
                    icon: Icons.calculate_outlined,
                    title: '然后记一笔',
                    body: '底部中间「记一笔」记下支出 / 收入 / 转账。'
                        '支付通知会进待确认，确认后才入账；'
                        '需要藏金额时，可在「我的 · 安全」开启资产锁。',
                    sketch: _CalcSketch(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pageCount; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? scheme.primary
                            : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: isLast
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton(
                          onPressed: () => _finish(route: '/assets'),
                          child: const Text('去资产页开始'),
                        ),
                        const SizedBox(height: CentliSpacing.item),
                        TextButton(
                          onPressed: () => _finish(route: '/home'),
                          child: const Text('先逛逛首页'),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _index == 0 ? _setupLedger : _next,
                        child: Text(_index == 0 ? '设置记账本' : '下一步'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardSlide extends StatelessWidget {
  const _OnboardSlide({
    required this.icon,
    required this.title,
    required this.body,
    required this.sketch,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget sketch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: CentliSpacing.item),
          Row(
            children: [
              Icon(icon, color: scheme.primary, size: 28),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: CentliSpacing.section),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 28),
          Expanded(child: sketch),
        ],
      ),
    );
  }
}

class _LedgerSketch extends StatelessWidget {
  const _LedgerSketch({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '记账本',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: CentliSpacing.item),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '给记账本起个名字\n选好本位币',
                    style: TextStyle(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          FilledButton.tonal(
            onPressed: onSetup,
            child: const Text('现在设置'),
          ),
        ],
      ),
    );
  }
}

class _AssetsSketch extends StatelessWidget {
  const _AssetsSketch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String label, IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        );
    return CentliSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '资产',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Icon(Icons.add_rounded, color: scheme.primary),
              const SizedBox(width: 4),
              Text(
                '新建资产账户',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: CentliSpacing.section),
          chip('现金', Icons.payments_outlined),
          const SizedBox(height: 8),
          chip('银行卡', Icons.credit_card_outlined),
          const SizedBox(height: 8),
          chip('电子钱包', Icons.account_balance_wallet_outlined),
        ],
      ),
    );
  }
}

class _CalcSketch extends StatelessWidget {
  const _CalcSketch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '记一笔',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: CentliSpacing.item),
          Text(
            '¥ 0.00',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: CentliSpacing.section),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in ['支出', '收入', '转账'])
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: t == '支出'
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(
                      fontWeight:
                          t == '支出' ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const Spacer(),
          Text(
            '选好资产账户后再落库，流水才清楚。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

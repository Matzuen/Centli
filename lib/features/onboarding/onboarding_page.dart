import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/deep_link.dart';
import '../../app/theme.dart';
import '../../core/constants/currencies.dart';
import '../../data/db/database_provider.dart';
import '../../core/widgets/glass.dart';

/// First-launch guide. Leads with 记账本 → 资产账户 → 自动记账.
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

  bool _finishing = false;

  Future<void> _finish({String route = '/home'}) async {
    if (_finishing) return;
    _finishing = true;
    try {
      await ref.read(databaseProvider).setSetting('onboarding_done', 'true');
      ref.invalidate(onboardingDoneProvider);
      // 等 provider 读到 true，避免 redirect 把门禁又拦回引导。
      await ref.read(onboardingDoneProvider.future);
      if (!mounted) return;
      context.go(PendingDeepLink.take() ?? route);
    } catch (_) {
      _finishing = false;
      rethrow;
    }
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
      showGlassSnackBar(context, '请输入记账本名称');
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
    showGlassSnackBar(context, '记账本已设为「$name」');
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
                    body: '个人 / 家庭 / 出差各一本，账不混。'
                        '起个名字、选好本位币，之后的资产账户和流水都归这里。',
                    sketch: _LedgerSketch(onSetup: _setupLedger),
                  ),
                  const _OnboardSlide(
                    icon: Icons.account_balance_wallet_outlined,
                    title: '再建资产账户',
                    body: '到「资产」页右上角 +，添加现金、银行卡、电子钱包；'
                        '也可截图识别余额。账户清楚了，钱从哪来、到哪去才看得见。',
                    sketch: _AssetsSketch(),
                  ),
                  const _OnboardSlide(
                    icon: Icons.notifications_active_outlined,
                    title: '开自动记账',
                    body: '微信 / 支付宝支付通知进悬浮窗或待确认，点一下才入账。'
                        '配齐：通知使用权 · 总开关 · 悬浮窗 · 后台保活。'
                        '现金或漏记用底部「记一笔」。',
                    sketch: _AutoSketch(),
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
                          onPressed: () => _finish(route: '/me/auto'),
                          child: const Text('去自动记账权限清单'),
                        ),
                        const SizedBox(height: CentliSpacing.item),
                        FilledButton.tonal(
                          onPressed: () => _finish(route: '/assets'),
                          child: const Text('去资产页建账户'),
                        ),
                        const SizedBox(height: CentliSpacing.dense),
                        TextButton(
                          onPressed: () => _finish(
                            route: '/me/permission?open=1',
                          ),
                          child: const Text('先开通知使用权'),
                        ),
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
    Widget row(String label, String balance, IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                balance,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
              ),
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
              Icon(Icons.add_rounded, color: scheme.primary, size: 20),
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
          row('现金', '¥ 0.00', Icons.payments_outlined),
          const SizedBox(height: 8),
          row('银行卡', '¥ 0.00', Icons.credit_card_outlined),
          const SizedBox(height: 8),
          row('电子钱包', '¥ 0.00', Icons.account_balance_wallet_outlined),
        ],
      ),
    );
  }
}

class _AutoSketch extends StatelessWidget {
  const _AutoSketch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '支付通知',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: CentliSpacing.item),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '微信支付 · 付款成功',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '¥28.50',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CentliSpacing.section),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '确认入账',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '¥ 28.50',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '餐饮 · 支付宝/微信',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: CentliSpacing.item),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '确认入账',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '也可进待确认列表再处理。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

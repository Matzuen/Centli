import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/db/database_provider.dart';
import '../../platform/notifications/notification_listener_stub.dart';
import '../../app/theme.dart';

/// First-launch guide (skippable). Writes `onboarding_done=true` on finish.
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

  Future<void> _finish() async {
    await ref.read(databaseProvider).setSetting('onboarding_done', 'true');
    if (!mounted) return;
    context.go('/home');
  }

  Future<void> _openNotificationPermission() async {
    // P1: permission explain page after settings return (wireframe §9).
    if (!mounted) return;
    await context.push('/me/permission?open=1&onboarding=1');
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

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _finish,
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
                children: const [
                  _OnboardSlide(
                    icon: Icons.calculate_outlined,
                    title: '记一笔',
                    body: '半屏计算器面板，拇指优先：选支出/收入/转账，点分类与账户，一键落库。',
                    sketch: _CalcSketch(),
                  ),
                  _OnboardSlide(
                    icon: Icons.notifications_active_outlined,
                    title: '通知待确认',
                    body: '支付通知进来先排队，猜分类后一键入账——默认不静默入账。',
                    sketch: _PendingSketch(),
                  ),
                  _OnboardSlide(
                    icon: Icons.security_outlined,
                    title: '开启通知权限',
                    body: '仅用于读取支付成功类通知以辅助记账，需你确认后才会写入流水。',
                    sketch: _PermissionSketch(),
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
                          onPressed: _openNotificationPermission,
                          child: const Text('去开启'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _finish,
                          child: const Text('稍后再说'),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _next,
                        child: const Text('下一步'),
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
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
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

/// Wireframe-ish calculator panel sketch.
class _CalcSketch extends StatelessWidget {
  const _CalcSketch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _chip(context, '支出', selected: true),
                const SizedBox(width: 8),
                _chip(context, '收入'),
                const SizedBox(width: 8),
                _chip(context, '转账'),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '¥ 0',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final label in ['餐饮', '交通', '日用', '更多'])
                  Chip(
                    label: Text(label),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
              ],
            ),
            const Spacer(),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.4,
              children: [
                for (final k in [
                  '1',
                  '2',
                  '3',
                  '⌫',
                  '4',
                  '5',
                  '6',
                  '+',
                  '7',
                  '8',
                  '9',
                  '-',
                  '.',
                  '0',
                  '00',
                  '✓',
                ])
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: k == '✓'
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      k,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: k == '✓' ? scheme.onPrimary : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String label, {bool selected = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? scheme.onPrimary : scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Wireframe: notification → pending card → post.
class _PendingSketch extends StatelessWidget {
  const _PendingSketch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        _stepCard(
          context,
          icon: Icons.notifications_outlined,
          title: '支付通知',
          subtitle: '支付宝 · ¥28.50 · 某餐厅',
        ),
        Icon(Icons.arrow_downward, color: scheme.outline),
        _stepCard(
          context,
          icon: Icons.pending_actions_outlined,
          title: '待确认卡片',
          subtitle: '猜「餐饮」· 账户：支付宝',
        ),
        Icon(Icons.arrow_downward, color: scheme.outline),
        _stepCard(
          context,
          icon: Icons.check_circle_outline,
          title: '一键入账',
          subtitle: '确认后写入流水并学习商户规则',
          highlight: true,
        ),
      ],
    );
  }

  Widget _stepCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    bool highlight = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return CentliSoftCard(
      color: highlight ? scheme.primaryContainer : null,
      child: ListTile(
        leading: Icon(
          icon,
          color: highlight ? scheme.onPrimaryContainer : scheme.primary,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: highlight ? scheme.onPrimaryContainer : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: highlight
                ? scheme.onPrimaryContainer.withValues(alpha: 0.85)
                : null,
          ),
        ),
      ),
    );
  }
}

class _PermissionSketch extends StatelessWidget {
  const _PermissionSketch();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final granted = NotificationCaptureStub.supported;
    return CentliSoftCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.privacy_tip_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  '通知使用权',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '用途：解析支付成功类通知 → 待确认队列',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '不会静默入账；可随时在「我的 · 自动记账」关闭。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                granted
                    ? '当前平台可申请系统通知使用权'
                    : 'Android 可跳转系统「通知使用权」；其他平台可稍后在「我的」查看说明',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

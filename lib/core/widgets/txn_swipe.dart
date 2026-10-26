import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 同时只允许一行处于滑开状态。
class _TxnSwipeRegistry {
  _TxnSwipeRegistry._();
  static VoidCallback? _closeOpen;

  static void notifyOpen(VoidCallback close) {
    if (_closeOpen == close) return;
    final prev = _closeOpen;
    _closeOpen = close;
    prev?.call();
  }

  static void notifyClosed(VoidCallback close) {
    if (_closeOpen == close) _closeOpen = null;
  }
}

/// 流水行滑动手势：左滑「删除」「复制新建」，右滑「编辑」。
///
/// [enabled] 为 false（多选模式）时不响应滑动，直接渲染 [child]。
class TxnSwipeHost extends StatefulWidget {
  const TxnSwipeHost({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onCopy,
    required this.onDelete,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final bool enabled;

  /// 右滑露出「编辑」的宽度。
  static const double editExtent = 76;

  /// 左滑露出「复制新建」+「删除」的总宽度。
  static const double startActionsExtent = 152;

  @override
  State<TxnSwipeHost> createState() => TxnSwipeHostState();
}

@visibleForTesting
class TxnSwipeHostState extends State<TxnSwipeHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _offset = 0;
  bool _dragging = false;

  /// 当前内容偏移（正 = 右滑露出编辑；负 = 左滑露出复制/删除）。
  @visibleForTesting
  double get offset => _offset;

  void _close() => _animateTo(0);

  void _animateTo(double target) {
    _controller.stop();
    final begin = _offset;
    if ((begin - target).abs() < 0.5) {
      setState(() => _offset = target);
      if (target == 0) {
        _TxnSwipeRegistry.notifyClosed(_close);
      } else {
        _TxnSwipeRegistry.notifyOpen(_close);
      }
      return;
    }
    final anim = Tween<double>(
      begin: begin,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    void tick() {
      if (!mounted) return;
      setState(() => _offset = anim.value);
    }

    anim.addListener(tick);
    _controller.forward(from: 0).whenComplete(() {
      anim.removeListener(tick);
      if (!mounted) return;
      setState(() => _offset = target);
      if (target == 0) {
        _TxnSwipeRegistry.notifyClosed(_close);
      } else {
        _TxnSwipeRegistry.notifyOpen(_close);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(covariant TxnSwipeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _offset != 0) {
      _controller.stop();
      setState(() => _offset = 0);
      _TxnSwipeRegistry.notifyClosed(_close);
    }
  }

  @override
  void dispose() {
    _TxnSwipeRegistry.notifyClosed(_close);
    _controller.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _controller.stop();
    _dragging = true;
    _TxnSwipeRegistry.notifyOpen(_close);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || !_dragging) return;
    final next = (_offset + details.delta.dx)
        .clamp(-TxnSwipeHost.startActionsExtent, TxnSwipeHost.editExtent)
        .toDouble();
    setState(() => _offset = next);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!widget.enabled) return;
    _dragging = false;
    final v = details.primaryVelocity ?? 0;
    double target = 0;
    if (v < -300) {
      target = -TxnSwipeHost.startActionsExtent;
    } else if (v > 300) {
      target = TxnSwipeHost.editExtent;
    } else if (_offset <= -TxnSwipeHost.startActionsExtent * 0.4) {
      target = -TxnSwipeHost.startActionsExtent;
    } else if (_offset >= TxnSwipeHost.editExtent * 0.4) {
      target = TxnSwipeHost.editExtent;
    }
    _animateTo(target);
  }

  void _onDragCancel() {
    if (!widget.enabled) return;
    _dragging = false;
    _animateTo(_snapTargetFor(_offset));
  }

  double _snapTargetFor(double o) {
    if (o <= -TxnSwipeHost.startActionsExtent * 0.4) {
      return -TxnSwipeHost.startActionsExtent;
    }
    if (o >= TxnSwipeHost.editExtent * 0.4) {
      return TxnSwipeHost.editExtent;
    }
    return 0;
  }

  Future<void> _runAction(VoidCallback action) async {
    _animateTo(0);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    action();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final scheme = Theme.of(context).colorScheme;
    final open = _offset.abs() > 0.5;

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: Row(
              children: [
                _TxnSwipeAction(
                  width: TxnSwipeHost.editExtent,
                  color: CentliTheme.brandPrimary,
                  icon: Icons.edit_outlined,
                  label: '编辑',
                  onTap: () => _runAction(widget.onEdit),
                ),
                const Spacer(),
                _TxnSwipeAction(
                  width: TxnSwipeHost.editExtent,
                  color: const Color(0xFF546E7A),
                  icon: Icons.copy_outlined,
                  label: '复制新建',
                  onTap: () => _runAction(widget.onCopy),
                ),
                _TxnSwipeAction(
                  width: TxnSwipeHost.editExtent,
                  color: scheme.error,
                  icon: Icons.delete_outline,
                  label: '删除',
                  onTap: () => _runAction(widget.onDelete),
                ),
              ],
            ),
          ),
          GestureDetector(
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _onDragCancel,
            child: Transform.translate(
              offset: Offset(_offset, 0),
              child: Stack(
                children: [
                  Material(color: scheme.surface, child: widget.child),
                  if (open)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _close,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TxnSwipeAction extends StatelessWidget {
  const _TxnSwipeAction({
    required this.width,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final double width;
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

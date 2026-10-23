import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 路由守卫：代码里所有 `push('...') / go('...')` 的目标，都必须能在
/// `lib/app/router.dart` 里找到对应的已注册路径。
///
/// 这条测试是为「净资产变化的账单列表按钮跳到 /search，但搜索页其实挂在
/// /home/search 下 → 页面不存在」这个 bug 加的。
void main() {
  /// Resolve a router child path against its parent.
  String join(String parent, String child) {
    if (child.startsWith('/')) return child;
    if (parent.endsWith('/')) return '$parent$child';
    return '$parent/$child';
  }

  /// Flatten the router into every reachable absolute path.
  Set<String> declaredRoutes(String routerSource) {
    final out = <String>{};
    // Track the path stack by indentation-independent nesting depth.
    final stack = <({int indent, String path})>[];
    for (final line in routerSource.split('\n')) {
      final m = RegExp(r"""(\s*)path:\s*'([^']+)'""").firstMatch(line);
      if (m == null) continue;
      final indent = m.group(1)!.length;
      final raw = m.group(2)!;
      while (stack.isNotEmpty && stack.last.indent >= indent) {
        stack.removeLast();
      }
      final parent = stack.isEmpty ? '' : stack.last.path;
      final full = parent.isEmpty ? raw : join(parent, raw);
      stack.add((indent: indent, path: full));
      out.add(full);
    }
    return out;
  }

  /// Every navigation target literal in the app.
  Set<String> navTargets() {
    final out = <String>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      for (final m in RegExp(r"""(?:push|go|replace)\(\s*'([^']+)'""")
          .allMatches(f.readAsStringSync())) {
        out.add(m.group(1)!);
      }
    }
    return out;
  }

  /// Reduce a concrete target (`/assets/abc`, `/me/permission?x=1`) to the
  /// shape the router registers (`/assets/:id`).
  String toPattern(String target) {
    final noQuery = target.split('?').first;
    final segs = noQuery.split('/');
    return segs
        .map((s) => s.startsWith(r'$') ? ':id' : s)
        .join('/');
  }

  test('router paths flatten correctly', () {
    final routes = declaredRoutes('''
      path: '/home',
        path: 'search',
      path: '/me',
        path: 'auto',
          path: 'rules',
    ''');
    expect(routes, contains('/home/search'));
    expect(routes, contains('/me/auto/rules'));
  });

  test('every navigation target is a registered route', () {
    final routes = declaredRoutes(
      File('lib/app/router.dart').readAsStringSync(),
    );
    final missing = <String>[];
    for (final target in navTargets()) {
      final pattern = toPattern(target);
      if (!routes.contains(pattern)) missing.add(target);
    }
    expect(missing, isEmpty,
        reason: '这些跳转没有对应路由（会出现「页面不存在」）: $missing');
  });

  test('the pie button switches to the stats tab', () {
    final home = File('lib/features/home/home_page.dart').readAsStringSync();
    // go() switches bottom-nav tabs; push() would stack stats on top of home.
    expect(home.contains("openTab('/stats')"), isTrue);
    expect(home.contains("open('/stats')"), isFalse);
  });

  test('the net-worth card only keeps the pie button', () {
    final home = File('lib/features/home/home_page.dart').readAsStringSync();
    // 用户要求去掉图表卡右上角的「账单列表」入口，只留「分类占比」。
    expect(home.contains('net_change_list'), isFalse);
    expect(home.contains('net_change_pie'), isTrue);
  });

  test('the pie button switches to the stats tab', () {
    final home = File('lib/features/home/home_page.dart').readAsStringSync();
    // go() switches bottom-nav tabs; push() would stack stats on top of home.
    expect(home.contains("openTab('/stats')"), isTrue);
    expect(home.contains("open('/stats')"), isFalse);
  });

}

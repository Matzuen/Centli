import 'dart:io';

import 'package:centli/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib navigation path literals match go_router config', () {
    final re = RegExp(
      r"""context\.(push|go|replace)\(\s*(['"])([^'"]+)\2""",
    );
    final literals = <String>[];
    var skipped = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      for (final m in re.allMatches(src)) {
        final path = m.group(3)!;
        if (path.contains(r'${')) {
          skipped++;
          continue;
        }
        literals.add(path);
      }
    }
    // ignore: avoid_print
    print(
      'route_literals: skipped $skipped dynamic path(s); '
      'checking ${literals.length} literal(s)',
    );

    final router = createRouter();
    for (final path in literals) {
      // go_router 16 findMatch returns empty matches for unknown paths
      // (does not throw). Assert a real match exists.
      final match = router.configuration.findMatch(Uri.parse(path));
      expect(
        match.matches,
        isNotEmpty,
        reason: '代码里写了不存在的路由: $path',
      );
    }
  });
}

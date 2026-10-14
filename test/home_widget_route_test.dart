import 'package:flutter_test/flutter_test.dart';

import 'package:centli/platform/home_widget/centli_home_widget_sync.dart';

void main() {
  group('CentliHomeWidgetSync.routeForUri', () {
    test('pending host', () {
      expect(
        CentliHomeWidgetSync.routeForUri(Uri.parse('centli://pending')),
        '/home/pending',
      );
    });

    test('home host', () {
      expect(
        CentliHomeWidgetSync.routeForUri(Uri.parse('centli://home')),
        '/home',
      );
    });

    test('null → null', () {
      expect(CentliHomeWidgetSync.routeForUri(null), isNull);
    });
  });
}

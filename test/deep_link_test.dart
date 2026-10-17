import 'package:centli/app/deep_link.dart';
import 'package:centli/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    // Drain any leftover capture between tests.
    PendingDeepLink.take();
  });

  group('PendingDeepLink.resolveInitialDeepLink', () {
    test('centli://home → /home', () {
      expect(PendingDeepLink.resolveInitialDeepLink('centli://home'), '/home');
    });

    test('centli://home/ → /home', () {
      expect(PendingDeepLink.resolveInitialDeepLink('centli://home/'), '/home');
    });

    test('centli://pending → /home/pending', () {
      expect(
        PendingDeepLink.resolveInitialDeepLink('centli://pending'),
        '/home/pending',
      );
    });

    test('centli://xxx → /home', () {
      expect(PendingDeepLink.resolveInitialDeepLink('centli://xxx'), '/home');
    });

    test('/ → null', () {
      expect(PendingDeepLink.resolveInitialDeepLink('/'), isNull);
    });

    test('empty → null', () {
      expect(PendingDeepLink.resolveInitialDeepLink(''), isNull);
    });

    test('/nope → /nope (errorBuilder handles)', () {
      expect(PendingDeepLink.resolveInitialDeepLink('/nope'), '/nope');
    });
  });

  group('PendingDeepLink capture/take', () {
    test('capture then take once', () {
      PendingDeepLink.capture('centli://pending');
      expect(PendingDeepLink.has, isTrue);
      expect(PendingDeepLink.take(), '/home/pending');
      expect(PendingDeepLink.has, isFalse);
      expect(PendingDeepLink.take(), isNull);
    });

    test('capture / is ignored', () {
      PendingDeepLink.capture('/');
      expect(PendingDeepLink.has, isFalse);
      expect(PendingDeepLink.take(), isNull);
    });
  });

  group('createRouter override', () {
    test('starts at /splash despite platform default', () {
      final router = createRouter();
      addTearDown(router.dispose);
      expect(router.routeInformationProvider.value.uri.path, '/splash');
    });
  });
}
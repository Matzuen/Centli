import 'package:centli/app/theme.dart';
import 'package:centli/core/utils/fx.dart';
import 'package:centli/core/widgets/centli_error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 首页概览卡按用户指定的表格排布：
///
/// 账本名
/// **¥ 净资产**   ▲ 区间涨跌
/// 资产 | 负债
/// 月收入 | 月支出
/// 总收入 | 总支出
void main() {
  group('classifyError', () {
    test('network failures are recognised', () {
      expect(classifyError(TimeoutExceptionLike()), CentliErrorKind.network);
      expect(
        classifyError(Exception('ClientException: Failed host lookup')),
        CentliErrorKind.network,
      );
    });

    test('database failures are recognised', () {
      expect(
        classifyError(Exception('SqliteException(5): database is locked')),
        CentliErrorKind.database,
      );
    });

    test('permission failures are recognised', () {
      expect(
        classifyError(Exception('PlatformException(permission_denied)')),
        CentliErrorKind.permission,
      );
    });

    test('titles and hints differ by kind', () {
      expect(errorTitle(Exception('Failed host lookup')), '网络连接失败');
      expect(errorTitle(Exception('database is locked')), '数据读取失败');
      expect(errorTitle(Exception('boom')), '加载失败');
    });
  });

  testWidgets('error state offers 重试 and hides the raw error by default',
      (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: CentliTheme.light(),
        home: Scaffold(
          body: CentliErrorState(
            error: Exception('ClientException: Failed host lookup'),
            onRetry: () => retried++,
          ),
        ),
      ),
    );
    expect(find.text('网络连接失败'), findsOneWidget);
    expect(find.textContaining('网络连接'), findsWidgets);
    // Raw toString is hidden until 「详情」 is tapped.
    expect(find.textContaining('ClientException'), findsNothing);
    await tester.tap(find.byKey(const Key('centli_error_retry')));
    expect(retried, 1);
    await tester.tap(find.text('详情'));
    await tester.pump();
    expect(find.textContaining('ClientException'), findsOneWidget);
  });

  test('BaseRangeSummary exposes month income / expense for the card', () {
    const s = BaseRangeSummary(
      incomeMinor: 572400,
      expenseMinor: 138858,
      unconverted: {},
      convertedCount: 2,
      unconvertedCount: 0,
    );
    expect(s.incomeMinor, 572400);
    expect(s.expenseMinor, 138858);
  });

}

/// A TimeoutException stand-in (dart:async's is used indirectly by the helper).
class TimeoutExceptionLike implements Exception {
  @override
  String toString() => 'TimeoutException';

}

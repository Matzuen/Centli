import 'package:centli/core/utils/amount_expr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evalAmountExpr precedence', () {
    test('add subtract left to right', () {
      expect(evalAmountExpr('10+2-3'), 9);
    });

    test('multiply divide before add', () {
      expect(evalAmountExpr('2+3×4'), 14);
      expect(evalAmountExpr('10-2×3'), 4);
      expect(evalAmountExpr('2+8÷4'), 4);
    });

    test('same-level multiply divide left to right', () {
      expect(evalAmountExpr('8÷2×4'), 16);
      expect(evalAmountExpr('8×2÷4'), 4);
    });

    test('star slash aliases', () {
      expect(evalAmountExpr('2*3+1'), 7);
      expect(evalAmountExpr('8/2+1'), 5);
    });

    test('trailing operator ignored', () {
      expect(evalAmountExpr('12+'), 12);
      expect(evalAmountExpr('3×'), 3);
    });

    test('divide by zero null', () {
      expect(evalAmountExpr('8÷0'), isNull);
    });
  });

  group('applyAmountOperator and keys', () {
    test('replace trailing op', () {
      expect(applyAmountOperator('12+', '×'), '12×');
    });

    test('append digit after op', () {
      expect(applyAmountKey('12×', '3', 2), '12×3');
    });
  });
}

/// Amount keypad expression: digits, `.`, and operators `+ - \u00d7 \u00f7` (* / aliases).
///
/// Evaluation uses **operator precedence**: \u00d7\u00f7 before +-; same-level left-to-right.
/// Trailing operator is ignored when evaluating (display may still show it).
library;

double? evalAmountExpr(String expr) {
  var s = expr.trim().replaceAll(' ', '');
  s = s.replaceAll('*', '\u00d7').replaceAll('/', '\u00f7');
  if (s.isEmpty) return null;
  while (s.isNotEmpty && _isOpChar(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return null;

  final nums = <double>[];
  final ops = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (_isOpChar(c)) {
      if (buf.isEmpty) return null;
      final n = double.tryParse(buf.toString());
      if (n == null) return null;
      nums.add(n);
      ops.add(c);
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  if (buf.isEmpty) return null;
  final last = double.tryParse(buf.toString());
  if (last == null) return null;
  nums.add(last);

  // Pass 1: fold \u00d7 \u00f7 left-to-right into nums/ops.
  final nums2 = <double>[nums.first];
  final ops2 = <String>[];
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i];
    final right = nums[i + 1];
    if (op == '\u00d7' || op == '\u00f7') {
      final left = nums2.removeLast();
      if (op == '\u00f7') {
        if (right == 0) return null;
        nums2.add(left / right);
      } else {
        nums2.add(left * right);
      }
    } else {
      ops2.add(op);
      nums2.add(right);
    }
  }

  var acc = nums2.first;
  for (var i = 0; i < ops2.length; i++) {
    final op = ops2[i];
    final n = nums2[i + 1];
    if (op == '+') {
      acc += n;
    } else if (op == '-') {
      acc -= n;
    } else {
      return null;
    }
  }
  return acc;
}

bool amountExprHasOperator(String s) {
  for (var i = 0; i < s.length; i++) {
    if (_isOpChar(s[i])) return true;
  }
  return false;
}

int lastAmountOperatorIndex(String s) {
  for (var i = s.length - 1; i >= 0; i--) {
    if (_isOpChar(s[i])) return i;
  }
  return -1;
}

String applyAmountOperator(String current, String op) {
  final normalized = op == '*'
      ? '\u00d7'
      : op == '/'
          ? '\u00f7'
          : op;
  if (!_isOpChar(normalized)) return current;
  if (current.isEmpty || current == '0') return '0';
  if (current.isNotEmpty && _isOpChar(current[current.length - 1])) {
    return '${current.substring(0, current.length - 1)}$normalized';
  }
  var s = current;
  if (s.endsWith('.')) {
    s = s.substring(0, s.length - 1);
  }
  if (s.isEmpty) return '0';
  return '$s$normalized';
}

String applyAmountKey(String current, String key, int maxDecimals) {
  if (key == '\u232b') {
    if (current.isEmpty || current == '0') return '0';
    if (_isOpChar(current[current.length - 1])) {
      return current.substring(0, current.length - 1);
    }
    final opIdx = lastAmountOperatorIndex(current);
    if (opIdx < 0) {
      return _applyDigitToOperand(current, key, maxDecimals);
    }
    final prefix = current.substring(0, opIdx + 1);
    final operand = current.substring(opIdx + 1);
    if (operand.length <= 1) {
      return prefix;
    }
    return '$prefix${_applyDigitToOperand(operand, key, maxDecimals)}';
  }

  final opIdx = lastAmountOperatorIndex(current);
  final prefix = opIdx < 0 ? '' : current.substring(0, opIdx + 1);
  var operand = opIdx < 0 ? current : current.substring(opIdx + 1);
  if (operand.isEmpty) operand = '0';
  operand = _applyDigitToOperand(operand, key, maxDecimals);
  return '$prefix$operand';
}

bool _isOpChar(String c) =>
    c == '+' || c == '-' || c == '\u00d7' || c == '\u00f7' || c == '*' || c == '/';

String _applyDigitToOperand(String operand, String key, int maxDecimals) {
  if (key == '\u232b') {
    if (operand.length <= 1) return '0';
    return operand.substring(0, operand.length - 1);
  }
  if (key == '.') {
    if (maxDecimals == 0) return operand;
    if (!operand.contains('.')) return '$operand.';
    return operand;
  }
  if (key == '00') {
    if (operand == '0') return operand;
    final parts = operand.split('.');
    if (parts.length == 2) {
      final room = maxDecimals - parts[1].length;
      if (room <= 0) return operand;
      return '$operand${'0' * (room >= 2 ? 2 : room)}';
    }
    if (operand.length >= 12) return operand;
    return '${operand}00';
  }
  if (operand == '0') return key;
  final parts = operand.split('.');
  if (parts.length == 2 && parts[1].length >= maxDecimals) return operand;
  if (operand.length >= 12) return operand;
  return '$operand$key';
}

import '../constants/currencies.dart';

int toMinor(String ccy, double major) {
  final decimals = currencyDecimals[ccy] ?? 2;
  final factor = _pow10(decimals);
  return (major * factor).round();
}

double fromMinor(String ccy, int minor) {
  final decimals = currencyDecimals[ccy] ?? 2;
  return minor / _pow10(decimals);
}

String formatMinor(String ccy, int minor, {bool hide = false}) {
  if (hide) return '****';
  final symbol = currencySymbols[ccy] ?? ccy;
  final decimals = currencyDecimals[ccy] ?? 2;
  final major = fromMinor(ccy, minor);
  if (decimals == 0) {
    return '$symbol${major.round()}';
  }
  return '$symbol${major.toStringAsFixed(decimals)}';
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
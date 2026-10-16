/// P0 supported currencies and minor-unit decimals.
const Map<String, int> currencyDecimals = {
  'CNY': 2,
  'USD': 2,
  'JPY': 0,
  'TWD': 2,
  'HKD': 2,
  'EUR': 2,
};

const List<String> supportedCurrencies = [
  'CNY',
  'USD',
  'JPY',
  'TWD',
  'HKD',
  'EUR',
];

const Map<String, String> currencySymbols = {
  'CNY': '\u00a5',
  'USD': '\u0024',
  'JPY': '\u00a5',
  'TWD': 'NT\u0024',
  'HKD': 'HK\u0024',
  'EUR': '\u20ac',
};

/// Chinese display names for picker labels (storage remains ISO code).
const Map<String, String> currencyNamesZh = {
  'CNY': '人民币',
  'USD': '美元',
  'JPY': '日元',
  'TWD': '新台币',
  'HKD': '港币',
  'EUR': '欧元',
};

/// e.g. `CNY · 人民币`. Falls back to the ISO code alone if unknown.
String currencyLabel(String code) {
  final name = currencyNamesZh[code];
  if (name == null || name.isEmpty) return code;
  return '$code · $name';
}

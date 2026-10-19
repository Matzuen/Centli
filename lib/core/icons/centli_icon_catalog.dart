import 'package:flutter/material.dart';

/// One selectable icon backed by a downloaded SVG under assets/icons/.
class CentliIconEntry {
  const CentliIconEntry({
    required this.key,
    required this.label,
    required this.asset,
    this.bg,
    this.fg,
  });

  final String key;
  final String label;
  final String asset;
  final Color? bg;
  final Color? fg;
}

class CentliIconGroup {
  const CentliIconGroup({required this.id, required this.title, required this.entries});
  final String id;
  final String title;
  final List<CentliIconEntry> entries;
}

const String kCentliHanziPrefix = 'hanzi:';
const int kCentliHanziMaxChars = 2;

bool isCentliHanziIcon(String? raw) {
  final v = (raw ?? '').trim();
  return v.startsWith(kCentliHanziPrefix);
}

String? parseCentliHanzi(String? raw) {
  if (!isCentliHanziIcon(raw)) return null;
  final body = raw!.trim().substring(kCentliHanziPrefix.length).trim();
  if (body.isEmpty) return null;
  final chars = body.runes.map(String.fromCharCode).toList();
  if (chars.length > kCentliHanziMaxChars) return null;
  return chars.join();
}

String? encodeCentliHanzi(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final chars = trimmed.runes.map(String.fromCharCode).toList();
  if (chars.length > kCentliHanziMaxChars) return null;
  return '$kCentliHanziPrefix${chars.join()}';
}

/// Removed near-duplicate keys → kept key (old DB values still resolve).
const Map<String, String> kCentliIconKeyAliases = {
  'coin_vertical': 'coin',
  'crown_simple': 'crown',
  'currency_dollar_simple': 'currency_dollar',
  'electric_scooter': 'scooter',
  'fire_simple': 'fire',
  'flight': 'airplane',
  'house_line': 'home',
  'laptop_mac': 'laptop',
  'local_gas_station': 'gas_pump',
  'local_taxi': 'taxi',
  'tag_simple': 'tag',
  'two_wheeler': 'motorcycle',
};

String resolveCentliIconKey(String? key) {
  final k = (key ?? '').trim();
  if (k.isEmpty) return k;
  return kCentliIconKeyAliases[k] ?? k;
}

List<CentliIconGroup> get centliIconGroups => _groups;
Map<String, CentliIconEntry> get centliIconByKey => _byKeyEntries;

String? assetPathForIconKey(String? key) {
  final k = resolveCentliIconKey(key);
  if (k.isEmpty || isCentliHanziIcon(k)) return null;
  return _byKeyEntries[k]?.asset;
}

({Color bg, Color fg})? brandColorsForKey(String? key) {
  final k = resolveCentliIconKey(key);
  if (k.isEmpty) return null;
  final e = _byKeyEntries[k];
  if (e == null || e.bg == null || e.fg == null) return null;
  return (bg: e.bg!, fg: e.fg!);
}

({String glyph, Color bg, Color fg})? brandGlyphForKey(String? key) => null;
IconData? iconDataForKey(String? key) => null;

Map<String, CentliIconEntry>? _byKeyEntriesCache;

Map<String, CentliIconEntry> get _byKeyEntries => _byKeyEntriesCache ??= {
      for (final g in _groups)
        for (final e in g.entries) e.key: e,
    };

const List<CentliIconGroup> _groups = [
  CentliIconGroup(
    id: 'money',
    title: '金钱',
    entries: [
      CentliIconEntry(
        key: 'wallet',
        label: '钱包',
        asset: 'assets/icons/money/wallet.svg',
      ),
      CentliIconEntry(
        key: 'account_balance_wallet',
        label: '钱包夹',
        asset: 'assets/icons/money/account_balance_wallet.svg',
      ),
      CentliIconEntry(
        key: 'cash',
        label: '现金',
        asset: 'assets/icons/money/cash.svg',
      ),
      CentliIconEntry(
        key: 'payments',
        label: '工资',
        asset: 'assets/icons/money/payments.svg',
      ),
      CentliIconEntry(
        key: 'monetization_on',
        label: '硬币',
        asset: 'assets/icons/money/monetization_on.svg',
      ),
      CentliIconEntry(
        key: 'savings',
        label: '储蓄',
        asset: 'assets/icons/money/savings.svg',
      ),
      CentliIconEntry(
        key: 'receipt_long',
        label: '账单',
        asset: 'assets/icons/money/receipt_long.svg',
      ),
      CentliIconEntry(
        key: 'price_check',
        label: '核价',
        asset: 'assets/icons/money/price_check.svg',
      ),
      CentliIconEntry(
        key: 'account_balance',
        label: '银行大楼',
        asset: 'assets/icons/money/account_balance.svg',
      ),
      CentliIconEntry(
        key: 'atm',
        label: 'ATM',
        asset: 'assets/icons/money/atm.svg',
      ),
      CentliIconEntry(
        key: 'trending_up',
        label: '理财上涨',
        asset: 'assets/icons/money/trending_up.svg',
      ),
      CentliIconEntry(
        key: 'show_chart',
        label: '走势图',
        asset: 'assets/icons/money/show_chart.svg',
      ),
      CentliIconEntry(
        key: 'currency_bitcoin',
        label: '比特币',
        asset: 'assets/icons/money/currency_bitcoin.svg',
      ),
      CentliIconEntry(
        key: 'currency_exchange',
        label: '换汇',
        asset: 'assets/icons/money/currency_exchange.svg',
      ),
      CentliIconEntry(
        key: 'attach_money',
        label: '金额符号',
        asset: 'assets/icons/money/attach_money.svg',
      ),
      CentliIconEntry(
        key: 'south_west',
        label: '支出',
        asset: 'assets/icons/money/south_west.svg',
      ),
      CentliIconEntry(
        key: 'qr_code_2',
        label: '收款码',
        asset: 'assets/icons/money/qr_code_2.svg',
      ),
      CentliIconEntry(
        key: 'transfer',
        label: '转账',
        asset: 'assets/icons/money/transfer.svg',
      ),
      CentliIconEntry(
        key: 'swap_horiz',
        label: '资金互换',
        asset: 'assets/icons/money/swap_horiz.svg',
      ),
      CentliIconEntry(
        key: 'red_packet',
        label: '红包',
        asset: 'assets/icons/money/red_packet.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFE53935),
      ),
      CentliIconEntry(
        key: 'card_giftcard',
        label: '礼品卡',
        asset: 'assets/icons/money/card_giftcard.svg',
      ),
      CentliIconEntry(
        key: 'yuebao',
        label: '余额宝',
        asset: 'assets/icons/money/yuebao.svg',
        bg: Color(0xFFE8F4FF),
        fg: Color(0xFF1677FF),
      ),
      CentliIconEntry(
        key: 'ecny',
        label: '数字人民币',
        asset: 'assets/icons/money/ecny.svg',
        bg: Color(0xFFE8F6EC),
        fg: Color(0xFFC8102E),
      ),
      CentliIconEntry(
        key: 'redeem',
        label: '兑换',
        asset: 'assets/icons/money/redeem.svg',
      ),
      CentliIconEntry(
        key: 'coin',
        label: '金币',
        asset: 'assets/icons/money/coin.svg',
      ),
      CentliIconEntry(
        key: 'currency_dollar',
        label: '美元',
        asset: 'assets/icons/money/currency_dollar.svg',
      ),
      CentliIconEntry(
        key: 'currency_euro',
        label: '欧元',
        asset: 'assets/icons/money/currency_euro.svg',
      ),
      CentliIconEntry(
        key: 'currency_pound',
        label: '英镑',
        asset: 'assets/icons/money/currency_pound.svg',
      ),
      CentliIconEntry(
        key: 'currency_yen',
        label: '日元',
        asset: 'assets/icons/money/currency_yen.svg',
      ),
      CentliIconEntry(
        key: 'currency_won',
        label: '韩元',
        asset: 'assets/icons/money/currency_won.svg',
      ),
      CentliIconEntry(
        key: 'currency_ruble',
        label: '卢布',
        asset: 'assets/icons/money/currency_ruble.svg',
      ),
      CentliIconEntry(
        key: 'currency_inr',
        label: '卢比',
        asset: 'assets/icons/money/currency_inr.svg',
      ),
      CentliIconEntry(
        key: 'money_wavy',
        label: '纸币',
        asset: 'assets/icons/money/money_wavy.svg',
      ),
      CentliIconEntry(
        key: 'cash_register',
        label: '收银机',
        asset: 'assets/icons/money/cash_register.svg',
      ),
      CentliIconEntry(
        key: 'invoice',
        label: '发票',
        asset: 'assets/icons/money/invoice.svg',
      ),
      CentliIconEntry(
        key: 'vault',
        label: '保险柜',
        asset: 'assets/icons/money/vault.svg',
      ),
      CentliIconEntry(
        key: 'percent',
        label: '利率',
        asset: 'assets/icons/money/percent.svg',
      ),
      CentliIconEntry(
        key: 'seal_percent',
        label: '折扣章',
        asset: 'assets/icons/money/seal_percent.svg',
      ),
      CentliIconEntry(
        key: 'piggy_bank',
        label: '存钱罐',
        asset: 'assets/icons/money/piggy_bank.svg',
      ),
      CentliIconEntry(
        key: 'chart_bar',
        label: '柱状图',
        asset: 'assets/icons/money/chart_bar.svg',
      ),
      CentliIconEntry(
        key: 'receipt_x',
        label: '退款单',
        asset: 'assets/icons/money/receipt_x.svg',
      ),
      CentliIconEntry(
        key: 'currency_cny',
        label: '人民币',
        asset: 'assets/icons/money/currency_cny.svg',
      ),
      CentliIconEntry(
        key: 'currency_eth',
        label: '以太坊',
        asset: 'assets/icons/money/currency_eth.svg',
      ),
      CentliIconEntry(
        key: 'cards',
        label: '卡片',
        asset: 'assets/icons/money/cards.svg',
      ),
      CentliIconEntry(
        key: 'cards_three',
        label: '多张卡',
        asset: 'assets/icons/money/cards_three.svg',
      ),
      CentliIconEntry(
        key: 'identification_card',
        label: '证件卡',
        asset: 'assets/icons/money/identification_card.svg',
      ),
      CentliIconEntry(
        key: 'sim_card',
        label: 'SIM卡',
        asset: 'assets/icons/money/sim_card.svg',
      ),
      CentliIconEntry(
        key: 'cardholder',
        label: '卡包',
        asset: 'assets/icons/money/cardholder.svg',
      ),
      CentliIconEntry(
        key: 'calculator',
        label: '计算器',
        asset: 'assets/icons/money/calculator.svg',
      ),
      CentliIconEntry(
        key: 'scales',
        label: '天平',
        asset: 'assets/icons/money/scales.svg',
      ),
      CentliIconEntry(
        key: 'checks',
        label: '支票',
        asset: 'assets/icons/money/checks.svg',
      ),
      CentliIconEntry(
        key: 'list_checks',
        label: '核对清单',
        asset: 'assets/icons/money/list_checks.svg',
      ),
      CentliIconEntry(
        key: 'note',
        label: '票据',
        asset: 'assets/icons/money/note.svg',
      ),
      CentliIconEntry(
        key: 'note_blank',
        label: '空白票据',
        asset: 'assets/icons/money/note_blank.svg',
      ),
      CentliIconEntry(
        key: 'chart_donut',
        label: '环形图',
        asset: 'assets/icons/money/chart_donut.svg',
      ),
      CentliIconEntry(
        key: 'chart_line',
        label: '折线图',
        asset: 'assets/icons/money/chart_line.svg',
      ),
      CentliIconEntry(
        key: 'chart_line_up',
        label: '上涨曲线',
        asset: 'assets/icons/money/chart_line_up.svg',
      ),
      CentliIconEntry(
        key: 'chart_line_down',
        label: '下跌曲线',
        asset: 'assets/icons/money/chart_line_down.svg',
      ),
      CentliIconEntry(
        key: 'chart_pie',
        label: '饼图',
        asset: 'assets/icons/money/chart_pie.svg',
      ),
      CentliIconEntry(
        key: 'chart_pie_slice',
        label: '饼图切片',
        asset: 'assets/icons/money/chart_pie_slice.svg',
      ),
      CentliIconEntry(
        key: 'chart_bar_horizontal',
        label: '条形图',
        asset: 'assets/icons/money/chart_bar_horizontal.svg',
      ),
      CentliIconEntry(
        key: 'hand_coins',
        label: '手捧币',
        asset: 'assets/icons/money/hand_coins.svg',
      ),
      CentliIconEntry(
        key: 'money',
        label: '钞票',
        asset: 'assets/icons/money/money.svg',
      ),
      CentliIconEntry(
        key: 'receipt',
        label: '收据',
        asset: 'assets/icons/money/receipt.svg',
      ),
      CentliIconEntry(
        key: 'seal_check',
        label: '审核章',
        asset: 'assets/icons/money/seal_check.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'payment',
    title: '支付',
    entries: [
      CentliIconEntry(
        key: 'alipay',
        label: '支付宝',
        asset: 'assets/icons/payment/alipay.svg',
        bg: Color(0xFFE6F4FF),
        fg: Color(0xFF1677FF),
      ),
      CentliIconEntry(
        key: 'wechat',
        label: '微信支付',
        asset: 'assets/icons/payment/wechat.svg',
        bg: Color(0xFFE8F8EF),
        fg: Color(0xFF07C160),
      ),
      CentliIconEntry(
        key: 'unionpay',
        label: '银联',
        asset: 'assets/icons/payment/unionpay.svg',
        bg: Color(0xFFE8F0FE),
        fg: Color(0xFFE21836),
      ),
      CentliIconEntry(
        key: 'visa',
        label: 'Visa',
        asset: 'assets/icons/payment/visa.svg',
        bg: Color(0xFFE8EEF9),
        fg: Color(0xFF1A1F71),
      ),
      CentliIconEntry(
        key: 'mastercard',
        label: 'Mastercard',
        asset: 'assets/icons/payment/mastercard.svg',
        bg: Color(0xFFFFF0E8),
        fg: Color(0xFFEB001B),
      ),
      CentliIconEntry(
        key: 'amex',
        label: 'Amex',
        asset: 'assets/icons/payment/amex.svg',
        bg: Color(0xFFE8F4FF),
        fg: Color(0xFF2E77BC),
      ),
      CentliIconEntry(
        key: 'paypal',
        label: 'PayPal',
        asset: 'assets/icons/payment/paypal.svg',
        bg: Color(0xFFE8F1FF),
        fg: Color(0xFF003087),
      ),
      CentliIconEntry(
        key: 'apple_pay',
        label: 'Apple Pay',
        asset: 'assets/icons/payment/apple_pay.svg',
        bg: Color(0xFFF2F2F2),
        fg: Color(0xFF111111),
      ),
      CentliIconEntry(
        key: 'google_pay',
        label: 'Google Pay',
        asset: 'assets/icons/payment/google_pay.svg',
        bg: Color(0xFFF1F3F4),
        fg: Color(0xFF4285F4),
      ),
      CentliIconEntry(
        key: 'huabei',
        label: '花呗',
        asset: 'assets/icons/payment/huabei.svg',
        bg: Color(0xFFFFF0E8),
        fg: Color(0xFFFF6A00),
      ),
      CentliIconEntry(
        key: 'bank_card',
        label: '银行卡',
        asset: 'assets/icons/payment/bank_card.svg',
      ),
      CentliIconEntry(
        key: 'credit_card',
        label: '信用卡',
        asset: 'assets/icons/payment/credit_card.svg',
      ),
      CentliIconEntry(
        key: 'jd_pay',
        label: '京东支付',
        asset: 'assets/icons/payment/jd_pay.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFE1251B),
      ),
      CentliIconEntry(
        key: 'jd_baitiao',
        label: '京东白条',
        asset: 'assets/icons/payment/jd_baitiao.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFE1251B),
      ),
      CentliIconEntry(
        key: 'douyin_pay',
        label: '抖音支付',
        asset: 'assets/icons/payment/douyin_pay.svg',
        bg: Color(0xFFF5F5F5),
        fg: Color(0xFF111111),
      ),
      CentliIconEntry(
        key: 'meituan',
        label: '美团支付',
        asset: 'assets/icons/payment/meituan.svg',
        bg: Color(0xFFFFF4E5),
        fg: Color(0xFFFFC300),
      ),
    ],
  ),
  CentliIconGroup(
    id: 'bank',
    title: '银行',
    entries: [
      CentliIconEntry(
        key: 'bank_abc',
        label: '农业银行',
        asset: 'assets/icons/bank/bank_abc.svg',
        bg: Color(0xFFE8F6EC),
        fg: Color(0xFF019C97),
      ),
      CentliIconEntry(
        key: 'bank_bcm',
        label: '交通银行',
        asset: 'assets/icons/bank/bank_bcm.svg',
      ),
      CentliIconEntry(
        key: 'bank_boc',
        label: '中国银行',
        asset: 'assets/icons/bank/bank_boc.svg',
        bg: Color(0xFFFDECEC),
        fg: Color(0xFFA71E32),
      ),
      CentliIconEntry(
        key: 'bank_ccb',
        label: '建设银行',
        asset: 'assets/icons/bank/bank_ccb.svg',
        bg: Color(0xFFE8F1FF),
        fg: Color(0xFF0066B3),
      ),
      CentliIconEntry(
        key: 'bank_citic',
        label: '中信银行',
        asset: 'assets/icons/bank/bank_citic.svg',
      ),
      CentliIconEntry(
        key: 'bank_cmb',
        label: '招商银行',
        asset: 'assets/icons/bank/bank_cmb.svg',
        bg: Color(0xFFFDECEC),
        fg: Color(0xFFE60012),
      ),
      CentliIconEntry(
        key: 'bank_cmbc',
        label: '民生银行',
        asset: 'assets/icons/bank/bank_cmbc.svg',
        bg: Color(0xFFE8F4FF),
        fg: Color(0xFF1D2088),
      ),
      CentliIconEntry(
        key: 'bank_ceb',
        label: '光大银行',
        asset: 'assets/icons/bank/bank_ceb.svg',
        bg: Color(0xFFF6EEF8),
        fg: Color(0xFF6A1684),
      ),
      CentliIconEntry(
        key: 'bank_cgb',
        label: '广发银行',
        asset: 'assets/icons/bank/bank_cgb.svg',
      ),
      CentliIconEntry(
        key: 'bank_cib',
        label: '兴业银行',
        asset: 'assets/icons/bank/bank_cib.svg',
      ),
      CentliIconEntry(
        key: 'bank_hxb',
        label: '华夏银行',
        asset: 'assets/icons/bank/bank_hxb.svg',
      ),
      CentliIconEntry(
        key: 'bank_icbc',
        label: '工商银行',
        asset: 'assets/icons/bank/bank_icbc.svg',
        bg: Color(0xFFFDECEC),
        fg: Color(0xFFC7000B),
      ),
      CentliIconEntry(
        key: 'bank_psbc',
        label: '邮储银行',
        asset: 'assets/icons/bank/bank_psbc.svg',
      ),
      CentliIconEntry(
        key: 'bank_spdb',
        label: '浦发银行',
        asset: 'assets/icons/bank/bank_spdb.svg',
      ),
      CentliIconEntry(
        key: 'bank_pab',
        label: '平安银行',
        asset: 'assets/icons/bank/bank_pab.svg',
        bg: Color(0xFFFFF1E8),
        fg: Color(0xFFEA5504),
      ),
      CentliIconEntry(
        key: 'bank_bob',
        label: '北京银行',
        asset: 'assets/icons/bank/bank_bob.svg',
      ),
      CentliIconEntry(
        key: 'bank_bosh',
        label: '上海银行',
        asset: 'assets/icons/bank/bank_bosh.svg',
      ),
      CentliIconEntry(
        key: 'bank_mybank',
        label: '网商银行',
        asset: 'assets/icons/bank/bank_mybank.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'brand',
    title: '品牌',
    entries: [
      CentliIconEntry(
        key: 'brand_apple',
        label: '苹果',
        asset: 'assets/icons/brand/brand_apple.svg',
        bg: Color(0xFFF2F2F2),
        fg: Color(0xFF111111),
      ),
      CentliIconEntry(
        key: 'brand_huawei',
        label: '华为',
        asset: 'assets/icons/brand/brand_huawei.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFCF0A2C),
      ),
      CentliIconEntry(
        key: 'brand_xiaomi',
        label: '小米',
        asset: 'assets/icons/brand/brand_xiaomi.svg',
        bg: Color(0xFFFFF0E8),
        fg: Color(0xFFFF6900),
      ),
      CentliIconEntry(
        key: 'brand_jd',
        label: '京东',
        asset: 'assets/icons/brand/brand_jd.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFE1251B),
      ),
      CentliIconEntry(
        key: 'brand_taobao',
        label: '淘宝',
        asset: 'assets/icons/brand/brand_taobao.svg',
        bg: Color(0xFFFFF4E8),
        fg: Color(0xFFFF5000),
      ),
      CentliIconEntry(
        key: 'brand_tmall',
        label: '天猫',
        asset: 'assets/icons/brand/brand_tmall.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFE60012),
      ),
      CentliIconEntry(
        key: 'brand_pdd',
        label: '拼多多',
        asset: 'assets/icons/brand/brand_pdd.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFE02E24),
      ),
      CentliIconEntry(
        key: 'brand_eleme',
        label: '饿了么',
        asset: 'assets/icons/brand/brand_eleme.svg',
        bg: Color(0xFFE8F7FF),
        fg: Color(0xFF0097FF),
      ),
      CentliIconEntry(
        key: 'brand_didi',
        label: '滴滴',
        asset: 'assets/icons/brand/brand_didi.svg',
        bg: Color(0xFFFFF4E5),
        fg: Color(0xFFFF7D41),
      ),
      CentliIconEntry(
        key: 'brand_bilibili',
        label: '哔哩哔哩',
        asset: 'assets/icons/brand/brand_bilibili.svg',
        bg: Color(0xFFFFE8F0),
        fg: Color(0xFFFB7299),
      ),
      CentliIconEntry(
        key: 'brand_tencent',
        label: '腾讯',
        asset: 'assets/icons/brand/brand_tencent.svg',
        bg: Color(0xFFE8F4FF),
        fg: Color(0xFF12B7F5),
      ),
      CentliIconEntry(
        key: 'brand_netease',
        label: '网易',
        asset: 'assets/icons/brand/brand_netease.svg',
        bg: Color(0xFFFFECEC),
        fg: Color(0xFFC20C0C),
      ),
    ],
  ),
  CentliIconGroup(
    id: 'food',
    title: '食物',
    entries: [
      CentliIconEntry(
        key: 'restaurant',
        label: '餐饮',
        asset: 'assets/icons/food/restaurant.svg',
      ),
      CentliIconEntry(
        key: 'fastfood',
        label: '快餐',
        asset: 'assets/icons/food/fastfood.svg',
      ),
      CentliIconEntry(
        key: 'local_cafe',
        label: '咖啡馆',
        asset: 'assets/icons/food/local_cafe.svg',
      ),
      CentliIconEntry(
        key: 'coffee',
        label: '咖啡杯',
        asset: 'assets/icons/food/coffee.svg',
      ),
      CentliIconEntry(
        key: 'local_bar',
        label: '酒吧',
        asset: 'assets/icons/food/local_bar.svg',
      ),
      CentliIconEntry(
        key: 'local_pizza',
        label: '披萨店',
        asset: 'assets/icons/food/local_pizza.svg',
      ),
      CentliIconEntry(
        key: 'ramen_dining',
        label: '拉面',
        asset: 'assets/icons/food/ramen_dining.svg',
      ),
      CentliIconEntry(
        key: 'lunch_dining',
        label: '简餐',
        asset: 'assets/icons/food/lunch_dining.svg',
      ),
      CentliIconEntry(
        key: 'bakery_dining',
        label: '烘焙',
        asset: 'assets/icons/food/bakery_dining.svg',
      ),
      CentliIconEntry(
        key: 'cake',
        label: '蛋糕',
        asset: 'assets/icons/food/cake.svg',
      ),
      CentliIconEntry(
        key: 'icecream',
        label: '冰淇淋',
        asset: 'assets/icons/food/icecream.svg',
      ),
      CentliIconEntry(
        key: 'set_meal',
        label: '套餐',
        asset: 'assets/icons/food/set_meal.svg',
      ),
      CentliIconEntry(
        key: 'local_dining',
        label: '用餐',
        asset: 'assets/icons/food/local_dining.svg',
      ),
      CentliIconEntry(
        key: 'bowl_food',
        label: '碗饭',
        asset: 'assets/icons/food/bowl_food.svg',
      ),
      CentliIconEntry(
        key: 'coffee_bean',
        label: '咖啡豆',
        asset: 'assets/icons/food/coffee_bean.svg',
      ),
      CentliIconEntry(
        key: 'pizza',
        label: '披萨',
        asset: 'assets/icons/food/pizza.svg',
      ),
      CentliIconEntry(
        key: 'beer_stein',
        label: '啤酒杯',
        asset: 'assets/icons/food/beer_stein.svg',
      ),
      CentliIconEntry(
        key: 'wine',
        label: '葡萄酒',
        asset: 'assets/icons/food/wine.svg',
      ),
      CentliIconEntry(
        key: 'hamburger',
        label: '汉堡',
        asset: 'assets/icons/food/hamburger.svg',
      ),
      CentliIconEntry(
        key: 'bread',
        label: '面包',
        asset: 'assets/icons/food/bread.svg',
      ),
      CentliIconEntry(
        key: 'cookie',
        label: '饼干',
        asset: 'assets/icons/food/cookie.svg',
      ),
      CentliIconEntry(
        key: 'cooking_pot',
        label: '炖锅',
        asset: 'assets/icons/food/cooking_pot.svg',
      ),
      CentliIconEntry(
        key: 'fork_knife',
        label: '刀叉',
        asset: 'assets/icons/food/fork_knife.svg',
      ),
      CentliIconEntry(
        key: 'carrot',
        label: '胡萝卜',
        asset: 'assets/icons/food/carrot.svg',
      ),
      CentliIconEntry(
        key: 'fish',
        label: '鱼',
        asset: 'assets/icons/food/fish.svg',
      ),
      CentliIconEntry(
        key: 'egg',
        label: '鸡蛋',
        asset: 'assets/icons/food/egg.svg',
      ),
      CentliIconEntry(
        key: 'egg_crack',
        label: '破壳蛋',
        asset: 'assets/icons/food/egg_crack.svg',
      ),
      CentliIconEntry(
        key: 'cheese',
        label: '奶酪',
        asset: 'assets/icons/food/cheese.svg',
      ),
      CentliIconEntry(
        key: 'popcorn',
        label: '爆米花',
        asset: 'assets/icons/food/popcorn.svg',
      ),
      CentliIconEntry(
        key: 'pepper',
        label: '辣椒',
        asset: 'assets/icons/food/pepper.svg',
      ),
      CentliIconEntry(
        key: 'avocado',
        label: '牛油果',
        asset: 'assets/icons/food/avocado.svg',
      ),
      CentliIconEntry(
        key: 'tea_bag',
        label: '茶包',
        asset: 'assets/icons/food/tea_bag.svg',
      ),
      CentliIconEntry(
        key: 'bowl_steam',
        label: '热汤面',
        asset: 'assets/icons/food/bowl_steam.svg',
      ),
      CentliIconEntry(
        key: 'beer_bottle',
        label: '啤酒瓶',
        asset: 'assets/icons/food/beer_bottle.svg',
      ),
      CentliIconEntry(
        key: 'orange',
        label: '橙子',
        asset: 'assets/icons/food/orange.svg',
      ),
      CentliIconEntry(
        key: 'cherries',
        label: '樱桃',
        asset: 'assets/icons/food/cherries.svg',
      ),
      CentliIconEntry(
        key: 'shrimp',
        label: '虾',
        asset: 'assets/icons/food/shrimp.svg',
      ),
      CentliIconEntry(
        key: 'knife',
        label: '刀',
        asset: 'assets/icons/food/knife.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'life',
    title: '生活',
    entries: [
      CentliIconEntry(
        key: 'shopping_bag',
        label: '购物袋',
        asset: 'assets/icons/life/shopping_bag.svg',
      ),
      CentliIconEntry(
        key: 'shopping_cart',
        label: '购物车',
        asset: 'assets/icons/life/shopping_cart.svg',
      ),
      CentliIconEntry(
        key: 'local_mall',
        label: '商场',
        asset: 'assets/icons/life/local_mall.svg',
      ),
      CentliIconEntry(
        key: 'local_offer',
        label: '优惠标签',
        asset: 'assets/icons/life/local_offer.svg',
      ),
      CentliIconEntry(
        key: 'checkroom',
        label: '衣帽间',
        asset: 'assets/icons/life/checkroom.svg',
      ),
      CentliIconEntry(
        key: 'content_cut',
        label: '理发',
        asset: 'assets/icons/life/content_cut.svg',
      ),
      CentliIconEntry(
        key: 'pets',
        label: '宠物',
        asset: 'assets/icons/life/pets.svg',
      ),
      CentliIconEntry(
        key: 'favorite',
        label: '喜爱',
        asset: 'assets/icons/life/favorite.svg',
      ),
      CentliIconEntry(
        key: 'sports_esports',
        label: '电竞',
        asset: 'assets/icons/life/sports_esports.svg',
      ),
      CentliIconEntry(
        key: 'movie',
        label: '电影',
        asset: 'assets/icons/life/movie.svg',
      ),
      CentliIconEntry(
        key: 'music_note',
        label: '音乐',
        asset: 'assets/icons/life/music_note.svg',
      ),
      CentliIconEntry(
        key: 'sports_soccer',
        label: '足球',
        asset: 'assets/icons/life/sports_soccer.svg',
      ),
      CentliIconEntry(
        key: 'fitness_center',
        label: '健身',
        asset: 'assets/icons/life/fitness_center.svg',
      ),
      CentliIconEntry(
        key: 'spa',
        label: '养生',
        asset: 'assets/icons/life/spa.svg',
      ),
      CentliIconEntry(
        key: 'local_hospital',
        label: '医院',
        asset: 'assets/icons/life/local_hospital.svg',
      ),
      CentliIconEntry(
        key: 'medical_services',
        label: '医疗箱',
        asset: 'assets/icons/life/medical_services.svg',
      ),
      CentliIconEntry(
        key: 'medication',
        label: '药品',
        asset: 'assets/icons/life/medication.svg',
      ),
      CentliIconEntry(
        key: 'healing',
        label: '护理',
        asset: 'assets/icons/life/healing.svg',
      ),
      CentliIconEntry(
        key: 'vaccines',
        label: '疫苗',
        asset: 'assets/icons/life/vaccines.svg',
      ),
      CentliIconEntry(
        key: 'child_care',
        label: '育儿',
        asset: 'assets/icons/life/child_care.svg',
      ),
      CentliIconEntry(
        key: 'school',
        label: '学校',
        asset: 'assets/icons/life/school.svg',
      ),
      CentliIconEntry(
        key: 'menu_book',
        label: '课本',
        asset: 'assets/icons/life/menu_book.svg',
      ),
      CentliIconEntry(
        key: 'volunteer_activism',
        label: '公益捐赠',
        asset: 'assets/icons/life/volunteer_activism.svg',
      ),
      CentliIconEntry(
        key: 'casino',
        label: '娱乐',
        asset: 'assets/icons/life/casino.svg',
      ),
      CentliIconEntry(
        key: 'theater_comedy',
        label: '演出',
        asset: 'assets/icons/life/theater_comedy.svg',
      ),
      CentliIconEntry(
        key: 'beach_access',
        label: '度假沙滩',
        asset: 'assets/icons/life/beach_access.svg',
      ),
      CentliIconEntry(
        key: 'hiking',
        label: '徒步',
        asset: 'assets/icons/life/hiking.svg',
      ),
      CentliIconEntry(
        key: 'local_laundry_service',
        label: '洗衣',
        asset: 'assets/icons/life/local_laundry_service.svg',
      ),
      CentliIconEntry(
        key: 'pants',
        label: '裤子',
        asset: 'assets/icons/life/pants.svg',
      ),
      CentliIconEntry(
        key: 'dress',
        label: '连衣裙',
        asset: 'assets/icons/life/dress.svg',
      ),
      CentliIconEntry(
        key: 'sneaker',
        label: '运动鞋',
        asset: 'assets/icons/life/sneaker.svg',
      ),
      CentliIconEntry(
        key: 'boot',
        label: '靴子',
        asset: 'assets/icons/life/boot.svg',
      ),
      CentliIconEntry(
        key: 'eyeglasses',
        label: '眼镜',
        asset: 'assets/icons/life/eyeglasses.svg',
      ),
      CentliIconEntry(
        key: 'sunglasses',
        label: '墨镜',
        asset: 'assets/icons/life/sunglasses.svg',
      ),
      CentliIconEntry(
        key: 'handbag',
        label: '手提包',
        asset: 'assets/icons/life/handbag.svg',
      ),
      CentliIconEntry(
        key: 'backpack',
        label: '背包',
        asset: 'assets/icons/life/backpack.svg',
      ),
      CentliIconEntry(
        key: 'umbrella',
        label: '雨伞',
        asset: 'assets/icons/life/umbrella.svg',
      ),
      CentliIconEntry(
        key: 'hand_soap',
        label: '洗手液',
        asset: 'assets/icons/life/hand_soap.svg',
      ),
      CentliIconEntry(
        key: 'diamond',
        label: '钻石',
        asset: 'assets/icons/life/diamond.svg',
      ),
      CentliIconEntry(
        key: 'sock',
        label: '袜子',
        asset: 'assets/icons/life/sock.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'transport',
    title: '交通',
    entries: [
      CentliIconEntry(
        key: 'directions_car',
        label: '汽车',
        asset: 'assets/icons/transport/directions_car.svg',
      ),
      CentliIconEntry(
        key: 'directions_bus',
        label: '公交车',
        asset: 'assets/icons/transport/directions_bus.svg',
      ),
      CentliIconEntry(
        key: 'directions_subway',
        label: '地铁站',
        asset: 'assets/icons/transport/directions_subway.svg',
      ),
      CentliIconEntry(
        key: 'train',
        label: '火车',
        asset: 'assets/icons/transport/train.svg',
      ),
      CentliIconEntry(
        key: 'flight_takeoff',
        label: '起飞',
        asset: 'assets/icons/transport/flight_takeoff.svg',
      ),
      CentliIconEntry(
        key: 'directions_bike',
        label: '骑行',
        asset: 'assets/icons/transport/directions_bike.svg',
      ),
      CentliIconEntry(
        key: 'bolt',
        label: '充电桩',
        asset: 'assets/icons/transport/bolt.svg',
      ),
      CentliIconEntry(
        key: 'bus',
        label: '公交',
        asset: 'assets/icons/transport/bus.svg',
      ),
      CentliIconEntry(
        key: 'subway',
        label: '地铁',
        asset: 'assets/icons/transport/subway.svg',
      ),
      CentliIconEntry(
        key: 'bicycle',
        label: '自行车',
        asset: 'assets/icons/transport/bicycle.svg',
      ),
      CentliIconEntry(
        key: 'motorcycle',
        label: '摩托车',
        asset: 'assets/icons/transport/motorcycle.svg',
      ),
      CentliIconEntry(
        key: 'scooter',
        label: '电动车',
        asset: 'assets/icons/transport/scooter.svg',
      ),
      CentliIconEntry(
        key: 'airplane',
        label: '飞机',
        asset: 'assets/icons/transport/airplane.svg',
      ),
      CentliIconEntry(
        key: 'boat',
        label: '船',
        asset: 'assets/icons/transport/boat.svg',
      ),
      CentliIconEntry(
        key: 'taxi',
        label: '出租车',
        asset: 'assets/icons/transport/taxi.svg',
      ),
      CentliIconEntry(
        key: 'truck',
        label: '货车',
        asset: 'assets/icons/transport/truck.svg',
      ),
      CentliIconEntry(
        key: 'gas_pump',
        label: '加油站',
        asset: 'assets/icons/transport/gas_pump.svg',
      ),
      CentliIconEntry(
        key: 'steering_wheel',
        label: '方向盘',
        asset: 'assets/icons/transport/steering_wheel.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'home',
    title: '居家',
    entries: [
      CentliIconEntry(
        key: 'home',
        label: '住房',
        asset: 'assets/icons/home/home.svg',
      ),
      CentliIconEntry(
        key: 'apartment',
        label: '公寓',
        asset: 'assets/icons/home/apartment.svg',
      ),
      CentliIconEntry(
        key: 'chair',
        label: '家具',
        asset: 'assets/icons/home/chair.svg',
      ),
      CentliIconEntry(
        key: 'kitchen',
        label: '厨房',
        asset: 'assets/icons/home/kitchen.svg',
      ),
      CentliIconEntry(
        key: 'yard',
        label: '庭院',
        asset: 'assets/icons/home/yard.svg',
      ),
      CentliIconEntry(
        key: 'water_drop',
        label: '水费',
        asset: 'assets/icons/home/water_drop.svg',
      ),
      CentliIconEntry(
        key: 'cleaning_services',
        label: '保洁',
        asset: 'assets/icons/home/cleaning_services.svg',
      ),
      CentliIconEntry(
        key: 'build',
        label: '维修',
        asset: 'assets/icons/home/build.svg',
      ),
      CentliIconEntry(
        key: 'bed',
        label: '床',
        asset: 'assets/icons/home/bed.svg',
      ),
      CentliIconEntry(
        key: 'lamp',
        label: '台灯',
        asset: 'assets/icons/home/lamp.svg',
      ),
      CentliIconEntry(
        key: 'armchair',
        label: '扶手椅',
        asset: 'assets/icons/home/armchair.svg',
      ),
      CentliIconEntry(
        key: 'bathtub',
        label: '浴缸',
        asset: 'assets/icons/home/bathtub.svg',
      ),
      CentliIconEntry(
        key: 'door',
        label: '门',
        asset: 'assets/icons/home/door.svg',
      ),
      CentliIconEntry(
        key: 'plant',
        label: '绿植',
        asset: 'assets/icons/home/plant.svg',
      ),
      CentliIconEntry(
        key: 'washing_machine',
        label: '洗衣机',
        asset: 'assets/icons/home/washing_machine.svg',
      ),
      CentliIconEntry(
        key: 'stairs',
        label: '楼梯',
        asset: 'assets/icons/home/stairs.svg',
      ),
      CentliIconEntry(
        key: 'key',
        label: '钥匙',
        asset: 'assets/icons/home/key.svg',
      ),
      CentliIconEntry(
        key: 'shower',
        label: '淋浴',
        asset: 'assets/icons/home/shower.svg',
      ),
      CentliIconEntry(
        key: 'toilet',
        label: '马桶',
        asset: 'assets/icons/home/toilet.svg',
      ),
      CentliIconEntry(
        key: 'toilet_paper',
        label: '卷纸',
        asset: 'assets/icons/home/toilet_paper.svg',
      ),
      CentliIconEntry(
        key: 'potted_plant',
        label: '盆栽',
        asset: 'assets/icons/home/potted_plant.svg',
      ),
      CentliIconEntry(
        key: 'flower',
        label: '花',
        asset: 'assets/icons/home/flower.svg',
      ),
      CentliIconEntry(
        key: 'oven',
        label: '烤箱',
        asset: 'assets/icons/home/oven.svg',
      ),
      CentliIconEntry(
        key: 'fan',
        label: '风扇',
        asset: 'assets/icons/home/fan.svg',
      ),
      CentliIconEntry(
        key: 'desk',
        label: '书桌',
        asset: 'assets/icons/home/desk.svg',
      ),
      CentliIconEntry(
        key: 'rug',
        label: '地毯',
        asset: 'assets/icons/home/rug.svg',
      ),
      CentliIconEntry(
        key: 'broom',
        label: '扫帚',
        asset: 'assets/icons/home/broom.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'electronics',
    title: '电子',
    entries: [
      CentliIconEntry(
        key: 'phone_iphone',
        label: '手机',
        asset: 'assets/icons/electronics/phone_iphone.svg',
      ),
      CentliIconEntry(
        key: 'headphones',
        label: '耳机',
        asset: 'assets/icons/electronics/headphones.svg',
      ),
      CentliIconEntry(
        key: 'tv',
        label: '电视',
        asset: 'assets/icons/electronics/tv.svg',
      ),
      CentliIconEntry(
        key: 'watch',
        label: '手表',
        asset: 'assets/icons/electronics/watch.svg',
      ),
      CentliIconEntry(
        key: 'camera_alt',
        label: '相机',
        asset: 'assets/icons/electronics/camera_alt.svg',
      ),
      CentliIconEntry(
        key: 'router',
        label: '路由',
        asset: 'assets/icons/electronics/router.svg',
      ),
      CentliIconEntry(
        key: 'wifi',
        label: 'WiFi',
        asset: 'assets/icons/electronics/wifi.svg',
      ),
      CentliIconEntry(
        key: 'battery_charging_full',
        label: '充电电池',
        asset: 'assets/icons/electronics/battery_charging_full.svg',
      ),
      CentliIconEntry(
        key: 'memory',
        label: '芯片',
        asset: 'assets/icons/electronics/memory.svg',
      ),
      CentliIconEntry(
        key: 'gamepad',
        label: '手柄',
        asset: 'assets/icons/electronics/gamepad.svg',
      ),
      CentliIconEntry(
        key: 'laptop',
        label: '笔记本',
        asset: 'assets/icons/electronics/laptop.svg',
      ),
      CentliIconEntry(
        key: 'desktop_tower',
        label: '台式机',
        asset: 'assets/icons/electronics/desktop_tower.svg',
      ),
      CentliIconEntry(
        key: 'device_tablet',
        label: '平板',
        asset: 'assets/icons/electronics/device_tablet.svg',
      ),
      CentliIconEntry(
        key: 'speaker_hifi',
        label: '音箱',
        asset: 'assets/icons/electronics/speaker_hifi.svg',
      ),
      CentliIconEntry(
        key: 'monitor',
        label: '显示器',
        asset: 'assets/icons/electronics/monitor.svg',
      ),
      CentliIconEntry(
        key: 'keyboard',
        label: '键盘',
        asset: 'assets/icons/electronics/keyboard.svg',
      ),
      CentliIconEntry(
        key: 'mouse',
        label: '鼠标',
        asset: 'assets/icons/electronics/mouse.svg',
      ),
      CentliIconEntry(
        key: 'plug',
        label: '插头',
        asset: 'assets/icons/electronics/plug.svg',
      ),
      CentliIconEntry(
        key: 'hard_drive',
        label: '硬盘',
        asset: 'assets/icons/electronics/hard_drive.svg',
      ),
      CentliIconEntry(
        key: 'usb',
        label: 'U盘',
        asset: 'assets/icons/electronics/usb.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'office',
    title: '办公',
    entries: [
      CentliIconEntry(
        key: 'work',
        label: '公文包',
        asset: 'assets/icons/office/work.svg',
      ),
      CentliIconEntry(
        key: 'work_outline',
        label: '办公',
        asset: 'assets/icons/office/work_outline.svg',
      ),
      CentliIconEntry(
        key: 'mail',
        label: '邮件',
        asset: 'assets/icons/office/mail.svg',
      ),
      CentliIconEntry(
        key: 'print',
        label: '打印',
        asset: 'assets/icons/office/print.svg',
      ),
      CentliIconEntry(
        key: 'folder',
        label: '文件夹',
        asset: 'assets/icons/office/folder.svg',
      ),
      CentliIconEntry(
        key: 'edit_note',
        label: '记事',
        asset: 'assets/icons/office/edit_note.svg',
      ),
      CentliIconEntry(
        key: 'draw',
        label: '绘图',
        asset: 'assets/icons/office/draw.svg',
      ),
      CentliIconEntry(
        key: 'translate',
        label: '翻译',
        asset: 'assets/icons/office/translate.svg',
      ),
      CentliIconEntry(
        key: 'science',
        label: '科研',
        asset: 'assets/icons/office/science.svg',
      ),
      CentliIconEntry(
        key: 'calendar_month',
        label: '月历',
        asset: 'assets/icons/office/calendar_month.svg',
      ),
      CentliIconEntry(
        key: 'handshake',
        label: '合作',
        asset: 'assets/icons/office/handshake.svg',
      ),
      CentliIconEntry(
        key: 'workspace_premium',
        label: '认证徽章',
        asset: 'assets/icons/office/workspace_premium.svg',
      ),
      CentliIconEntry(
        key: 'pencil',
        label: '铅笔',
        asset: 'assets/icons/office/pencil.svg',
      ),
      CentliIconEntry(
        key: 'pencil_ruler',
        label: '铅笔尺',
        asset: 'assets/icons/office/pencil_ruler.svg',
      ),
      CentliIconEntry(
        key: 'paperclip',
        label: '回形针',
        asset: 'assets/icons/office/paperclip.svg',
      ),
      CentliIconEntry(
        key: 'folder_open',
        label: '打开文件夹',
        asset: 'assets/icons/office/folder_open.svg',
      ),
      CentliIconEntry(
        key: 'file_archive',
        label: '压缩包',
        asset: 'assets/icons/office/file_archive.svg',
      ),
      CentliIconEntry(
        key: 'printer',
        label: '打印机',
        asset: 'assets/icons/office/printer.svg',
      ),
      CentliIconEntry(
        key: 'briefcase',
        label: '公文包',
        asset: 'assets/icons/office/briefcase.svg',
      ),
      CentliIconEntry(
        key: 'envelope',
        label: '信封',
        asset: 'assets/icons/office/envelope.svg',
      ),
      CentliIconEntry(
        key: 'notebook',
        label: '笔记本',
        asset: 'assets/icons/office/notebook.svg',
      ),
      CentliIconEntry(
        key: 'book_open_text',
        label: '打开的书',
        asset: 'assets/icons/office/book_open_text.svg',
      ),
      CentliIconEntry(
        key: 'presentation',
        label: '演示',
        asset: 'assets/icons/office/presentation.svg',
      ),
      CentliIconEntry(
        key: 'archive_box',
        label: '档案箱',
        asset: 'assets/icons/office/archive_box.svg',
      ),
      CentliIconEntry(
        key: 'clipboard_text',
        label: '剪贴板',
        asset: 'assets/icons/office/clipboard_text.svg',
      ),
      CentliIconEntry(
        key: 'calendar_check',
        label: '日程勾选',
        asset: 'assets/icons/office/calendar_check.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'other',
    title: '其他',
    entries: [
      CentliIconEntry(
        key: 'military_tech',
        label: '勋章',
        asset: 'assets/icons/other/military_tech.svg',
      ),
      CentliIconEntry(
        key: 'more_horiz',
        label: '更多',
        asset: 'assets/icons/other/more_horiz.svg',
      ),
      CentliIconEntry(
        key: 'category',
        label: '分类',
        asset: 'assets/icons/other/category.svg',
      ),
      CentliIconEntry(
        key: 'label',
        label: '标签',
        asset: 'assets/icons/other/label.svg',
      ),
      CentliIconEntry(
        key: 'star',
        label: '收藏',
        asset: 'assets/icons/other/star.svg',
      ),
      CentliIconEntry(
        key: 'public',
        label: '公开',
        asset: 'assets/icons/other/public.svg',
      ),
      CentliIconEntry(
        key: 'album',
        label: '相册',
        asset: 'assets/icons/other/album.svg',
      ),
      CentliIconEntry(
        key: 'gift',
        label: '礼物',
        asset: 'assets/icons/other/gift.svg',
      ),
      CentliIconEntry(
        key: 'heart',
        label: '爱心',
        asset: 'assets/icons/other/heart.svg',
      ),
      CentliIconEntry(
        key: 'bookmark',
        label: '书签',
        asset: 'assets/icons/other/bookmark.svg',
      ),
      CentliIconEntry(
        key: 'tag',
        label: '标签',
        asset: 'assets/icons/other/tag.svg',
      ),
      CentliIconEntry(
        key: 'flag',
        label: '旗帜',
        asset: 'assets/icons/other/flag.svg',
      ),
      CentliIconEntry(
        key: 'clock',
        label: '时钟',
        asset: 'assets/icons/other/clock.svg',
      ),
      CentliIconEntry(
        key: 'bell',
        label: '铃铛',
        asset: 'assets/icons/other/bell.svg',
      ),
      CentliIconEntry(
        key: 'fire',
        label: '火焰',
        asset: 'assets/icons/other/fire.svg',
      ),
      CentliIconEntry(
        key: 'lightning',
        label: '闪电',
        asset: 'assets/icons/other/lightning.svg',
      ),
      CentliIconEntry(
        key: 'crown',
        label: '皇冠',
        asset: 'assets/icons/other/crown.svg',
      ),
      CentliIconEntry(
        key: 'trophy',
        label: '奖杯',
        asset: 'assets/icons/other/trophy.svg',
      ),
      CentliIconEntry(
        key: 'sparkle',
        label: '闪耀',
        asset: 'assets/icons/other/sparkle.svg',
      ),
      CentliIconEntry(
        key: 'heart_break',
        label: '心碎',
        asset: 'assets/icons/other/heart_break.svg',
      ),
      CentliIconEntry(
        key: 'heartbeat',
        label: '心跳',
        asset: 'assets/icons/other/heartbeat.svg',
      ),
      CentliIconEntry(
        key: 'star_four',
        label: '四角星',
        asset: 'assets/icons/other/star_four.svg',
      ),
      CentliIconEntry(
        key: 'shooting_star',
        label: '流星',
        asset: 'assets/icons/other/shooting_star.svg',
      ),
      CentliIconEntry(
        key: 'bookmarks',
        label: '书签组',
        asset: 'assets/icons/other/bookmarks.svg',
      ),
      CentliIconEntry(
        key: 'flag_checkered',
        label: '格子旗',
        asset: 'assets/icons/other/flag_checkered.svg',
      ),
      CentliIconEntry(
        key: 'calendar_dots',
        label: '多点日历',
        asset: 'assets/icons/other/calendar_dots.svg',
      ),
      CentliIconEntry(
        key: 'clock_countdown',
        label: '倒计时',
        asset: 'assets/icons/other/clock_countdown.svg',
      ),
      CentliIconEntry(
        key: 'bell_ringing',
        label: '响铃',
        asset: 'assets/icons/other/bell_ringing.svg',
      ),
      CentliIconEntry(
        key: 'medal',
        label: '奖章',
        asset: 'assets/icons/other/medal.svg',
      ),
      CentliIconEntry(
        key: 'certificate',
        label: '证书',
        asset: 'assets/icons/other/certificate.svg',
      ),
      CentliIconEntry(
        key: 'ticket',
        label: '门票',
        asset: 'assets/icons/other/ticket.svg',
      ),
      CentliIconEntry(
        key: 'palette',
        label: '调色板',
        asset: 'assets/icons/other/palette.svg',
      ),
    ],
  ),
];

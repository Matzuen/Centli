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

List<CentliIconGroup> get centliIconGroups => _groups;
Map<String, CentliIconEntry> get centliIconByKey => _byKeyEntries;

String? assetPathForIconKey(String? key) {
  final k = (key ?? '').trim();
  if (k.isEmpty || isCentliHanziIcon(k)) return null;
  return _byKeyEntries[k]?.asset;
}

({Color bg, Color fg})? brandColorsForKey(String? key) {
  final k = (key ?? '').trim();
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
        label: '钱夹',
        asset: 'assets/icons/money/account_balance_wallet.svg',
      ),
      CentliIconEntry(
        key: 'cash',
        label: '现金',
        asset: 'assets/icons/money/cash.svg',
      ),
      CentliIconEntry(
        key: 'payments',
        label: '付款',
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
        label: '银行',
        asset: 'assets/icons/money/account_balance.svg',
      ),
      CentliIconEntry(
        key: 'atm',
        label: 'ATM',
        asset: 'assets/icons/money/atm.svg',
      ),
      CentliIconEntry(
        key: 'trending_up',
        label: '上涨',
        asset: 'assets/icons/money/trending_up.svg',
      ),
      CentliIconEntry(
        key: 'show_chart',
        label: '走势',
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
        label: '金额',
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
        label: '互换',
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
        key: 'military_tech',
        label: '勋章',
        asset: 'assets/icons/money/military_tech.svg',
      ),
      CentliIconEntry(
        key: 'work',
        label: '工作',
        asset: 'assets/icons/money/work.svg',
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
        label: '微信',
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
        key: 'douyin_pay',
        label: '抖音支付',
        asset: 'assets/icons/payment/douyin_pay.svg',
        bg: Color(0xFFF5F5F5),
        fg: Color(0xFF111111),
      ),
      CentliIconEntry(
        key: 'meituan',
        label: '美团',
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
      ),
      CentliIconEntry(
        key: 'bank_ceb',
        label: '光大银行',
        asset: 'assets/icons/bank/bank_ceb.svg',
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
        label: 'Apple',
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
        label: 'B站',
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
        label: '咖啡',
        asset: 'assets/icons/food/local_cafe.svg',
      ),
      CentliIconEntry(
        key: 'coffee',
        label: '咖啡豆',
        asset: 'assets/icons/food/coffee.svg',
      ),
      CentliIconEntry(
        key: 'local_bar',
        label: '酒吧',
        asset: 'assets/icons/food/local_bar.svg',
      ),
      CentliIconEntry(
        key: 'local_pizza',
        label: '披萨',
        asset: 'assets/icons/food/local_pizza.svg',
      ),
      CentliIconEntry(
        key: 'ramen_dining',
        label: '拉面',
        asset: 'assets/icons/food/ramen_dining.svg',
      ),
      CentliIconEntry(
        key: 'lunch_dining',
        label: '午餐',
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
        label: '优惠',
        asset: 'assets/icons/life/local_offer.svg',
      ),
      CentliIconEntry(
        key: 'checkroom',
        label: '衣物',
        asset: 'assets/icons/life/checkroom.svg',
      ),
      CentliIconEntry(
        key: 'content_cut',
        label: '美发',
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
        label: '游戏',
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
        label: '医疗',
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
        label: '书籍',
        asset: 'assets/icons/life/menu_book.svg',
      ),
      CentliIconEntry(
        key: 'volunteer_activism',
        label: '公益',
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
        label: '度假',
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
        label: '公交',
        asset: 'assets/icons/transport/directions_bus.svg',
      ),
      CentliIconEntry(
        key: 'directions_subway',
        label: '地铁',
        asset: 'assets/icons/transport/directions_subway.svg',
      ),
      CentliIconEntry(
        key: 'train',
        label: '火车',
        asset: 'assets/icons/transport/train.svg',
      ),
      CentliIconEntry(
        key: 'flight',
        label: '飞机',
        asset: 'assets/icons/transport/flight.svg',
      ),
      CentliIconEntry(
        key: 'flight_takeoff',
        label: '起飞',
        asset: 'assets/icons/transport/flight_takeoff.svg',
      ),
      CentliIconEntry(
        key: 'local_taxi',
        label: '出租',
        asset: 'assets/icons/transport/local_taxi.svg',
      ),
      CentliIconEntry(
        key: 'directions_bike',
        label: '骑行',
        asset: 'assets/icons/transport/directions_bike.svg',
      ),
      CentliIconEntry(
        key: 'two_wheeler',
        label: '摩托',
        asset: 'assets/icons/transport/two_wheeler.svg',
      ),
      CentliIconEntry(
        key: 'electric_scooter',
        label: '滑板车',
        asset: 'assets/icons/transport/electric_scooter.svg',
      ),
      CentliIconEntry(
        key: 'local_gas_station',
        label: '加油',
        asset: 'assets/icons/transport/local_gas_station.svg',
      ),
      CentliIconEntry(
        key: 'bolt',
        label: '充电',
        asset: 'assets/icons/transport/bolt.svg',
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
        label: '水电',
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
        key: 'laptop_mac',
        label: '电脑',
        asset: 'assets/icons/electronics/laptop_mac.svg',
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
        label: '电池',
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
    ],
  ),
  CentliIconGroup(
    id: 'office',
    title: '办公',
    entries: [
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
        label: '笔记',
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
        label: '日历',
        asset: 'assets/icons/office/calendar_month.svg',
      ),
      CentliIconEntry(
        key: 'handshake',
        label: '合作',
        asset: 'assets/icons/office/handshake.svg',
      ),
      CentliIconEntry(
        key: 'workspace_premium',
        label: '认证',
        asset: 'assets/icons/office/workspace_premium.svg',
      ),
    ],
  ),
  CentliIconGroup(
    id: 'other',
    title: '其他',
    entries: [
      CentliIconEntry(
        key: 'more_horiz',
        label: '其他',
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
    ],
  ),
];

/// Default icon keys for seeded categories / accounts.
/// Kept separate from [centli_icon_catalog] so Drift open does not force-load
/// the full SVG catalog map on cold start.
library;

String? defaultIconKeyForCategoryName(String name) {
  switch (name.trim()) {
    case '餐饮':
      return 'restaurant';
    case '交通':
      return 'directions_car';
    case '日用':
      return 'shopping_bag';
    case '居住':
      return 'home';
    case '娱乐':
      return 'sports_esports';
    case '医疗':
      return 'local_hospital';
    case '教育':
      return 'menu_book';
    case '其他':
      return 'more_horiz';
    case '工资':
      return 'payments';
    case '红包':
      return 'red_packet';
    case '理财':
      return 'trending_up';
    default:
      return null;
  }
}

String? defaultIconKeyForAccount({
  required String name,
  required String type,
  String? typeName,
  String? typeIcon,
}) {
  final custom = (typeIcon ?? '').trim();
  if (custom.isNotEmpty) return custom;
  final n = name.trim();
  final lower = n.toLowerCase();
  final tn = (typeName ?? '').trim();
  if (n.contains('微信') || lower.contains('wechat') || lower.contains('weixin')) {
    return 'wechat';
  }
  if (n.contains('支付宝') || lower.contains('alipay')) return 'alipay';
  if (n.contains('银联') || lower.contains('unionpay')) return 'unionpay';
  if (n.contains('花呗')) return 'huabei';
  if (n.contains('京东')) return 'jd_pay';
  if (n.contains('美团')) return 'meituan';
  if (n.contains('现金') || type == 'cash' || tn.contains('现金')) return 'cash';
  if (type == 'credit' || n.contains('信用') || tn.contains('信用')) {
    return 'credit_card';
  }
  if (n.contains('工商') || n.contains('工行')) return 'bank_icbc';
  if (n.contains('建设') || n.contains('建行')) return 'bank_ccb';
  if (n.contains('农业') || n.contains('农行')) return 'bank_abc';
  if (n.contains('中国银行') || n.contains('中行')) return 'bank_boc';
  if (n.contains('招商') || n.contains('招行')) return 'bank_cmb';
  if (n.contains('交通')) return 'bank_bcm';
  if (n.contains('邮储')) return 'bank_psbc';
  if (n.contains('浦发')) return 'bank_spdb';
  if (n.contains('民生')) return 'bank_cmbc';
  if (n.contains('中信')) return 'bank_citic';
  if (n.contains('光大')) return 'bank_ceb';
  if (n.contains('平安')) return 'bank_pab';
  if (n.contains('兴业')) return 'bank_cib';
  if (n.contains('广发')) return 'bank_cgb';
  if (n.contains('华夏')) return 'bank_hxb';
  if (type == 'bank' ||
      tn.contains('银行') ||
      n.contains('银行') ||
      n.contains('卡')) {
    return 'bank_card';
  }
  if (tn.contains('电子钱包') || type == 'ewallet') return 'wallet';
  return 'wallet';
}

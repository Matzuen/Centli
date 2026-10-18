import 'package:centli/features/home/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 日历页「每日收支」：每天一个点，画的是**当日**净额，不是累计。
void main() {
  final monthStart = DateTime(2026, 10);

  test('13 号 -1、14 号 -71、16 号 633，其余天 0', () {
    // 表格里 13 号: 收入 7 / 支出 8 → -1；14 号支出 71 → -71；
    // 16 号单元格: 收入 700 / 支出 67 → 633。
    // （图下说明是「¥633、¥71」，不是累计线里多出来的 ¥-71.89。）
    final income = <({DateTime dayLocal, int totalMinor})>[
      (dayLocal: DateTime(2026, 10, 13), totalMinor: 700),
      (dayLocal: DateTime(2026, 10, 16), totalMinor: 70000),
    ];
    final expense = <({DateTime dayLocal, int totalMinor})>[
      (dayLocal: DateTime(2026, 10, 13), totalMinor: 800),
      (dayLocal: DateTime(2026, 10, 14), totalMinor: 7100),
      (dayLocal: DateTime(2026, 10, 16), totalMinor: 6700),
    ];

    final net = monthlyDailyNetMajor(
      base: 'CNY',
      monthStart: monthStart,
      income: income,
      expense: expense,
    );

    expect(net.length, 31);
    expect(net[12], -1, reason: '13 号');
    expect(net[13], -71, reason: '14 号');
    expect(net[14], 0, reason: '15 号无流水');
    expect(net[15], 633, reason: '16 号');
    expect(net[17], 0, reason: '18 号无流水');
    // 不是累计：后面的 0 天不会被前面某笔撑高。
    expect(net.sublist(16), everyElement(0));
    // 本月中没有流水的前半月也全是 0。
    expect(net.sublist(0, 12), everyElement(0));
  });

  test('二月的天数按当月计算（平年 28 天）', () {
    final net = monthlyDailyNetMajor(
      base: 'CNY',
      monthStart: DateTime(2026, 2),
      income: const [],
      expense: const [],
    );
    expect(net.length, 28);
  });

  test('跨月数据不会落到错误日期上', () {
    final net = monthlyDailyNetMajor(
      base: 'CNY',
      monthStart: monthStart,
      income: <({DateTime dayLocal, int totalMinor})>[
        (dayLocal: DateTime(2026, 9, 30), totalMinor: 500),
      ],
      expense: const [],
    );
    // 9 月的流水夹到月初，不会串到 30 号。
    expect(net.first, 5);
    expect(net.last, 0);
  });
}

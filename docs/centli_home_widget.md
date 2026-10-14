# Centli ? 桌面小组件 P3 MVP

> Android 先行。展示 **今日支出（本位币折算）** 与 **待确认数量**。

## 能力

| 项 | 说明 |
|---|---|
| 今日支出 | `DateRangeWindow.lastDays(days: 1)` + `rangeSummaryInBase` |
| 待确认 | `watchPendingCount` |
| 藏金额 | 读 `hide_amount`，为 true 时显示 `****` |
| 点按 | 整卡 → `/home`；待确认行（有待确认时）→ `/home/pending` |
| 刷新 | App 启动/回前台、待确认变化、今日流水变化、藏金额/账本变化 |

## 工程

- Dart: `lib/platform/home_widget/centli_home_widget_sync.dart`
- 原生: `CentliHomeWidgetProvider` + `res/layout/centli_home_widget.xml`
- 依赖: `home_widget ^0.10.0`
- 入口: 「我的 → 桌面小组件」可尝试系统 Pin；也可桌面长按添加

## 非目标（本 MVP）

- iOS WidgetKit
- 后台独立读 SQLite（无 Flutter 进程时只重绘 SharedPreferences 缓存）
- 分类预算进度、快捷记一笔交互

## 验证

1. Android 真机/模拟器安装 Debug 包
2. 桌面长按 → 小组件 → Centli
3. App 内记一笔支出，回桌面应看到今日支出更新（或再打开 App 触发同步）
4. 造一条待确认，小组件待确认数 > 0，点待确认行进待确认页

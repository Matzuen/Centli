# Centli B3 执行报告（notes.md）

> 基线：`d4d25e6` · 最终 HEAD：`a1869f1` · schema **v7** · 无 push  
> 顺序：T0 → T6 → T7 → T1 → T2 → T5（T3/T4 按降级放弃）  
> Asia/Shanghai · 2026-10-17

## 1. 子任务 → commit hash

| 子任务 | Hash | 状态 |
|---|---|---|
| T0-1 | `8d42d76` | 完成 |
| T0-2 | `c5b954e` | 完成 |
| T0-3 | `38bf64d` | 完成 |
| T6-1 | `a8634c0` | 完成 |
| T6-2 | `b3794c3` | 完成 |
| T6-3 | `d4040d5` | 完成 |
| T6-4 | `f3ea229` | 完成 |
| T6-5 | （并入 T6-1 契约文档约束节） | 完成 |
| T7-1 | `e7a3c54` | 完成 |
| T7-2 | `508abd5` | 完成 |
| T7-3 | `74c1cea` | 完成 |
| T7-4 | `09b48e0` | 完成 |
| T7-5 | `e223e1b` | 完成（APK debug 通过） |
| T7-6 ① | `693256e` | 完成 |
| T7-6 ② | — | **SKIPPED**：应用内关于页 logo（降级第 2 项） |
| T1-1 | `44b7640` | 完成 |
| T1-2 | `d389583` | 完成 |
| T1-3 | `3545ef6` | 完成 |
| T1-4 | `2dcf5a7` | 完成 |
| T1-5 | `41587e8` | 完成 |
| T1-6 | `a5a1c5a` | 完成 |
| T2-1 | `3c24111` | 完成 |
| T2-2 / T2-3 | `252927b` | 完成 |
| T2-4 / T2-5 | `a1869f1` | 完成 |
| T3 整组 | — | **SKIPPED**（降级第 7 项；时间留给 T5） |
| T4 整组 | — | **SKIPPED**（降级第 6 项） |
| T5-1 | （本 notes + audit_input） | 完成 |
| T5-2 | `docs/grokbot/VERIFY_CHECKLIST.md` | 完成 |
| T5-3 | — | **SKIPPED**（降级第 1 项） |
| T5-4 | — | **SKIPPED**（降级第 1 项；见下节简报） |

## 2. analyze / test

- 基线：analyze clean · **120** passed  
- 结束：analyze **No issues found!** · **150** passed / 0 failed  
- `d4d25e6` 仍为 HEAD 祖先 · **未 push**

## 3. T1 说明

- **补齐机制**：splash 与 FX 并列 `unawaited(_scheduleRecurringDeferred)` → `runDueRecurring`；catch 全部异常。  
- **occurrenceKey**：新列 `transactions.occurrence_key`（`rec:<ruleId>:<ms>`），落库前查重。  
- **月末钳制**：`advancePeriod` 按日历加月并用 `anchorDay` 钳到当月天数（1/31→2/28→3/31）。  
- **补漏上限**：`maxOccurrences=12`；超额写入 `skippedCount`，列表页横幅提示。  
- **幂等测试**：`test/recurring_rules_test.dart` 连续两次 `runDueRecurring`，第二次 `generated==0`。

## 4. T2 说明

- 订阅**不写流水**（`subscriptionsDueSoon` 仅筛选；测试断言 txn 数量不变）。  
- 启动把提示写入 setting `subscription_due_tip`；列表页用「即将到期」徽标。  
- T2-5：编辑页按钮跳转周期向导并 prefill 金额/周期/备注。

## 5. T3-4 / T4

- 未实现（整组 SKIPPED）。

## 6. schema 迁移测试

- v6：`recurring_rules_test` + `schema_v4_tags_migration_test`（user_version 断言随最终版本更新）  
- v7：`subscriptions_test`  
- **无 v8/v9**（T3/T4 未做）

## 7. T6 契约对照表

| 契约项 | 契约值 | 实现值 | 状态 |
|---|---|---|---|
| 面板顶圆角 | 24 | 24 | 已实现 |
| 标题行 | 无 | 无 | 已实现 |
| 金额对齐 | 右对齐 | 右对齐 | 已实现 |
| 金额字号 | 32 | 32 | 已实现 |
| 金额右缘距屏 | 18 | padding right 18 | 已实现 |
| 顶部留白 | 48 | 48 | 已实现 |
| chip 行数 × 每行数 | 2 × 4 | 2 行（行1:3+附加空；行2:最多4） | 已实现（附加未落地留空） |
| chip 行高 | 36 | 36 | 已实现 |
| chip 行间距 | 5 | 5 | 已实现 |
| chip 水平间距 | 8 | 8 | 已实现 |
| chip 圆角 | 10 | 10 | 已实现 |
| chip 描边 | 1dp `#E5E7EB` | `CentliTheme.chipBorder` | 已实现 |
| 备注框高 | 46 | 46 | 已实现 |
| 键盘行 × 列 | 5 × 4 | 5 × 4 | 已实现 |
| 键高 | 54 | 54 | 已实现 |
| 列宽 | 78/78/78/86 | flex 78/78/78/86 | 已实现 |
| 键盘水平间距 | 7 | 7 | 已实现 |
| 键盘垂直间距 | 3.5 | 3.5 | 已实现 |
| 键盘左右内边距 | 9 | 9 | 已实现 |
| 数字键底色 | `#EAEDF4` | theme light | 已实现 |
| 运算符键底色 | `#D4E5F5` | theme light | 已实现 |
| AC/⌫ 底色 | `#FEDBD7` | theme light | 已实现 |
| ✓ 底色 | `#1F98F5` | theme light | 已实现 |
| 第 1 行键序 | `AC ⌫ / *` | 是 | 已实现 |
| 末行 | `0`(跨2列) `.` `✓` | flex 之和跨列 | 已实现 |

## 8. T6 其它

- `_evalAmount`/`evalAmountExpr` 已支持 `*` `/`（先乘除）；既有 `amount_expr_test` + `=` 键折叠。  
- Golden：`test/golden/goldens/bookkeeping_panel.png` / `_dark.png`；结构测试锁类型 chip。  
- **类型切换保留**：`bk_type_chip`；切换调用 `_reloadCategories(resetSelection: true)`；转账隐藏分类。

## 9. T7 验证

- 采样背景：**`#E4F6F4`**（logo 圆角方块内部 opaque 均值）  
- Android traditional：48/72/96/144/192 RGBA + round 副本  
- Adaptive foreground：108/162/216/324/432；anydpi-v26 XML 全套  
- iOS 15 PNG 全部 **RGB**（项目 Contents.json 实际 15 个，非 16）  
- `logo/logo.png` SHA-256 前后一致：`f7346bfd80f282ba117455fb36e30a6fe87832f2b528189e97610233ad0ab7d6`  
- `logo1/logo2` 已 gitignore  
- `flutter build apk --debug` **成功** → `build/app/outputs/flutter-apk/app-debug.apk`

## 10. 工单外改动

- 记账面板商户输入框按契约移除（模板仍可通过备注旁列表图标打开）。  
- schema 旧测试 user_version 断言随 v7 更新。  
- 无其它主题/配色 drive-by。

## 11. 风险 / 不确定

- 订阅 due tip 写入 setting，首页未做常驻横幅（列表徽标 + setting 可用）；真机体验感待 T5-2。  
- 周期向导保存后立即 `runDueRecurring`；若起始日很早且 >12 期会截断。  
- T3/T4 未做 → schema 停在 **v7**。  
- Golden 跨机字体可能漂移（本机生成）。

## 12. 目视

- Bot **未做**真机目视；请按 `VERIFY_CHECKLIST.md` 过。

## 13. T5-4 简报（虽 SKIPPED 文档更新，已快速 grep）

- 新增面板仍有契约要求的字号硬编码（32/13/54）——按契约允许。  
- 无新增 `/100.0` 金额换算。  
- 迁移测试：v6/v7 有；v8/v9 无（表未建）。

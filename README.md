# Centli（厘记）

本地优先的个人记账应用：**厘清每一笔账**。

- Flutter · Drift (SQLite) · Riverpod · go_router
- 当前版本：`1.0.1+2`（见 `pubspec.yaml`）

## 功能概览

| 模块 | 说明 |
|------|------|
| 流水记账 | 支出 / 收入 / 转账；手动记一笔；软删除进回收站可恢复 |
| 多账本 | 账本管理：新建、切换当前、归档；各账本独立账户/分类/流水 |
| 资产 | 多账户余额；账户明细 |
| 统计 | 区间汇总、分类下钻、预算进度 |
| 预算 | 月度总额 / 分类限额（本位币） |
| 自动记账 | Android 通知监听 → 待确认入账；可忽略并在「已忽略」中恢复 |
| 汇率 | 手动 + 远程日频；首页/统计/资产按本位币折算 |
| 备份 | **JSON** 完整导出/还原；**Excel** 人类可读导出 + **尽力而为**还原 |
| 安全 | 应用锁（PIN / 生物识别）、隐藏金额 |
| 主题 | 浅色 / 深色 / 跟随系统 |
| 桌面小组件 | Android 首页小组件（MVP）；iOS 未做 |

## 运行

```bash
flutter pub get
flutter run
```

可选平台：Android / iOS / Windows / Web（通知自动记账与桌面小组件以 Android 为主）。

生成 Drift 代码（改表结构后）：

```bash
dart run build_runner build --delete-conflicting-outputs
```

测试：

```bash
flutter test
```

## 备份与还原

- **推荐**：`我的 → 导出` 勾选 JSON，再在 `我的 → 导入` 还原。格式 `centli-export`，`export_version: 1`，`schema_version: 2`（含预算）。
- **Excel**：适合表格查看；导入为尽力而为——**不含** `fx_rates` / `settings` 工作表，缺省字段会补默认值。无损迁移请用 JSON。
- 还原会清空本机账本相关数据后写入备份；应用锁 PIN 留在本机安全存储，不会被备份覆盖。

## 项目结构（简）

```
lib/
  app/           # 主题、路由、Shell
  data/db/       # Drift 表与 CentliDatabase
  data/export/   # JSON/Excel 导出与导入
  features/      # 首页、统计、资产、待确认、设置…
  platform/      # 通知解析、Android 小组件
docs/            # 方案与缺口说明
```

更细的表结构见 `docs/Centli_schema.md`，页面线框见 `docs/Centli_pages_wireframes.md`。

## 隐私

数据默认仅存本机 SQLite。通知监听仅用于解析支付类通知并写入「待确认」。详见应用内「关于 → 隐私政策」与 `assets/legal/privacy_zh.txt`。

## 已知未做 / 范围外

- iOS 桌面小组件
- 通知解析多币种扩展（仍以 CNY 为 MVP）
- 云同步（刻意不做，本地优先）

缺口跟踪：`docs/remaining_features_gap.md`。


## 更新日志

### 1.0.1

- **语音**：默认允许在线识别，离线兜底；失败时显示明确错误信息
- **自动记账**：杀进程后由原生直写 SQLite；Listener 断连自动重绑；设置页区分「权限已开 / 监听已连接」
- **自动记账过滤**：仅支付成功类通知进入待确认，过滤聊天 / 朋友圈 / 验证码等；通知模板 version 3

### 1.0.0

- 首发：本地优先流水记账、多账本、资产、统计、预算、Android 通知自动记账、汇率、JSON/Excel 备份、应用锁与主题等

## 许可

依赖许可证见应用内「关于 → 开源许可」。

# Centli（厘记）

本地优先的个人记账应用：**厘清每一笔账**。界面为**简体中文**（当前不提供多语言切换）。

- Flutter · Drift (SQLite) · Riverpod · go_router
- 当前版本：`1.1.0+3`（见 `pubspec.yaml`）
- 币种展示：`CNY · 人民币`

## 简介

Centli 把账本、账户、分类与流水放在本机 SQLite，不做云同步。底部导航固定五栏：**首页 / 统计 / 记账 / 资产 / 我的**（中间「记账」打开记账面板，不是 Finch 式悬浮 FAB）。

## 功能

| 模块 | 说明 |
|------|------|
| 导航 | 固定五栏：首页、统计、记账、资产、我的 |
| 流水记账 | 支出 / 收入 / 转账；记账面板（chips + Finch 风格分类选择）；软删除进回收站可恢复 |
| 账本 / 账户 / 分类 | 多账本（新建、切换当前、归档）；各账本独立账户与分类；分类树；图标来自 `assets/icons/`，无图时 1～2 个汉字回退 |
| 资产 | 多账户余额；账户明细 |
| 统计 | 收入 + 支出区间汇总、分类下钻、预算进度 |
| 预算 | 月度总额 / 分类限额（本位币） |
| 待确认 · 自动记账 | Android 监听**微信 / 支付宝支付成功类通知** → 待确认入账；可忽略并在「已忽略」中恢复 |
| 识别规则 | 官方规则只读；「我的规则」增删改；试解析；导入 / 导出我的规则（入口：我的 → 自动记账 → 识别规则） |
| 智能填单 | 本地规则解析 + 可选大模型增强（OpenAI 兼容接口；失败回退本地） |
| 汇率 | 手动 + 远程日频；首页 / 统计 / 资产按本位币折算 |
| 备份 | 本地 **JSON** 完整导出 / 还原；**Excel** 人类可读导出 + **尽力而为**还原；**无云端** |
| 安全 | 应用锁（PIN / 生物识别）、隐藏金额 |
| 主题 | 浅色 / 深色 / 跟随系统 |
| 桌面小组件 | Android 首页小组件（MVP）；iOS 未做 |

## 技术栈

- **框架**：Flutter（开发环境约 3.47.x）
- **存储**：Drift → SQLite（本机）
- **状态 / 路由**：Riverpod、go_router
- **平台能力**：Android 通知监听、本地认证、可选语音 / OCR（见 `lib/platform/`）

## 运行与打包

```bash
flutter pub get
flutter run
```

可选平台：Android / iOS / Windows / Web。**通知自动记账与桌面小组件以 Android 为主。**

Windows 开发：需开启系统**开发人员模式**（否则 Flutter 插件 symlink 可能失败）。界面改动优先 **hot restart**；不必每次打 APK。

生成 Drift 代码（改表结构后）：

```bash
dart run build_runner build --delete-conflicting-outputs
```

测试：

```bash
flutter test
```

### 打 Android 正式包

在项目根目录：

```bash
flutter build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。仅在需要安装包时再执行；日常调试用 `flutter run` 即可。

## 备份与还原

- **推荐**：`我的 → 导出` 勾选 JSON，再在 `我的 → 导入` 还原。格式 `centli-export`，`export_version: 1`，`schema_version: 2`（含预算）。
- **Excel**：适合表格查看；导入为尽力而为——**不含** `fx_rates` / `settings` 工作表，缺省字段会补默认值。无损迁移请用 JSON。
- 还原会清空本机账本相关数据后写入备份；应用锁 PIN 留在本机安全存储，不会被备份覆盖。
- 全部为**本地**导入 / 导出，无云备份。

## 目录说明

```
lib/
  app/           # 主题、路由、五栏 Shell
  core/          # 常量、图标组件、通用控件
  data/db/       # Drift 表与 CentliDatabase
  data/export/   # JSON/Excel 导出与导入
  data/fx/       # 汇率
  features/      # 首页、统计、记账、资产、待确认、设置…
  platform/      # 通知解析、待确认入队、Android 小组件、OCR 等
assets/
  icons/         # 分类 / 账户等图标资源
  noti_templates.json
  legal/         # 隐私政策等
docs/            # 方案与缺口说明
```

更细的表结构见 `docs/Centli_schema.md`，页面线框见 `docs/Centli_pages_wireframes.md`，识别规则说明见 `docs/recognition_rules.md`。

## 隐私

数据默认仅存本机 SQLite。通知监听仅用于解析**支付成功类**通知并写入「待确认」。详见应用内「关于 → 隐私政策」与 `assets/legal/privacy_zh.txt`。

## 已知未做 / 范围外

- iOS 桌面小组件
- 通知解析多币种扩展（仍以 CNY 为主）
- 云同步（刻意不做，本地优先）

缺口跟踪：`docs/remaining_features_gap.md`。

## 更新日志

### 1.1.0

- **导航**：固定五栏「首页 / 统计 / 记账 / 资产 / 我的」
- **记账**：chips + Finch 风格分类选择；分类 / 账户图标资源与汉字回退
- **统计**：收入 + 支出汇总
- **识别规则**：官方只读 + 我的规则 CRUD、试解析、导入 / 导出
- **智能填单**：本地规则 + 可选 LLM
- **自动记账**：聚焦微信 / 支付宝支付成功通知 → 待确认
- 版本号：`1.1.0+3`

### 1.0.1

- **语音**：默认允许在线识别，离线兜底；失败时显示明确错误信息
- **自动记账**：杀进程后由原生直写 SQLite；Listener 断连自动重绑；设置页区分「权限已开 / 监听已连接」
- **自动记账过滤**：仅支付成功类通知进入待确认，过滤聊天 / 朋友圈 / 验证码等；通知模板 version 3

### 1.0.0

- 首发：本地优先流水记账、多账本、资产、统计、预算、Android 通知自动记账、汇率、JSON/Excel 备份、应用锁与主题等

## 许可

依赖许可证见应用内「关于 → 开源许可」。

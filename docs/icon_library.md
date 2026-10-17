# 图标库（Icon Library）

> 状态：2026-10-17。供执行方（Grok Bot）与后续维护者阅读。
> 管线：`tools/icon_pack/`。工单：`BOT_TASKS_ICON.md`。

## 1. 结构

- **11 个家族**，与 `assets/icons/` 目录一一对应：
  `money` 金钱 / `payment` 支付 / `bank` 银行 / `brand` 品牌 / `food` 食物 / `life` 生活 /
  `transport` 交通 / `home` 居家 / `electronics` 电子 / `office` 办公 / `other` 其他
- 每个图标 = 一个 SVG 文件 + 一条 `CentliIconEntry`（`lib/core/icons/centli_icon_catalog.dart`）。
- 运行时查询：`centliIconByKey` / `assetPathForIconKey`；汉字图标走 `hanzi:` 前缀回退。
- 家族切换与网格选择见 `lib/core/widgets/icon_picker_sheet.dart`。

## 2. 当前规模与覆盖率

| 家族 | 图标数 | 参照 Finch 的覆盖率 |
|---|---|---|
| money | 69 | 68% |
| food | 38 | 63% |
| home | 28 | 72% |
| life | 40 | 70% |
| transport | 23 | 68% |
| office | 25 | 68% |
| electronics | 21 | 70% |
| other | 34 | 71% |
| payment | 15 | 12%（品牌类，有意不追平） |
| bank | 18 | 11%（品牌类，有意不追平） |
| brand | 12 | 30%（品牌类，有意不追平） |
| **合计** | **323** | — |

目标：**通用家族 ~70%，品牌类保持现状**。不追求与参照产品数量一致。

## 3. 图标从哪来（许可）

只用仓库内已 vendored 的图标包（`assets/_icon_packs/*.icons.json`，均已跟踪）：

| 包 | 许可 | 用途 |
|---|---|---|
| `phosphor` | MIT | 通用图标的**主力来源**（256×256，风格与现有图标一致） |
| `remix` | Apache-2.0 | 备选 |
| `simple-icons` | CC0 | 品牌 logo（商标仍归各品牌） |
| `arcticons` | CC BY-SA 4.0 | 谨慎使用：会引入**署名 + 相同方式共享**义务 |

**不要**从任何第三方 App 的安装包里提取图标或字体。家族分类法可以借鉴，图形资产不行。

## 4. 加图标的唯一正确姿势

```bash
# 1) 编辑 tools/icon_pack/targets.json，追加
#    { "family": "money", "key": "currency_chf", "label": "瑞士法郎",
#      "source": "phosphor", "name": "currency-chf" }

# 2) 干跑：确认能全部解析（unresolved 必须为 0）
python tools/icon_pack/sync_icons.py

# 3) 落地：写 SVG + 追加 catalog 条目（幂等，重复执行安全）
python tools/icon_pack/sync_icons.py --apply

# 4) 验收
flutter analyze --no-pub          # 必须 No issues found
python tools/icon_pack/audit_icons.py   # 三层一致性必须 0 处问题
```

`key` 已存在时自动跳过；`name` 找不到时不静默失败，会进 `unresolved` 列表。

## 5. 三条禁止事项

1. **不要跑 `dart format` 重排 `centli_icon_catalog.dart`**：该文件在本次改动前就不符合 `dart format`，整体重排会产生大量与本工单无关的 diff。
2. **不要往 `bank` / `payment` / `brand` 里堆量**：这些家族以品牌 logo 为主，商标风险与业务价值不匹配。需要某个具体品牌时单独提工单。
3. **不要提交 `_re_finch/`**：该目录在 `.gitignore` 中，是逆向分析的工作区（含第三方 App 的字体与渲染图），不应进入仓库。

## 6. 常见故障

- **条目"消失"**：若 `centli_icon_catalog.dart` 正被编辑器打开，编辑器可能用旧缓冲区覆盖磁盘。表现为 catalog 条目数回落、但新 SVG 还在。处理：重新 `--apply`，并在编辑器里 *Reload from Disk*。
- **图标显示为空白**：`audit_icons.py` 会报「条目指向的资产缺失」或「默认图标键无法解析」，按报告补齐即可。

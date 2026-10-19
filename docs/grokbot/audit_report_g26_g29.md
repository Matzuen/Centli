# G26–G29 审计报告

> 范围：`60035e6..b9883cd`（**15 个提交**）
> 时间：2026-10-18 15:05–15:40（Asia/Shanghai）
> 结论：**四组全部落地，两个关键承诺未验证，一处逻辑是死代码。**

---

## 0. 门槛（我自己跑的）

```
flutter analyze   →  No issues found!           退出码 0   ✅
flutter test      →  237 passed（225 → 237, +12）  ✅
tools/verify.ps1  →  VERIFY: OK  analyze_rc=0 test_rc=0  ✅
HEAD.txt          →  b9883cd == git HEAD                    ✅
版本 / schema     →  1.4.4+10 / 11（一次 bump 覆盖四组）    ✅
README 三处        →  1.4.4+10                              ✅
```

---

## 1. G26 用户视角七条 —— **全部正确**

| 项 | 证据 | 结论 |
|---|---|---|
| U1 拖拽把手 | `bookkeeping_sheet.dart:24 showDragHandle: true` | ✅ |
| U2 退格键改图标 | `:1252` 保留 `'\u232b'`；`:1359-1361` 渲染 `Icons.backspace_outlined` | ✅ **key 没被改**（这是最容易做错的地方） |
| U3 退格键换色 | `:1264/:1274` 用 `keypadNumBg/Fg`，`AC` 独占警示色 | ✅ |
| U4 文案 | `home_page.dart:420 '点底部「记一笔」记下第一笔'` | ✅ |
| U5 不计入标记 | `txn_list_tile.dart:157-161` 拼 `时间 · 未折算 · 不计入`；`:163` **不计入走 muted**（只有未折算用 error）；**未受 `hide` 影响** | ✅ 三处细节都对 |
| U6 组合位置名 | `pending_page.dart:215 '…可到「识别规则」页点「试一试」调整模板。'` | ✅ |
| U7 分栏居中 | `:171 child: Center(child: SegmentedButton…)` | ✅ |

**golden 我独立验证过**（见 §4）。

---

## 2. G27 死链 —— **修对了，守卫真的会失败**

```dart
// capture_intake_actions.dart:20
if (context.mounted) context.push('/home/pending?tab=pending');
```

- 路径正确 ✅
- **带了 `?tab=pending`** ✅（否则用户看不到刚识别的那条）
- 用 `push` 不是 `go` ✅（`initialFilter` 只在 `initState` 生效）

**我自己做了破坏性验证**（不采信它的记录）：

| 操作 | 结果 |
|---|---|
| 改回 `context.push('/pending')` | 退出码 **1**，报错 `代码里写了不存在的路由: /pending` ✅ |
| 恢复 | 退出码 0，`43 literal(s)` 全通过 |

（第一次我用 `Set-Content` 改，把引号写坏了，得到的是**编译错误**——那是无效自证，已改用精确编辑重做。）

---

## 3. G28 被忽略的通知 —— **实现完整，但核心验收没做**

**已实现且正确**：

| 项 | 证据 |
|---|---|
| 原生环形缓冲 | `CentliNotificationListener.kt:48/52/65` 三个 reason（disabled/not_watched/blank）；`:210-211` `MAX_DROPS=20`；`:238` 截断；`:87-秒` 去重 |
| 只存 pkg+title | `:236` 只有 reason/title/when，**没有正文** ✅ |
| UI 卡片 | `auto_capture_page.dart:553-559`「最近被忽略的通知」；`:324 _joinWatch`；`:335 _clearDropped`；**空列表整卡不显示** ✅ |
| **持久化并集**（我强调的陷阱） | `noti_template_store.dart:37` key；**`:698 pkgs.addAll(await _loadExtraWatchedPackages())`** ✅ |
| 并集单测 | `dropped_notifications_test.dart:63-85`，真断言（空→模板集、2 个→去重并集）✅ |

**但 `notes.md:112-113` 自己写明了**：

> `Device kill-restart acceptance: **not run** (no Android device)`
> `Self-prove extras wipe: … **Not physically commented** in CI; code path reviewed`

→ **"重启后白名单是否保留"这个 G28 唯一的核心承诺，没有被验证。** 代码看起来对，但没有证据。

---

## 4. G29 关键词放宽 + 通知内入账 —— **主体完成，一处逻辑是死的**

**已实现**：

| 项 | 证据 |
|---|---|
| 关键词放宽 | `NativeCaptureIngest.kt:165-166` 已换成宽词表（交易/支付/收款/退款/红包/转账/扣款/消费/入账/到账/支出/收入/余额，微信多「零钱」）✅ |
| 通知 action | `PendingConfirmNotifier.kt:121-122` 加了 confirm/edit（+ignore）；`:91-98` RemoteInput ✅ |
| requestCode 唯一 | `PendingActionReceiver.kt:49` `(hash(pendingId) + actionIndex*100_000_003) and 0x7fffffff` ✅ 带了 actionIndex |
| 原生落账 | `:144-156` 写 `account_id/category_id/source='noti_action'` 后 `insertOrThrow("transactions")` ✅ |
| 兜底 | `:133-134 resolveAccountId/resolveCategoryId` ✅ |
| Dart 侧 weak 丢弃 | `notification_ingest_bridge.dart:51-71` → 记入 G28 的缓冲（`reason=weak`）✅ 两组打通了 |

### 🔴 问题 F1：营销词判断是**死代码**，而且测试"通过得不明不白"

`notification_noise.dart:38-50`：

```dart
if (templateMatched && amountMinor != null) return false;
if (templateMatched) return false;                          // 命中但无金额 → 进解析失败
final body = '$title\n$text';
if (amountMinor == null && !templateMatched) return true;    // ← 这一行已覆盖"无金额未命中"
if (amountMinor == null && containsMarketingWord(body)) return true;   // ← 永远到不了
```

**第 48 行不可达**，`containsMarketingWord` 全项目只在这一处被调用 → **营销词表形同虚设**。

我用临时测试把矩阵跑了一遍（已删除）：

```
PROBE A 命中+有金额+营销词 -> drop=false
PROBE B 命中+无金额+营销词 -> drop=false   ← 应该 true（G29.1 第 4 行）
PROBE C 命中+无金额+普通词 -> drop=false
PROBE D 未命中+无金额+普通词 -> drop=true
PROBE E 未命中+无金额+营销词 -> drop=true
```

**B 和 C 结果完全相同** → 证明营销词**一点作用都没有**。

后果：一条**营销通知**只要恰好命中了模板的 `mustContain`、又没有金额，就会进「解析失败」——
正是我写 G29.1 时想拦住的那类噪音。

**它的测试也是假通过**（`g29_notification_actions_test.dart:20-31`）：

```dart
shouldDropAsWeakNoise(templateMatched: false, amountMinor: null, title:'红包优惠活动限时抽奖', …)
```
`templateMatched:false + amountMinor:null` 本来就返回 true，**把标题换成"随便"也一样通过**。
第二条 `expect(containsMarketingWord(...), isTrue)` 只测了字符串匹配，没测它的**效果**。

### 修法（1 处 + 2 个测试）

```dart
bool shouldDropAsWeakNoise({...}) {
  final body = '$title\n$text';
  // 营销词 + 无金额 → 无论是否命中模板都丢弃
  if (amountMinor == null && containsMarketingWord(body)) return true;
  if (templateMatched) return false;
  if (amountMinor == null) return true;
  return false;
}
```

测试必须加上**能失败的对照组**：

| 用例 | 期望 |
|---|---|
| `matched:true, amount:null, 营销词` | **true**（改前是 false → 这才叫守卫） |
| `matched:true, amount:null, 普通词` | false |
| `matched:true, amount:2470, 营销词` | false |

---

## 5. 我认为做得好的地方

**① notes.md 这次主动承认"没验"**

```
Device kill-restart acceptance: not run (no Android device on this Windows agent)
Self-prove extras wipe: Not physically commented in CI; code path reviewed
```

上一批的毛病是"把没做的写成做了"。这次它明确区分了 **实测** 和 **代码审阅**——这比多做一个测试更有价值。

**② 我提的两个陷阱都避开了**

- `\u232b` key 没被改（只改渲染）
- `extra_watched_packages` 并集写在了 `syncWatchedPackagesToNative` 里，没被"每次重建"冲掉

**③ G28 和 G29 打通了**

G29 丢弃的"弱噪音"直接记进 G28 的缓冲（`reason=weak`），用户在「最近被忽略的通知」里能看到**为什么没记上**。这是两单之间正确的衔接，不是我要求的。

---

## 6. 未验证清单（这是本批最大的风险）

| # | 未验证项 | 谁能验 |
|---|---|---|
| 1 | **G28 杀进程重启后，手动加入的包名是否还在白名单** | 只能真机 |
| 2 | **G29 通知里点「入账」能否不打开 App 就落账** | 只能真机 |
| 3 | G29 「改金额」RemoteInput 输入 → 直接入账 | 只能真机 |
| 4 | 三条 action 会不会串号（两条通知同时点） | 只能真机 |
| 5 | 放宽关键词后，真实支付宝/微信流量的噪音比例 | 只能真机（要跑一天） |

**代码层面全绿，但这五项才是 G28/G29 的成败所在。**

---

## 7. 其它小问题

| 级别 | 项 |
|---|---|
| P4 | `requestCode` 用 `hash + idx*1e8`，理论上"两条通知的 hash 恰差 1e8"会串号（UUID 下概率极低） |
| P4 | 无「移出监听」入口（notes 已标注） |
| — | 工作区有未跟踪的 `logo/logo3.png`（应该是你的文件，不是 Bot 的） |

---

## 8. 结论

| 组 | 落地 | 验证 |
|---|---|---|
| G26 | ✅ 七条全对 | ✅ 我独立验证 golden 会红 |
| G27 | ✅ 修对 | ✅ **我独立验证守卫会红** |
| G28 | ✅ 实现完整 | ⚠️ **核心验收（重启持久化）未做** |
| G29 | ✅ 主体完成 | ⚠️ **真机行为未验**；**F1 死代码** |

**建议**：先修 F1（1 处 + 2 个测试，10 分钟），然后你在手机上把 §6 的 1–4 项走一遍。
这四项走不通的话，G28/G29 等于没做完——**代码在，效果不在**。

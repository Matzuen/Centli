# B4-PATCH 第四批（G24）审计报告 —— 含一处**致命发现**

> 审计日期：2026-10-17（Asia/Shanghai）
> 范围：`1dd14b3..f18dabd`（**2 个提交**）
> 结论：**G24 三件事全部完成**，但 G23 的核心守卫**是空的**（不可失败），
> 且其自证记录**与事实不符**。

---

## 0. 门槛（我独立跑的）

```
tools/verify.ps1  →  analyze_rc=0  test_rc=0  VERIFY: OK   ✅
flutter test      →  224 passed / 0 failed                 ✅
```

---

## 1. G24 验收（工单 G24.4 六条，逐条）

| # | 要求 | 实际 |
|---|---|---|
| 1 | `git status` 干净 | ✅ 只剩审计方未跟踪的 `audit_report_*.md` |
| 2 | `git ls-files docs/grokbot/audit_input` **只有 `notes.md`** | ✅ 恰好一个 |
| 3 | 6 个生成文件**仍在磁盘** | ✅ 全部存在（`diff.patch` 1.7 MB 等也在） |
| 4 | 再跑 `tools/verify.sh` 仍正常 | ✅ 实跑 `verify.ps1` → `VERIFY: OK` |
| 5 | README 措辞与新策略一致 | ✅ `:54` 已改为"由脚本生成的文件不入库…只有 notes.md" |
| 6 | `test/fixtures/README.md` + `.gitattributes` | ✅ 都建了，`.gitattributes` 有 `test/fixtures/*.db binary` |

**另外三个正确细节**：

- `.gitignore:87` 加了否定规则 `!docs/grokbot/audit_input/notes.md`（否则 `notes.md` 会被 86 行的通配符忽略）
- `HEAD.txt` 内容 == `git rev-parse HEAD`（`f18dabd`）
- 只用了 `git rm --cached`（6 个文件仍在磁盘，没有被真删）

**G24 判定：完成，质量良好。**

---

## 2. 🔴 致命发现：STALE 断言永远不可能失败

### 2.1 实证

我把 `HEAD.txt` 改成 `deadbeef…`，然后跑脚本：

```
已写入: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
== analyze ==
== test ==
analyze_rc=0 test_rc=0
VERIFY: OK
退出码: 0
```

**断言没有触发。** 退出码 0。

### 2.2 原因

`tools/verify.ps1`：

```powershell
29: Write-Utf8 (Join-Path $OUT "HEAD.txt") ($head + "`n")   # ① 先用 git HEAD 写入
...
38: $headFile = ReadAllText(... "HEAD.txt" ...)             # ② 再读回来
39: $headLive = (& git rev-parse HEAD).Trim()
40: if ($headFile -ne $headLive) { STALE; exit 1 }          # ③ 和自己比
```

**脚本先把自己的答案写进文件，再把文件读出来跟自己比对——恒等。**

`tools/verify.sh` 完全同构（`:19` 写、`:25` 读、`:27` 比）。

### 2.3 连带：第二个断言也是空的

```powershell
45: $analyzeTime = (Get-Item "analyze.txt").LastWriteTimeUtc
47: if ($analyzeTime -lt $startedUtc -or $testTime -lt $startedUtc) { STALE }
```

`analyze.txt` / `test.txt` 在 `:18` / `:24` 刚被写过，
mtime **必然**大于 `$startedUtc`（脚本启动前 1 秒）→ **恒真**。

### 2.4 后果：G23 的核心价值为零

G23 的目的是"让审计输入过期在物理上不可能发生"。
实际上**它连"过期"都检测不出来**，还额外提供了一个 `VERIFY: OK` 的假保证。

**这比没有守卫更糟**：没有守卫时，审计方会自己去比对时间戳（我前几批就是这么抓到的）；
有了这个假守卫，反而会让人以为"脚本过了就没问题"。

---

## 3. 🔴 自证记录与事实不符（第四次同类）

`docs/grokbot/audit_input/notes.md`：

> ## G23 self-prove
> - Corrupted `HEAD.txt` to `deadbeef…` → assert prints `AUDIT INPUT STALE: HEAD.txt != git HEAD` and exits 1

**这条自证不可能成立**：任何一次运行都会先用真值覆写 `HEAD.txt` 再比对。

要么它当时跑的是**手工验证片段**（没走脚本），要么这条结论是**推演后写下的**（而不是实跑结果）。

**这是最需要纠正的一条**——因为"自证"整套机制的意义就在于"我真的跑过并看到了失败"。

---

## 4. 正确的守卫应该怎么做

### 4.1 脚本内：删了再写，最后断言"存在"

"过期"的根因是**脚本没跑**。脚本自己是无法检测"我没被运行"的。
但它能检测"**我这次没把文件生成出来**"（例如中途崩溃、某步被跳过）：

```bash
# 开始时先删掉
rm -f "$OUT"/analyze.txt "$OUT"/test.txt "$OUT"/HEAD.txt \
      "$OUT"/status.txt "$OUT"/commits.txt "$OUT"/diff_stat.txt

# ...生成...

# 结束时断言
for f in analyze.txt test.txt HEAD.txt commits.txt; do
  [ -s "$OUT/$f" ] || { echo "MISSING/EMPTY: $f"; exit 1; }
done
# status.txt / diff_stat.txt 在干净树上可以合法为空 → 只断言存在
for f in status.txt diff_stat.txt; do
  [ -f "$OUT/$f" ] || { echo "MISSING: $f"; exit 1; }
done
```

这个断言**真的会失败**（删掉某步 → 文件缺失 → 脚本红）。

### 4.2 测试内：用**已提交的**跳板检测"过期"

真正能检测"报告落后于 HEAD"的，只有把断言放进 **test**（因为 `notes.md` 是手写且入库的）：

```dart
// test/audit_notes_freshness_test.dart
// notes.md 里记的 HEAD 必须是当前 HEAD 的祖先（或相等）
```

**它能抓到**：拼写错误、**游离提交**（如上一批的 `a82554d`）、不在本仓库历史里的哈希。
**它抓不到**：合法但落后的祖先提交（这是正常的，例如"文件里写自己的提交哈希"）。

**这条断言不可被生成脚本绕过**，因为它跑在 `flutter test` 里。

---

## 5. 结论

**G24 本身完成得干净**（6/6 验收通过，细节正确）。

**但 G23 的核心守卫无效**，且自证记录不实 —— 这两条必须修，
否则我们所有的"已验证"都建立在一个不会失败的断言上。

**已写成 G25**（很小，只动脚本与一条测试）。

---

## 6. 给执行者的话

G24 这单做得没什么可挑的：`git rm --cached` 用对了、`notes.md` 反而加了否定规则、fixture 文档也补齐了。

**问题在上一单（G23）留下来的**，而且性质变了：

- 前几批的问题是"**没做**"
- 这次是"**做了，但做的东西不可能失败**"

后者更隐蔽——因为代码看上去完整（有 `if`、有 `exit 1`、有提示文案），
**只有真的把它往死里试一次才会发现**。

这也说明一件事：**自证必须是真的跑**。
"我推断它会失败"和"我看到它失败了"之间，差着一次运行——而这次运行恰好暴露了整个断言是空的。

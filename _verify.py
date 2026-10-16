from pathlib import Path
import re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

checks = []

def ok(name, cond, detail=""):
    checks.append((name, bool(cond), detail))
    print(("OK " if cond else "FAIL ") + name + ((" :: " + detail) if detail else ""))

db = (ROOT/"lib/data/db/centli_database.dart").read_text(encoding="utf-8")
ok("#1 scoped delete", "t.ledgerId.equals(lid)" in db and "await delete(transactions).go();" not in db.split("restoreFromImportBundle")[1][:800])
ok("#1 replaceFxRates", "bool replaceFxRates = true" in db)
ok("#2 merchant insert", "String? merchant," in db and "merchant: Value(merchant)," in db)
ok("#22 foreign_keys", "PRAGMA foreign_keys = ON" in db)

imp = (ROOT/"lib/data/export/import_service.dart").read_text(encoding="utf-8")
ok("#3 require keys", "missing required field" in imp or "缺少必填" in imp or "containsKey(key)" in imp)
ok("#3 null throw", "cannot be null" in imp)
ok("#4 replaceFxRates param", "replaceFxRates: replaceFxRates" in imp)
ok("#24 schema<=3", "schemaVersion > 3" in imp)

exp = (ROOT/"lib/data/export/export_service.dart").read_text(encoding="utf-8")
ok("#24 export schema 3", "'schema_version': 3" in exp)
ok("#43 appVersion", "1.0.1+2" in exp)

io = (ROOT/"lib/platform/notifications/notification_listener_io.dart").read_text(encoding="utf-8")
ok("#5 channelSupported", "channelSupported" in io and "Platform.isIOS" in io)
ok("#5 bridgeReady", "bridgeReady" in io)
ok("#51 single handler", io.count("setMethodCallHandler") == 1)

np = (ROOT/"lib/platform/notifications/notification_parse.dart").read_text(encoding="utf-8")
ok("#9 require symbol", "USD|EUR|CNY" in np and "allMatches" in np)

bk = (ROOT/"lib/features/ledger/bookkeeping_sheet.dart").read_text(encoding="utf-8")
ok("#2 _merchant", "String? _merchant;" in bk and "merchant: merchant," in bk)
ok("#6 archived account", "getAccount(id)" in bk)
ok("#6/35 unique keys", "dd-from-" in bk and "dd-to-" in bk and "dd-acc-" in bk)
ok("#6 no placeholder", "KEY_TRANSFER_FROM_PLACEHOLDER" not in bk)
ok("#7 finally dispose", "finally {\n      toCtrl.dispose();" in bk)

nat = (ROOT/"android/app/src/main/kotlin/com/centli/centli/NativeCaptureIngest.kt").read_text(encoding="utf-8")
ok("#8 toMinor", "currencyDecimals" in nat and "toMinor(currency, major)" in nat)
ok("#11 keep title", "Align Dart merchantFromTitle" in nat)

lis = (ROOT/"android/app/src/main/kotlin/com/centli/centli/CentliNotificationListener.kt").read_text(encoding="utf-8")
ok("#13 default false", "getBoolean(KEY_AUTO, false)" in lis)
ok("#10 peekQueue", "fun peekQueue" in lis and "fun clearQueue" in lis)

ma = (ROOT/"android/app/src/main/kotlin/com/centli/centli/MainActivity.kt").read_text(encoding="utf-8")
ok("#10 bridgeReady native", '"bridgeReady"' in ma and "dartBridgeReady" in ma)
ok("#10 no early flush", "flushQueuedCaptures()" not in ma.split("mainHandler.post")[1].split("}")[0] or "bridgeReady" in ma)

pe = (ROOT/"lib/features/settings/permission_explain_page.dart").read_text(encoding="utf-8")
ok("#12 no force true", "auto_capture_enabled', 'true'" not in pe)

pp = (ROOT/"lib/features/pending/pending_page.dart").read_text(encoding="utf-8")
ok("#20 in+out", "loadCategories(widget.ledgerId, 'in')" in pp)
ok("#23 kDebugMode", "kDebugMode" in pp and "science_outlined" in pp)

als = (ROOT/"lib/features/security/app_lock_service.dart").read_text(encoding="utf-8")
ok("#14 lockout", "_maxFails" in als and "lockoutRemaining" in als)

man = (ROOT/"android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
# BROWSABLE should not appear next to host=pending
i = man.find('android:host="pending"')
chunk = man[max(0,i-250):i+80]
ok("#16 no BROWSABLE near pending", "BROWSABLE" not in chunk, chunk.replace("\n"," ")[:120])

baks = list(ROOT.rglob("*.bak*"))
ok("#47 no bak", len(baks)==0, str(len(baks)))

priv = (ROOT/"assets/legal/privacy_zh.txt").read_text(encoding="utf-8")
ok("#15 privacy LLM", "LLM" in priv or "OpenAI" in priv)

ip = (ROOT/"lib/features/settings/import_page.dart").read_text(encoding="utf-8")
ok("#4 excel skip fx", "replaceFxRates: preview.sourceKind != 'excel'" in ip)

print("\n=== SUMMARY ===")
fails = [c for c in checks if not c[1]]
print("passed", len(checks)-len(fails), "/", len(checks))
for n,c,d in fails:
    print(" FAIL", n, d)

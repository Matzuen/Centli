# -*- coding: utf-8 -*-
"""Apply P3 FX remote auto-refresh onto Centli tree."""
import base64, json, pathlib, re, sys

ROOT = pathlib.Path(r"D:\Resource\Codebase\studyProject\Centli")
PAYLOAD = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path(__file__).with_name("payload.json")
data = json.loads(PAYLOAD.read_text(encoding="utf-8"))

def write_b64(rel, key):
    path = ROOT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(base64.b64decode(data[key]))
    print("wrote", path, path.stat().st_size)

write_b64(r"lib\data\fx\fx_remote_service.dart", "fx_remote_service.dart")
write_b64(r"lib\features\settings\fx_rates_page.dart", "fx_rates_page.dart")

# --- pubspec: add http ---
pub = ROOT / "pubspec.yaml"
pt = pub.read_text(encoding="utf-8")
if re.search(r"^  http:", pt, re.M):
    print("pubspec already has http")
else:
    # after flutter_riverpod line
    if "flutter_riverpod:" not in pt:
        raise SystemExit("flutter_riverpod not found in pubspec")
    pt2 = re.sub(
        r"(  flutter_riverpod: [^\n]+\n)",
        r"\1  http: ^1.2.2\n",
        pt,
        count=1,
    )
    if pt2 == pt:
        raise SystemExit("failed to insert http into pubspec")
    pub.write_text(pt2, encoding="utf-8")
    print("patched pubspec.yaml +http")

# --- database: watchSetting ---
db = ROOT / r"lib\data\db\centli_database.dart"
dt = db.read_text(encoding="utf-8")
if "Stream<String?> watchSetting(" in dt:
    print("db already has watchSetting")
else:
    needle = """  Future<void> setSetting(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }
"""
    insert = needle + """
  Stream<String?> watchSetting(String key) {
    return (select(appSettings)..where((t) => t.key.equals(key)))
        .watchSingleOrNull()
        .map((row) => row?.value);
  }
"""
    if needle not in dt:
        raise SystemExit("setSetting block not found")
    dt = dt.replace(needle, insert, 1)
    db.write_text(dt, encoding="utf-8")
    print("patched centli_database.dart +watchSetting")

# --- splash: schedule daily FX refresh ---
sp = ROOT / r"lib\features\onboarding\splash_page.dart"
st = sp.read_text(encoding="utf-8")
if "scheduleFxAutoRefresh" in st:
    print("splash already schedules FX")
else:
    if "import '../../data/fx/fx_remote_service.dart';" not in st:
        st = st.replace(
            "import '../../data/db/database_provider.dart';\n",
            "import '../../data/db/database_provider.dart';\n"
            "import '../../data/fx/fx_remote_service.dart';\n",
            1,
        )
    boot_old = """    final done = await db.getSetting('onboarding_done');
    final lockOn = (await db.getSetting('app_lock')) == 'true';
"""
    boot_new = """    final done = await db.getSetting('onboarding_done');
    final lockOn = (await db.getSetting('app_lock')) == 'true';
    // P3: once-per-day remote FX (non-blocking; failures ignored).
    final ledgerId = await db.currentLedgerId();
    var base = 'CNY';
    if (ledgerId != null) {
      final ledger = await db.getLedger(ledgerId);
      if (ledger != null) base = ledger.baseCurrency;
    }
    scheduleFxAutoRefresh(db, base);
"""
    if boot_old not in st:
        raise SystemExit("splash boot marker not found")
    st = st.replace(boot_old, boot_new, 1)
    sp.write_text(st, encoding="utf-8")
    print("patched splash_page.dart")

# --- me_page subtitle ---
me = ROOT / r"lib\features\settings\me_page.dart"
mt = me.read_text(encoding="utf-8")
old_sub = """            subtitle: const Text(
              '\\u624b\\u5de5\\u7f13\\u5b58\\uff1b\\u9996\\u9875/\\u7edf\\u8ba1/\\u51c0\\u989d\\u6298\\u7b97\\u4e3a\\u672c\\u4f4d\\u5e01',
            ),"""
# File may use real Unicode rather than escapes
candidates = [
    old_sub,
    """            subtitle: const Text(
              '手工缓存；首页/统计/净额折算为本位币',
            ),""",
]
# Also try reading what's actually there
import re as _re
m = _re.search(r"Icons\.currency_exchange.*?onTap: \(\) => context\.push\('/me/fx'\)", mt, _re.S)
if not m:
    print("WARN: FX list tile not found for subtitle patch")
else:
    block = m.group(0)
    if "远程" in block or "\\u8fdc\\u7a0b" in block:
        print("me_page FX subtitle already mentions remote")
    else:
        mt2 = mt.replace(
            block,
            block.replace(
                "手工缓存；首页/统计/净额折算为本位币",
                "手工 + 远程日频；折算为本位币",
            ).replace(
                "\\u624b\\u5de5\\u7f13\\u5b58\\uff1b\\u9996\\u9875/\\u7edf\\u8ba1/\\u51c0\\u989d\\u6298\\u7b97\\u4e3a\\u672c\\u4f4d\\u5e01",
                "\\u624b\\u5de5 + \\u8fdc\\u7a0b\\u65e5\\u9891\\uff1b\\u6298\\u7b97\\u4e3a\\u672c\\u4f4d\\u5e01",
            ),
            1,
        )
        # Direct unicode replace on the subtitle string content
        if mt2 == mt:
            mt2 = _re.sub(
                r"(leading: const Icon\(Icons\.currency_exchange\),.*?subtitle: const Text\()(.*?)(\),)",
                r"\1'手工 + 远程日频；折算为本位币'\3",
                mt,
                count=1,
                flags=_re.S,
            )
        if mt2 == mt:
            # try multiline subtitle
            mt2 = _re.sub(
                r"(Icons\.currency_exchange[\s\S]*?subtitle: const Text\(\s*)['\"][^'\"]*['\"]",
                r"\1'手工 + 远程日频；折算为本位币'",
                mt,
                count=1,
            )
        if mt2 == mt:
            print("WARN: could not patch me_page subtitle; dumping snippet:")
            print(block[:400])
        else:
            me.write_text(mt2, encoding="utf-8")
            print("patched me_page FX subtitle")

# --- Android main INTERNET for release ---
man = ROOT / r"android\app\src\main\AndroidManifest.xml"
mtxt = man.read_text(encoding="utf-8")
if "android.permission.INTERNET" in mtxt:
    print("main manifest already has INTERNET")
else:
    mtxt2 = mtxt.replace(
        "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n",
        "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\">\n"
        "    <uses-permission android:name=\"android.permission.INTERNET\" />\n",
        1,
    )
    if mtxt2 == mtxt:
        raise SystemExit("failed to patch AndroidManifest INTERNET")
    man.write_text(mtxt2, encoding="utf-8")
    print("patched main AndroidManifest +INTERNET")

print("DONE")

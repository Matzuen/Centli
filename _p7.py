from pathlib import Path
import re
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

# ===== #16 remove BROWSABLE from centli://pending =====
mp = ROOT / "android/app/src/main/AndroidManifest.xml"
man = mp.read_text(encoding="utf-8")
# Find deep link intent-filter with centli pending and remove BROWSABLE category
old = '''            <!-- Deep link: centli://pending?... -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="centli" android:host="pending" />
            </intent-filter>'''
# Flexible match
m = re.search(
    r"<!-- Deep link: centli://pending\?\.\.\. -->\s*"
    r"<intent-filter>\s*"
    r"<action android:name=\"android\.intent\.action\.VIEW\"\s*/>\s*"
    r"<category android:name=\"android\.intent\.category\.DEFAULT\"\s*/>\s*"
    r"<category android:name=\"android\.intent\.category\.BROWSABLE\"\s*/>\s*"
    r"<data android:scheme=\"centli\" android:host=\"pending\"\s*/>\s*"
    r"</intent-filter>",
    man,
)
if not m:
    # try without comments / order
    m = re.search(
        r"(<intent-filter>\s*"
        r"<action android:name=\"android\.intent\.action\.VIEW\"\s*/>\s*"
        r"<category android:name=\"android\.intent\.category\.DEFAULT\"\s*/>\s*)"
        r"<category android:name=\"android\.intent\.category\.BROWSABLE\"\s*/>\s*"
        r"(<data android:scheme=\"centli\" android:host=\"pending\"\s*/>\s*"
        r"</intent-filter>)",
        man,
    )
    if m:
        man = man[:m.start()] + m.group(1) + m.group(2) + man[m.end():]
        mp.write_text(man, encoding="utf-8", newline="\n")
        print("removed BROWSABLE from centli pending")
    else:
        print("WARN: BROWSABLE centli pending filter not found; dump nearby")
        i = man.find('android:host="pending"')
        print(repr(man[i-300:i+100]) if i>=0 else "no pending host")
else:
    new = '''            <!-- Deep link: centli://pending?... (no BROWSABLE: block web inject #16) -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:scheme="centli" android:host="pending" />
            </intent-filter>'''
    man = man[:m.start()] + new + man[m.end():]
    mp.write_text(man, encoding="utf-8", newline="\n")
    print("removed BROWSABLE (full match)")

# ===== #47 delete bak files =====
baks = list(ROOT.rglob("*.bak*"))
for b in baks:
    try:
        b.unlink()
        print("deleted", b.relative_to(ROOT))
    except Exception as e:
        print("fail delete", b, e)

# ===== #15 privacy_zh.txt disclosure =====
priv = ROOT / "assets/legal/privacy_zh.txt"
if priv.exists():
    t = priv.read_text(encoding="utf-8")
    marker = "LLM"
    if "智能填单" not in t and "OpenAI" not in t and "大模型" not in t:
        add = (
            "\n\n【智能填单与语音】\n"
            "· 本地规则解析默认在设备上完成。\n"
            "· 语音识别可能使用系统语音服务（speech_to_text）；"
            "首次尝试可能允许联网识别（onDevice:false），失败时回退到设备端识别。\n"
            "· 若你在设置中开启「LLM 增强填单」并自行配置 API Key / Base URL，"
            "相关文本会发送至你指定的 OpenAI 兼容服务端；默认关闭，密钥仅存在本机安全存储。\n"
        )
        priv.write_text(t.rstrip() + add + "\n", encoding="utf-8", newline="\n")
        print("appended privacy LLM/speech disclosure")
    else:
        print("privacy already mentions LLM/speech-ish")
else:
    print("privacy_zh.txt missing")

# ===== #31 close http client if easy =====
fxp = ROOT / "lib/data/fx/fx_remote_service.dart"
fx = fxp.read_text(encoding="utf-8")
if "void close(" not in fx and "_client" in fx:
    # add close method
    if "class FxRemoteService" in fx and "dispose" not in fx:
        # append close before last closing of class - find last method
        fx2 = fx.rstrip()
        if fx2.endswith("}"):
            fx2 = fx2[:-1] + "\n  void close() {\n    _client.close();\n  }\n}\n"
            fxp.write_text(fx2, encoding="utf-8", newline="\n")
            print("added FxRemoteService.close()")
        else:
            print("WARN cannot add close")
else:
    print("fx close skip")

print("p7 done")

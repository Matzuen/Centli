from pathlib import Path
t = Path(r"C:\Users\ponyhch\AppData\Local\Pub\Cache\hosted\pub.dev\speech_to_text-7.5.0\lib\speech_to_text.dart").read_text(encoding="utf-8")
# SpeechListenOptions is in platform interface
pi = Path(r"C:\Users\ponyhch\AppData\Local\Pub\Cache\hosted\pub.dev\speech_to_text_platform_interface-2.5.0\lib\speech_to_text_platform_interface.dart").read_text(encoding="utf-8")
i = pi.find("class SpeechListenOptions")
print(pi[i:i+1500] if i>=0 else "not in pi")
# also check android plugin onDevice behavior
android = list(Path(r"C:\Users\ponyhch\AppData\Local\Pub\Cache\hosted\pub.dev\speech_to_text-7.5.0").rglob("*SpeechToTextPlugin*"))
print("android plugins", android)
for a in android:
    if a.suffix in (".kt",".java"):
        txt = a.read_text(encoding="utf-8", errors="replace")
        if "onDevice" in txt or "EXTRA_PREFER_OFFLINE" in txt:
            print("===", a.name, "===")
            for line in txt.splitlines():
                if "onDevice" in line or "OFFLINE" in line or "prefer" in line.lower():
                    print(line)

from pathlib import Path
root = Path(r"D:\Resource\Codebase\studyProject\Centli")
# applicationId
for p in [root/"android/app/build.gradle", root/"android/app/build.gradle.kts"]:
    if p.exists():
        print("===", p, "===")
        print(p.read_text(encoding="utf-8")[:2000])
# path_provider android documents
pp = list(Path(r"C:\Users\ponyhch\AppData\Local\Pub\Cache\hosted\pub.dev").glob("path_provider_android-*/android/**/*.kt"))
print("pp files", pp[:5])
for f in pp:
    t=f.read_text(encoding="utf-8", errors="replace")
    if "Documents" in t or "filesDir" in t:
        print("FILE", f)
        for line in t.splitlines():
            if "Document" in line or "filesDir" in line or "getDir" in line:
                print(line)

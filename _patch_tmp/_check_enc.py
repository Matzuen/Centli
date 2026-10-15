import sys
sys.stdout.reconfigure(encoding="utf-8")
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\lib\platform\notifications\notification_parse.dart")
raw = p.read_bytes()
idx = raw.find(b"mustContainRegex")
print("bytes around mustContain:", raw[idx:idx+90])
t = p.read_text(encoding="utf-8")
import re
for m in re.finditer(r"mustContainRegex: '([^']+)'", t):
    s = m.group(1)
    print("mustContain:", repr(s))
    print("codepoints:", [hex(ord(c)) for c in s])
for m in re.finditer(r"excludeTextRegex: '([^']+)'", t):
    s = m.group(1)
    print("exclude:", repr(s))
# amount regex
idx2 = t.find("kAmountRegex")
print(t[idx2:idx2+200])
# assets
p2 = Path(r"D:\Resource\Codebase\studyProject\Centli\assets\noti_templates.json")
print("assets exists", p2.exists())
if p2.exists():
    out = Path(r"D:\Resource\Codebase\studyProject\Centli\_patch_tmp\_tpl_dump.txt")
    out.write_text(p2.read_text(encoding="utf-8"), encoding="utf-8")
    print("wrote tpl dump", out)

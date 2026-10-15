# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
t = p.read_text(encoding='utf-8')
print('has ingestAndNotify', 'fun ingestAndNotify' in t)
print('has yen literal', '\u00a5' in t or '\\u00a5' in t)
# show AMOUNT line
for line in t.splitlines():
    if 'AMOUNT' in line or 'Pattern.compile' in line or 'guessMerchant' in line and 'fun' in line:
        print(repr(line[:120]))
# Fix if Pattern has wrong escaping - rewrite AMOUNT cleanly
import re
# Replace AMOUNT pattern with a clean version using actual unicode chars
old = None
for m in re.finditer(r'private val AMOUNT: Pattern = Pattern\.compile\(\s*"[^"]+"\s*,?\s*\)', t):
    old = m.group(0)
    print('FOUND AMOUNT block len', len(old))
    print(repr(old[:200]))

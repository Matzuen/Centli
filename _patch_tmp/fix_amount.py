# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
t = p.read_text(encoding="utf-8")

# Fix AMOUNT pattern - use real unicode currency chars in Kotlin string
import re
t2, n = re.subn(
    r'private val AMOUNT: Pattern = Pattern\.compile\(\s*"[^"]+"\s*,?\s*\)',
    'private val AMOUNT: Pattern = Pattern.compile(\n'
    '        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\\\s*)?(?:[\u00a5\uffe5$\u20ac])?\\\\s*'
    '([0-9]+(?:,[0-9]{3})*(?:\\\\.[0-9]{1,2})?)",\n'
    '    )',
    t,
    count=1,
)
print("AMOUNT replaced", n)

# Fix detectCurrency euro checks that may be wrong
# Show lines with backslash-u
for i, line in enumerate(t2.splitlines(), 1):
    if "\\u" in line or "contains('\\u" in line or 'contains("\\u' in line:
        print(i, repr(line[:100]))

p.write_text(t2, encoding="utf-8", newline="\n")
print("saved")

# -*- coding: utf-8 -*-
from pathlib import Path
native = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
nt = native.read_text(encoding="utf-8")
# Find the raw bytes around AMOUNT
i = nt.find("private val AMOUNT")
chunk = nt[i:i+250]
print(repr(chunk))
# Fix: ensure double-backslash for regex
import re
fixed = re.sub(
    r'private val AMOUNT: Pattern = Pattern\.compile\(\s*"[^"]*"\s*,?\s*\)',
    'private val AMOUNT: Pattern = Pattern.compile(\n'
    r'        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\s*)?(?:[\u00a5\uffe5$\u20ac])?\\s*([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)",'
    '\n    )',
    nt,
    count=1,
)
i2 = fixed.find("private val AMOUNT")
print("AFTER:", repr(fixed[i2:i2+250]))
native.write_text(fixed, encoding="utf-8", newline="\n")
print("fixed")

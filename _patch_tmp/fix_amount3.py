# -*- coding: utf-8 -*-
from pathlib import Path
native = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
nt = native.read_text(encoding="utf-8")
start = nt.find("private val AMOUNT")
end = nt.find("private fun parseAmount", start)
# Correct Kotlin source: need \\s and \\. in the .kt file (two chars each)
replacement = (
    "private val AMOUNT: Pattern = Pattern.compile(\n"
    '        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\\\s*)?(?:[\u00a5\uffe5$\u20ac])?\\\\s*'
    '([0-9]+(?:,[0-9]{3})*(?:\\\\.[0-9]{1,2})?)",\n'
    "    )\n\n    "
)
# In Python normal string: \\\\ becomes \\ in output file = two backslashes = correct for Kotlin regex
nt2 = nt[:start] + replacement + nt[end:]
native.write_text(nt2, encoding="utf-8", newline="\n")
chunk = native.read_text(encoding="utf-8")[start:start+220]
print(repr(chunk))
# Also fix body = "$title\n$text" - check
for line in native.read_text(encoding="utf-8").splitlines():
    if "val body" in line or "val tip" in line:
        print("LINE", repr(line))

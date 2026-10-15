# -*- coding: utf-8 -*-
from pathlib import Path
native = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
t = native.read_text(encoding="utf-8")
# Fix $ in string template - escape it
old = '(?:[\u00a5\uffe5$\u20ac])?'
# In file it may already be literal yen chars
import re
m = re.search(r'\(\?:\[([^\]]+)\]\)\?', t)
if m:
    print("char class:", repr(m.group(1)))
# Replace the currency optional group carefully
t2 = t.replace(
    "(?:[¥￥$€])?",
    "(?:[¥￥€]|\\\\$)?",
)
if t2 == t:
    # try unicode forms
    t2 = re.sub(
        r'\(\?:\[[^\]]*\$[^\]]*\]\)\?',
        '(?:[\u00a5\uffe5\u20ac]|\\\\$)?',
        t,
        count=1,
    )
print("changed", t2 != t)
# Also fix detectCurrency window.contains('$') - in single quotes OK for Char
# formatYuan "USD" -> "$" - OK as "$" alone might be empty template? In Kotlin "$" is just dollar if nothing follows... actually "$" at end of string is literal. "$something" is template. Alone "$" is fine.
native.write_text(t2, encoding="utf-8", newline="\n")
i = t2.find("private val AMOUNT")
print(repr(t2[i:i+220]))

from pathlib import Path
p = Path("lib/features/pending/pending_page.dart")
t = p.read_text(encoding="utf-8")
t = t.replace(
    "import 'package:flutter/foundation.dart';\nimport 'package:flutter/material.dart';",
    "import 'package:flutter/foundation.dart' show kDebugMode;\nimport 'package:flutter/material.dart';",
    1,
)
# Also fix indentation of if (kDebugMode)
t = t.replace(
    "          ),\nif (kDebugMode)\n          IconButton(",
    "          ),\n          if (kDebugMode)\n            IconButton(",
    1,
)
# Indent the IconButton body one more level - careful, may be messy.
# Read the button block and re-indent
import re
m = re.search(
    r"          if \(kDebugMode\)\n            IconButton\([\s\S]*?science_outlined[\s\S]*?          \),",
    t,
)
if m:
    block = m.group(0)
    # Ensure IconButton children use 2 more spaces than original IconButton at 10 spaces
    # Currently mixed. Simpler: leave and just fix import; analyzer only complained about Category.
    pass
p.write_text(t, encoding="utf-8", newline="\n")
print("fixed import")
# show analyzer line 467 area
lines = t.splitlines()
for i in range(450, min(480, len(lines))):
    print(f"{i+1}|{lines[i]}")

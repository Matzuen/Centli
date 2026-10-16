from pathlib import Path
import re
p = Path("lib/data/fx/fx_remote_service.dart")
t = p.read_text(encoding="utf-8")
# remove broken close at end
bad = """
  void close() {
    _client.close();
  }
}
"""
# The file ends with scheduleFxAutoRefresh having close wrongly - fix by removing close and restoring closing of function
t2 = re.sub(
    r"\n  void close\(\) \{\n    _client\.close\(\);\n  \}\n\}\n?\s*$",
    "\n}\n",
    t,
)
# find class FxRemoteService and client field
m = re.search(r"class FxRemoteService[\s\S]{0,400}", t2)
print(m.group(0) if m else "no class")
# Find if Client is stored
for line in t2.splitlines():
    if "Client" in line or "_client" in line or "http." in line:
        print(">", line)
p.write_text(t2, encoding="utf-8", newline="\n")
print("removed broken close")

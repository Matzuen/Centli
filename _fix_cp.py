from pathlib import Path
n = Path("android/app/src/main/kotlin/com/centli/centli/NativeCaptureIngest.kt").read_text(encoding="utf-8")
i = n.find("private val AMOUNT")
chunk = n[i:i+250]
# extract the string literal
s = chunk.split('"')[1]
Path("_cp.txt").write_text("len=%d\n" % len(s) + "\n".join("%r U+%04X" % (c, ord(c)) for c in s[:80]), encoding="utf-8")
# Also verify date chars in parseAmount
j = n.find("ch == ")
Path("_cp2.txt").write_text("\n".join("%r U+%04X" % (c, ord(c)) for c in n[j:j+120] if ord(c)>127), encoding="utf-8")
print("ok")

from pathlib import Path
n = Path("android/app/src/main/kotlin/com/centli/centli/NativeCaptureIngest.kt").read_text(encoding="utf-8")
i = n.find("private val AMOUNT")
Path("_amt_snip.txt").write_text(repr(n[i:i+500]), encoding="utf-8")
j = n.find("private fun currencyDecimals")
Path("_amt_snip2.txt").write_text(n[j:j+1200] if j>0 else "missing", encoding="utf-8")
print("wrote snips", i, j)

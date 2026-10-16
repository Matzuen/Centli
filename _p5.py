from pathlib import Path
import re
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(r"D:\Resource\Codebase\studyProject\Centli")

# ===== NativeCaptureIngest #8 #9 #11 =====
np = ROOT / "android/app/src/main/kotlin/com/centli/centli/NativeCaptureIngest.kt"
n = np.read_text(encoding="utf-8")

# Replace AMOUNT pattern - require currency marker
old_amt = None
m = re.search(r'private val AMOUNT: Pattern = Pattern\.compile\(\n\s*"([^"]+)",\n\s*\)', n)
if not m:
    raise SystemExit("AMOUNT pattern missing")
new_amt_pat = (
    '(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\\\s*|(?:[\\\\u00a5\\\\uffe5]|\\\\$|\\\\u20ac))\\\\s*'
    '([0-9]+(?:,[0-9]{3})*(?:\\\\.[0-9]{1,2})?)'
)
# In Kotlin source we want actual unicode escapes in the string
new_amt_src = '''    private val AMOUNT: Pattern = Pattern.compile(
        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\\\s*|(?:[\\\\u00a5\\\\uffe5]|\\\\$|\\\\u20ac))\\\\s*([0-9]+(?:,[0-9]{3})*(?:\\\\.[0-9]{1,2})?)",
    )'''
# Simpler: write with real yen/euro chars
new_amt_src = (
    '    private val AMOUNT: Pattern = Pattern.compile(\n'
    '        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\\\s*|(?:[\u00a5\uffe5]|\\\\$|\u20ac))\\\\s*'
    '([0-9]+(?:,[0-9]{3})*(?:\\\\.[0-9]{1,2})?)",\n'
    '    )'
)
n = n[:m.start()] + new_amt_src + n[m.end():]

# parseAmount: currency-aware minor + skip date suffix
old_parse = '''    private fun parseAmount(title: String, text: String): Parsed {
        val body = "$title\\n$text"
        val m = AMOUNT.matcher(body)
        if (!m.find()) {
            return Parsed(null, "CNY", guessMerchant(title, text))
        }
        val raw = (m.group(1) ?: "").replace(",", "")
        val major = raw.toDoubleOrNull()
        if (major == null) {
            return Parsed(null, "CNY", guessMerchant(title, text))
        }
        val currency = detectCurrency(body, m.start(), m.end(), m.group(0) ?: "")
        val minor = Math.round(major * 100.0).toInt()
        return Parsed(minor, currency, guessMerchant(title, text))
    }'''

new_parse = '''    private fun currencyDecimals(ccy: String): Int = when (ccy) {
        "JPY" -> 0
        else -> 2
    }

    private fun toMinor(ccy: String, major: Double): Int {
        val factor = Math.pow(10.0, currencyDecimals(ccy).toDouble())
        return Math.round(major * factor).toInt()
    }

    private fun parseAmount(title: String, text: String): Parsed {
        val body = "$title\\n$text"
        val m = AMOUNT.matcher(body)
        while (m.find()) {
            val end = m.end()
            if (end < body.length) {
                val ch = body[end]
                if (ch == '\u6708' || ch == '\u65e5' || ch == '\u53f7' ||
                    ch == '\u65f6' || ch == '\u5206' || ch == '\u79d2'
                ) {
                    continue
                }
            }
            val raw = (m.group(1) ?: "").replace(",", "")
            val major = raw.toDoubleOrNull()
            if (major == null) continue
            val currency = detectCurrency(body, m.start(), m.end(), m.group(0) ?: "")
            val minor = toMinor(currency, major)
            return Parsed(minor, currency, guessMerchant(title, text))
        }
        return Parsed(null, "CNY", guessMerchant(title, text))
    }'''

if old_parse not in n:
    raise SystemExit("parseAmount missing")
n = n.replace(old_parse, new_parse, 1)

# formatYuan fix for JPY decimals
old_fmt = '''    private fun formatYuan(currency: String, minor: Int): String {
        val major = minor / 100.0
        val symbol = when (currency) {
            "USD" -> "$"
            "EUR" -> "\\u20ac"
            "JPY" -> "\\u00a5"
            else -> "\\u00a5"
        }
        return if (currency == "JPY") {
            "$symbol$minor"
        } else {
            "$symbol${"%.2f".format(major)}"
        }
    }'''

# Match whatever is in file for formatYuan
m2 = re.search(
    r"    private fun formatYuan\(currency: String, minor: Int\): String \{.*?\n    \}",
    n,
    re.S,
)
if not m2:
    raise SystemExit("formatYuan missing")
new_fmt = '''    private fun formatYuan(currency: String, minor: Int): String {
        val decimals = currencyDecimals(currency)
        val major = minor / Math.pow(10.0, decimals.toDouble())
        val symbol = when (currency) {
            "USD" -> "$"
            "EUR" -> "\u20ac"
            "JPY" -> "\u00a5"
            else -> "\u00a5"
        }
        return if (decimals == 0) {
            "$symbol${major.toInt()}"
        } else {
            "$symbol${"%.${decimals}f".format(major)}"
        }
    }'''
# Kotlin string format with decimals variable - use when instead for simplicity
new_fmt = '''    private fun formatYuan(currency: String, minor: Int): String {
        val decimals = currencyDecimals(currency)
        val major = minor / Math.pow(10.0, decimals.toDouble())
        val symbol = when (currency) {
            "USD" -> "$"
            "EUR" -> "\u20ac"
            "JPY" -> "\u00a5"
            else -> "\u00a5"
        }
        return if (decimals == 0) {
            "$symbol${major.toInt()}"
        } else {
            "$symbol${"%.2f".format(major)}"
        }
    }'''
n = n[:m2.start()] + new_fmt + n[m2.end():]

# #11 guessMerchant: keep title when strip empties (align Dart merchantFromTitle)
old_gm = '''    private fun guessMerchant(title: String, text: String): String? {
        val t = title.trim()
        if (t.isNotEmpty() && !t.contains("\\u652f\\u4ed8\\u6210\\u529f") && !t.contains("\\u4ed8\\u6b3e\\u6210\\u529f")) {
            val cut = t.replace(Regex("-?\\u5fae\\u4fe1\\u652f\\u4ed8$"), "").trim()
            if (cut.isNotEmpty()) return cut
        }
        val body = "$title\\n$text"
        val m = Regex("(?:\\u5411|\\u7ed9|\\u5546\\u6237)\\\\s*(.+?)(?:\\\\s|$)").find(body)
        return m?.groupValues?.getOrNull(1)?.trim()?.ifEmpty { null }
    }'''

# Use actual unicode from file - find function and replace
m3 = re.search(
    r"    private fun guessMerchant\(title: String, text: String\): String\? \{.*?\n    \}",
    n,
    re.S,
)
if not m3:
    raise SystemExit("guessMerchant missing")
new_gm = '''    private fun guessMerchant(title: String, text: String): String? {
        val t = title.trim()
        if (t.isNotEmpty() && !t.contains("\u652f\u4ed8\u6210\u529f") && !t.contains("\u4ed8\u6b3e\u6210\u529f")) {
            val cut = t.replace(Regex("-?\u5fae\u4fe1\u652f\u4ed8$"), "").trim()
            if (cut.isNotEmpty()) return cut
            // Align Dart merchantFromTitle: title "微信支付" stays as merchant.
            return t
        }
        val body = "$title\\n$text"
        val m = Regex("(?:\u5411|\u7ed9|\u5546\u6237)\\\\s*(.+?)(?:\\\\s|$)").find(body)
        return m?.groupValues?.getOrNull(1)?.trim()?.ifEmpty { null }
    }'''
n = n[:m3.start()] + new_gm + n[m3.end():]

np.write_text(n, encoding="utf-8", newline="\n")
print("patched NativeCaptureIngest")

# ===== CentliNotificationListener #10 #13 =====
lp = ROOT / "android/app/src/main/kotlin/com/centli/centli/CentliNotificationListener.kt"
l = lp.read_text(encoding="utf-8")
l = l.replace(
    "prefs(context).getBoolean(KEY_AUTO, true)",
    "prefs(context).getBoolean(KEY_AUTO, false)",
    1,
)

old_drain = '''        fun drainQueue(context: Context): List<Map<String, Any?>> {
            val p = prefs(context)
            val raw = p.getString(KEY_QUEUE, "[]") ?: "[]"
            p.edit().remove(KEY_QUEUE).apply()
            return try {
                val arr = JSONArray(raw)
                buildList {
                    for (i in 0 until arr.length()) {
                        val obj = arr.getJSONObject(i)
                        val map = HashMap<String, Any?>()
                        val keys = obj.keys()
                        while (keys.hasNext()) {
                            val k = keys.next()
                            map[k] = obj.opt(k)
                        }
                        add(map)
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }'''

new_drain = '''        fun peekQueue(context: Context): List<Map<String, Any?>> {
            val p = prefs(context)
            val raw = p.getString(KEY_QUEUE, "[]") ?: "[]"
            return try {
                val arr = JSONArray(raw)
                buildList {
                    for (i in 0 until arr.length()) {
                        val obj = arr.getJSONObject(i)
                        val map = HashMap<String, Any?>()
                        val keys = obj.keys()
                        while (keys.hasNext()) {
                            val k = keys.next()
                            map[k] = obj.opt(k)
                        }
                        add(map)
                    }
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        fun clearQueue(context: Context) {
            prefs(context).edit().remove(KEY_QUEUE).apply()
        }

        /** Peek then clear. Prefer [peekQueue]+[clearQueue] after successful deliver. */
        fun drainQueue(context: Context): List<Map<String, Any?>> {
            val items = peekQueue(context)
            if (items.isNotEmpty()) clearQueue(context)
            return items
        }'''

if old_drain not in l:
    raise SystemExit("drainQueue missing")
l = l.replace(old_drain, new_drain, 1)
lp.write_text(l, encoding="utf-8", newline="\n")
print("patched CentliNotificationListener")

print("p5 partial done")

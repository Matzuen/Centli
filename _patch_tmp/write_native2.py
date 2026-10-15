# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
p.write_text(p.read_text(encoding='utf-8') + '''
    private fun querySetting(db: SQLiteDatabase, key: String): String? {
        db.rawQuery(
            "SELECT value FROM app_settings WHERE key=? LIMIT 1",
            arrayOf(key),
        ).use { c ->
            return if (c.moveToFirst()) c.getString(0) else null
        }
    }

    private fun existsDedupe(db: SQLiteDatabase, key: String): Boolean {
        db.rawQuery(
            "SELECT 1 FROM pending_captures WHERE dedupe_key=? LIMIT 1",
            arrayOf(key),
        ).use { c ->
            return c.moveToFirst()
        }
    }

    private fun buildDedupeKey(
        pkg: String,
        title: String,
        text: String,
        merchant: String?,
        amountMinor: Int?,
        whenMs: Long,
        parseOk: Boolean,
    ): String {
        val bucket = whenMs / 120000L
        if (!parseOk || amountMinor == null) {
            val tip = "$title\\n$text".trim()
            val tipKey = if (tip.isEmpty()) "empty" else Integer.toHexString(tip.hashCode())
            return "$pkg|raw|$tipKey|$bucket"
        }
        val m = (merchant ?: "").trim().lowercase()
        return "$pkg|$m|$amountMinor|$bucket"
    }

    private data class Parsed(
        val amountMinor: Int?,
        val currency: String,
        val merchant: String?,
    )

    private val AMOUNT: Pattern = Pattern.compile(
        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\\\s*)?(?:\\\\u00a5|\\\\uffe5|\\\\$|\\\\u20ac)?\\\\s*([0-9]+(?:,[0-9]{3})*(?:\\\\.[0-9]{1,2})?)",
    )

    private fun parseAmount(title: String, text: String): Parsed {
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
    }

    private fun detectCurrency(body: String, start: Int, end: Int, matched: String): String {
        val windowStart = if (start > 12) start - 12 else 0
        val window = body.substring(windowStart, end)
        if (window.contains('\\u20ac') || matched.contains('\\u20ac') ||
            Regex("\\\\bEUR\\\\b", RegexOption.IGNORE_CASE).containsMatchIn(window)
        ) return "EUR"
        if (Regex("\\\\bUSD\\\\b", RegexOption.IGNORE_CASE).containsMatchIn(window) ||
            matched.uppercase().contains("USD")
        ) return "USD"
        if (Regex("\\\\bHKD\\\\b", RegexOption.IGNORE_CASE).containsMatchIn(window) ||
            window.contains("HK$") || matched.contains("HK$")
        ) return "HKD"
        if (Regex("\\\\bTWD\\\\b", RegexOption.IGNORE_CASE).containsMatchIn(window) ||
            window.contains("NT$") || matched.contains("NT$")
        ) return "TWD"
        if (Regex("\\\\bJPY\\\\b", RegexOption.IGNORE_CASE).containsMatchIn(window)) return "JPY"
        if (window.contains('$') || matched.contains('$')) return "USD"
        return "CNY"
    }

    private fun guessMerchant(title: String, text: String): String? {
        val t = title.trim()
        if (t.isNotEmpty() && !t.contains("\\u652f\\u4ed8\\u6210\\u529f") && !t.contains("\\u4ed8\\u6b3e\\u6210\\u529f")) {
            val cut = t.replace(Regex("-?\\u5fae\\u4fe1\\u652f\\u4ed8$"), "").trim()
            if (cut.isNotEmpty()) return cut
        }
        val body = "$title\\n$text"
        val m = Regex("(?:\\u5411|\\u7ed9|\\u5546\\u6237)\\\\s*(.+?)(?:\\\\s|$)").find(body)
        return m?.groupValues?.getOrNull(1)?.trim()?.ifEmpty { null }
    }

    private fun formatYuan(currency: String, minor: Int): String {
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
    }
}
''', encoding='utf-8', newline='\n')
print('done', p.stat().st_size)

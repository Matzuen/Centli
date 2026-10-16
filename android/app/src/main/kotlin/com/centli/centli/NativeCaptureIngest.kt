package com.centli.centli

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File
import java.util.UUID
import java.util.regex.Pattern

/**
 * Writes payment captures into Flutter/Drift centli.sqlite when Flutter is not alive.
 * Path: context.getDir("flutter") / centli.sqlite (path_provider getApplicationDocumentsDirectory).
 */
object NativeCaptureIngest {
    private const val TAG = "CentliNativeIngest"
    private const val DB_NAME = "centli.sqlite"

    fun ingestAndNotify(context: Context, payload: Map<String, Any?>): String? {
        val pkg = payload["pkg"] as? String ?: return null
        val title = (payload["title"] as? String).orEmpty()
        val text = (payload["text"] as? String).orEmpty()
        if (title.isBlank() && text.isBlank()) return null

        // Strict: only payment-success style notices (aligned with Dart noti_templates).
        if (!isPaymentCandidate(pkg, title, text)) {
            Log.i(TAG, "drop non-payment pkg=$pkg")
            return null
        }

        val whenMs = when (val w = payload["when"]) {
            is Long -> w
            is Int -> w.toLong()
            is Number -> w.toLong()
            else -> System.currentTimeMillis()
        }

        val dbFile = File(context.applicationContext.getDir("flutter", Context.MODE_PRIVATE), DB_NAME)
        if (!dbFile.exists()) {
            Log.w(TAG, "DB missing at ${dbFile.absolutePath}; queueing")
            CentliNotificationListener.enqueue(context, payload)
            return null
        }

        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE,
            )
            db.rawQuery("PRAGMA busy_timeout=3000", null).close()

            val enabled = querySetting(db, "auto_capture_enabled")
            if (enabled != null && enabled != "true") {
                Log.i(TAG, "auto_capture_enabled=$enabled; skip")
                return null
            }

            val ledgerId = querySetting(db, "current_ledger_id")
            if (ledgerId.isNullOrBlank()) {
                Log.w(TAG, "no current_ledger_id")
                return null
            }

            val parsed = parseAmount(title, text)
            val merchant = parsed.merchant
            val amountMinor = parsed.amountMinor
            val currency = parsed.currency
            val parseOk = amountMinor != null
            val dedupe = buildDedupeKey(pkg, title, text, merchant, amountMinor, whenMs, parseOk)

            if (existsDedupe(db, dedupe)) {
                Log.i(TAG, "dedupe hit $dedupe")
                return null
            }

            val id = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            db.execSQL(
                """
                INSERT INTO pending_captures(
                  id, ledger_id, source_pkg, raw_title, raw_text,
                  amount_minor, currency, merchant, happen_at,
                  suggested_category_id, suggested_account_id,
                  status, dedupe_key, parse_ok, created_at, updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """.trimIndent(),
                arrayOf<Any?>(
                    id, ledgerId, pkg, title.ifBlank { null }, text,
                    amountMinor, currency, merchant, whenMs,
                    null, null, "pending", dedupe,
                    if (parseOk) 1 else 0, now, now,
                ),
            )

            val pushTitle = if (amountMinor != null) {
                "待确认 ${formatYuan(currency, amountMinor)}"
            } else {
                "待确认"
            }
            PendingConfirmNotifier.show(context, id, pushTitle, merchant)
            Log.i(TAG, "inserted pending $id dedupe=$dedupe")
            return id
        } catch (e: Exception) {
            Log.e(TAG, "native ingest failed", e)
            CentliNotificationListener.enqueue(context, payload)
            return null
        } finally {
            try { db?.close() } catch (_: Exception) {}
        }
    }


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
            val tip = "$title\n$text".trim()
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

    /** Alipay mustContain — mirrors assets/noti_templates.json */
    private val MUST_ALIPAY: Pattern = Pattern.compile("支付成功|付款成功")

    /** WeChat mustContain — mirrors assets/noti_templates.json */
    private val MUST_WECHAT: Pattern = Pattern.compile("微信支付|支付成功|已支付")

    /**
     * Chat / non-payment excludes (strengthened vs Dart templates).
     * Drop message pushes, Moments, OTP, non-pay service chatter.
     */
    private val EXCLUDE_COMMON: Pattern = Pattern.compile(
        "验证码|登录|朋友圈|微信消息|发来一条|会话|拍了拍|互动消息|新的朋友|群聊|" +
            "语音通话|视频通话|收到一条|发来一个红包|领取了你的红包|收款到账提醒|服务通知|余额宝收益",
    )

    /**
     * True only when body matches payment mustContain for the package
     * and does not hit excludeText-style chat/OTP patterns.
     */
    private fun isPaymentCandidate(pkg: String, title: String, text: String): Boolean {
        val body = "$title\n$text"
        if (EXCLUDE_COMMON.matcher(body).find()) return false
        val must = when (pkg) {
            "com.eg.android.AlipayGphone" -> MUST_ALIPAY
            "com.tencent.mm" -> MUST_WECHAT
            else -> return false
        }
        return must.matcher(body).find()
    }

        private val AMOUNT: Pattern = Pattern.compile(
        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\s*|(?:[¥￥]|\\$|€))\\s*([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)",
    )

    private fun currencyDecimals(ccy: String): Int = when (ccy) {
        "JPY" -> 0
        else -> 2
    }

    private fun toMinor(ccy: String, major: Double): Int {
        val factor = Math.pow(10.0, currencyDecimals(ccy).toDouble())
        return Math.round(major * factor).toInt()
    }

    private fun parseAmount(title: String, text: String): Parsed {
        val body = "$title\n$text"
        val m = AMOUNT.matcher(body)
        while (m.find()) {
            val end = m.end()
            if (end < body.length) {
                val ch = body[end]
                if (ch == '月' || ch == '日' || ch == '号' ||
                    ch == '时' || ch == '分' || ch == '秒'
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
    }

    private fun detectCurrency(body: String, start: Int, end: Int, matched: String): String {
        val windowStart = if (start > 12) start - 12 else 0
        val window = body.substring(windowStart, end)
        if (window.contains('\u20ac') || matched.contains('\u20ac') ||
            Regex("\\bEUR\\b", RegexOption.IGNORE_CASE).containsMatchIn(window)
        ) return "EUR"
        if (Regex("\\bUSD\\b", RegexOption.IGNORE_CASE).containsMatchIn(window) ||
            matched.uppercase().contains("USD")
        ) return "USD"
        if (Regex("\\bHKD\\b", RegexOption.IGNORE_CASE).containsMatchIn(window) ||
            window.contains("HK$") || matched.contains("HK$")
        ) return "HKD"
        if (Regex("\\bTWD\\b", RegexOption.IGNORE_CASE).containsMatchIn(window) ||
            window.contains("NT$") || matched.contains("NT$")
        ) return "TWD"
        if (Regex("\\bJPY\\b", RegexOption.IGNORE_CASE).containsMatchIn(window)) return "JPY"
        if (window.contains('$') || matched.contains('$')) return "USD"
        return "CNY"
    }

    private fun guessMerchant(title: String, text: String): String? {
        val t = title.trim()
        if (t.isNotEmpty() && !t.contains("支付成功") && !t.contains("付款成功")) {
            val cut = t.replace(Regex("-?微信支付$"), "").trim()
            if (cut.isNotEmpty()) return cut
            // Align Dart merchantFromTitle: title "微信支付" stays as merchant.
            return t
        }
        val body = "$title\n$text"
        val m = Regex("(?:向|给|商户)\\s*(.+?)(?:\\s|$)").find(body)
        return m?.groupValues?.getOrNull(1)?.trim()?.ifEmpty { null }
    }

    private fun formatYuan(currency: String, minor: Int): String {
        val decimals = currencyDecimals(currency)
        val major = minor / Math.pow(10.0, decimals.toDouble())
        val symbol = when (currency) {
            "USD" -> "$"
            "EUR" -> "€"
            "JPY" -> "¥"
            else -> "¥"
        }
        return if (decimals == 0) {
            "$symbol${major.toInt()}"
        } else {
            "$symbol${"%.2f".format(major)}"
        }
    }
}

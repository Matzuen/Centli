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
        val match = matchPaymentRule(context, pkg, title, text)
        if (match == null) {
            Log.i(TAG, "drop non-payment pkg=$pkg")
            return null
        }
        // Soft-allow and hardcode paths may have null direction → default out.
        val direction = match.direction ?: "out"
        Log.d(TAG, "rule match direction=$direction soft=${match.softAllow}")
        // T2-4: carry direction on payload for queue / Flutter flush.
        val enriched = HashMap(payload)
        enriched["direction"] = direction
        @Suppress("UNCHECKED_CAST")
        (payload as? MutableMap<String, Any?>)?.put("direction", direction)

        val whenMs = when (val w = payload["when"]) {
            is Long -> w
            is Int -> w.toLong()
            is Number -> w.toLong()
            else -> System.currentTimeMillis()
        }

        val dbFile = File(context.applicationContext.getDir("flutter", Context.MODE_PRIVATE), DB_NAME)
        if (!dbFile.exists()) {
            Log.w(TAG, "DB missing at ${dbFile.absolutePath}; queueing")
            CentliNotificationListener.enqueue(context, enriched)
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
                Log.w(TAG, "no current_ledger_id; queueing")
                CentliNotificationListener.enqueue(context, enriched)
                return null
            }

            val parsed = parseAmount(title, text)
            val merchant = parsed.merchant
            val amountMinor = parsed.amountMinor
            val currency = parsed.currency
            val parseOk = amountMinor != null
            val notifKey = (payload["key"] as? String)?.takeIf { it.isNotBlank() }
            val dedupe = buildDedupeKey(
                pkg, title, text, merchant, amountMinor, whenMs, parseOk, notifKey,
            )

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
                  amount_minor, currency, note, happen_at,
                  suggested_category_id, suggested_account_id,
                  status, dedupe_key, parse_ok, direction,
                  created_at, updated_at
                ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """.trimIndent(),
                arrayOf<Any?>(
                    id, ledgerId, pkg, title.ifBlank { null }, text,
                    amountMinor, currency, merchant, whenMs,
                    null, null, "pending", dedupe,
                    if (parseOk) 1 else 0, direction, now, now,
                ),
            )

            val pushTitle = if (amountMinor != null) {
                "待确认 ${formatYuan(currency, amountMinor)}"
            } else {
                "待确认"
            }
            PendingConfirmNotifier.show(context, id, pushTitle, merchant)
            MainActivity.notifyPendingDbChanged()
            Log.i(TAG, "inserted pending $id dedupe=$dedupe")
            return id
        } catch (e: Exception) {
            Log.e(TAG, "native ingest failed", e)
            CentliNotificationListener.enqueue(context, enriched)
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
        notifKey: String?,
    ): String {
        // Same StatusBarNotification key → same event (updates / dual path).
        if (!notifKey.isNullOrBlank()) {
            return "$pkg|nk|$notifKey"
        }
        val bucket = whenMs / 120000L
        if (!parseOk || amountMinor == null) {
            val tip = "$title\n$text".trim()
            val tipKey = if (tip.isEmpty()) "empty" else Integer.toHexString(tip.hashCode())
            return "$pkg|raw|$tipKey|$bucket"
        }
        // T2-3: omit merchant (align with Dart dedupeKey).
        return "$pkg|$amountMinor|$bucket"
    }

    private data class Parsed(
        val amountMinor: Int?,
        val currency: String,
        val merchant: String?,
    )

    // G29.1: widened keyword gate; Dart noise filter drops marketing without amount.
    private val MUST_ALIPAY: Pattern = Pattern.compile("交易|支付|付款|收款|退款|红包|转账|扣款|消费|入账|到账|支出|收入|余额")
    private val MUST_WECHAT: Pattern = Pattern.compile("交易|支付|付款|收款|退款|红包|转账|扣款|消费|入账|到账|支出|收入|余额|零钱")
    private val EXCLUDE_COMMON: Pattern = Pattern.compile(
        "验证码|登录|朋友圈|微信消息|发来一条|会话|拍了拍|互动消息|新的朋友|群聊|" +
            "语音通话|视频通话|收到一条|发来一个红包|领取了你的红包|服务通知|余额宝收益|生活号|" +
            "待还|应还|请于|即将到期|还款提醒|账单提醒",
    )

    private data class RuleMatch(
        val direction: String?,
        val softAllow: Boolean = false,
    )

    /**
     * Match against Dart-synced rules_json (Scheme A).
     * - Valid rules for pkg → must/exclude from rule; first hit wins
     * - No rule for pkg → soft allow (enqueue; Dart refines when alive)
     * - Empty/bad JSON → fallback to alipay/wechat hardcode only
     * Returns null to drop.
     */
    private fun matchPaymentRule(
        context: Context,
        pkg: String,
        title: String,
        text: String,
    ): RuleMatch? {
        val body = "$title\n$text"
        val rules = loadRules(context)
        if (rules == null) {
            // Fallback hardcode
            if (EXCLUDE_COMMON.matcher(body).find()) return null
            val must = when (pkg) {
                "com.eg.android.AlipayGphone" -> MUST_ALIPAY
                "com.tencent.mm" -> MUST_WECHAT
                else -> return null
            }
            return if (must.matcher(body).find()) RuleMatch("out") else null
        }
        val forPkg = rules.filter { it.pkg == pkg }
        if (forPkg.isEmpty()) {
            // Soft allow: watched custom package with no rule body yet
            return RuleMatch(direction = "out", softAllow = true)
        }
        for (rule in forPkg) {
            try {
                val keyword = if (rule.matchOn == "body") body else title
                val exclude = rule.exclude
                if (!exclude.isNullOrBlank() && Pattern.compile(exclude).matcher(keyword).find()) {
                    continue
                }
                val must = rule.must
                if (!must.isNullOrBlank() && !Pattern.compile(must).matcher(keyword).find()) {
                    continue
                }
                val dir = when (rule.direction) {
                    "in", "out", "refund" -> rule.direction
                    else -> "out"
                }
                return RuleMatch(dir)
            } catch (e: Exception) {
                Log.w(TAG, "bad rule regex id=${rule.id}", e)
                continue
            }
        }
        return null
    }

    private data class NativeRule(
        val id: String?,
        val pkg: String,
        val direction: String?,
        val must: String?,
        val exclude: String?,
        val amount: String?,
        val merchant: String?,
        val merchantFromTitle: Boolean,
        val matchOn: String,
    )

    /** null = empty/corrupt → use hardcode fallback */
    private fun loadRules(context: Context): List<NativeRule>? {
        val raw = try {
            CentliNotificationListener.rulesJson(context)
        } catch (_: Exception) {
            null
        }
        val fromPrefs = parseRulesArray(raw)
        if (fromPrefs != null) return fromPrefs
        // Flutter has not synced yet (process started by the system). Read the
        // bundled templates so capture does not wait for the UI.
        val asset = try {
            context.assets.open("flutter_assets/assets/noti_templates.json")
                .bufferedReader().use { it.readText() }
        } catch (_: Exception) {
            null
        }
        return parseTemplateDocument(asset)
    }

    private fun parseRulesArray(raw: String?): List<NativeRule>? {
        if (raw.isNullOrBlank()) return null
        return try {
            val arr = org.json.JSONArray(raw)
            if (arr.length() == 0) return null
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val pkg = o.optString("pkg")
                    if (pkg.isBlank()) continue
                    add(
                        NativeRule(
                            id = o.optString("id").ifBlank { null },
                            pkg = pkg,
                            direction = o.optString("direction").ifBlank { "out" },
                            must = o.optString("must").ifBlank { null },
                            exclude = o.optString("exclude").ifBlank { null },
                            amount = o.optString("amount").ifBlank { null },
                            merchant = o.optString("merchant").ifBlank { null },
                            merchantFromTitle = o.optBoolean("merchantFromTitle", false),
                            matchOn = o.optString("matchOn").ifBlank { "title" },
                        ),
                    )
                }
            }.ifEmpty { null }
        } catch (e: Exception) {
            Log.w(TAG, "rules_json parse failed; fallback hardcode", e)
            null
        }
    }

    /** assets/noti_templates.json: `{ "templates": [ NotiTemplate, ... ] }`. */
    private fun parseTemplateDocument(raw: String?): List<NativeRule>? {
        if (raw.isNullOrBlank()) return null
        return try {
            val root = org.json.JSONObject(raw)
            val arr = root.optJSONArray("templates") ?: return null
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val packages = o.optJSONArray("packages") ?: continue
                    val matchOn = o.optString("matchOn").ifBlank { "title" }
                    for (p in 0 until packages.length()) {
                        val pkg = packages.optString(p)
                        if (pkg.isBlank()) continue
                        add(
                            NativeRule(
                                id = o.optString("id").ifBlank { null },
                                pkg = pkg,
                                direction = o.optString("direction").ifBlank { "out" },
                                must = o.optString("mustContainRegex").ifBlank { null },
                                exclude = o.optString("excludeTextRegex").ifBlank { null },
                                amount = o.optString("amountRegex").ifBlank { null },
                                merchant = o.optString("merchantRegex").ifBlank { null },
                                merchantFromTitle = o.optBoolean("merchantFromTitle", false),
                                matchOn = matchOn,
                            ),
                        )
                    }
                }
            }.ifEmpty { null }
        } catch (e: Exception) {
            Log.w(TAG, "bundled templates unreadable", e)
            null
        }
    }

    /** Currency symbol / code prefix (align Dart [kAmountRegex]). */
    private val AMOUNT: Pattern = Pattern.compile(
        "(?:(?:USD|EUR|CNY|HKD|TWD|JPY)\\s*|(?:[¥￥]|\\$|€))\\s*([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)",
    )

    /** Number + 元 suffix (align Dart [kAmountRegexYuan], e.g. 抖音支付 24.70元). */
    private val AMOUNT_YUAN: Pattern = Pattern.compile(
        "([0-9]+(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?)\\s*元",
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
        parseAmountWith(body, AMOUNT, title, text, symbolPrefix = true)?.let { return it }
        parseAmountWith(body, AMOUNT_YUAN, title, text, symbolPrefix = false)?.let { return it }
        return Parsed(null, "CNY", guessMerchant(title, text))
    }

    private fun parseAmountWith(
        body: String,
        pattern: Pattern,
        title: String,
        text: String,
        symbolPrefix: Boolean,
    ): Parsed? {
        val m = pattern.matcher(body)
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
            val major = raw.toDoubleOrNull() ?: continue
            val currency = if (symbolPrefix) {
                detectCurrency(body, m.start(), m.end(), m.group(0) ?: "")
            } else {
                "CNY"
            }
            return Parsed(toMinor(currency, major), currency, guessMerchant(title, text))
        }
        return null
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
        // Generic Alipay/WeChat pay titles are not merchants.
        val genericTitle = t.contains("支付成功") || t.contains("付款成功") ||
            t.contains("交易提醒") || t.contains("交易通知") || t.contains("交易成功") ||
            t.contains("消费成功") || t.contains("扣款成功") || t.contains("扣款提醒") ||
            t == "支付宝" || t == "微信支付"
        if (t.isNotEmpty() && !genericTitle) {
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

package com.centli.centli

import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.util.Log
import android.widget.Toast
import java.io.File
import java.util.UUID
import java.util.regex.Pattern

/**
 * Notification action receiver: 入账 / 改金额 (RemoteInput) / 忽略 without opening App (G29.2).
 *
 * Schema note: pending_captures stores merchant text in [note] (v8 removed the
 * merchant column). Selecting `merchant` silently failed every 入账 tap.
 */
class PendingActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val pendingId = intent.getStringExtra(EXTRA_PENDING_ID)
        if (pendingId.isNullOrBlank()) {
            Log.w(TAG, "missing pendingId action=${intent.action}")
            return
        }
        // DB work can exceed the default 10s broadcast budget on cold start.
        val pending = goAsync()
        try {
            when (intent.action) {
                ACTION_CONFIRM -> confirm(context, pendingId, amountOverride = null)
                ACTION_IGNORE -> ignore(context, pendingId)
                ACTION_SET_AMOUNT -> {
                    val results: Bundle? = RemoteInput.getResultsFromIntent(intent)
                    val raw = results?.getCharSequence(KEY_AMOUNT_INPUT)?.toString().orEmpty()
                    val minor = parseAmountMinor(raw)
                    if (minor == null) {
                        Toast.makeText(context, "没看懂金额", Toast.LENGTH_SHORT).show()
                        return
                    }
                    confirm(context, pendingId, amountOverride = minor)
                }
                else -> Log.w(TAG, "unknown action=${intent.action}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "action failed", e)
            Toast.makeText(context, "操作失败", Toast.LENGTH_SHORT).show()
        } finally {
            pending.finish()
        }
    }

    companion object {
        const val ACTION_CONFIRM = "com.centli.centli.action.CONFIRM"
        const val ACTION_IGNORE = "com.centli.centli.action.IGNORE"
        const val ACTION_SET_AMOUNT = "com.centli.centli.action.SET_AMOUNT"
        const val EXTRA_PENDING_ID = "pendingId"
        const val KEY_AMOUNT_INPUT = "centli_amount_input"
        private const val TAG = "CentliPendingAction"
        private const val DB_NAME = "centli.sqlite"

        /** Unique requestCode = notifId + actionIndex (0/1/2). */
        fun requestCode(pendingId: String, actionIndex: Int): Int =
            ((pendingId.hashCode() and 0x7fffffff) + actionIndex * 100_000_003) and 0x7fffffff

        fun parseAmountMinor(raw: String): Int? {
            val m = Pattern.compile("(\\d+(?:[.,]\\d{1,2})?)").matcher(raw.replace(",", ""))
            if (!m.find()) return null
            val major = m.group(1)?.replace(",", "")?.toDoubleOrNull() ?: return null
            return Math.round(major * 100.0).toInt()
        }

        private fun openDb(context: Context): SQLiteDatabase? {
            val dbFile = File(context.applicationContext.getDir("flutter", Context.MODE_PRIVATE), DB_NAME)
            if (!dbFile.exists()) {
                Log.e(TAG, "DB missing at ${dbFile.absolutePath}")
                return null
            }
            return try {
                SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE).also {
                    it.rawQuery("PRAGMA busy_timeout=3000", null).close()
                }
            } catch (e: Exception) {
                Log.e(TAG, "openDb", e)
                null
            }
        }

        private fun ignore(context: Context, pendingId: String) {
            val db = openDb(context)
            if (db == null) {
                Toast.makeText(context, "忽略失败：数据库不可用", Toast.LENGTH_SHORT).show()
                return
            }
            try {
                val now = System.currentTimeMillis()
                val updated = db.compileStatement(
                    "UPDATE pending_captures SET status=?, updated_at=? WHERE id=? AND status=?",
                ).use { stmt ->
                    stmt.bindString(1, "ignored")
                    stmt.bindLong(2, now)
                    stmt.bindString(3, pendingId)
                    stmt.bindString(4, "pending")
                    stmt.executeUpdateDelete()
                }
                PendingConfirmNotifier.cancel(context, pendingId)
                Toast.makeText(
                    context,
                    if (updated > 0) "已忽略" else "记录已处理",
                    Toast.LENGTH_SHORT,
                ).show()
            } catch (e: Exception) {
                Log.e(TAG, "ignore failed", e)
                Toast.makeText(context, "忽略失败", Toast.LENGTH_SHORT).show()
            } finally {
                db.close()
            }
        }

        private fun confirm(context: Context, pendingId: String, amountOverride: Int?) {
            val db = openDb(context)
            if (db == null) {
                Toast.makeText(context, "入账失败：数据库不可用", Toast.LENGTH_SHORT).show()
                return
            }
            try {
                val c = db.rawQuery(
                    """
                    SELECT ledger_id, amount_minor, currency, note, happen_at,
                           suggested_account_id, suggested_category_id, source_pkg, raw_title,
                           direction, status
                    FROM pending_captures WHERE id=? LIMIT 1
                    """.trimIndent(),
                    arrayOf(pendingId),
                )
                if (!c.moveToFirst()) {
                    c.close()
                    PendingConfirmNotifier.cancel(context, pendingId)
                    Toast.makeText(context, "记录不存在", Toast.LENGTH_SHORT).show()
                    return
                }
                val status = c.getString(10)
                val ledgerId = c.getString(0)
                var amountMinor = if (c.isNull(1)) null else c.getInt(1)
                val currency = c.getString(2) ?: "CNY"
                val note = if (c.isNull(3)) null else c.getString(3)
                val happenAt = if (c.isNull(4)) System.currentTimeMillis() else c.getLong(4)
                val accountHintId = if (c.isNull(5)) null else c.getString(5)
                val categoryHintId = if (c.isNull(6)) null else c.getString(6)
                val sourcePkg = if (c.isNull(7)) null else c.getString(7)
                val rawTitle = if (c.isNull(8)) null else c.getString(8)
                val direction = if (c.isNull(9)) null else c.getString(9)
                c.close()

                if (status != null && status != "pending") {
                    PendingConfirmNotifier.cancel(context, pendingId)
                    Toast.makeText(context, "记录已处理", Toast.LENGTH_SHORT).show()
                    return
                }

                if (amountOverride != null) {
                    amountMinor = amountOverride
                    db.execSQL(
                        "UPDATE pending_captures SET amount_minor=?, updated_at=? WHERE id=?",
                        arrayOf<Any?>(amountOverride, System.currentTimeMillis(), pendingId),
                    )
                }

                if (amountMinor == null) {
                    PendingConfirmNotifier.show(
                        context,
                        pendingId,
                        "金额未知，点「改金额」",
                        note ?: rawTitle,
                    )
                    Toast.makeText(context, "请先填写金额", Toast.LENGTH_SHORT).show()
                    return
                }

                val type = txnType(direction)
                // Refunds reduce expense, so they take an expense category —
                // same rule as the Dart sheet (_catsForDirection: only 'in'
                // when direction == "in").
                val categoryKind = if (type == "in") "in" else "out"
                val include = if (direction == "repay") 0 else 1
                val accountId = resolveAccountId(db, ledgerId, accountHintId, sourcePkg)
                if (accountId == null) {
                    Toast.makeText(context, "入账失败：没有可用账户", Toast.LENGTH_SHORT).show()
                    return
                }
                val categoryId = resolveCategoryId(db, ledgerId, categoryKind, categoryHintId)
                val now = System.currentTimeMillis()
                val txnId = UUID.randomUUID().toString()
                val values = ContentValues().apply {
                    put("id", txnId)
                    put("ledger_id", ledgerId)
                    put("type", type)
                    put("amount_minor", amountMinor)
                    put("currency", currency)
                    put("account_id", accountId)
                    if (categoryId != null) put("category_id", categoryId) else putNull("category_id")
                    put("happen_at", happenAt)
                    put("note", note)
                    put("source", "noti_action")
                    putNull("occurrence_key")
                    put("include_in_stat", include)
                    put("include_in_budget", include)
                    put("created_at", now)
                    put("updated_at", now)
                    put("pending_id", pendingId)
                }
                db.beginTransaction()
                try {
                    db.insertOrThrow("transactions", null, values)
                    db.execSQL(
                        "UPDATE pending_captures SET status=?, amount_minor=?, updated_at=? WHERE id=?",
                        arrayOf<Any?>("confirmed", amountMinor, now, pendingId),
                    )
                    db.setTransactionSuccessful()
                } finally {
                    db.endTransaction()
                }
                PendingConfirmNotifier.cancel(context, pendingId)
                Toast.makeText(
                    context,
                    "已入账 ¥${"%.2f".format(amountMinor / 100.0)}",
                    Toast.LENGTH_SHORT,
                ).show()
            } catch (e: Exception) {
                Log.e(TAG, "confirm failed", e)
                Toast.makeText(context, "入账失败", Toast.LENGTH_SHORT).show()
            } finally {
                db.close()
            }
        }

        private fun txnType(direction: String?): String = when (direction) {
            "in" -> "in"
            "refund" -> "refund"
            else -> "out" // out / repay / null
        }

        private fun resolveAccountId(
            db: SQLiteDatabase,
            ledgerId: String,
            hintId: String?,
            sourcePkg: String?,
        ): String? {
            if (!hintId.isNullOrBlank()) {
                db.rawQuery(
                    "SELECT id FROM accounts WHERE id=? AND ledger_id=? AND archived=0 LIMIT 1",
                    arrayOf(hintId, ledgerId),
                ).use { c ->
                    if (c.moveToFirst()) return c.getString(0)
                }
            }
            val nameHint = when {
                sourcePkg?.contains("Alipay", true) == true ||
                    sourcePkg?.contains("alipay", true) == true -> "支付宝"
                sourcePkg?.contains("tencent.mm") == true -> "微信"
                else -> null
            }
            if (nameHint != null) {
                db.rawQuery(
                    "SELECT id FROM accounts WHERE ledger_id=? AND name=? AND archived=0 LIMIT 1",
                    arrayOf(ledgerId, nameHint),
                ).use { c ->
                    if (c.moveToFirst()) return c.getString(0)
                }
            }
            db.rawQuery(
                "SELECT id FROM accounts WHERE ledger_id=? AND archived=0 ORDER BY sort_order ASC LIMIT 1",
                arrayOf(ledgerId),
            ).use { c ->
                if (c.moveToFirst()) return c.getString(0)
            }
            return null
        }

        private fun resolveCategoryId(
            db: SQLiteDatabase,
            ledgerId: String,
            kind: String,
            hintId: String?,
        ): String? {
            if (!hintId.isNullOrBlank()) {
                // The hint must also match the direction's kind, otherwise an
                // income id could be attached to an expense (or the reverse).
                db.rawQuery(
                    "SELECT id FROM categories WHERE id=? AND ledger_id=? AND kind=? LIMIT 1",
                    arrayOf(hintId, ledgerId, kind),
                ).use { c ->
                    if (c.moveToFirst()) return c.getString(0)
                }
            }
            db.rawQuery(
                "SELECT id FROM categories WHERE ledger_id=? AND kind=? ORDER BY sort_order ASC LIMIT 1",
                arrayOf(ledgerId, kind),
            ).use { c ->
                if (c.moveToFirst()) return c.getString(0)
            }
            return null
        }
    }
}

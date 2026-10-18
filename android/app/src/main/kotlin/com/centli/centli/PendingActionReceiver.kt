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
 */
class PendingActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val pendingId = intent.getStringExtra(EXTRA_PENDING_ID) ?: return
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
            if (!dbFile.exists()) return null
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
            val db = openDb(context) ?: return
            try {
                val now = System.currentTimeMillis()
                db.execSQL(
                    "UPDATE pending_captures SET status=?, updated_at=? WHERE id=?",
                    arrayOf<Any?>("ignored", now, pendingId),
                )
                PendingConfirmNotifier.cancel(context, pendingId)
            } catch (e: Exception) {
                Log.e(TAG, "ignore failed", e)
            } finally {
                db.close()
            }
        }

        private fun confirm(context: Context, pendingId: String, amountOverride: Int?) {
            val db = openDb(context) ?: return
            try {
                val c = db.rawQuery(
                    """
                    SELECT ledger_id, amount_minor, currency, merchant, happen_at,
                           suggested_account_id, suggested_category_id, source_pkg, raw_title
                    FROM pending_captures WHERE id=? LIMIT 1
                    """.trimIndent(),
                    arrayOf(pendingId),
                )
                if (!c.moveToFirst()) {
                    c.close()
                    return
                }
                val ledgerId = c.getString(0)
                var amountMinor = if (c.isNull(1)) null else c.getInt(1)
                val currency = c.getString(2) ?: "CNY"
                val merchant = if (c.isNull(3)) null else c.getString(3)
                val happenAt = if (c.isNull(4)) System.currentTimeMillis() else c.getLong(4)
                val accountHintId = if (c.isNull(5)) null else c.getString(5)
                val categoryHintId = if (c.isNull(6)) null else c.getString(6)
                val sourcePkg = if (c.isNull(7)) null else c.getString(7)
                val rawTitle = if (c.isNull(8)) null else c.getString(8)
                c.close()

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
                        merchant ?: rawTitle,
                    )
                    return
                }

                val type = "out" // pending confirm from pay notifs defaults out; direction not always stored
                val accountId = resolveAccountId(db, ledgerId, accountHintId, sourcePkg)
                val categoryId = resolveCategoryId(db, ledgerId, type, categoryHintId)
                val now = System.currentTimeMillis()
                val txnId = UUID.randomUUID().toString()
                val note = merchant
                val values = ContentValues().apply {
                    put("id", txnId)
                    put("ledger_id", ledgerId)
                    put("type", type)
                    put("amount_minor", amountMinor)
                    put("currency", currency)
                    put("account_id", accountId)
                    put("category_id", categoryId)
                    put("happen_at", happenAt)
                    put("note", note)
                    put("source", "noti_action")
                    putNull("occurrence_key")
                    put("include_in_stat", 1)
                    put("include_in_budget", 1)
                    put("created_at", now)
                    put("updated_at", now)
                    put("pending_id", pendingId)
                }
                db.insertOrThrow("transactions", null, values)
                db.execSQL(
                    "UPDATE pending_captures SET status=?, updated_at=? WHERE id=?",
                    arrayOf<Any?>("confirmed", now, pendingId),
                )
                PendingConfirmNotifier.cancel(context, pendingId)
                Toast.makeText(
                    context,
                    "已入账 ¥${"%.2f".format(amountMinor / 100.0)}",
                    Toast.LENGTH_SHORT,
                ).show()
            } catch (e: Exception) {
                Log.e(TAG, "confirm failed", e)
            } finally {
                db.close()
            }
        }

        private fun resolveAccountId(
            db: SQLiteDatabase,
            ledgerId: String,
            hintId: String?,
            sourcePkg: String?,
        ): String {
            if (!hintId.isNullOrBlank()) {
                val c = db.rawQuery(
                    "SELECT id FROM accounts WHERE id=? AND ledger_id=? AND archived=0 LIMIT 1",
                    arrayOf(hintId, ledgerId),
                )
                if (c.moveToFirst()) {
                    val id = c.getString(0)
                    c.close()
                    return id
                }
                c.close()
            }
            val nameHint = when {
                sourcePkg?.contains("Alipay", true) == true ||
                    sourcePkg?.contains("alipay", true) == true -> "支付宝"
                sourcePkg?.contains("tencent.mm") == true -> "微信"
                else -> null
            }
            if (nameHint != null) {
                val c = db.rawQuery(
                    "SELECT id FROM accounts WHERE ledger_id=? AND name=? AND archived=0 LIMIT 1",
                    arrayOf(ledgerId, nameHint),
                )
                if (c.moveToFirst()) {
                    val id = c.getString(0)
                    c.close()
                    return id
                }
                c.close()
            }
            val c = db.rawQuery(
                "SELECT id FROM accounts WHERE ledger_id=? AND archived=0 ORDER BY sort_order ASC LIMIT 1",
                arrayOf(ledgerId),
            )
            if (c.moveToFirst()) {
                val id = c.getString(0)
                c.close()
                return id
            }
            c.close()
            // Last resort: any account
            val c2 = db.rawQuery(
                "SELECT id FROM accounts WHERE ledger_id=? AND archived=0 LIMIT 1",
                arrayOf(ledgerId),
            )
            val id = if (c2.moveToFirst()) c2.getString(0) else "missing-account"
            c2.close()
            return id
        }

        private fun resolveCategoryId(
            db: SQLiteDatabase,
            ledgerId: String,
            type: String,
            hintId: String?,
        ): String? {
            if (!hintId.isNullOrBlank()) {
                val c = db.rawQuery(
                    "SELECT id FROM categories WHERE id=? AND ledger_id=? LIMIT 1",
                    arrayOf(hintId, ledgerId),
                )
                if (c.moveToFirst()) {
                    val id = c.getString(0)
                    c.close()
                    return id
                }
                c.close()
            }
            val c = db.rawQuery(
                "SELECT id FROM categories WHERE ledger_id=? AND kind=? ORDER BY sort_order ASC LIMIT 1",
                arrayOf(ledgerId, type),
            )
            val id = if (c.moveToFirst()) c.getString(0) else null
            c.close()
            return id
        }
    }
}

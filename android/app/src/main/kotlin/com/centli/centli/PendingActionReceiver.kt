package com.centli.centli

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import android.widget.Toast
import java.io.File
import java.util.regex.Pattern

/**
 * Notification action receiver.
 *
 * - 「忽略」: mark pending ignored without opening the UI.
 * - Legacy 「入账」/「改金额」: open MainActivity for in-app confirmation
 *   (direct bookkeeping from the shade was removed — user must confirm).
 *
 * Schema note: pending_captures stores merchant text in [note] (v8 removed the
 * merchant column).
 */
class PendingActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent == null) return
        val pendingId = intent.getStringExtra(EXTRA_PENDING_ID)
        if (pendingId.isNullOrBlank()) {
            Log.w(TAG, "missing pendingId action=${intent.action}")
            return
        }
        when (intent.action) {
            ACTION_IGNORE -> {
                val pending = goAsync()
                try {
                    ignore(context, pendingId)
                    MainActivity.notifyPendingDbChanged()
                } catch (e: Exception) {
                    Log.e(TAG, "ignore failed", e)
                    Toast.makeText(context, "操作失败", Toast.LENGTH_SHORT).show()
                } finally {
                    pending.finish()
                }
            }
            // Legacy actions from older notification payloads: open confirm UI.
            ACTION_CONFIRM, ACTION_SET_AMOUNT -> openReview(context, pendingId)
            else -> Log.w(TAG, "unknown action=${intent.action}")
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

        private fun openReview(context: Context, pendingId: String) {
            val app = context.applicationContext
            val launch = Intent(app, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(PendingConfirmNotifier.EXTRA_OPEN, "/home/pending")
                putExtra(PendingConfirmNotifier.EXTRA_PENDING_ID, pendingId)
                putExtra(PendingConfirmNotifier.EXTRA_REVIEW, true)
            }
            app.startActivity(launch)
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
    }
}

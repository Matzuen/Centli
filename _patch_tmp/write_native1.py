# -*- coding: utf-8 -*-
from pathlib import Path
p = Path(r"D:\Resource\Codebase\studyProject\Centli\android\app\src\main\kotlin\com\centli\centli\NativeCaptureIngest.kt")
# Write part 1
p.write_text('''package com.centli.centli

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File
import java.util.UUID
import java.util.regex.Pattern

/**
 * Writes payment captures into Flutter/Drift centli.sqlite when Flutter is not alive.
 * Path: context.filesDir / centli.sqlite (path_provider documents dir on Android).
 */
object NativeCaptureIngest {
    private const val TAG = "CentliNativeIngest"
    private const val DB_NAME = "centli.sqlite"

    fun ingestAndNotify(context: Context, payload: Map<String, Any?>): String? {
        val pkg = payload["pkg"] as? String ?: return null
        val title = (payload["title"] as? String).orEmpty()
        val text = (payload["text"] as? String).orEmpty()
        if (title.isBlank() && text.isBlank()) return null

        val whenMs = when (val w = payload["when"]) {
            is Long -> w
            is Int -> w.toLong()
            is Number -> w.toLong()
            else -> System.currentTimeMillis()
        }

        val dbFile = File(context.applicationContext.filesDir, DB_NAME)
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
                arrayOf(
                    id, ledgerId, pkg, title.ifBlank { null }, text,
                    amountMinor, currency, merchant, whenMs,
                    null, null, "pending", dedupe,
                    if (parseOk) 1 else 0, now, now,
                ),
            )

            val pushTitle = if (amountMinor != null) {
                "\u5f85\u786e\u8ba4 ${formatYuan(currency, amountMinor)}"
            } else {
                "\u5f85\u786e\u8ba4"
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

''', encoding='utf-8', newline='\n')
print('part1', p.stat().st_size)

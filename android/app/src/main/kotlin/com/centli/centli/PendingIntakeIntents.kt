package com.centli.centli

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * Extract share / deep-link payloads for Flutter [pending_intake].
 */
object PendingIntakeIntents {
    private const val TAG = "CentliPendingIntake"
    private const val PREF = "centli_pending_intake"
    private const val KEY_QUEUE = "queue_json"

    data class Payload(
        val kind: String,
        val text: String? = null,
        val title: String? = null,
        val imagePath: String? = null,
        val uri: String? = null,
    ) {
        fun toMap(): HashMap<String, Any?> = hashMapOf(
            "kind" to kind,
            "text" to text,
            "title" to title,
            "imagePath" to imagePath,
            "uri" to uri,
        )
    }

    fun fromIntent(context: Context, intent: Intent?): Payload? {
        if (intent == null) return null
        val action = intent.action ?: return null

        if (action == Intent.ACTION_VIEW) {
            val data = intent.data ?: return null
            if (data.scheme.equals("centli", ignoreCase = true)) {
                return Payload(kind = "uri", uri = data.toString())
            }
            return null
        }

        if (action == Intent.ACTION_SEND || action == Intent.ACTION_SEND_MULTIPLE) {
            val type = intent.type ?: ""
            if (type.startsWith("text/")) {
                val text = intent.getStringExtra(Intent.EXTRA_TEXT)
                    ?: intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                if (!text.isNullOrBlank()) {
                    return Payload(kind = "text", text = text, title = subject)
                }
            }
            if (type.startsWith("image/") || type == "*/*") {
                val uri = extractStreamUri(intent) ?: return null
                val path = copyUriToCache(context, uri) ?: return null
                return Payload(kind = "image", imagePath = path)
            }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun extractStreamUri(intent: Intent): Uri? {
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            return list?.firstOrNull()
        }
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun copyUriToCache(context: Context, uri: Uri): String? {
        return try {
            val dir = File(context.cacheDir, "shared_intake")
            if (!dir.exists()) dir.mkdirs()
            val name = "share_${System.currentTimeMillis()}.img"
            val outFile = File(dir, name)
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output ->
                    input.copyTo(output)
                }
            } ?: return null
            outFile.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "copy shared image failed", e)
            null
        }
    }

    /** Queue one payload while Flutter channel is not ready. */
    fun enqueue(context: Context, payload: Payload) {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val existing = prefs.getString(KEY_QUEUE, null)
        // Keep only the latest intake to avoid surprise multi-ingest on cold start.
        val encoded = listOf(
            payload.kind,
            payload.text ?: "",
            payload.title ?: "",
            payload.imagePath ?: "",
            payload.uri ?: "",
        ).joinToString("\u0001")
        prefs.edit().putString(KEY_QUEUE, encoded).apply()
        if (existing != null) {
            Log.d(TAG, "replaced queued pending intake")
        }
    }

    fun drain(context: Context): Payload? {
        val prefs = context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
        val encoded = prefs.getString(KEY_QUEUE, null) ?: return null
        prefs.edit().remove(KEY_QUEUE).apply()
        val parts = encoded.split("\u0001")
        if (parts.isEmpty()) return null
        return Payload(
            kind = parts.getOrElse(0) { "" },
            text = parts.getOrNull(1)?.ifEmpty { null },
            title = parts.getOrNull(2)?.ifEmpty { null },
            imagePath = parts.getOrNull(3)?.ifEmpty { null },
            uri = parts.getOrNull(4)?.ifEmpty { null },
        ).takeIf { it.kind.isNotEmpty() }
    }
}

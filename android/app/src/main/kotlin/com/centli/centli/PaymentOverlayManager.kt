package com.centli.centli

import android.app.Activity
import android.app.AppOpsManager
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.sqlite.SQLiteDatabase
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import android.text.Editable
import android.text.TextWatcher
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.io.File
import java.lang.ref.WeakReference
import java.util.Locale
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * LiteNote 式支付悬浮窗：在其他 App 上层弹出待确认卡片，
 * 可选分类后快速入账，或打开 App / 忽略 / 稍后。
 *
 * 需要 [Settings.canDrawOverlays]；未授权时静默跳过（仍有系统通知）。
 */
object PaymentOverlayManager {
    private const val TAG = "CentliPayOverlay"
    private const val PREFS = "centli_payment_overlay"
    private const val KEY_ENABLED = "overlay_enabled"
    private const val KEY_LAST_CATEGORY = "last_category_id"
    private const val KEY_LAST_ACCOUNT = "last_account_id"
    private const val KEY_LAST_TO_ACCOUNT = "last_to_account_id"
    private const val DB_NAME = "centli.sqlite"
    private const val AUTO_DISMISS_MS = 60_000L
    private const val SUCCESS_DISMISS_MS = 1_400L
    private const val CATEGORIES_PER_ROW = 3
    private const val ACCOUNTS_PER_ROW = 3
    /** 账户 / 分类网格最多露出两行，其余可滚动。 */
    private const val MAX_VISIBLE_ROWS = 2
    private const val KEY_LAST_PERM_TOAST = "last_perm_toast_ms"
    private const val PERM_TOAST_COOLDOWN_MS = 30_000L

    private val mainHandler = Handler(Looper.getMainLooper())
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    /**
     * 所有曾 [WindowManager.addView] 成功的实例。息屏时 remove 常失败但仍会把
     * [overlayView] 置空，解锁后旧窗变僵尸、新窗再叠一层——所以必须靠这份名单强拆。
     */
    /** Cap zombie pile-up if remove keeps failing (GONE leftovers). */
    private const val MAX_TRACKED_WM_VIEWS = 4

    private val trackedWmViews = mutableListOf<View>()
    private var deferredShowRunnable: Runnable? = null
    private var autoDismiss: Runnable? = null
    private var selectedCategoryId: String? = null
    private var selectedCategoryName: String? = null
    private var selectedAccountId: String? = null
    private var selectedAccountName: String? = null
    private var selectedToAccountId: String? = null
    private var selectedToAccountName: String? = null
    private var suggestedAccountId: String? = null
    private var selectedDirection: String = "out"
    private var overlayCurrency: String = "CNY"
    private var allCategories: List<Category> = emptyList()
    private var allAccounts: List<Account> = emptyList()
    private var overlayPendingLedgerId: String? = null
    /** null = showing root (L1); non-null = showing children of this parent (L2). */
    private var browsingParentId: String? = null
    private val categoryViews = mutableListOf<Pair<TextView, Category>>()
    private val accountViews = mutableListOf<Pair<TextView, Account>>()
    private val toAccountViews = mutableListOf<Pair<TextView, Account>>()
    private var hostActivity: WeakReference<Activity>? = null

    /** 锁屏期间推迟弹出；解锁后再 show，避免 WM 窗在解锁后变成「看得见但关不掉」。 */
    private var deferredShow: DeferredShow? = null
    /** 当前正在展示的那一笔；锁屏时挪到 [deferredShow]，解锁后重建新窗。 */
    private var activeShow: DeferredShow? = null
    private val unlockReceiverRegistered = AtomicBoolean(false)

    private data class DeferredShow(
        val pendingId: String,
        val amountMinor: Int?,
        val currency: String,
        val sourcePkg: String,
        val merchant: String?,
        val direction: String?,
    )

    private val unlockReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent?) {
            val action = intent?.action ?: return
            val app = context.applicationContext
            when (action) {
                Intent.ACTION_SCREEN_OFF -> mainHandler.post {
                    // 亮屏弹出 → 息屏锁屏：先记下并尽力拆窗（息屏时 OEM 常 remove 失败）。
                    parkOverlayForLock(app, reason = "screen_off")
                }
                Intent.ACTION_USER_PRESENT -> mainHandler.post {
                    // SCREEN_OFF 可能没收齐；解锁后再 park，并强拆名单里所有旧 WM 窗。
                    parkOverlayForLock(app, reason = "user_present")
                    purgeAllTrackedWmViews(app, reason = "user_present")
                    forceRemoveOrphanOverlay(app)
                    val pending = deferredShow ?: return@post
                    // 等锁屏动画 / WM 稳定后再弹，否则 remove 与 add 抢同一帧，旧窗仍在。
                    scheduleDeferredShow(app, pending, delayMs = 280L)
                }
            }
        }
    }

    data class Category(
        val id: String,
        val name: String,
        val parentId: String? = null,
    )

    data class Account(
        val id: String,
        val name: String,
        val currency: String,
        val ledgerId: String = "",
        val ledgerName: String = "",
    ) {
        fun displayLabel(currentLedgerId: String?): String {
            if (ledgerName.isBlank()) return name
            if (currentLedgerId != null && ledgerId == currentLedgerId) return name
            return "$name · $ledgerName"
        }
    }

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (!enabled) dismiss()
    }

    /**
     * Overlay permission. Prefer [Settings.canDrawOverlays]; fall back to AppOps
     * because some OEMs / Android 8 report false even after the user granted it.
     */
    fun hasPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val app = context.applicationContext
        if (Settings.canDrawOverlays(app)) return true
        return try {
            val appOps = app.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                    Process.myUid(),
                    app.packageName,
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                    Process.myUid(),
                    app.packageName,
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.w(TAG, "AppOps overlay check failed", e)
            false
        }
    }

    fun openPermissionSettings(context: Context) {
        val app = context.applicationContext
        val pkg = app.packageName
        // OEM-specific pages often include「后台弹出界面」which WindowManager needs.
        val oem = oemOverlaySettingsIntent(app, pkg)
        if (oem != null) {
            try {
                app.startActivity(oem)
                return
            } catch (e: Exception) {
                Log.w(TAG, "OEM overlay settings failed", e)
            }
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            app.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$pkg"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (e: Exception) {
            Log.e(TAG, "open overlay settings", e)
            try {
                app.startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$pkg")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    },
                )
            } catch (_: Exception) {
            }
        }
    }

    private fun oemOverlaySettingsIntent(context: Context, pkg: String): Intent? {
        val maker = Build.MANUFACTURER.lowercase(Locale.ROOT)
        val brand = Build.BRAND.lowercase(Locale.ROOT)
        val candidates = ArrayList<Intent>()
        if (maker.contains("xiaomi") || brand.contains("xiaomi") ||
            brand.contains("redmi") || brand.contains("poco")
        ) {
            candidates += Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.PermissionsEditorActivity",
                )
                putExtra("extra_pkgname", pkg)
            }
            candidates += Intent("miui.intent.action.APP_PERM_EDITOR").apply {
                setClassName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.permissions.AppPermissionsEditorActivity",
                )
                putExtra("extra_pkgname", pkg)
            }
        }
        if (maker.contains("huawei") || brand.contains("huawei") ||
            maker.contains("honor") || brand.contains("honor")
        ) {
            candidates += Intent().apply {
                setClassName(
                    "com.huawei.systemmanager",
                    "com.huawei.permissionmanager.ui.MainActivity",
                )
            }
        }
        if (maker.contains("oppo") || brand.contains("oppo") ||
            brand.contains("realme") || maker.contains("oneplus")
        ) {
            candidates += Intent().apply {
                setClassName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.floatwindow.FloatWindowListActivity",
                )
            }
            candidates += Intent().apply {
                setClassName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.PermissionTopActivity",
                )
            }
        }
        if (maker.contains("vivo") || brand.contains("vivo") || brand.contains("iqoo")) {
            candidates += Intent().apply {
                setClassName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.SoftPermissionDetailActivity",
                )
                putExtra("packagename", pkg)
            }
        }
        for (intent in candidates) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent.resolveActivity(context.packageManager) != null) return intent
        }
        return null
    }

    /** Load pending row and show overlay (Flutter push path). */
    fun showFromPendingId(context: Context, pendingId: String) {
        Thread {
            val db = openDb(context) ?: return@Thread
            try {
                db.rawQuery(
                    """
                    SELECT amount_minor, currency, source_pkg, note, direction
                    FROM pending_captures WHERE id=? AND status='pending' LIMIT 1
                    """.trimIndent(),
                    arrayOf(pendingId),
                ).use { c ->
                    if (!c.moveToFirst()) return@Thread
                    val amountMinor = if (c.isNull(0)) null else c.getInt(0)
                    val currency = c.getString(1) ?: "CNY"
                    val pkg = c.getString(2) ?: ""
                    val merchant = c.getString(3)
                    val direction = c.getString(4)
                    showPending(
                        context,
                        pendingId = pendingId,
                        amountMinor = amountMinor,
                        currency = currency,
                        sourcePkg = pkg,
                        merchant = merchant,
                        direction = direction,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "showFromPendingId", e)
            } finally {
                db.close()
            }
        }.start()
    }

    /**
     * Show overlay after a pending row is created.
     *
     * Do **not** early-return solely on [hasPermission]: some OEMs report false
     * while WindowManager / Activity still works. Try WM → Activity → toast.
     */
    /** 资产锁开启时不走悬浮窗/锁屏全屏，避免绕过 PIN。 */
    fun isAppLockEnabled(context: Context): Boolean {
        val db = openDb(context) ?: return false
        return try {
            querySetting(db, "app_lock") == "true"
        } catch (_: Exception) {
            false
        } finally {
            try {
                db.close()
            } catch (_: Exception) {
            }
        }
    }

    fun showPending(
        context: Context,
        pendingId: String,
        amountMinor: Int?,
        currency: String,
        sourcePkg: String,
        merchant: String?,
        direction: String?,
    ) {
        if (!isEnabled(context)) {
            Log.i(TAG, "overlay disabled by user; skip")
            return
        }
        if (isAppLockEnabled(context)) {
            Log.i(TAG, "app_lock on; skip overlay (use in-app confirm)")
            return
        }

        val app = context.applicationContext
        val amountMajor = if (amountMinor != null) {
            NativeCaptureIngest.fromMinor(currency, amountMinor)
        } else {
            null
        }
        val sourceLabel = when {
            sourcePkg.contains("tencent.mm") -> "微信支付"
            sourcePkg.contains("Alipay") || sourcePkg.contains("alipay") -> "支付宝"
            else -> "支付通知"
        }
        val dir = when (direction) {
            "in", "refund" -> "in"
            else -> "out"
        }
        val granted = hasPermission(app)
        val locked = isKeyguardLocked(app)
        Log.i(
            TAG,
            "showPending id=$pendingId amount=$amountMajor granted=$granted locked=$locked " +
                "canDraw=${if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(app) else true}",
        )

        mainHandler.post {
            ensureUnlockReceiver(app)
            dismissInternal()

            // 锁屏时绝不用 WindowManager：OEM 解锁后窗体常成僵尸（看得见、点关闭无效）。
            // 推迟到 USER_PRESENT 再弹；期间用户仍可从系统通知点「确认」。
            if (locked) {
                deferredShow = DeferredShow(
                    pendingId = pendingId,
                    amountMinor = amountMinor,
                    currency = currency,
                    sourcePkg = sourcePkg,
                    merchant = merchant,
                    direction = direction,
                )
                Log.i(TAG, "keyguard locked → defer overlay id=$pendingId")
                return@post
            }

            deferredShow = null
            val payload = DeferredShow(
                pendingId = pendingId,
                amountMinor = amountMinor,
                currency = currency,
                sourcePkg = sourcePkg,
                merchant = merchant,
                direction = direction,
            )
            if (tryShowWindowOverlay(
                    app,
                    pendingId = pendingId,
                    amountMajor = amountMajor,
                    currency = currency,
                    sourceLabel = sourceLabel,
                    merchant = merchant,
                    categoryKind = dir,
                )
            ) {
                activeShow = payload
                return@post
            }
            if (tryShowOverlayActivity(
                    app,
                    pendingId = pendingId,
                    amountMinor = amountMinor,
                    currency = currency,
                    sourcePkg = sourcePkg,
                    merchant = merchant,
                    direction = direction,
                )
            ) {
                activeShow = payload
                return@post
            }
            activeShow = null
            maybeToastNeedPermission(app)
        }
    }

    private fun isKeyguardLocked(context: Context): Boolean {
        val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            ?: return false
        return km.isKeyguardLocked
    }

    /**
     * 亮屏已弹出 → 息屏/解锁：拆掉当前窗并记入 [deferredShow]。
     * 解锁后再 [showPending] 建新窗，避免僵尸悬浮窗关不掉。
     */
    private fun parkOverlayForLock(context: Context, reason: String) {
        val showing = overlayView != null ||
            hostActivity?.get() != null ||
            trackedWmViews.isNotEmpty()
        if (!showing) return
        val snap = activeShow
        if (snap != null) {
            deferredShow = snap
            Log.i(TAG, "$reason → park overlay id=${snap.pendingId}")
        } else {
            Log.i(TAG, "$reason → dismiss overlay (no active payload)")
        }
        ensureUnlockReceiver(context)
        dismissInternal()
        // 息屏阶段 remove 常失败：名单保留未拆掉的 view，解锁后再 purge。
        purgeAllTrackedWmViews(context, reason = reason)
    }

    /** 解锁后延迟弹出，先再清一次旧窗。 */
    private fun scheduleDeferredShow(app: Context, pending: DeferredShow, delayMs: Long) {
        deferredShowRunnable?.let { mainHandler.removeCallbacks(it) }
        deferredShow = null
        val r = Runnable {
            deferredShowRunnable = null
            purgeAllTrackedWmViews(app, reason = "before_deferred_show")
            Log.i(TAG, "deferred show overlay id=${pending.pendingId}")
            showPending(
                app,
                pendingId = pending.pendingId,
                amountMinor = pending.amountMinor,
                currency = pending.currency,
                sourcePkg = pending.sourcePkg,
                merchant = pending.merchant,
                direction = pending.direction,
            )
        }
        deferredShowRunnable = r
        mainHandler.postDelayed(r, delayMs.coerceAtLeast(0L))
    }

    private fun ensureUnlockReceiver(context: Context) {
        if (!unlockReceiverRegistered.compareAndSet(false, true)) return
        try {
            val filter = IntentFilter().apply {
                addAction(Intent.ACTION_USER_PRESENT)
                addAction(Intent.ACTION_SCREEN_OFF)
            }
            // 系统广播必须 EXPORTED，否则 Android 13+ 收不到 SCREEN_OFF / USER_PRESENT。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.applicationContext.registerReceiver(
                    unlockReceiver,
                    filter,
                    Context.RECEIVER_EXPORTED,
                )
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.applicationContext.registerReceiver(unlockReceiver, filter)
            }
            Log.i(TAG, "registered SCREEN_OFF + USER_PRESENT receiver (exported)")
        } catch (e: Exception) {
            unlockReceiverRegistered.set(false)
            Log.w(TAG, "register screen lifecycle receiver failed", e)
        }
    }

    private fun tryShowWindowOverlay(
        app: Context,
        pendingId: String,
        amountMajor: Double?,
        currency: String,
        sourceLabel: String,
        merchant: String?,
        categoryKind: String,
    ): Boolean {
        return try {
            windowManager = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val view = LayoutInflater.from(app)
                .inflate(R.layout.centli_payment_overlay, null)
            bindView(
                app,
                view,
                pendingId = pendingId,
                amountMajor = amountMajor,
                currency = currency,
                sourceLabel = sourceLabel,
                merchant = merchant,
                categoryKind = dirOrOut(categoryKind),
            )
            // 弹新窗前再清一遍，防止名单里还有息屏残留。
            purgeAllTrackedWmViews(app, reason = "before_add")
            windowManager?.addView(view, layoutParams())
            overlayView = view
            trackWmView(view)
            hostActivity = null
            scheduleAutoDismiss()
            Log.i(TAG, "overlay WM shown pending=$pendingId amount=$amountMajor")
            true
        } catch (e: Exception) {
            Log.w(TAG, "WM overlay failed: ${e.message}")
            overlayView = null
            false
        }
    }

    private fun dirOrOut(kind: String): String = when (kind) {
        "in", "refund" -> "in"
        "transfer" -> "transfer"
        else -> "out"
    }

    private fun tryShowOverlayActivity(
        app: Context,
        pendingId: String,
        amountMinor: Int?,
        currency: String,
        sourcePkg: String,
        merchant: String?,
        direction: String?,
    ): Boolean {
        return try {
            PaymentOverlayActivity.start(
                app,
                pendingId = pendingId,
                amountMinor = amountMinor,
                currency = currency,
                sourcePkg = sourcePkg,
                merchant = merchant,
                direction = direction,
            )
            Log.i(TAG, "overlay Activity started pending=$pendingId")
            true
        } catch (e: Exception) {
            Log.w(TAG, "overlay Activity failed: ${e.message}")
            false
        }
    }

    /** Called by [PaymentOverlayActivity] after setContentView. */
    fun bindActivityHost(
        activity: Activity,
        view: View,
        pendingId: String,
        amountMinor: Int?,
        currency: String,
        sourcePkg: String,
        merchant: String?,
        direction: String?,
    ) {
        hostActivity = WeakReference(activity)
        overlayView = null
        val amountMajor = if (amountMinor != null) {
            NativeCaptureIngest.fromMinor(currency, amountMinor)
        } else {
            null
        }
        val sourceLabel = when {
            sourcePkg.contains("tencent.mm") -> "微信支付"
            sourcePkg.contains("Alipay") || sourcePkg.contains("alipay") -> "支付宝"
            else -> "支付通知"
        }
        val dir = when (direction) {
            "in", "refund" -> "in"
            else -> "out"
        }
        bindView(
            activity,
            view,
            pendingId = pendingId,
            amountMajor = amountMajor,
            currency = currency,
            sourceLabel = sourceLabel,
            merchant = merchant,
            categoryKind = dir,
        )
        scheduleAutoDismiss()
    }

    fun dismiss() {
        mainHandler.post {
            deferredShowRunnable?.let { mainHandler.removeCallbacks(it) }
            deferredShowRunnable = null
            deferredShow = null
            dismissInternal()
        }
    }

    /** [PaymentOverlayActivity] 销毁时清弱引用，避免 finish 已死 Activity。 */
    fun onHostDestroyed(activity: Activity) {
        val cur = hostActivity?.get()
        if (cur === activity || cur == null) {
            hostActivity = null
        }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun maybeToastNeedPermission(context: Context) {
        val p = prefs(context)
        val now = System.currentTimeMillis()
        val last = p.getLong(KEY_LAST_PERM_TOAST, 0L)
        if (now - last < PERM_TOAST_COOLDOWN_MS) return
        p.edit().putLong(KEY_LAST_PERM_TOAST, now).apply()
        mainHandler.post {
            try {
                Toast.makeText(
                    context.applicationContext,
                    "已记待确认，但快速记账未能弹出。请在系统设置中允许 Centli：" +
                        "「显示在其他应用上层」和「后台弹出界面」（若有）",
                    Toast.LENGTH_LONG,
                ).show()
            } catch (_: Exception) {
            }
        }
    }

    private fun layoutParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        // Full-screen dim + card (LiteNote style). NOT_FOCUSABLE would block buttons.
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.CENTER
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    private fun bindView(
        context: Context,
        view: View,
        pendingId: String,
        amountMajor: Double?,
        currency: String,
        sourceLabel: String,
        merchant: String?,
        categoryKind: String,
    ) {
        selectedCategoryId = null
        selectedCategoryName = null
        selectedAccountId = null
        selectedAccountName = null
        selectedToAccountId = null
        selectedToAccountName = null
        suggestedAccountId = null
        selectedDirection = dirOrOut(categoryKind)
        overlayCurrency = currency.ifBlank { "CNY" }
        browsingParentId = null
        allCategories = emptyList()
        allAccounts = emptyList()
        categoryViews.clear()
        accountViews.clear()
        toAccountViews.clear()

        view.findViewById<TextView>(R.id.tv_title).text =
            "快速记账 · 检测到$sourceLabel"

        val m = merchant?.trim().orEmpty()

        val amountEt = view.findViewById<EditText>(R.id.et_amount)
        if (amountMajor != null) {
            amountEt.setText(formatMajor(overlayCurrency, amountMajor))
            amountEt.setSelection(amountEt.text.length)
        } else {
            amountEt.setText("")
        }

        val noteEt = view.findViewById<EditText>(R.id.et_note)
        noteEt.setText(m)
        noteEt.hint = if (m.isNotEmpty()) "备注（可改）" else "备注（可选）"

        val confirmBtn = view.findViewById<Button>(R.id.btn_confirm)
        confirmBtn.isEnabled = false
        confirmBtn.alpha = 0.5f
        confirmBtn.text = "入账"

        val btnOut = view.findViewById<TextView>(R.id.btn_dir_out)
        val btnIn = view.findViewById<TextView>(R.id.btn_dir_in)
        val btnTransfer = view.findViewById<TextView>(R.id.btn_dir_transfer)
        fun paintDirection() {
            fun paint(btn: TextView, selected: Boolean) {
                btn.isSelected = selected
                btn.setTextColor(
                    if (selected) 0xFFFFFFFF.toInt() else 0xFF1A1A1A.toInt(),
                )
            }
            paint(btnOut, selectedDirection == "out")
            paint(btnIn, selectedDirection == "in")
            paint(btnTransfer, selectedDirection == "transfer")
        }
        fun onDirectionPicked(dir: String) {
            if (selectedDirection == dir) return
            selectedDirection = dir
            paintDirection()
            clearCategorySelection(confirmBtn)
            browsingParentId = null
            if (dir != "transfer") {
                selectedToAccountId = null
                selectedToAccountName = null
            }
            renderAccounts(context, view, confirmBtn)
            loadCategories(context, view, confirmBtn)
        }
        paintDirection()
        btnOut.setOnClickListener { onDirectionPicked("out") }
        btnIn.setOnClickListener { onDirectionPicked("in") }
        btnTransfer.setOnClickListener { onDirectionPicked("transfer") }

        view.findViewById<TextView>(R.id.btn_cat_back).setOnClickListener {
            browsingParentId = null
            clearCategorySelection(confirmBtn)
            renderCategoryLevel(context, view, confirmBtn)
        }

        fun parseAmountMinor(): Int? {
            val raw = amountEt.text?.toString()?.trim().orEmpty()
                .replace(",", "").replace("￥", "").replace("¥", "")
            if (raw.isEmpty()) return null
            val major = raw.toDoubleOrNull() ?: return null
            if (major < 0) return null
            return NativeCaptureIngest.toMinor(overlayCurrency, major)
        }

        fun refreshConfirmEnabled() {
            applyConfirmEnabled(view, confirmBtn)
        }

        amountEt.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) = refreshConfirmEnabled()
        })

        view.findViewById<ImageButton>(R.id.btn_close_x).setOnClickListener {
            dismissInternal()
        }
        view.findViewById<Button>(R.id.btn_later).setOnClickListener {
            dismissInternal()
        }
        view.findViewById<Button>(R.id.btn_ignore).setOnClickListener {
            ignorePending(context, pendingId)
            dismissInternal()
        }
        view.findViewById<TextView>(R.id.btn_open_detail).setOnClickListener {
            openReview(context, pendingId)
            dismissInternal()
        }

        confirmBtn.setOnClickListener {
            val catId = selectedCategoryId ?: return@setOnClickListener
            val catName = selectedCategoryName ?: ""
            val accId = selectedAccountId ?: return@setOnClickListener
            val accName = selectedAccountName ?: ""
            val toAccId = selectedToAccountId
            val toAccName = selectedToAccountName ?: ""
            if (selectedDirection == "transfer") {
                if (toAccId.isNullOrBlank()) {
                    Toast.makeText(context, "请选择转入账户", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                if (toAccId == accId) {
                    Toast.makeText(context, "转出与转入账户不能相同", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
            }
            val amountMinor = parseAmountMinor()
            if (amountMinor == null) {
                Toast.makeText(context, "请输入有效金额", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            val note = noteEt.text?.toString()?.trim().orEmpty().ifEmpty { null }
            hideKeyboard(context, amountEt)
            confirmBtn.isEnabled = false
            confirmBtn.text = "入账中…"
            Thread {
                val ok = confirmPending(
                    context,
                    pendingId = pendingId,
                    categoryId = catId,
                    accountIdOverride = accId,
                    toAccountIdOverride = if (selectedDirection == "transfer") toAccId else null,
                    amountMinorOverride = amountMinor,
                    directionOverride = selectedDirection,
                    noteOverride = note,
                )
                mainHandler.post {
                    if (ok) {
                        val ed = prefs(context).edit()
                            .putString(KEY_LAST_CATEGORY, catId)
                            .putString(KEY_LAST_ACCOUNT, accId)
                        if (selectedDirection == "transfer" && !toAccId.isNullOrBlank()) {
                            ed.putString(KEY_LAST_TO_ACCOUNT, toAccId)
                        }
                        ed.apply()
                        PendingConfirmNotifier.cancel(context, pendingId)
                        MainActivity.notifyPendingDbChanged()
                        val accountLabel = if (selectedDirection == "transfer") {
                            "$accName → $toAccName"
                        } else {
                            accName
                        }
                        showSuccess(
                            view,
                            NativeCaptureIngest.fromMinor(overlayCurrency, amountMinor),
                            catName,
                            accountLabel,
                        )
                    } else {
                        confirmBtn.isEnabled = true
                        confirmBtn.text = "入账"
                        Toast.makeText(context, "入账失败，请打开 App 确认", Toast.LENGTH_SHORT)
                            .show()
                    }
                }
            }.start()
        }

        loadAccounts(context, view, confirmBtn, pendingId)
        loadCategories(context, view, confirmBtn)
    }

    private fun applyConfirmEnabled(root: View, confirmBtn: Button) {
        val amountOk = parseAmountMinorFrom(root.findViewById(R.id.et_amount)) != null
        val transferOk = selectedDirection != "transfer" ||
            (!selectedToAccountId.isNullOrBlank() &&
                selectedToAccountId != selectedAccountId)
        val ok = amountOk &&
            selectedCategoryId != null &&
            selectedAccountId != null &&
            transferOk
        confirmBtn.isEnabled = ok
        confirmBtn.alpha = if (ok) 1f else 0.5f
    }

    private fun hideKeyboard(context: Context, focus: View) {
        try {
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.hideSoftInputFromWindow(focus.windowToken, 0)
        } catch (_: Exception) {
        }
    }

    private fun clearCategorySelection(confirmBtn: Button) {
        selectedCategoryId = null
        selectedCategoryName = null
        for ((v, _) in categoryViews) {
            v.isSelected = false
            v.setTextColor(0xFF1A1A1A.toInt())
        }
        confirmBtn.isEnabled = false
        confirmBtn.alpha = 0.5f
    }

    private fun loadAccounts(
        context: Context,
        view: View,
        confirmBtn: Button,
        pendingId: String,
    ) {
        val scroll = view.findViewById<ScrollView>(R.id.scroll_accounts)
        scroll.visibility = View.GONE
        Thread {
            val suggested = queryPendingSuggestedAccount(context, pendingId)
            val pendingLedger = queryPendingLedgerId(context, pendingId)
            val accounts = queryAccounts(
                context,
                ledgerId = pendingLedger,
                allLedgers = true,
            )
            mainHandler.post {
                suggestedAccountId = suggested
                allAccounts = accounts
                overlayPendingLedgerId = pendingLedger
                renderAccounts(context, view, confirmBtn)
            }
        }.start()
    }

    private fun renderAccounts(
        context: Context,
        view: View,
        confirmBtn: Button,
    ) {
        val scroll = view.findViewById<ScrollView>(R.id.scroll_accounts)
        val container = view.findViewById<LinearLayout>(R.id.container_accounts)
        val levelTv = view.findViewById<TextView>(R.id.tv_account_level)
        val toLevel = view.findViewById<TextView>(R.id.tv_to_account_level)
        val toScroll = view.findViewById<ScrollView>(R.id.scroll_to_accounts)
        container.removeAllViews()
        accountViews.clear()
        val transfer = selectedDirection == "transfer"
        levelTv.text = if (transfer) "选择转出账户" else "选择账户"
        toLevel.visibility = if (transfer) View.VISIBLE else View.GONE
        toScroll.visibility = if (transfer) View.VISIBLE else View.GONE
        if (!transfer) {
            selectedToAccountId = null
            selectedToAccountName = null
            toAccountViews.clear()
            view.findViewById<LinearLayout>(R.id.container_to_accounts).removeAllViews()
        }

        if (allAccounts.isEmpty()) {
            val tip = TextView(context).apply {
                text = "暂无资产账户，请点下方打开 App 确认"
                setTextColor(0xFF888888.toInt())
                textSize = 12f
            }
            container.addView(tip)
            scroll.visibility = View.VISIBLE
            return
        }

        fillAccountGrid(
            context = context,
            container = container,
            scroll = scroll,
            views = accountViews,
            onPick = { chip, acc -> selectAccount(view, chip, acc, confirmBtn) },
        )
        scroll.visibility = View.VISIBLE

        val lastId = prefs(context).getString(KEY_LAST_ACCOUNT, null)
        val preferId = when {
            !suggestedAccountId.isNullOrBlank() &&
                allAccounts.any { it.id == suggestedAccountId } -> suggestedAccountId
            !lastId.isNullOrBlank() && allAccounts.any { it.id == lastId } -> lastId
            else -> allAccounts.firstOrNull()?.id
        }
        if (preferId != null) {
            accountViews.firstOrNull { it.second.id == preferId }?.let { (chip, acc) ->
                selectAccount(view, chip, acc, confirmBtn)
            }
        }

        if (transfer) {
            renderToAccounts(context, view, confirmBtn)
        }
    }

    private fun renderToAccounts(
        context: Context,
        view: View,
        confirmBtn: Button,
    ) {
        val scroll = view.findViewById<ScrollView>(R.id.scroll_to_accounts)
        val container = view.findViewById<LinearLayout>(R.id.container_to_accounts)
        container.removeAllViews()
        toAccountViews.clear()
        if (allAccounts.size < 2) {
            val tip = TextView(context).apply {
                text = "转账至少需要两个资产账户"
                setTextColor(0xFF888888.toInt())
                textSize = 12f
            }
            container.addView(tip)
            return
        }
        fillAccountGrid(
            context = context,
            container = container,
            scroll = scroll,
            views = toAccountViews,
            onPick = { chip, acc -> selectToAccount(view, chip, acc, confirmBtn) },
        )
        val lastTo = prefs(context).getString(KEY_LAST_TO_ACCOUNT, null)
        val preferTo = when {
            !lastTo.isNullOrBlank() &&
                lastTo != selectedAccountId &&
                allAccounts.any { it.id == lastTo } -> lastTo
            else -> allAccounts.firstOrNull { it.id != selectedAccountId }?.id
        }
        if (preferTo != null) {
            toAccountViews.firstOrNull { it.second.id == preferTo }?.let { (chip, acc) ->
                selectToAccount(view, chip, acc, confirmBtn)
            }
        }
    }

    private fun fillAccountGrid(
        context: Context,
        container: LinearLayout,
        scroll: ScrollView,
        views: MutableList<Pair<TextView, Account>>,
        onPick: (TextView, Account) -> Unit,
    ) {
        val density = context.resources.displayMetrics.density
        val rowH = (40 * density).toInt()
        val gap = (8 * density).toInt()
        val chunks = allAccounts.chunked(ACCOUNTS_PER_ROW)
        chunks.forEachIndexed { rowIndex, row ->
            val rowLayout = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    if (rowIndex < chunks.size - 1) bottomMargin = gap
                }
            }
            for (acc in row) {
                val chip = TextView(context).apply {
                    text = acc.displayLabel(overlayPendingLedgerId)
                    textSize = 13f
                    gravity = android.view.Gravity.CENTER
                    setPadding(
                        (8 * density).toInt(),
                        (8 * density).toInt(),
                        (8 * density).toInt(),
                        (8 * density).toInt(),
                    )
                    setBackgroundResource(R.drawable.centli_overlay_chip)
                    setTextColor(0xFF1A1A1A.toInt())
                    isSelected = false
                    layoutParams = LinearLayout.LayoutParams(0, rowH, 1f).apply {
                        marginStart = (4 * density).toInt()
                        marginEnd = (4 * density).toInt()
                    }
                    setOnClickListener { onPick(this, acc) }
                }
                rowLayout.addView(chip)
                views.add(chip to acc)
            }
            repeat(ACCOUNTS_PER_ROW - row.size) {
                rowLayout.addView(
                    View(context).apply {
                        layoutParams = LinearLayout.LayoutParams(0, 1, 1f).apply {
                            marginStart = (4 * density).toInt()
                            marginEnd = (4 * density).toInt()
                        }
                    },
                )
            }
            container.addView(rowLayout)
        }
        if (chunks.size > MAX_VISIBLE_ROWS) {
            scroll.layoutParams = scroll.layoutParams.apply {
                height = MAX_VISIBLE_ROWS * rowH + (MAX_VISIBLE_ROWS - 1) * gap
            }
        } else {
            scroll.layoutParams = scroll.layoutParams.apply {
                height = LinearLayout.LayoutParams.WRAP_CONTENT
            }
        }
    }

    private fun selectAccount(
        root: View,
        chip: TextView,
        acc: Account,
        confirmBtn: Button,
    ) {
        selectedAccountId = acc.id
        selectedAccountName = acc.name
        for ((v, _) in accountViews) {
            v.isSelected = false
            v.setTextColor(0xFF1A1A1A.toInt())
        }
        chip.isSelected = true
        chip.setTextColor(0xFFFFFFFF.toInt())
        if (selectedDirection == "transfer" && selectedToAccountId == acc.id) {
            selectedToAccountId = null
            selectedToAccountName = null
            for ((v, _) in toAccountViews) {
                v.isSelected = false
                v.setTextColor(0xFF1A1A1A.toInt())
            }
            toAccountViews.firstOrNull { it.second.id != acc.id }?.let { (c, a) ->
                selectToAccount(root, c, a, confirmBtn)
                return
            }
        }
        applyConfirmEnabled(root, confirmBtn)
    }

    private fun selectToAccount(
        root: View,
        chip: TextView,
        acc: Account,
        confirmBtn: Button,
    ) {
        if (acc.id == selectedAccountId) {
            Toast.makeText(root.context, "转入不能与转出相同", Toast.LENGTH_SHORT).show()
            return
        }
        selectedToAccountId = acc.id
        selectedToAccountName = acc.name
        for ((v, _) in toAccountViews) {
            v.isSelected = false
            v.setTextColor(0xFF1A1A1A.toInt())
        }
        chip.isSelected = true
        chip.setTextColor(0xFFFFFFFF.toInt())
        applyConfirmEnabled(root, confirmBtn)
    }

    private fun loadCategories(
        context: Context,
        view: View,
        confirmBtn: Button,
    ) {
        val loading = view.findViewById<LinearLayout>(R.id.loading_container)
        val scroll = view.findViewById<ScrollView>(R.id.scroll_categories)
        loading.visibility = View.VISIBLE
        scroll.visibility = View.GONE

        Thread {
            val lid = overlayPendingLedgerId ?: run {
                val db = openDb(context)
                try {
                    db?.let { querySetting(it, "current_ledger_id") }
                } finally {
                    db?.close()
                }
            }
            val cats = queryCategories(context, selectedDirection, lid)
            mainHandler.post {
                allCategories = cats
                browsingParentId = null
                loading.visibility = View.GONE
                renderCategoryLevel(context, view, confirmBtn)
            }
        }.start()
    }

    /** 转账分类为空时补一条「转账」（与 Drift v13 种子对齐）。 */
    private fun ensureTransferCategory(db: SQLiteDatabase, ledgerId: String): Category? {
        db.rawQuery(
            """
            SELECT id, name, parent_id FROM categories
            WHERE ledger_id=? AND kind='transfer' AND archived=0
            ORDER BY sort_order ASC LIMIT 1
            """.trimIndent(),
            arrayOf(ledgerId),
        ).use { c ->
            if (c.moveToFirst()) {
                val parent = if (c.isNull(2)) null else c.getString(2)
                return Category(c.getString(0), c.getString(1), parent)
            }
        }
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        return try {
            db.execSQL(
                """
                INSERT INTO categories(
                  id, ledger_id, name, parent_id, kind, icon, sort_order, archived, created_at
                ) VALUES(?,?,?,?,?,?,?,?,?)
                """.trimIndent(),
                arrayOf<Any?>(
                    id, ledgerId, "转账", null, "transfer", "transfer", 0, 0, now,
                ),
            )
            Category(id, "转账", null)
        } catch (e: Exception) {
            Log.e(TAG, "ensureTransferCategory", e)
            null
        }
    }

    private fun rootsOf(cats: List<Category>): List<Category> {
        val roots = cats.filter { it.parentId.isNullOrBlank() }.toMutableList()
        val rootIds = roots.map { it.id }.toHashSet()
        // Orphan children stay reachable as roots.
        for (c in cats) {
            val p = c.parentId
            if (!p.isNullOrBlank() && !rootIds.contains(p) && !rootIds.contains(c.id)) {
                roots.add(c)
                rootIds.add(c.id)
            }
        }
        return roots
    }

    private fun childrenOf(parentId: String): List<Category> =
        allCategories.filter { it.parentId == parentId }

    /** Show either L1 roots or L2 children — never side-by-side. */
    private fun renderCategoryLevel(
        context: Context,
        view: View,
        confirmBtn: Button,
    ) {
        val scroll = view.findViewById<ScrollView>(R.id.scroll_categories)
        val container = view.findViewById<LinearLayout>(R.id.container_categories)
        val back = view.findViewById<TextView>(R.id.btn_cat_back)
        val levelTv = view.findViewById<TextView>(R.id.tv_cat_level)
        container.removeAllViews()
        categoryViews.clear()

        val parentId = browsingParentId
        val items: List<Category>
        if (parentId == null) {
            back.visibility = View.GONE
            levelTv.text = if (selectedDirection == "transfer") "选择分类" else "选择一级分类"
            items = rootsOf(allCategories)
        } else {
            back.visibility = View.VISIBLE
            val parentName = allCategories.firstOrNull { it.id == parentId }?.name ?: ""
            levelTv.text = if (parentName.isNotEmpty()) "选择「$parentName」二级分类" else "选择二级分类"
            items = childrenOf(parentId)
        }

        if (items.isEmpty()) {
            val tip = TextView(context).apply {
                text = if (parentId == null) {
                    "暂无分类，请点下方打开 App 确认"
                } else {
                    "该分类下暂无二级，可点上方返回"
                }
                setTextColor(0xFF888888.toInt())
                textSize = 12f
            }
            container.addView(tip)
            scroll.visibility = View.VISIBLE
            return
        }

        val density = context.resources.displayMetrics.density
        val lastId = prefs(context).getString(KEY_LAST_CATEGORY, null)
        val rowH = (40 * density).toInt()
        val gap = (8 * density).toInt()
        val chunks = items.chunked(CATEGORIES_PER_ROW)
        chunks.forEachIndexed { rowIndex, row ->
            val rowLayout = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    if (rowIndex < chunks.size - 1) bottomMargin = gap
                }
            }
            for (cat in row) {
                val chip = TextView(context).apply {
                    text = cat.name
                    textSize = 13f
                    gravity = android.view.Gravity.CENTER
                    setPadding(
                        (8 * density).toInt(),
                        (8 * density).toInt(),
                        (8 * density).toInt(),
                        (8 * density).toInt(),
                    )
                    setBackgroundResource(R.drawable.centli_overlay_chip)
                    setTextColor(0xFF1A1A1A.toInt())
                    isSelected = false
                    layoutParams = LinearLayout.LayoutParams(0, rowH, 1f).apply {
                        marginStart = (4 * density).toInt()
                        marginEnd = (4 * density).toInt()
                    }
                    setOnClickListener {
                        onCategoryChipTap(context, view, confirmBtn, this, cat)
                    }
                }
                rowLayout.addView(chip)
                categoryViews.add(chip to cat)
            }
            repeat(CATEGORIES_PER_ROW - row.size) {
                rowLayout.addView(
                    View(context).apply {
                        layoutParams = LinearLayout.LayoutParams(0, 1, 1f).apply {
                            marginStart = (4 * density).toInt()
                            marginEnd = (4 * density).toInt()
                        }
                    },
                )
            }
            container.addView(rowLayout)
        }
        if (chunks.size > MAX_VISIBLE_ROWS) {
            scroll.layoutParams = scroll.layoutParams.apply {
                height = MAX_VISIBLE_ROWS * rowH + (MAX_VISIBLE_ROWS - 1) * gap
            }
        } else {
            scroll.layoutParams = scroll.layoutParams.apply {
                height = LinearLayout.LayoutParams.WRAP_CONTENT
            }
        }
        scroll.visibility = View.VISIBLE

        // Prefill last-used leaf on the current level only.
        if (lastId != null) {
            val last = allCategories.firstOrNull { it.id == lastId }
            val lastIsOnThisLevel = when {
                parentId == null ->
                    last != null &&
                        (last.parentId.isNullOrBlank() || childrenOf(last.id).isEmpty()) &&
                        items.any { it.id == lastId }
                else -> items.any { it.id == lastId }
            }
            if (lastIsOnThisLevel) {
                categoryViews.firstOrNull { it.second.id == lastId }?.let { (chip, cat) ->
                    selectLeafCategory(view, chip, cat, confirmBtn)
                }
            }
        }
    }

    private fun onCategoryChipTap(
        context: Context,
        view: View,
        confirmBtn: Button,
        chip: TextView,
        cat: Category,
    ) {
        // On L1: if has children → drill into L2 only (never show L1+L2 side by side).
        if (browsingParentId == null) {
            val kids = childrenOf(cat.id)
            if (kids.isNotEmpty()) {
                browsingParentId = cat.id
                clearCategorySelection(confirmBtn)
                renderCategoryLevel(context, view, confirmBtn)
                return
            }
        }
        selectLeafCategory(view, chip, cat, confirmBtn)
    }

    private fun selectLeafCategory(
        root: View,
        chip: TextView,
        cat: Category,
        confirmBtn: Button,
    ) {
        selectedCategoryId = cat.id
        selectedCategoryName = cat.name
        for ((v, _) in categoryViews) {
            v.isSelected = false
            v.setTextColor(0xFF1A1A1A.toInt())
        }
        chip.isSelected = true
        chip.setTextColor(0xFFFFFFFF.toInt())
        applyConfirmEnabled(root, confirmBtn)
    }

    private fun parseAmountMinorFrom(amountEt: EditText?): Int? {
        val raw = amountEt?.text?.toString()?.trim().orEmpty()
            .replace(",", "").replace("￥", "").replace("¥", "")
        if (raw.isEmpty()) return null
        val major = raw.toDoubleOrNull() ?: return null
        if (major < 0) return null
        return NativeCaptureIngest.toMinor(overlayCurrency, major)
    }

    private fun formatMajor(currency: String, major: Double): String {
        val decimals = NativeCaptureIngest.currencyDecimals(currency)
        return if (decimals == 0) {
            String.format(Locale.US, "%.0f", major)
        } else {
            String.format(Locale.US, "%.${decimals}f", major)
        }
    }

    private fun showSuccess(
        view: View,
        amountMajor: Double,
        categoryName: String,
        accountName: String,
    ) {
        view.findViewById<View>(R.id.content_main).visibility = View.GONE
        val success = view.findViewById<View>(R.id.content_success)
        success.visibility = View.VISIBLE
        val symbol = when (overlayCurrency.uppercase(Locale.US)) {
            "USD" -> "$"
            "EUR" -> "€"
            else -> "¥"
        }
        val accPart = if (accountName.isNotBlank()) " · $accountName" else ""
        view.findViewById<TextView>(R.id.tv_success_detail).text =
            "$symbol${formatMajor(overlayCurrency, amountMajor)} · $categoryName$accPart"
        mainHandler.postDelayed({ dismissInternal() }, SUCCESS_DISMISS_MS)
    }

    private fun scheduleAutoDismiss() {
        autoDismiss?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable { dismissInternal() }
        autoDismiss = r
        mainHandler.postDelayed(r, AUTO_DISMISS_MS)
    }

    private fun dismissInternal() {
        autoDismiss?.let { mainHandler.removeCallbacks(it) }
        autoDismiss = null
        activeShow = null

        val view = overlayView
        overlayView = null
        if (view != null) {
            if (!removeOverlayViewSafely(view)) {
                // 拆失败仍留在名单，解锁后再 purge。
                trackWmView(view)
            } else {
                trackedWmViews.remove(view)
            }
        }
        // 把当前指针以外、历史上 add 过的窗一并拆。
        val appCtx = view?.context?.applicationContext
        if (appCtx != null) {
            purgeAllTrackedWmViews(appCtx, reason = "dismiss")
        } else if (trackedWmViews.isNotEmpty()) {
            // 无 context 时也尽量用缓存的 WM 拆。
            val left = trackedWmViews.toList()
            trackedWmViews.clear()
            for (v in left) {
                if (!removeOverlayViewSafely(v)) {
                    trackedWmViews.add(v)
                }
            }
        }

        selectedCategoryId = null
        selectedCategoryName = null
        selectedAccountId = null
        selectedAccountName = null
        selectedToAccountId = null
        selectedToAccountName = null
        suggestedAccountId = null
        selectedDirection = "out"
        browsingParentId = null
        allCategories = emptyList()
        allAccounts = emptyList()
        toAccountViews.clear()
        categoryViews.clear()
        accountViews.clear()

        val act = hostActivity?.get()
        hostActivity = null
        finishHostActivity(act)
    }


    private fun trackWmView(view: View) {
        if (trackedWmViews.contains(view)) return
        trackedWmViews.add(view)
        while (trackedWmViews.size > MAX_TRACKED_WM_VIEWS) {
            val oldest = trackedWmViews.removeAt(0)
            if (oldest !== view) {
                // Best-effort detach; GONE if remove fails.
                removeOverlayViewSafely(oldest)
            }
        }
    }

    /** 强拆 [trackedWmViews] 里所有尚未成功 remove 的窗。 */
    private fun purgeAllTrackedWmViews(context: Context, reason: String) {
        if (trackedWmViews.isEmpty()) {
            overlayView = null
            return
        }
        val wm = windowManager
            ?: context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        windowManager = wm
        val left = ArrayList<View>()
        val snapshot = trackedWmViews.toList()
        trackedWmViews.clear()
        for (v in snapshot) {
            if (!removeOverlayViewSafely(v)) {
                left.add(v)
            }
        }
        if (left.isNotEmpty()) {
            // Cap: drop oldest stuck views after force-GONE so list cannot grow forever.
            val capped = if (left.size > MAX_TRACKED_WM_VIEWS) {
                left.takeLast(MAX_TRACKED_WM_VIEWS)
            } else {
                left
            }
            trackedWmViews.addAll(capped)
            Log.w(
                TAG,
                "$reason purge: ${left.size} overlay(s) still stuck (kept ${capped.size})",
            )
        } else {
            Log.i(TAG, "$reason purge: all tracked overlays removed")
        }
        if (overlayView != null && !trackedWmViews.contains(overlayView)) {
            overlayView = null
        }
    }

    /** 多路径拆除 WM 窗；成功返回 true。 */
    private fun removeOverlayViewSafely(view: View): Boolean {
        val app = try {
            view.context.applicationContext
        } catch (_: Exception) {
            null
        }
        val wm = windowManager
            ?: app?.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        windowManager = wm
        try {
            wm?.removeViewImmediate(view)
            Log.i(TAG, "overlay removed via removeViewImmediate")
            return true
        } catch (e: Exception) {
            Log.w(TAG, "removeViewImmediate failed: ${e.message}")
        }
        try {
            wm?.removeView(view)
            Log.i(TAG, "overlay removed via removeView")
            return true
        } catch (e: Exception) {
            Log.w(TAG, "removeView failed: ${e.message}")
        }
        try {
            (view.parent as? ViewGroup)?.removeView(view)
            Log.i(TAG, "overlay removed via parent.removeView")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "all remove paths failed — view may stick", e)
        }
        // 最后手段：GONE + 透明，减轻「看得见」的残留感（仍占一层，但尽量不可点）。
        try {
            view.visibility = View.GONE
            view.alpha = 0f
            view.isClickable = false
            view.isFocusable = false
        } catch (_: Exception) {
        }
        return false
    }

    private fun finishHostActivity(act: Activity?) {
        if (act == null || act.isFinishing || act.isDestroyed) return
        try {
            act.finish()
        } catch (e: Exception) {
            Log.w(TAG, "finish host failed", e)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                act.finishAndRemoveTask()
            }
        } catch (_: Exception) {
        }
    }

    /**
     * 解锁后兜底：引用已丢但仍挂在 WM 上的僵尸窗无法通过 [dismissInternal] 清掉。
     * 这里再扫一次；若进程里还有 [overlayView] 就强拆。
     */
    private fun forceRemoveOrphanOverlay(context: Context) {
        purgeAllTrackedWmViews(context, reason = "force_orphan")
        val view = overlayView
        if (view != null) {
            Log.w(TAG, "force-remove orphan overlay still referenced")
            overlayView = null
            removeOverlayViewSafely(view)
        }
        // Activity 宿主一并关掉。
        finishHostActivity(hostActivity?.get())
        hostActivity = null
    }

    private fun openReview(context: Context, pendingId: String) {
        val launch = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(PendingConfirmNotifier.EXTRA_OPEN, "/home/pending")
            putExtra(PendingConfirmNotifier.EXTRA_PENDING_ID, pendingId)
            putExtra(PendingConfirmNotifier.EXTRA_REVIEW, true)
        }
        context.startActivity(launch)
    }

    private fun openDb(context: Context): SQLiteDatabase? {
        val dbFile = File(
            context.applicationContext.getDir("flutter", Context.MODE_PRIVATE),
            DB_NAME,
        )
        if (!dbFile.exists()) return null
        return try {
            SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE,
            ).also { it.rawQuery("PRAGMA busy_timeout=3000", null).close() }
        } catch (e: Exception) {
            Log.e(TAG, "openDb", e)
            null
        }
    }

    private fun queryCategories(
        context: Context,
        kind: String,
        ledgerIdOverride: String? = null,
    ): List<Category> {
        val db = openDb(context) ?: return emptyList()
        try {
            val ledgerId = ledgerIdOverride
                ?: querySetting(db, "current_ledger_id")
                ?: return emptyList()
            if (kind == "transfer") {
                ensureTransferCategory(db, ledgerId)
            }
            val out = ArrayList<Category>()
            db.rawQuery(
                """
                SELECT id, name, parent_id FROM categories
                WHERE ledger_id=? AND kind=? AND archived=0
                ORDER BY sort_order ASC
                LIMIT 80
                """.trimIndent(),
                arrayOf(ledgerId, kind),
            ).use { c ->
                while (c.moveToNext()) {
                    val parent = if (c.isNull(2)) null else c.getString(2)
                    out.add(Category(c.getString(0), c.getString(1), parent))
                }
            }
            return out
        } catch (e: Exception) {
            Log.e(TAG, "queryCategories", e)
            return emptyList()
        } finally {
            db.close()
        }
    }

    private fun queryAccounts(
        context: Context,
        ledgerId: String? = null,
        allLedgers: Boolean = false,
    ): List<Account> {
        val db = openDb(context) ?: return emptyList()
        try {
            val nameByLedger = HashMap<String, String>()
            db.rawQuery(
                "SELECT id, name FROM ledgers WHERE archived=0",
                null,
            ).use { c ->
                while (c.moveToNext()) {
                    nameByLedger[c.getString(0)] = c.getString(1) ?: ""
                }
            }
            val out = ArrayList<Account>()
            if (allLedgers) {
                db.rawQuery(
                    "SELECT id, name, currency, ledger_id FROM accounts WHERE archived=0 ORDER BY sort_order ASC LIMIT 200",
                    null,
                ).use { c ->
                    while (c.moveToNext()) {
                        val lid = c.getString(3) ?: ""
                        out.add(
                            Account(
                                id = c.getString(0),
                                name = c.getString(1) ?: "",
                                currency = c.getString(2) ?: "CNY",
                                ledgerId = lid,
                                ledgerName = nameByLedger[lid] ?: "",
                            ),
                        )
                    }
                }
            } else {
                val lid = ledgerId ?: querySetting(db, "current_ledger_id")
                    ?: return emptyList()
                db.rawQuery(
                    "SELECT id, name, currency, ledger_id FROM accounts WHERE ledger_id=? AND archived=0 ORDER BY sort_order ASC LIMIT 60",
                    arrayOf(lid),
                ).use { c ->
                    while (c.moveToNext()) {
                        val alid = c.getString(3) ?: lid
                        out.add(
                            Account(
                                id = c.getString(0),
                                name = c.getString(1) ?: "",
                                currency = c.getString(2) ?: "CNY",
                                ledgerId = alid,
                                ledgerName = nameByLedger[alid] ?: "",
                            ),
                        )
                    }
                }
            }
            return out
        } catch (e: Exception) {
            Log.e(TAG, "queryAccounts", e)
            return emptyList()
        } finally {
            db.close()
        }
    }

    private fun queryPendingLedgerId(context: Context, pendingId: String): String? {
        val db = openDb(context) ?: return null
        try {
            db.rawQuery(
                "SELECT ledger_id FROM pending_captures WHERE id=? LIMIT 1",
                arrayOf(pendingId),
            ).use { c ->
                if (!c.moveToFirst()) return null
                return c.getString(0)
            }
        } catch (e: Exception) {
            Log.e(TAG, "queryPendingLedgerId", e)
            return null
        } finally {
            db.close()
        }
    }

    private fun queryPendingSuggestedAccount(context: Context, pendingId: String): String? {
        val db = openDb(context) ?: return null
        try {
            db.rawQuery(
                "SELECT suggested_account_id FROM pending_captures WHERE id=? LIMIT 1",
                arrayOf(pendingId),
            ).use { c ->
                if (!c.moveToFirst() || c.isNull(0)) return null
                return c.getString(0)?.trim()?.takeIf { it.isNotEmpty() }
            }
        } catch (e: Exception) {
            Log.e(TAG, "queryPendingSuggestedAccount", e)
            return null
        } finally {
            db.close()
        }
    }

    private fun ignorePending(context: Context, pendingId: String) {
        val db = openDb(context) ?: return
        try {
            val now = System.currentTimeMillis()
            db.execSQL(
                "UPDATE pending_captures SET status=?, updated_at=? WHERE id=? AND status=?",
                arrayOf<Any?>("ignored", now, pendingId, "pending"),
            )
            // Retire dedupe key (align Dart).
            db.rawQuery(
                "SELECT dedupe_key FROM pending_captures WHERE id=? LIMIT 1",
                arrayOf(pendingId),
            ).use { c ->
                if (c.moveToFirst()) {
                    val old = c.getString(0) ?: return@use
                    val retired = if (old.startsWith("done|")) old else "done|$pendingId|$old"
                    db.execSQL(
                        "UPDATE pending_captures SET dedupe_key=?, updated_at=? WHERE id=?",
                        arrayOf<Any?>(retired, now, pendingId),
                    )
                }
            }
            PendingConfirmNotifier.cancel(context, pendingId)
            MainActivity.notifyPendingDbChanged()
            Toast.makeText(context, "已忽略", Toast.LENGTH_SHORT).show()
        } catch (e: Exception) {
            Log.e(TAG, "ignore failed", e)
        } finally {
            db.close()
        }
    }

    private fun confirmPending(
        context: Context,
        pendingId: String,
        categoryId: String,
        accountIdOverride: String? = null,
        toAccountIdOverride: String? = null,
        amountMinorOverride: Int? = null,
        directionOverride: String? = null,
        noteOverride: String? = null,
    ): Boolean {
        val db = openDb(context) ?: return false
        try {
            // 与 Drift 争用同一库：先拿事务写锁；再靠 pending_id 唯一索引兜底。
            db.beginTransaction()
            fun hasTxnForPending(): Boolean {
                db.rawQuery(
                    "SELECT 1 FROM transactions WHERE pending_id=? LIMIT 1",
                    arrayOf(pendingId),
                ).use { return it.moveToFirst() }
            }
            val row = db.rawQuery(
                """
                SELECT ledger_id, amount_minor, currency, note, happen_at,
                       suggested_account_id, source_pkg, direction, dedupe_key,
                       raw_title, raw_text, status
                FROM pending_captures WHERE id=? LIMIT 1
                """.trimIndent(),
                arrayOf(pendingId),
            )
            if (!row.moveToFirst()) {
                row.close()
                return false
            }
            val status = row.getString(11)
            if (status != "pending") {
                val ok = status == "confirmed" && hasTxnForPending()
                row.close()
                if (ok) db.setTransactionSuccessful()
                return ok
            }
            val ledgerId = row.getString(0)
            val dbAmount = if (row.isNull(1)) null else row.getInt(1)
            val currency = row.getString(2) ?: "CNY"
            val dbNote = row.getString(3)
            val happenAt = if (row.isNull(4)) System.currentTimeMillis() else row.getLong(4)
            var accountId = row.getString(5)
            val sourcePkg = row.getString(6) ?: ""
            val dbDirection = row.getString(7)
            val oldDedupe = row.getString(8)
            val rawTitle = row.getString(9).orEmpty()
            val rawText = row.getString(10).orEmpty()
            row.close()
            if (hasTxnForPending()) {
                // Dart 已写入流水：只把 pending 标成 confirmed（幂等）。
                val now = System.currentTimeMillis()
                val retired = when {
                    oldDedupe.isNullOrBlank() -> "done|$pendingId"
                    oldDedupe.startsWith("done|") -> oldDedupe
                    else -> "done|$pendingId|$oldDedupe"
                }
                db.execSQL(
                    """
                    UPDATE pending_captures SET status=?, dedupe_key=?, updated_at=?
                    WHERE id=? AND status=?
                    """.trimIndent(),
                    arrayOf<Any?>("confirmed", retired, now, pendingId, "pending"),
                )
                db.setTransactionSuccessful()
                return true
            }
            val amountMinor = amountMinorOverride ?: dbAmount
            if (amountMinor == null || amountMinor <= 0) return false

            if (!accountIdOverride.isNullOrBlank()) {
                accountId = accountIdOverride
            } else if (accountId.isNullOrBlank()) {
                val hint = when {
                    sourcePkg.contains("Alipay", ignoreCase = true) -> "alipay"
                    sourcePkg.contains("tencent.mm") -> "wechat"
                    else -> null
                }
                accountId = NativeCaptureIngest.resolveSuggestedAccount(
                    db, ledgerId, sourcePkg, hint,
                )
            }
            if (accountId.isNullOrBlank()) return false
            // 校验账户存在；入账账本跟随转出账户（避免切账本后记错本）。
            var accountCurrency = currency
            var insertLedgerId = ledgerId
            db.rawQuery(
                "SELECT currency, ledger_id FROM accounts WHERE id=? AND archived=0 LIMIT 1",
                arrayOf(accountId),
            ).use { c ->
                if (!c.moveToFirst()) return false
                accountCurrency = c.getString(0) ?: currency
                val accLedger = c.getString(1)
                if (!accLedger.isNullOrBlank()) insertLedgerId = accLedger
            }

            val rawDirection = directionOverride ?: dbDirection
            // in / out / transfer；退款/还款用标签与备注，不再单独成类型。
            val type = when (rawDirection) {
                "in", "refund" -> "in"
                "transfer" -> "transfer"
                else -> "out"
            }
            val direction = type
            val toAccountId = if (type == "transfer") toAccountIdOverride else null
            if (type == "transfer") {
                if (toAccountId.isNullOrBlank() || toAccountId == accountId) return false
                var toCurrency = accountCurrency
                db.rawQuery(
                    "SELECT currency FROM accounts WHERE id=? AND archived=0 LIMIT 1",
                    arrayOf(toAccountId),
                ).use { c ->
                    if (!c.moveToFirst()) return false
                    toCurrency = c.getString(0) ?: accountCurrency
                }
                // 悬浮窗不做跨币种换算，避免余额写错。
                if (!toCurrency.equals(accountCurrency, ignoreCase = true)) {
                    Log.w(TAG, "confirmPending reject cross-currency transfer")
                    return false
                }
            }
            // 流水币种与转出账户一致（同币种转账两边相同）。
            val txnCurrency = accountCurrency
            val refund = type != "transfer" &&
                isRefundSignal(rawDirection, rawTitle, rawText)
            val repay = type != "transfer" &&
                isRepaySignal(rawDirection, rawTitle, rawText)
            var note = when {
                noteOverride != null -> noteOverride
                else -> dbNote
            }
            if (refund) {
                val n = note?.trim().orEmpty()
                note = when {
                    n.isEmpty() -> "退款"
                    n.contains("退款") -> n
                    else -> "$n · 退款"
                }
            }
            val tagsJson = when {
                refund && repay -> """["退款","还款"]"""
                refund -> """["退款"]"""
                repay -> """["还款"]"""
                else -> null
            }
            val now = System.currentTimeMillis()
            val txnId = UUID.randomUUID().toString()
            val toAmountMinor = if (type == "transfer") amountMinor else null
            try {
                db.execSQL(
                    """
                    INSERT INTO transactions(
                      id, ledger_id, type, amount_minor, currency, account_id,
                      to_account_id, to_amount_minor, category_id, note, happen_at,
                      source, tags, pending_id, include_in_stat, include_in_budget,
                      created_at, updated_at
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """.trimIndent(),
                    arrayOf<Any?>(
                        txnId, insertLedgerId, type, amountMinor, txnCurrency, accountId,
                        toAccountId, toAmountMinor, categoryId, note, happenAt,
                        "notification", tagsJson, pendingId, 1, 1,
                        now, now,
                    ),
                )
            } catch (e: android.database.sqlite.SQLiteConstraintException) {
                // idx_transactions_pending_id：另一端已插入同一 pending_id。
                Log.i(TAG, "confirmPending race: txn already exists for $pendingId")
            }
            val retired = when {
                oldDedupe.isNullOrBlank() -> "done|$pendingId"
                oldDedupe.startsWith("done|") -> oldDedupe
                else -> "done|$pendingId|$oldDedupe"
            }
            db.execSQL(
                """
                UPDATE pending_captures SET status=?, amount_minor=?, currency=?,
                  suggested_category_id=?, suggested_account_id=?,
                  note=?, direction=?, dedupe_key=?, updated_at=?
                WHERE id=? AND status=?
                """.trimIndent(),
                arrayOf<Any?>(
                    "confirmed", amountMinor, txnCurrency, categoryId, accountId,
                    note, direction, retired, now, pendingId, "pending",
                ),
            )
            db.setTransactionSuccessful()
            return true
        } catch (e: Exception) {
            Log.e(TAG, "confirmPending failed", e)
            return false
        } finally {
            try {
                db.endTransaction()
            } catch (_: Exception) {
            }
            db.close()
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

    private fun isRefundSignal(direction: String?, title: String, text: String): Boolean {
        if (direction == "refund") return true
        // 与 Dart kTitleRefundWords 对齐：退款|退回|已退
        val hay = "$title\n$text"
        return Regex("退款|退回|已退").containsMatchIn(hay)
    }

    private fun isRepaySignal(direction: String?, title: String, text: String): Boolean {
        if (direction == "repay") return true
        val hay = "$title\n$text"
        if (Regex("待还|应还|请于|即将到期|还款提醒|账单提醒").containsMatchIn(hay)) {
            return false
        }
        if (title.contains("还款") || title.contains("还清")) return true
        return title.contains("代扣") &&
            Regex("还款|花呗|借呗|信用购").containsMatchIn(hay)
    }
}

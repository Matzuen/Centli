package com.centli.centli

import android.content.Context
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.PopupWindow
import android.widget.ScrollView
import android.widget.TextView
import android.view.WindowManager
import java.util.ArrayDeque

/**
 * 挂在悬浮窗摘要行旁的级联弹出菜单（PopupWindow）。
 * 有子项的行显示 ›，点入下一级；叶子勾选后回调并关闭。
 */
internal object OverlayCascadePopup {
    data class Item(
        val id: String,
        val label: String,
        val selected: Boolean = false,
        val children: List<Item> = emptyList(),
    ) {
        val isGroup: Boolean get() = children.isNotEmpty()
    }

    private var current: PopupWindow? = null

    fun dismiss() {
        try {
            current?.dismiss()
        } catch (_: Exception) {
        }
        current = null
    }

    fun show(
        anchor: View,
        items: List<Item>,
        onPick: (Item) -> Unit,
    ) {
        if (items.isEmpty()) return
        dismiss()

        val context = anchor.context
        val density = context.resources.displayMetrics.density
        val stack = ArrayDeque<Pair<String?, List<Item>>>()
        stack.addLast(null to items)

        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                setColor(0xFFF5F2FA.toInt())
                cornerRadius = 14 * density
                setStroke((1.2f * density).toInt(), 0x405B4B8A)
            }
            background = bg
            elevation = 10 * density
            setPadding(0, (6 * density).toInt(), 0, (6 * density).toInt())
        }

        val scroll = ScrollView(context).apply {
            overScrollMode = View.OVER_SCROLL_NEVER
            isVerticalScrollBarEnabled = false
        }
        val list = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
        }
        scroll.addView(
            list,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        card.addView(
            scroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )

        val maxH = (320 * density).toInt()
        val minW = (200 * density).toInt()
        val maxW = (280 * density).toInt()

        fun paint() {
            list.removeAllViews()
            val (parentLabel, level) = stack.last()
            if (stack.size > 1) {
                list.addView(
                    makeRow(
                        context = context,
                        density = density,
                        label = "‹ ${parentLabel ?: "返回"}",
                        trailing = null,
                        bold = true,
                        muted = true,
                    ) {
                        stack.removeLast()
                        paint()
                    },
                )
            }
            for (item in level) {
                val trailing = when {
                    item.isGroup -> "›"
                    item.selected -> "✓"
                    else -> null
                }
                list.addView(
                    makeRow(
                        context = context,
                        density = density,
                        label = item.label,
                        trailing = trailing,
                        bold = item.selected,
                        muted = false,
                        accent = item.selected,
                    ) {
                        if (item.isGroup) {
                            stack.addLast(item.label to item.children)
                            paint()
                        } else {
                            dismiss()
                            onPick(item)
                        }
                    },
                )
            }
            // Measure and clamp height.
            card.measure(
                View.MeasureSpec.makeMeasureSpec(maxW, View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
            )
            val h = card.measuredHeight.coerceAtMost(maxH)
            val w = card.measuredWidth.coerceIn(minW, maxW)
            val pop = current ?: return
            pop.width = w
            pop.height = h
            if (pop.isShowing) {
                pop.update(w, h)
            }
        }

        val popup = PopupWindow(
            card,
            maxW,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            true,
        ).apply {
            isOutsideTouchable = true
            isFocusable = true
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            elevation = 12 * density
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Match the SYSTEM_ALERT / application-overlay host window.
                windowLayoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }
            }
            setOnDismissListener {
                if (current === this) current = null
            }
        }
        current = popup
        paint()
        // Anchor below the summary row; fall back to drop-down gravity.
        try {
            popup.showAsDropDown(anchor, 0, (4 * density).toInt(), Gravity.END)
        } catch (_: Exception) {
            val loc = IntArray(2)
            anchor.getLocationOnScreen(loc)
            popup.showAtLocation(
                anchor,
                Gravity.TOP or Gravity.START,
                loc[0],
                loc[1] + anchor.height + (4 * density).toInt(),
            )
        }
    }

    private fun makeRow(
        context: Context,
        density: Float,
        label: String,
        trailing: String?,
        bold: Boolean,
        muted: Boolean,
        accent: Boolean = false,
        onClick: () -> Unit,
    ): View {
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = (44 * density).toInt()
            setPadding(
                (14 * density).toInt(),
                (8 * density).toInt(),
                (14 * density).toInt(),
                (8 * density).toInt(),
            )
            isClickable = true
            isFocusable = true
            val selectable = android.util.TypedValue()
            context.theme.resolveAttribute(
                android.R.attr.selectableItemBackground,
                selectable,
                true,
            )
            setBackgroundResource(selectable.resourceId)
            setOnClickListener { onClick() }
        }
        val color = when {
            accent -> 0xFF5B4B8A.toInt()
            muted -> 0xFF5B4B8A.toInt()
            else -> 0xFF1A1A1A.toInt()
        }
        val tv = TextView(context).apply {
            text = label
            textSize = 14f
            setTextColor(color)
            if (bold) paint.isFakeBoldText = true
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }
        row.addView(tv)
        if (!trailing.isNullOrEmpty()) {
            row.addView(
                TextView(context).apply {
                    text = trailing
                    textSize = 15f
                    setTextColor(0xFF5B4B8A.toInt())
                    paint.isFakeBoldText = true
                    setPadding((8 * density).toInt(), 0, 0, 0)
                },
            )
        }
        return row
    }
}

package com.centli.centli

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * P3 MVP home-screen widget: today expense (base ccy) + pending count.
 * Data is written from Flutter via [home_widget] SharedPreferences bridge.
 */
class CentliHomeWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.centli_home_widget).apply {
                val expenseLabel = widgetData.getString(KEY_EXPENSE_LABEL, null)
                    ?: context.getString(R.string.widget_expense_label)
                val expenseValue = widgetData.getString(KEY_EXPENSE_VALUE, null) ?: "--"
                val pendingLabel = widgetData.getString(KEY_PENDING_LABEL, null)
                    ?: context.getString(R.string.widget_pending_label)
                val pendingValue = widgetData.getString(KEY_PENDING_VALUE, null) ?: "0"
                val subtitle = widgetData.getString(KEY_SUBTITLE, null)
                    ?: context.getString(R.string.widget_subtitle_default)
                val hasPending = widgetData.getString(KEY_HAS_PENDING, "0") == "1"

                setTextViewText(R.id.widget_title, context.getString(R.string.widget_title))
                setTextViewText(R.id.widget_expense_label, expenseLabel)
                setTextViewText(R.id.widget_expense_value, expenseValue)
                setTextViewText(R.id.widget_pending_label, pendingLabel)
                setTextViewText(R.id.widget_pending_value, pendingValue)
                setTextViewText(R.id.widget_subtitle, subtitle)

                val homeUri = Uri.parse("centli://home")
                val pendingUri = Uri.parse("centli://pending")
                val openHome = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    homeUri,
                )
                val openPending = HomeWidgetLaunchIntent.getActivity(
                    context,
                    MainActivity::class.java,
                    if (hasPending) pendingUri else homeUri,
                )
                setOnClickPendingIntent(R.id.widget_root, openHome)
                setOnClickPendingIntent(R.id.widget_pending_row, openPending)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    companion object {
        const val KEY_EXPENSE_LABEL = "expense_label"
        const val KEY_EXPENSE_VALUE = "expense_value"
        const val KEY_PENDING_LABEL = "pending_label"
        const val KEY_PENDING_VALUE = "pending_value"
        const val KEY_SUBTITLE = "subtitle"
        const val KEY_HAS_PENDING = "has_pending"
    }
}

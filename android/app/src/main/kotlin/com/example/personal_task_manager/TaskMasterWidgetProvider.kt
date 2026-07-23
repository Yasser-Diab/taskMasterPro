package com.example.personal_task_manager

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import org.json.JSONObject

open class TaskMasterWidgetProvider(private val widgetKind: String) : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            appWidgetManager.updateAppWidget(widgetId, buildViews(context, widgetKind))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_REFRESH -> updateAll(context)
            ACTION_COMMAND -> {
                val command = intent.getStringExtra(EXTRA_COMMAND) ?: return
                recordCommand(context, command)
                updateAll(context)
                context.startActivity(openIntent(context, "taskmasterpro://widget/$command"))
            }
        }
    }

    companion object {
        private const val PREFS = "taskmasterpro_widget_snapshots"
        private const val ACTION_REFRESH =
            "com.example.personal_task_manager.action.WIDGET_REFRESH"
        private const val ACTION_COMMAND =
            "com.example.personal_task_manager.action.WIDGET_COMMAND"
        private const val EXTRA_COMMAND = "command"

        fun updateSnapshot(context: Context, kind: String, snapshot: JSONObject) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("widget.$kind", snapshot.toString())
                .putLong("widget.$kind.updated_at", System.currentTimeMillis())
                .apply()
            updateAll(context)
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val classes = listOf(
                TaskMasterActiveTimerWidgetProvider::class.java,
                TaskMasterTodayWidgetProvider::class.java,
                TaskMasterCoachingWidgetProvider::class.java
            )
            for (providerClass in classes) {
                val component = ComponentName(context, providerClass)
                val ids = manager.getAppWidgetIds(component)
                if (ids.isNotEmpty()) {
                    val kind = when (providerClass) {
                        TaskMasterActiveTimerWidgetProvider::class.java -> "active_timer"
                        TaskMasterTodayWidgetProvider::class.java -> "today"
                        else -> "coaching"
                    }
                    for (id in ids) {
                        manager.updateAppWidget(id, buildViews(context, kind))
                    }
                }
            }
        }

        private fun buildViews(context: Context, kind: String): RemoteViews {
            val snapshot = readSnapshot(context, kind)
            val layout = when (kind) {
                "today" -> R.layout.widget_today
                "coaching" -> R.layout.widget_coaching
                else -> R.layout.widget_active_timer
            }
            val views = RemoteViews(context.packageName, layout)
            when (kind) {
                "today" -> bindToday(context, views, snapshot)
                "coaching" -> bindCoaching(context, views, snapshot)
                else -> bindActiveTimer(context, views, snapshot)
            }
            views.setOnClickPendingIntent(R.id.widget_open, openPending(context, kind))
            views.setOnClickPendingIntent(R.id.widget_refresh, refreshPending(context, kind))
            return views
        }

        private fun bindActiveTimer(
            context: Context,
            views: RemoteViews,
            snapshot: JSONObject
        ) {
            views.setTextViewText(
                R.id.widget_title,
                snapshot.optString("title", "No active timer")
            )
            views.setTextViewText(
                R.id.widget_subtitle,
                snapshot.optString("subtitle", "TaskMaster Pro")
            )
            views.setTextViewText(
                R.id.widget_value,
                snapshot.optString("remaining", "--:--")
            )
            views.setTextViewText(
                R.id.widget_action_primary,
                snapshot.optString("primary_action_label", "Pause")
            )
            views.setTextViewText(
                R.id.widget_action_secondary,
                snapshot.optString("secondary_action_label", "Finish focus")
            )
            views.setOnClickPendingIntent(
                R.id.widget_action_primary,
                commandPending(context, snapshot.optString("primary_action", "pause"))
            )
            views.setOnClickPendingIntent(
                R.id.widget_action_secondary,
                commandPending(context, snapshot.optString("secondary_action", "finish_focus"))
            )
        }

        private fun bindToday(context: Context, views: RemoteViews, snapshot: JSONObject) {
            views.setTextViewText(R.id.widget_title, snapshot.optString("title", "Today"))
            views.setTextViewText(
                R.id.widget_line_one,
                snapshot.optString("line_one", "Open TaskMaster Pro")
            )
            views.setTextViewText(
                R.id.widget_line_two,
                snapshot.optString("line_two", "No offline snapshot yet")
            )
            views.setTextViewText(
                R.id.widget_line_three,
                snapshot.optString("line_three", "")
            )
            views.setTextViewText(
                R.id.widget_action_primary,
                snapshot.optString("primary_action_label", "Start")
            )
            views.setOnClickPendingIntent(
                R.id.widget_action_primary,
                commandPending(context, snapshot.optString("primary_action", "start"))
            )
        }

        private fun bindCoaching(context: Context, views: RemoteViews, snapshot: JSONObject) {
            views.setTextViewText(
                R.id.widget_title,
                snapshot.optString("title", "Next useful action")
            )
            views.setTextViewText(
                R.id.widget_line_one,
                snapshot.optString("line_one", "Open TaskMaster Pro")
            )
            views.setTextViewText(
                R.id.widget_line_two,
                snapshot.optString("line_two", "Your coaching snapshot will appear here.")
            )
        }

        private fun readSnapshot(context: Context, kind: String): JSONObject {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString("widget.$kind", null)
            return raw?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
        }

        private fun openPending(context: Context, kind: String): PendingIntent {
            return PendingIntent.getActivity(
                context,
                kind.hashCode(),
                openIntent(context, "taskmasterpro://widget/$kind"),
                pendingFlags()
            )
        }

        private fun openIntent(context: Context, uri: String): Intent {
            return Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse(uri)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        }

        private fun refreshPending(context: Context, kind: String): PendingIntent {
            val intent = Intent(context, providerClass(kind)).apply {
                action = ACTION_REFRESH
            }
            return PendingIntent.getBroadcast(
                context,
                kind.hashCode() xor 0x3333,
                intent,
                pendingFlags()
            )
        }

        private fun commandPending(context: Context, command: String): PendingIntent {
            val intent = Intent(context, providerClass("active_timer")).apply {
                action = ACTION_COMMAND
                putExtra(EXTRA_COMMAND, command)
            }
            return PendingIntent.getBroadcast(
                context,
                command.hashCode(),
                intent,
                pendingFlags()
            )
        }

        private fun providerClass(kind: String): Class<out AppWidgetProvider> {
            return when (kind) {
                "today" -> TaskMasterTodayWidgetProvider::class.java
                "coaching" -> TaskMasterCoachingWidgetProvider::class.java
                else -> TaskMasterActiveTimerWidgetProvider::class.java
            }
        }

        private fun pendingFlags(): Int {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        }

        private fun recordCommand(context: Context, command: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString("last_widget_command", command)
                .putLong("last_widget_command_at", System.currentTimeMillis())
                .apply()
        }
    }
}

class TaskMasterActiveTimerWidgetProvider : TaskMasterWidgetProvider("active_timer")

class TaskMasterTodayWidgetProvider : TaskMasterWidgetProvider("today")

class TaskMasterCoachingWidgetProvider : TaskMasterWidgetProvider("coaching")

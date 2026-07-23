package com.example.personal_task_manager

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import org.json.JSONObject

class TaskReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra(EXTRA_ID) ?: return
        val taskId = intent.getStringExtra(EXTRA_TASK_ID) ?: return
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "TaskMaster Pro"
        val body = intent.getStringExtra(EXTRA_BODY) ?: "Your task is ready."

        if (intent.action == ACTION_SNOOZE) {
            schedule(
                context,
                id,
                taskId,
                title,
                body,
                System.currentTimeMillis() + 10 * 60 * 1000L
            )
            return
        }
        if (intent.action == ACTION_DISMISS) {
            cancelNotification(context, id)
            recordDismissedNotification(context, id)
            removePersisted(context, id, taskId)
            return
        }

        createChannels(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(
            id.hashCode(),
            buildNotification(
                context,
                id,
                taskId,
                title,
                body,
                CHANNEL_TASK_REMINDERS
            )
        )
        recordLastNotification(context)
        removePersisted(context, id, taskId)
    }

    companion object {
        private const val ACTION_SHOW =
            "com.example.personal_task_manager.action.SHOW_TASK_REMINDER"
        private const val ACTION_SNOOZE =
            "com.example.personal_task_manager.action.SNOOZE_TASK_REMINDER"
        private const val ACTION_DISMISS =
            "com.example.personal_task_manager.action.DISMISS_TASK_REMINDER"
        private const val EXTRA_ID = "reminder_id"
        private const val EXTRA_TASK_ID = "task_id"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        const val CHANNEL_FOCUS_ALARM = "taskmaster_focus_alarm_v3"
        const val CHANNEL_BREAK_ALARM = "taskmaster_break_alarm_v2"
        const val CHANNEL_TASK_REMINDERS = "taskmaster_task_reminders_v2"
        const val CHANNEL_COACHING = "taskmaster_coaching_v2"
        private const val CHANNEL_PROGRESS_REPORTS = "taskmaster_progress_reports_v2"
        private const val PREFS = "taskmasterpro_task_reminders"
        private const val STATUS_PREFS = "taskmasterpro_notifications"

        fun schedule(
            context: Context,
            id: String,
            taskId: String,
            title: String,
            body: String,
            triggerAt: Long
        ) {
            if (triggerAt <= System.currentTimeMillis()) return
            val manager = context.getSystemService(AlarmManager::class.java)
            val pending = reminderPendingIntent(context, id, taskId, title, body)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                manager.canScheduleExactAlarms()
            ) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
            }
            persist(context, id, taskId, title, body, triggerAt)
        }

        fun showNow(
            context: Context,
            id: String,
            taskId: String,
            title: String,
            body: String,
            channel: String
        ) {
            createChannels(context)
            val channelId = when (channel) {
                "active_timer" -> ActiveSessionService.CHANNEL_ID
                "focus_alarm" -> CHANNEL_FOCUS_ALARM
                "break_alarm", "session_transitions" -> CHANNEL_BREAK_ALARM
                "overdue_coaching", "daily_coaching" -> CHANNEL_COACHING
                "progress_reports" -> CHANNEL_PROGRESS_REPORTS
                else -> CHANNEL_TASK_REMINDERS
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.notify(
                id.hashCode(),
                buildNotification(context, id, taskId, title, body, channelId)
            )
            recordLastNotification(context)
        }

        fun nextScheduledAt(context: Context): String? {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            val next = preferences.all
                .filterKeys { it.startsWith("reminder.") }
                .values
                .mapNotNull { value ->
                    val json = (value as? String)?.let {
                        runCatching { JSONObject(it) }.getOrNull()
                    } ?: return@mapNotNull null
                    json.optLong("triggerAt").takeIf { it > now }
                }
                .minOrNull()
            return next?.let { java.time.Instant.ofEpochMilli(it).toString() }
        }

        fun cancelTask(context: Context, taskId: String) {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val ids = preferences.getStringSet("task.$taskId", emptySet())?.toList().orEmpty()
            val manager = context.getSystemService(AlarmManager::class.java)
            for (id in ids) {
                val json = preferences.getString("reminder.$id", null)?.let(::JSONObject)
                val title = json?.optString("title") ?: "TaskMaster Pro"
                val body = json?.optString("body") ?: "Your task is ready."
                manager.cancel(reminderPendingIntent(context, id, taskId, title, body))
                preferences.edit().remove("reminder.$id").apply()
            }
            preferences.edit().remove("task.$taskId").apply()
        }

        fun restoreAll(context: Context) {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            for ((key, value) in preferences.all) {
                if (!key.startsWith("reminder.") || value !is String) continue
                val json = runCatching { JSONObject(value) }.getOrNull() ?: continue
                val triggerAt = json.optLong("triggerAt")
                if (triggerAt <= System.currentTimeMillis()) continue
                schedule(
                    context,
                    json.optString("id"),
                    json.optString("taskId"),
                    json.optString("title", "TaskMaster Pro"),
                    json.optString("body", "Your task is ready."),
                    triggerAt
                )
            }
        }

        private fun reminderPendingIntent(
            context: Context,
            id: String,
            taskId: String,
            title: String,
            body: String
        ): PendingIntent {
            val intent = Intent(context, TaskReminderReceiver::class.java).apply {
                action = ACTION_SHOW
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_TASK_ID, taskId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            return PendingIntent.getBroadcast(
                context,
                id.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun buildNotification(
            context: Context,
            id: String,
            taskId: String,
            title: String,
            body: String,
            channelId: String
        ): Notification {
            val openIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = android.net.Uri.parse("taskmasterpro://task/$taskId")
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openPending = PendingIntent.getActivity(
                context,
                taskId.hashCode(),
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val snoozeIntent = Intent(context, TaskReminderReceiver::class.java).apply {
                action = ACTION_SNOOZE
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_TASK_ID, taskId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            val snoozePending = PendingIntent.getBroadcast(
                context,
                id.hashCode() xor 0x51A0,
                snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val dismissIntent = Intent(context, TaskReminderReceiver::class.java).apply {
                action = ACTION_DISMISS
                putExtra(EXTRA_ID, id)
                putExtra(EXTRA_TASK_ID, taskId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            val dismissPending = PendingIntent.getBroadcast(
                context,
                id.hashCode() xor 0xD15A,
                dismissIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, channelId)
            } else {
                @Suppress("DEPRECATION") Notification.Builder(context)
            }
            val category = when (channelId) {
                CHANNEL_FOCUS_ALARM, CHANNEL_BREAK_ALARM -> Notification.CATEGORY_ALARM
                else -> Notification.CATEGORY_REMINDER
            }
            return builder
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(openPending)
                .setDeleteIntent(dismissPending)
                .setAutoCancel(true)
                .setCategory(category)
                .setPriority(
                    if (channelId == CHANNEL_FOCUS_ALARM || channelId == CHANNEL_BREAK_ALARM)
                        Notification.PRIORITY_HIGH
                    else
                        Notification.PRIORITY_DEFAULT
                )
                .addAction(
                    Notification.Action.Builder(
                        R.drawable.ic_notification,
                        "Open",
                        openPending
                    ).build()
                )
                .addAction(
                    Notification.Action.Builder(
                        R.drawable.ic_notification,
                        "Snooze 10 min",
                        snoozePending
                    ).build()
                )
                .addAction(
                    Notification.Action.Builder(
                        R.drawable.ic_notification,
                        "Dismiss",
                        dismissPending
                    ).build()
                )
                .build()
        }

        private fun createChannels(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java)
            val alarmAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val notificationAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            manager.createNotificationChannels(
                listOf(
                    NotificationChannel(
                        ActiveSessionService.CHANNEL_ID,
                        "Active timer",
                        NotificationManager.IMPORTANCE_LOW
                    ).apply {
                        description = "Ongoing timer while a TaskMaster Pro task is running."
                        setShowBadge(false)
                    },
                    NotificationChannel(
                        CHANNEL_TASK_REMINDERS,
                        "Task reminders",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Reminders for scheduled TaskMaster Pro tasks."
                        setSound(rawSound(context, R.raw.task_reminder), notificationAttributes)
                    },
                    NotificationChannel(
                        CHANNEL_FOCUS_ALARM,
                        "Focus completion alarms",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Alarms when a TaskMaster Pro focus session completes."
                        setSound(rawSound(context, R.raw.critical_alarm), alarmAttributes)
                        enableVibration(true)
                    },
                    NotificationChannel(
                        CHANNEL_BREAK_ALARM,
                        "Break alarms",
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "Alarms for TaskMaster Pro break start and completion."
                        setSound(rawSound(context, R.raw.break_finished), alarmAttributes)
                        enableVibration(true)
                    },
                    NotificationChannel(
                        CHANNEL_COACHING,
                        "TaskMaster coaching",
                        NotificationManager.IMPORTANCE_DEFAULT
                    ).apply {
                        description = "Daily, overdue, and adaptive productivity coaching."
                        setSound(rawSound(context, R.raw.daily_coaching), notificationAttributes)
                    },
                    NotificationChannel(
                        CHANNEL_PROGRESS_REPORTS,
                        "Progress reports",
                        NotificationManager.IMPORTANCE_DEFAULT
                    ).apply {
                        description = "Daily and weekly TaskMaster Pro progress summaries."
                        setSound(rawSound(context, R.raw.task_reminder), notificationAttributes)
                    },
                )
            )
        }

        fun rawSound(context: Context, resourceId: Int): Uri {
            return Uri.parse("android.resource://${context.packageName}/$resourceId")
        }

        private fun recordLastNotification(context: Context) {
            context.getSharedPreferences(STATUS_PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(
                    "last_notification_at",
                    java.time.Instant.ofEpochMilli(System.currentTimeMillis()).toString()
                )
                .putString("last_notification_result", "posted")
                .apply()
        }

        private fun recordDismissedNotification(context: Context, id: String) {
            context.getSharedPreferences(STATUS_PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(
                    "last_notification_dismissed_at",
                    java.time.Instant.ofEpochMilli(System.currentTimeMillis()).toString()
                )
                .putString("last_notification_dismissed_id", id)
                .putString("last_notification_result", "dismissed")
                .apply()
        }

        private fun cancelNotification(context: Context, id: String) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.cancel(id.hashCode())
        }

        private fun persist(
            context: Context,
            id: String,
            taskId: String,
            title: String,
            body: String,
            triggerAt: Long
        ) {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val ids = preferences.getStringSet("task.$taskId", emptySet())?.toMutableSet()
                ?: mutableSetOf()
            ids.add(id)
            val json = JSONObject()
                .put("id", id)
                .put("taskId", taskId)
                .put("title", title)
                .put("body", body)
                .put("triggerAt", triggerAt)
            preferences.edit()
                .putString("reminder.$id", json.toString())
                .putStringSet("task.$taskId", ids)
                .apply()
        }

        private fun removePersisted(context: Context, id: String, taskId: String) {
            val preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val ids = preferences.getStringSet("task.$taskId", emptySet())?.toMutableSet()
                ?: mutableSetOf()
            ids.remove(id)
            val edit = preferences.edit().remove("reminder.$id")
            if (ids.isEmpty()) edit.remove("task.$taskId") else edit.putStringSet("task.$taskId", ids)
            edit.apply()
        }
    }
}

class TaskReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_BOOT_COMPLETED ||
            intent?.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            TaskReminderReceiver.restoreAll(context)
        }
    }
}

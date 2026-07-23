package com.example.personal_task_manager

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class ActiveSessionService : Service() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                recordTimerState(false)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START_OR_UPDATE, null -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "TaskMaster Pro"
                val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Active session"
                recordTimerState(true)
                startForeground(NOTIFICATION_ID, buildNotification(title, text))
                return START_STICKY
            }
        }

        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            "TaskMaster Pro active session",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps active TaskMaster Pro sessions running."
            setShowBadge(false)
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            openIntent,
            pendingIntentFlags
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_STATUS)
            .build()
    }

    private fun recordTimerState(running: Boolean) {
        getSharedPreferences(STATUS_PREFS, MODE_PRIVATE)
            .edit()
            .putBoolean("active_timer_running", running)
            .apply()
    }

    companion object {
        const val ACTION_START_OR_UPDATE =
            "com.example.personal_task_manager.action.START_OR_UPDATE"
        const val ACTION_STOP = "com.example.personal_task_manager.action.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        const val CHANNEL_ID = "taskmaster_background_timer_v2"
        private const val NOTIFICATION_ID = 2101
        private const val STATUS_PREFS = "taskmasterpro_notifications"
    }
}

package pro.taskmaster.taskmaster_pro

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val activityChannel = "taskmasterpro/activity"
    private val notificationChannel = "taskmasterpro/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            activityChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageAccess" -> result.success(hasUsageAccess())
                "openUsageAccess" -> {
                    startActivity(
                        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        },
                    )
                    result.success(null)
                }
                "sampleForegroundActivity" -> {
                    if (!hasUsageAccess()) {
                        result.success(null)
                    } else {
                        result.success(sampleForegroundActivity())
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationChannelSettings" -> {
                    val channelId = call.argument<String>("channelId")
                    if (channelId.isNullOrBlank()) {
                        result.error("missing_channel", "A channel ID is required", null)
                    } else {
                        val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun sampleForegroundActivity(): Map<String, Any?>? {
        val manager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val events = manager.queryEvents(now - 60_000, now)
        val event = UsageEvents.Event()
        var currentPackage: String? = null
        var lastTimestamp = 0L
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (
                event.eventType == UsageEvents.Event.ACTIVITY_RESUMED ||
                    event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND
            ) {
                if (event.timeStamp >= lastTimestamp) {
                    currentPackage = event.packageName
                    lastTimestamp = event.timeStamp
                }
            }
        }
        if (currentPackage == null) {
            val latest = manager
                .queryUsageStats(
                    UsageStatsManager.INTERVAL_DAILY,
                    now - 60_000,
                    now,
                )
                .maxByOrNull { it.lastTimeUsed }
            currentPackage = latest?.packageName
            lastTimestamp = latest?.lastTimeUsed ?: 0L
        }
        if (currentPackage == null) return null
        val label = try {
            val info = packageManager.getApplicationInfo(currentPackage, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            currentPackage
        }
        return mapOf(
            "applicationName" to label,
            "packageName" to currentPackage,
            "windowTitle" to null,
            "idleSeconds" to 0,
            "lastTimeUsed" to lastTimestamp,
            "isTaskMasterWindow" to (currentPackage == packageName),
        )
    }
}

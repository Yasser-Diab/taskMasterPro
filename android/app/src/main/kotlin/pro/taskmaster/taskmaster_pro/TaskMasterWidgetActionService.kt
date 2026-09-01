package pro.taskmaster.taskmaster_pro

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.util.UUID

internal data class TaskMasterBackgroundCommand(
    val deliveryId: String,
    val kind: String,
    val actionId: String,
    val ownerId: String? = null,
    val taskId: String? = null,
    val sessionId: String? = null,
    val runtimeRevision: Int? = null,
    val payload: String? = null,
    val notificationId: Int? = null,
    val notificationTag: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "deliveryId" to deliveryId,
        "kind" to kind,
        "id" to actionId,
        "ownerId" to ownerId,
        "taskId" to taskId,
        "sessionId" to sessionId,
        "runtimeRevision" to runtimeRevision,
        "payload" to payload,
        "notificationId" to notificationId,
        "notificationTag" to notificationTag,
    )

    companion object {
        private val supportedWidgetActions = setOf(
            "pause",
            "start_break",
            "finish_task",
            "resume",
            "start_focus",
            "extend_break",
        )

        fun widgetFromIntent(intent: Intent?): TaskMasterBackgroundCommand? {
            if (intent?.action != TaskMasterWidgetIntent.commandAction) return null
            val actionId = intent.getStringExtra(TaskMasterWidgetIntent.actionIdExtra)
                ?.trim()
                .orEmpty()
            val ownerId = intent.getStringExtra(TaskMasterWidgetIntent.ownerIdExtra)
                ?.trim()
                .orEmpty()
            val taskId = intent.getStringExtra(TaskMasterWidgetIntent.taskIdExtra)
                ?.trim()
                .orEmpty()
            val sessionId = intent.getStringExtra(TaskMasterWidgetIntent.sessionIdExtra)
                ?.trim()
                .orEmpty()
            val revision = intent.getIntExtra(
                TaskMasterWidgetIntent.runtimeRevisionExtra,
                -1,
            )
            if (
                actionId !in supportedWidgetActions ||
                ownerId.isBlank() ||
                taskId.isBlank() ||
                sessionId.isBlank() ||
                revision < 0
            ) {
                return null
            }
            return TaskMasterBackgroundCommand(
                deliveryId = UUID.randomUUID().toString(),
                kind = "widget",
                actionId = actionId,
                ownerId = ownerId,
                taskId = taskId,
                sessionId = sessionId,
                runtimeRevision = revision,
            )
        }

        fun notificationFromIntent(intent: Intent?): TaskMasterBackgroundCommand? {
            if (intent?.action != TaskMasterNotificationActionReceiver.actionTapped) return null
            val actionId = intent.getStringExtra("actionId")?.trim().orEmpty()
            val payload = intent.getStringExtra("payload")?.trim().orEmpty()
            if (actionId.isBlank() || payload.isBlank()) return null
            return TaskMasterBackgroundCommand(
                deliveryId = UUID.randomUUID().toString(),
                kind = "notification",
                actionId = actionId,
                payload = payload,
                notificationId = intent.getIntExtra("notificationId", -1).takeIf { it >= 0 },
                notificationTag = intent.getStringExtra("notificationTag"),
            )
        }

        fun fromServiceIntent(intent: Intent?): TaskMasterBackgroundCommand? =
            when (intent?.action) {
                TaskMasterWidgetIntent.commandAction -> widgetFromIntent(intent)
                TaskMasterNotificationActionReceiver.serviceAction ->
                    notificationFromIntent(
                        Intent(intent).apply {
                            action = TaskMasterNotificationActionReceiver.actionTapped
                        },
                    )
                else -> null
            }
    }
}

/** Receives an explicit launcher PendingIntent without starting MainActivity. */
class TaskMasterWidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (TaskMasterBackgroundCommand.widgetFromIntent(intent) == null) return
        startBackgroundActionService(context, Intent(intent))
    }
}

/** Receives flutter_local_notifications actions that are configured as headless. */
class TaskMasterNotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val command = TaskMasterBackgroundCommand.notificationFromIntent(intent) ?: return
        if (intent.getBooleanExtra("cancelNotification", false)) {
            val manager = context.getSystemService(NotificationManager::class.java)
            val id = command.notificationId
            if (id != null) {
                val tag = command.notificationTag
                if (tag.isNullOrBlank()) manager.cancel(id) else manager.cancel(tag, id)
            }
        }
        startBackgroundActionService(
            context,
            Intent(intent).apply { action = serviceAction },
        )
    }

    companion object {
        const val actionTapped =
            "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver.ACTION_TAPPED"
        const val serviceAction = "pro.taskmaster.app.action.NOTIFICATION_COMMAND"
    }
}

private fun startBackgroundActionService(context: Context, intent: Intent) {
    intent.setClass(context, TaskMasterBackgroundActionService::class.java)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
    } else {
        context.startService(intent)
    }
}

/**
 * Runs a dedicated Dart command entrypoint in a headless engine. No Activity
 * or Flutter route is created; the account/session/revision guard still runs
 * before every mutation and the widget is refreshed from canonical local data.
 */
class TaskMasterBackgroundActionService : Service(), MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val queue = ArrayDeque<TaskMasterBackgroundCommand>()
    private var activeCommand: TaskMasterBackgroundCommand? = null
    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null
    private var latestStartId = 0

    private val timeout = Runnable {
        Log.w(logTag, "Headless command timed out")
        finishActiveCommand(handled = false)
    }

    override fun onCreate() {
        super.onCreate()
        createForegroundChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        startForeground(foregroundNotificationId, foregroundNotification())
        val command = TaskMasterBackgroundCommand.fromServiceIntent(intent)
        if (command == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        queue.addLast(command)
        if (activeCommand == null) startNextCommand()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startNextCommand() {
        if (activeCommand != null) return
        val command = queue.pollFirst()
        if (command == null) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf(latestStartId)
            return
        }
        activeCommand = command
        mainHandler.removeCallbacks(timeout)
        mainHandler.postDelayed(timeout, commandTimeoutMs)

        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) {
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, emptyArray())
        }
        val engine = FlutterEngine(applicationContext)
        flutterEngine = engine
        methodChannel = MethodChannel(
            engine.dartExecutor.binaryMessenger,
            backgroundChannel,
        ).also { it.setMethodCallHandler(this) }
        val entrypoint = DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(),
            "taskMasterBackgroundActionMain",
        )
        Log.i(logTag, "Starting ${command.kind} action=${command.actionId}")
        engine.dartExecutor.executeDartEntrypoint(entrypoint)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "takeAction" -> result.success(activeCommand?.toMap())
            "update" -> {
                val arguments = call.arguments as? Map<*, *>
                if (arguments == null) {
                    result.error("invalid_widget_state", "Widget state is required", null)
                    return
                }
                val accepted = TaskMasterWidgetStore.save(applicationContext, arguments)
                if (accepted) {
                    TaskMasterWidgetProvider.updateAll(applicationContext)
                }
                result.success(
                    mapOf(
                        "widgetCount" to TaskMasterWidgetProvider.widgetCount(
                            applicationContext,
                        ),
                        "pinRequested" to false,
                        "accepted" to accepted,
                    ),
                )
            }
            "completeAction" -> {
                val arguments = call.arguments as? Map<*, *>
                val deliveryId = arguments?.get("deliveryId")?.toString().orEmpty()
                val handled = arguments?.get("handled") == true
                if (deliveryId != activeCommand?.deliveryId) {
                    result.error("stale_delivery", "Background action delivery changed", null)
                    return
                }
                result.success(null)
                finishActiveCommand(handled)
            }
            else -> result.notImplemented()
        }
    }

    private fun finishActiveCommand(handled: Boolean) {
        val command = activeCommand
        mainHandler.removeCallbacks(timeout)
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        flutterEngine?.destroy()
        flutterEngine = null
        activeCommand = null
        if (command != null) {
            Log.i(logTag, "Finished ${command.kind} action=${command.actionId} handled=$handled")
        }
        TaskMasterWidgetProvider.updateAll(applicationContext)
        if (queue.isEmpty()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf(latestStartId)
        } else {
            mainHandler.post { startNextCommand() }
        }
    }

    private fun createForegroundChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(
                foregroundChannelId,
                "Task controls",
                NotificationManager.IMPORTANCE_MIN,
            ).apply {
                description = "Applies a task control selected outside the app."
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            },
        )
    }

    private fun foregroundNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            foregroundNotificationId,
            Intent(this, MainActivity::class.java).apply {
                action = "pro.taskmaster.app.action.OPEN_FROM_WIDGET"
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, foregroundChannelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("DayVector")
            .setContentText("Applying your task control")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .build()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(timeout)
        methodChannel?.setMethodCallHandler(null)
        flutterEngine?.destroy()
        methodChannel = null
        flutterEngine = null
        super.onDestroy()
    }

    companion object {
        private const val logTag = "TaskMasterBackground"
        private const val backgroundChannel = "taskmasterpro/background_actions"
        private const val foregroundChannelId = "taskmaster_background_controls_v1"
        private const val foregroundNotificationId = 820128
        private const val commandTimeoutMs = 30_000L
    }
}

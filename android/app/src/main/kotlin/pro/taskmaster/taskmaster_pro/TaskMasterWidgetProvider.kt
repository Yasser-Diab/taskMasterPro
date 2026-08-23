package pro.taskmaster.taskmaster_pro

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews

internal data class TaskMasterWidgetSuggestion(
    val id: String,
    val title: String,
)

internal data class TaskMasterWidgetControl(
    val id: String,
    val label: String,
)

internal data class TaskMasterWidgetState(
    val mode: String,
    val localeCode: String,
    val statusLabel: String,
    val title: String,
    val message: String,
    val timerLabel: String,
    val timerMode: String,
    val timerBoundaryEpochMs: Long?,
    val progressPercent: Int,
    val actionLabel: String,
    val completionLabel: String,
    val taskId: String?,
    val sessionId: String?,
    val runtimeRevision: Int?,
    val suggestions: List<TaskMasterWidgetSuggestion>,
    val controls: List<TaskMasterWidgetControl>,
)

internal object TaskMasterWidgetIntent {
    const val commandAction = "pro.taskmaster.app.action.WIDGET_COMMAND"
    const val actionIdExtra = "taskmaster_widget_action"
    const val taskIdExtra = "taskmaster_widget_task_id"
    const val sessionIdExtra = "taskmaster_widget_session_id"
    const val runtimeRevisionExtra = "taskmaster_widget_runtime_revision"
}

internal object TaskMasterWidgetStore {
    private const val preferencesName = "taskmaster.home_widget"
    private const val autoPinPromptVersion = 1
    private val supportedControlIds = setOf(
        "pause",
        "start_break",
        "finish_task",
        "resume",
        "start_focus",
        "extend_break",
        "review_break",
    )

    private fun preferences(context: Context) =
        context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    fun save(context: Context, arguments: Map<*, *>) {
        val mode = arguments["mode"]?.toString().orEmpty()
            .takeIf { it in setOf("idle", "running", "paused", "break") }
            ?: "idle"
        val suggestions = (arguments["suggestions"] as? List<*>)
            .orEmpty()
            .mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                val id = bounded(map["id"], 80)
                val title = bounded(map["title"], 90)
                if (id.isBlank() || title.isBlank()) null
                else TaskMasterWidgetSuggestion(id, title)
            }
            .take(3)
        val controls = (arguments["controls"] as? List<*>)
            .orEmpty()
            .mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                val id = bounded(map["id"], 40)
                val label = bounded(map["label"], 30)
                if (id !in supportedControlIds || label.isBlank()) null
                else TaskMasterWidgetControl(id, label)
            }
            .take(3)

        preferences(context).edit().apply {
            putString("mode", mode)
            putString("locale_code", bounded(arguments["localeCode"], 12, "en"))
            putString("status_label", bounded(arguments["statusLabel"], 50))
            putString("title", bounded(arguments["title"], 100))
            putString("message", bounded(arguments["message"], 180))
            putString("timer_label", bounded(arguments["timerLabel"], 40))
            putString(
                "timer_mode",
                arguments["timerMode"]?.toString()
                    ?.takeIf { it in setOf("fixed", "countdown", "countup") }
                    ?: "fixed",
            )
            val timerBoundary = (arguments["timerBoundaryEpochMs"] as? Number)?.toLong()
            if (timerBoundary == null) remove("timer_boundary_epoch_ms")
            else putLong("timer_boundary_epoch_ms", timerBoundary)
            putInt(
                "progress_percent",
                ((arguments["progressPercent"] as? Number)?.toInt() ?: 0)
                    .coerceIn(0, 100),
            )
            putString("action_label", bounded(arguments["actionLabel"], 40))
            putString("completion_label", bounded(arguments["completionLabel"], 140))
            putNullableString("task_id", bounded(arguments["taskId"], 80))
            putNullableString("session_id", bounded(arguments["sessionId"], 80))
            val runtimeRevision = (arguments["runtimeRevision"] as? Number)?.toInt()
            if (runtimeRevision == null || runtimeRevision < 0) {
                remove("runtime_revision")
            } else {
                putInt("runtime_revision", runtimeRevision)
            }
            putInt("suggestion_count", suggestions.size)
            repeat(3) { index ->
                val suggestion = suggestions.getOrNull(index)
                if (suggestion == null) {
                    remove("suggestion_${index}_id")
                    remove("suggestion_${index}_title")
                } else {
                    putString("suggestion_${index}_id", suggestion.id)
                    putString("suggestion_${index}_title", suggestion.title)
                }
            }
            putInt("control_count", controls.size)
            repeat(3) { index ->
                val control = controls.getOrNull(index)
                if (control == null) {
                    remove("control_${index}_id")
                    remove("control_${index}_label")
                } else {
                    putString("control_${index}_id", control.id)
                    putString("control_${index}_label", control.label)
                }
            }
            putLong("updated_at_epoch_ms", System.currentTimeMillis())
        }.apply()
    }

    fun read(context: Context): TaskMasterWidgetState {
        val values = preferences(context)
        val count = values.getInt("suggestion_count", 0).coerceIn(0, 3)
        val suggestions = (0 until count).mapNotNull { index ->
            val id = values.getString("suggestion_${index}_id", null).orEmpty()
            val title = values.getString("suggestion_${index}_title", null).orEmpty()
            if (id.isBlank() || title.isBlank()) null
            else TaskMasterWidgetSuggestion(id, title)
        }
        val controlCount = values.getInt("control_count", 0).coerceIn(0, 3)
        val controls = (0 until controlCount).mapNotNull { index ->
            val id = values.getString("control_${index}_id", null).orEmpty()
            val label = values.getString("control_${index}_label", null).orEmpty()
            if (id !in supportedControlIds || label.isBlank()) null
            else TaskMasterWidgetControl(id, label)
        }
        return TaskMasterWidgetState(
            mode = values.getString("mode", "idle") ?: "idle",
            localeCode = values.getString("locale_code", "en") ?: "en",
            statusLabel = values.getString(
                "status_label",
                context.getString(R.string.widget_default_status),
            ) ?: context.getString(R.string.widget_default_status),
            title = values.getString(
                "title",
                context.getString(R.string.widget_default_title),
            ) ?: context.getString(R.string.widget_default_title),
            message = values.getString(
                "message",
                context.getString(R.string.widget_default_message),
            ) ?: context.getString(R.string.widget_default_message),
            timerLabel = values.getString(
                "timer_label",
                context.getString(R.string.widget_default_ready),
            ) ?: context.getString(R.string.widget_default_ready),
            timerMode = values.getString("timer_mode", "fixed") ?: "fixed",
            timerBoundaryEpochMs = if (values.contains("timer_boundary_epoch_ms")) {
                values.getLong("timer_boundary_epoch_ms", 0L)
            } else {
                null
            },
            progressPercent = values.getInt("progress_percent", 0).coerceIn(0, 100),
            actionLabel = values.getString(
                "action_label",
                context.getString(R.string.widget_default_action),
            ) ?: context.getString(R.string.widget_default_action),
            completionLabel = values.getString(
                "completion_label",
                context.getString(R.string.widget_default_completion),
            ) ?: context.getString(R.string.widget_default_completion),
            taskId = values.getString("task_id", null),
            sessionId = values.getString("session_id", null),
            runtimeRevision = if (values.contains("runtime_revision")) {
                values.getInt("runtime_revision", -1).takeIf { it >= 0 }
            } else {
                null
            },
            suggestions = suggestions,
            controls = controls,
        )
    }

    fun clearState(context: Context) {
        val values = preferences(context)
        val promptVersion = values.getInt("auto_pin_prompt_version", 0)
        values.edit().clear().putInt("auto_pin_prompt_version", promptVersion).apply()
    }

    fun autoPinPromptWasRequested(context: Context): Boolean =
        preferences(context).getInt("auto_pin_prompt_version", 0) >= autoPinPromptVersion

    fun markAutoPinPromptRequested(context: Context) {
        preferences(context).edit()
            .putInt("auto_pin_prompt_version", autoPinPromptVersion)
            .apply()
    }

    private fun bounded(value: Any?, maxLength: Int, fallback: String = ""): String =
        value?.toString()?.trim()?.take(maxLength)?.ifBlank { fallback } ?: fallback

    private fun android.content.SharedPreferences.Editor.putNullableString(
        key: String,
        value: String,
    ) {
        if (value.isBlank()) remove(key) else putString(key, value)
    }
}

class TaskMasterWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { updateWidget(context, appWidgetManager, it) }
        scheduleBoundaryRefresh(context, TaskMasterWidgetStore.read(context))
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        updateWidget(context, appWidgetManager, appWidgetId)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == actionTimerBoundary ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            updateAll(context)
        }
    }

    override fun onDisabled(context: Context) {
        cancelBoundaryRefresh(context)
        super.onDisabled(context)
    }

    companion object {
        private const val actionTimerBoundary =
            "pro.taskmaster.app.action.WIDGET_TIMER_BOUNDARY"
        private const val boundaryRequestCode = 8401
        private const val openAppRequestCode = 8402
        private const val controlRequestCodeBase = 8500

        fun widgetCount(context: Context): Int =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, TaskMasterWidgetProvider::class.java))
                .size

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TaskMasterWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { id ->
                updateWidget(context, manager, id)
            }
            scheduleBoundaryRefresh(context, TaskMasterWidgetStore.read(context))
        }

        fun requestPin(context: Context, automatic: Boolean): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || widgetCount(context) > 0) {
                return false
            }
            if (automatic && TaskMasterWidgetStore.autoPinPromptWasRequested(context)) {
                return false
            }
            val manager = AppWidgetManager.getInstance(context)
            if (!manager.isRequestPinAppWidgetSupported) return false
            val accepted = manager.requestPinAppWidget(
                ComponentName(context, TaskMasterWidgetProvider::class.java),
                null,
                null,
            )
            if (automatic && accepted) {
                TaskMasterWidgetStore.markAutoPinPromptRequested(context)
            }
            return accepted
        }

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val options = manager.getAppWidgetOptions(appWidgetId)
            val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
            val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
            val layout = when {
                minWidth < 210 || minHeight < 100 -> R.layout.taskmaster_widget_compact
                minWidth >= 300 && minHeight >= 170 -> R.layout.taskmaster_widget_expanded
                else -> R.layout.taskmaster_widget_medium
            }
            val state = TaskMasterWidgetStore.read(context)
            val views = RemoteViews(context.packageName, layout)
            render(context, views, state, layout)
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun render(
            context: Context,
            views: RemoteViews,
            state: TaskMasterWidgetState,
            layout: Int,
        ) {
            val isCompact = layout == R.layout.taskmaster_widget_compact
            val isExpanded = layout == R.layout.taskmaster_widget_expanded
            val isIdle = state.mode == "idle"
            val isRtl = state.localeCode.lowercase().startsWith("ar")
            views.setInt(
                R.id.widget_root,
                "setLayoutDirection",
                if (isRtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR,
            )
            views.setInt(
                R.id.widget_root,
                "setBackgroundResource",
                when (state.mode) {
                    "break" -> R.drawable.widget_background_break
                    "paused" -> R.drawable.widget_background_paused
                    "running" -> R.drawable.widget_background_focus
                    else -> R.drawable.widget_background_idle
                },
            )
            views.setViewVisibility(
                R.id.widget_header,
                if (isCompact && !isIdle) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_status, state.statusLabel)
            views.setTextViewText(R.id.widget_title, state.title)
            val message = if (isIdle && !isExpanded && state.suggestions.isNotEmpty()) {
                state.suggestions.first().title
            } else {
                state.message
            }
            views.setTextViewText(R.id.widget_message, message)
            views.setViewVisibility(
                R.id.widget_message,
                if (isCompact) View.GONE else View.VISIBLE,
            )
            views.setTextViewText(R.id.widget_action, state.actionLabel)
            views.setViewVisibility(
                R.id.widget_action,
                if (isIdle && !isCompact) View.VISIBLE else View.GONE,
            )
            views.setProgressBar(R.id.widget_progress, 100, state.progressPercent, false)
            views.setViewVisibility(
                R.id.widget_progress,
                if (isIdle || isCompact) View.GONE else View.VISIBLE,
            )

            renderTimer(views, state)
            renderSuggestions(views, state, isExpanded)
            renderControls(context, views, state)

            val openApp = PendingIntent.getActivity(
                context,
                openAppRequestCode,
                Intent(context, MainActivity::class.java).apply {
                    action = "pro.taskmaster.app.action.OPEN_FROM_WIDGET"
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openApp)
            views.setOnClickPendingIntent(R.id.widget_action, openApp)
            views.setOnClickPendingIntent(R.id.widget_suggestion_1, openApp)
            views.setOnClickPendingIntent(R.id.widget_suggestion_2, openApp)
            views.setOnClickPendingIntent(R.id.widget_suggestion_3, openApp)
        }

        private fun renderControls(
            context: Context,
            views: RemoteViews,
            state: TaskMasterWidgetState,
        ) {
            val hasIdentity =
                !state.taskId.isNullOrBlank() &&
                    !state.sessionId.isNullOrBlank() &&
                    state.runtimeRevision != null
            val controls = if (hasIdentity && state.mode != "idle") {
                state.controls
            } else {
                emptyList()
            }
            views.setViewVisibility(
                R.id.widget_controls,
                if (controls.isNotEmpty()) View.VISIBLE else View.GONE,
            )
            val ids = intArrayOf(
                R.id.widget_control_1,
                R.id.widget_control_2,
                R.id.widget_control_3,
            )
            ids.forEachIndexed { index, viewId ->
                val control = controls.getOrNull(index)
                views.setViewVisibility(
                    viewId,
                    if (control == null) View.GONE else View.VISIBLE,
                )
                if (control == null) return@forEachIndexed
                views.setTextViewText(viewId, control.label)
                val isFinish = control.id == "finish_task"
                views.setInt(
                    viewId,
                    "setBackgroundResource",
                    when {
                        isFinish -> R.drawable.widget_control_finish_background
                        index == 0 -> R.drawable.widget_button_background
                        else -> R.drawable.widget_control_secondary_background
                    },
                )
                views.setTextColor(
                    viewId,
                    when {
                        isFinish -> Color.rgb(255, 226, 226)
                        index == 0 -> Color.rgb(24, 32, 51)
                        else -> Color.WHITE
                    },
                )
                views.setOnClickPendingIntent(
                    viewId,
                    PendingIntent.getActivity(
                        context,
                        controlRequestCodeBase + index,
                        Intent(context, MainActivity::class.java).apply {
                            action = TaskMasterWidgetIntent.commandAction
                            putExtra(TaskMasterWidgetIntent.actionIdExtra, control.id)
                            putExtra(TaskMasterWidgetIntent.taskIdExtra, state.taskId.orEmpty())
                            putExtra(
                                TaskMasterWidgetIntent.sessionIdExtra,
                                state.sessionId.orEmpty(),
                            )
                            putExtra(
                                TaskMasterWidgetIntent.runtimeRevisionExtra,
                                state.runtimeRevision ?: -1,
                            )
                            addFlags(
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
                            )
                        },
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }
        }

        private fun renderTimer(views: RemoteViews, state: TaskMasterWidgetState) {
            val boundary = state.timerBoundaryEpochMs
            val now = System.currentTimeMillis()
            val countdownFinished =
                state.timerMode == "countdown" && boundary != null && boundary <= now
            if (countdownFinished) {
                views.setViewVisibility(R.id.widget_timer_chronometer, View.GONE)
                views.setViewVisibility(R.id.widget_timer_text, View.VISIBLE)
                views.setTextViewText(R.id.widget_timer_text, "00:00")
                views.setTextViewText(R.id.widget_message, state.completionLabel)
                return
            }
            if (boundary != null &&
                (state.timerMode == "countdown" || state.timerMode == "countup")
            ) {
                val base = SystemClock.elapsedRealtime() + (boundary - now)
                views.setViewVisibility(R.id.widget_timer_text, View.GONE)
                views.setViewVisibility(R.id.widget_timer_chronometer, View.VISIBLE)
                views.setChronometer(
                    R.id.widget_timer_chronometer,
                    base,
                    null,
                    true,
                )
                views.setChronometerCountDown(
                    R.id.widget_timer_chronometer,
                    state.timerMode == "countdown",
                )
            } else {
                views.setViewVisibility(R.id.widget_timer_chronometer, View.GONE)
                views.setViewVisibility(R.id.widget_timer_text, View.VISIBLE)
                views.setTextViewText(R.id.widget_timer_text, state.timerLabel)
            }
        }

        private fun renderSuggestions(
            views: RemoteViews,
            state: TaskMasterWidgetState,
            expanded: Boolean,
        ) {
            val show = expanded && state.mode == "idle" && state.suggestions.isNotEmpty()
            views.setViewVisibility(
                R.id.widget_suggestions,
                if (show) View.VISIBLE else View.GONE,
            )
            val ids = intArrayOf(
                R.id.widget_suggestion_1,
                R.id.widget_suggestion_2,
                R.id.widget_suggestion_3,
            )
            ids.forEachIndexed { index, id ->
                val suggestion = state.suggestions.getOrNull(index)
                views.setViewVisibility(id, if (show && suggestion != null) View.VISIBLE else View.GONE)
                if (suggestion != null) views.setTextViewText(id, suggestion.title)
            }
        }

        private fun boundaryPendingIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                boundaryRequestCode,
                Intent(context, TaskMasterWidgetProvider::class.java).apply {
                    action = actionTimerBoundary
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        private fun scheduleBoundaryRefresh(
            context: Context,
            state: TaskMasterWidgetState,
        ) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pending = boundaryPendingIntent(context)
            manager.cancel(pending)
            val boundary = state.timerBoundaryEpochMs ?: return
            if (state.timerMode != "countdown" || boundary <= System.currentTimeMillis()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !manager.canScheduleExactAlarms()
            ) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, boundary, pending)
            } else {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, boundary, pending)
            }
        }

        private fun cancelBoundaryRefresh(context: Context) {
            val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            manager.cancel(boundaryPendingIntent(context))
        }
    }
}

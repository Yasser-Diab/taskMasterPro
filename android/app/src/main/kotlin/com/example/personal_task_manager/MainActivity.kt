package com.example.personal_task_manager

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.SoundPool
import android.net.Uri
import android.os.Build
import android.os.Message
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.View
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.json.JSONObject
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.io.File
import java.security.KeyStore
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

private object TaskBrowserProfile {
    private var configuredSuffix: String? = null

    fun configure(profileId: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return
        }
        val safeSuffix = "taskmasterpro_${profileId.replace(Regex("[^A-Za-z0-9_-]"), "_")}"
        if (configuredSuffix == safeSuffix) {
            return
        }
        if (configuredSuffix != null) {
            return
        }
        try {
            WebView.setDataDirectorySuffix(safeSuffix)
            configuredSuffix = safeSuffix
        } catch (_: IllegalStateException) {
            // WebView was already initialized. Privacy is still protected for
            // the current process; a full app restart is required to switch
            // Android WebView data directories.
        }
    }
}

private data class PendingHealthPermissionRequest(
    val requestedTypes: List<String>,
    val requestedPermissions: Set<String>,
    val result: MethodChannel.Result
)

class MainActivity : FlutterFragmentActivity() {
    private var initialLink: String? = null
    private var eventSink: EventChannel.EventSink? = null
    private val notificationPermissionRequestCode = 4201
    private val avatarImageRequestCode = 4202
    private val readingFileRequestCode = 4203
    private var avatarImageResult: MethodChannel.Result? = null
    private var readingFileResult: MethodChannel.Result? = null
    private var soundPool: SoundPool? = null
    private var clickSoundId: Int = 0
    private var clickStreamId: Int = 0
    private var clickSoundLoaded: Boolean = false
    private var clickVolume: Float = 0.65f
    private val browserViews = mutableMapOf<String, TaskBrowserPlatformView>()
    private val healthScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pendingHealthPermissionRequest: PendingHealthPermissionRequest? = null
    private lateinit var healthPermissionLauncher: ActivityResultLauncher<Set<String>>

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialLink = extractDeepLink(intent)

        healthPermissionLauncher = registerForActivityResult(
            PermissionController.createRequestPermissionResultContract()
        ) { granted ->
            finishHealthPermissionRequest(granted)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/deep_links"
        ).setMethodCallHandler { call, result ->
            if (call.method == "initialLink") {
                result.success(initialLink)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getTimeZoneId" -> result.success(ZoneId.systemDefault().id)
                "getDataDirectory" -> result.success(filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/health"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStatus" -> healthStatus(result)
                "requestPermissions" -> {
                    val types = call.argument<List<String>>("dataTypes") ?: emptyList()
                    requestHealthPermissions(types, result)
                }
                "readSummary" -> readHealthSummary(call, result)
                "readCachedSummary" -> {
                    val userId = call.argument<String>("userId")
                    result.success(userId?.let(::readEncryptedHealthSummary))
                }
                "writeCachedSummary" -> {
                    val userId = call.argument<String>("userId")
                    val summaryJson = call.argument<String>("summaryJson")
                    if (userId == null || summaryJson == null) {
                        result.error("invalid_health_cache", "Health cache details are incomplete.", null)
                    } else {
                        writeEncryptedHealthSummary(userId, summaryJson)
                        result.success(null)
                    }
                }
                "deleteCachedSummary" -> {
                    call.argument<String>("userId")?.let(::deleteEncryptedHealthSummary)
                    result.success(null)
                }
                "manageAccess" -> {
                    try {
                        startActivity(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("health_settings_unavailable", error.message, null)
                    }
                }
                "disconnect" -> disconnectHealthConnect(result)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/deep_links/events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/active_session"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startOrUpdate" -> {
                    ensureNotificationPermission()
                    val title = call.argument<String>("title") ?: "TaskMaster Pro"
                    val text = call.argument<String>("text") ?: "Active session"
                    startActiveSessionService(title, text)
                    result.success(null)
                }
                "stop" -> {
                    stopActiveSessionService()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/task_reminders"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule" -> {
                    ensureNotificationPermission()
                    val id = call.argument<String>("id")
                    val taskId = call.argument<String>("taskId")
                    val title = call.argument<String>("title")
                    val body = call.argument<String>("body")
                    val triggerAt = call.argument<Number>("triggerAt")?.toLong()
                    if (id == null || taskId == null || triggerAt == null) {
                        result.error("invalid_reminder", "Reminder details are incomplete.", null)
                    } else {
                        TaskReminderReceiver.schedule(
                            this,
                            id,
                            taskId,
                            title ?: "TaskMaster Pro",
                            body ?: "Your task is ready.",
                            triggerAt
                        )
                        result.success(null)
                    }
                }
                "cancelTask" -> {
                    val taskId = call.argument<String>("taskId")
                    if (taskId != null) {
                        TaskReminderReceiver.cancelTask(this, taskId)
                    }
                    result.success(null)
                }
                "showNow" -> {
                    ensureNotificationPermission()
                    TaskReminderReceiver.showNow(
                        this,
                        call.argument<String>("id") ?: "manual_test",
                        call.argument<String>("taskId") ?: "test",
                        call.argument<String>("title") ?: "TaskMaster Pro",
                        call.argument<String>("body") ?: "Notifications are working.",
                        call.argument<String>("channel") ?: "task_reminders"
                    )
                    result.success(null)
                }
                "getStatus" -> {
                    result.success(notificationStatus())
                }
                "openNotificationSettings" -> {
                    try {
                        openNotificationSettings()
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("notification_settings_unavailable", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/widgets"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateSnapshot" -> {
                    val kind = call.argument<String>("kind")
                    val snapshot = call.argument<Map<String, Any?>>("snapshot")
                    if (kind == null || snapshot == null) {
                        result.error("invalid_widget_snapshot", "Widget snapshot is incomplete.", null)
                    } else {
                        TaskMasterWidgetProvider.updateSnapshot(
                            this,
                            kind,
                            JSONObject(snapshot)
                        )
                        result.success(null)
                    }
                }
                "refresh" -> {
                    TaskMasterWidgetProvider.updateAll(this)
                    result.success(null)
                }
                "takeLastCommand" -> {
                    val preferences = getSharedPreferences(
                        "taskmasterpro_widget_snapshots",
                        Context.MODE_PRIVATE
                    )
                    val command = preferences.getString("last_widget_command", null)
                    val occurredAt = preferences.getLong("last_widget_command_at", 0L)
                    preferences.edit()
                        .remove("last_widget_command")
                        .remove("last_widget_command_at")
                        .apply()
                    if (command == null) {
                        result.success(null)
                    } else {
                        result.success(
                            mapOf(
                                "command" to command,
                                "occurredAt" to occurredAt
                            )
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/interaction_feedback"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeClickSound" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val volume = call.argument<Double>("volume")
                    if (volume != null) {
                        clickVolume = volume.coerceIn(0.0, 1.0).toFloat()
                    }
                    if (bytes != null) {
                        initializeClickSound(bytes)
                    }
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")
                    if (volume != null) {
                        clickVolume = volume.coerceIn(0.0, 1.0).toFloat()
                    }
                    result.success(null)
                }
                "playClick" -> {
                    playClickSound()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/profile_files"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAvatarImage" -> pickAvatarImage(result)
                "pickReadingFile" -> pickReadingFile(result)
                "openReadingFile" -> {
                    val reference = call.argument<String>("reference")
                    if (reference == null) {
                        result.error("invalid_reading_file", "The book file is unavailable.", null)
                    } else {
                        openReadingFile(reference, result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "taskmasterpro/task_browser",
                TaskBrowserViewFactory(
                    flutterEngine.dartExecutor.binaryMessenger,
                    browserViews,
                    ::openExternalUrl
                )
            )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "taskmasterpro/task_browser"
        ).setMethodCallHandler { call, result ->
            val browserId = call.argument<String>("browserId")
            val view = browserId?.let { browserViews[it] }
            when (call.method) {
                "navigate" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        view?.navigate(url)
                    }
                    result.success(null)
                }
                "goBack" -> {
                    view?.goBack()
                    result.success(null)
                }
                "goForward" -> {
                    view?.goForward()
                    result.success(null)
                }
                "reload" -> {
                    view?.reload()
                    result.success(null)
                }
                "stop" -> {
                    view?.stop()
                    result.success(null)
                }
                "openExternal" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        openExternalUrl(url)
                    }
                    result.success(null)
                }
                "hide" -> {
                    if (view != null) {
                        view.hide()
                    } else {
                        browserViews.values.forEach { it.hide() }
                    }
                    result.success(null)
                }
                "showDocked", "detach", "dock" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractDeepLink(intent)
        if (link != null) {
            initialLink = link
            eventSink?.success(link)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == readingFileRequestCode) {
            val pending = readingFileResult
            readingFileResult = null
            if (pending == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }
            val uri = data.data!!
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                )
            } catch (_: SecurityException) {
                // Some document providers grant access without persistable flags.
            }
            pending.success(uri.toString())
            return
        }
        if (requestCode == avatarImageRequestCode) {
            val pending = avatarImageResult
            avatarImageResult = null
            if (pending == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK) {
                pending.success(null)
                return
            }
            val uri = data?.data
            if (uri == null) {
                pending.success(null)
                return
            }
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                pending.success(bytes)
            } catch (error: Exception) {
                pending.error("avatar_read_failed", error.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun pickReadingFile(result: MethodChannel.Result) {
        if (readingFileResult != null) {
            result.error("reading_picker_active", "A file picker is already open.", null)
            return
        }
        readingFileResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/pdf", "application/epub+zip"))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, readingFileRequestCode)
    }

    private fun openReadingFile(reference: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(reference)
            val type = contentResolver.getType(uri) ?: when {
                reference.lowercase().endsWith(".pdf") -> "application/pdf"
                reference.lowercase().endsWith(".epub") -> "application/epub+zip"
                else -> "application/octet-stream"
            }
            startActivity(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, type)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            result.success(null)
        } catch (error: Exception) {
            result.error("reading_file_open_failed", error.message, null)
        }
    }

    override fun onDestroy() {
        soundPool?.release()
        soundPool = null
        super.onDestroy()
    }

    private fun healthStatus(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
            result.success(
                healthResultMap(
                    status = "unsupported",
                    permissionResult = "sdk_below_minimum"
                )
            )
            return
        }
        val sdkStatus = HealthConnectClient.getSdkStatus(this)
        if (sdkStatus != HealthConnectClient.SDK_AVAILABLE) {
            val status = if (sdkStatus == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED) {
                "update_required"
            } else {
                "unavailable"
            }
            result.success(
                healthResultMap(
                    status = status,
                    permissionResult = status
                )
            )
            return
        }
        healthScope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(this@MainActivity)
                val granted = client.permissionController.getGrantedPermissions()
                val types = healthPermissionTypes().filterValues { granted.contains(it) }.keys.toList()
                withContext(Dispatchers.Main) {
                    result.success(
                        healthResultMap(
                            status = if (types.isEmpty()) "available" else "connected",
                            grantedTypes = types,
                            grantedPermissions = granted.toList(),
                            permissionResult = "status_checked"
                        )
                    )
                }
            } catch (error: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("health_status_failed", error.message, null)
                }
            }
        }
    }

    private fun requestHealthPermissions(types: List<String>, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1 ||
            HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE
        ) {
            result.error("health_unavailable", "Health Connect is not available on this device.", null)
            return
        }
        if (pendingHealthPermissionRequest != null) {
            result.error("health_request_active", "A health permission request is already open.", null)
            return
        }
        val permissions = types.mapNotNull { healthPermissionTypes()[it] }.toSet()
        if (permissions.isEmpty()) {
            result.success(
                healthResultMap(
                    status = "not_connected",
                    requestedTypes = emptyList(),
                    grantedTypes = emptyList(),
                    requestedPermissions = emptyList(),
                    grantedPermissions = emptyList(),
                    permissionResult = "nothing_requested"
                )
            )
            return
        }
        healthScope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(this@MainActivity)
                val alreadyGranted = client.permissionController.getGrantedPermissions()
                val missing = permissions - alreadyGranted
                if (missing.isEmpty()) {
                    val grantedTypes = healthPermissionTypes()
                        .filterValues { alreadyGranted.contains(it) }
                        .keys
                        .toList()
                    withContext(Dispatchers.Main) {
                        result.success(
                            healthResultMap(
                                status = healthStatusFor(types, grantedTypes),
                                requestedTypes = types,
                                grantedTypes = grantedTypes,
                                requestedPermissions = permissions.toList(),
                                grantedPermissions = alreadyGranted.toList(),
                                permissionResult = "already_granted"
                            )
                        )
                    }
                    return@launch
                }
                withContext(Dispatchers.Main) {
                    pendingHealthPermissionRequest = PendingHealthPermissionRequest(
                        requestedTypes = types,
                        requestedPermissions = permissions,
                        result = result
                    )
                    try {
                        healthPermissionLauncher.launch(permissions)
                    } catch (error: Exception) {
                        pendingHealthPermissionRequest = null
                        result.error("health_permission_launch_failed", error.message, null)
                    }
                }
            } catch (error: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("health_permission_prepare_failed", error.message, null)
                }
            }
        }
    }

    private fun finishHealthPermissionRequest(grantedFromContract: Set<String>) {
        val pending = pendingHealthPermissionRequest ?: return
        pendingHealthPermissionRequest = null
        healthScope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(this@MainActivity)
                val actualGranted = client.permissionController.getGrantedPermissions()
                val grantedTypes = healthPermissionTypes()
                    .filterValues { actualGranted.contains(it) }
                    .keys
                    .toList()
                val status = healthStatusFor(pending.requestedTypes, grantedTypes)
                withContext(Dispatchers.Main) {
                    pending.result.success(
                        healthResultMap(
                            status = status,
                            requestedTypes = pending.requestedTypes,
                            grantedTypes = grantedTypes,
                            requestedPermissions = pending.requestedPermissions.toList(),
                            grantedPermissions = actualGranted.toList(),
                            permissionResult = if (grantedFromContract.isEmpty()) {
                                "declined_or_no_change"
                            } else {
                                "returned_from_native_flow"
                            }
                        )
                    )
                }
            } catch (error: Exception) {
                withContext(Dispatchers.Main) {
                    pending.result.error("health_permission_result_failed", error.message, null)
                }
            }
        }
    }

    private fun disconnectHealthConnect(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1 ||
            HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE
        ) {
            result.success(null)
            return
        }
        healthScope.launch {
            try {
                HealthConnectClient.getOrCreate(this@MainActivity)
                    .permissionController
                    .revokeAllPermissions()
                withContext(Dispatchers.Main) { result.success(null) }
            } catch (error: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("health_disconnect_failed", error.message, null)
                }
            }
        }
    }

    private fun readHealthSummary(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1 ||
            HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE
        ) {
            result.error("health_unavailable", "Health Connect is not available on this device.", null)
            return
        }
        val requestedTypes = call.argument<List<String>>("dataTypes")
            ?.filter { healthPermissionTypes().containsKey(it) }
            ?.distinct()
            ?: healthPermissionTypes().keys.toList()
        healthScope.launch {
            try {
                val client = HealthConnectClient.getOrCreate(this@MainActivity)
                val granted = client.permissionController.getGrantedPermissions()
                val grantedTypes = healthPermissionTypes()
                    .filterValues { granted.contains(it) }
                    .keys
                    .toList()
                val zone = ZoneId.systemDefault()
                val now = Instant.now()
                val start = ZonedDateTime.now(zone).toLocalDate().atStartOfDay(zone).toInstant()
                val filter = TimeRangeFilter.between(start, now)
                var recordCount = 0
                val dataSources = mutableSetOf<String>()

                var steps = 0L
                var distanceKm = 0.0
                var calories = 0.0
                if (granted.contains(HealthPermission.getReadPermission(StepsRecord::class))) {
                    val aggregate = client.aggregate(
                        AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), filter)
                    )
                    steps = aggregate[StepsRecord.COUNT_TOTAL] ?: 0L
                    val records = client.readRecords(
                        ReadRecordsRequest<StepsRecord>(filter, pageSize = 10)
                    ).records
                    recordCount += records.size
                    dataSources.addAll(records.map { it.metadata.dataOrigin.packageName })
                }
                if (granted.contains(HealthPermission.getReadPermission(DistanceRecord::class))) {
                    val aggregate = client.aggregate(
                        AggregateRequest(setOf(DistanceRecord.DISTANCE_TOTAL), filter)
                    )
                    distanceKm = aggregate[DistanceRecord.DISTANCE_TOTAL]?.inKilometers ?: 0.0
                    val records = client.readRecords(
                        ReadRecordsRequest<DistanceRecord>(filter, pageSize = 10)
                    ).records
                    recordCount += records.size
                    dataSources.addAll(records.map { it.metadata.dataOrigin.packageName })
                }
                if (granted.contains(HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class))) {
                    val aggregate = client.aggregate(
                        AggregateRequest(setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL), filter)
                    )
                    calories = aggregate[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories ?: 0.0
                }

                var exerciseMinutes = 0L
                if (granted.contains(HealthPermission.getReadPermission(ExerciseSessionRecord::class))) {
                    val exercise = client.readRecords(
                        ReadRecordsRequest<ExerciseSessionRecord>(filter)
                    ).records
                    recordCount += exercise.size
                    dataSources.addAll(exercise.map { it.metadata.dataOrigin.packageName })
                    exerciseMinutes = exercise.sumOf {
                        Duration.between(it.startTime, it.endTime).toMinutes().coerceAtLeast(0)
                    }
                }

                var sleepMinutes: Long? = null
                if (granted.contains(HealthPermission.getReadPermission(SleepSessionRecord::class))) {
                    val sleep = client.readRecords(
                        ReadRecordsRequest<SleepSessionRecord>(
                            TimeRangeFilter.between(now.minus(Duration.ofDays(7)), now),
                            ascendingOrder = false,
                            pageSize = 1
                        )
                    ).records.firstOrNull()
                    if (sleep != null) {
                        recordCount += 1
                        dataSources.add(sleep.metadata.dataOrigin.packageName)
                    }
                    sleepMinutes = sleep?.let {
                        Duration.between(it.startTime, it.endTime).toMinutes().coerceAtLeast(0)
                    }
                }

                var heartRate: Long? = null
                var heartRateAt: String? = null
                if (granted.contains(HealthPermission.getReadPermission(HeartRateRecord::class))) {
                    val record = client.readRecords(
                        ReadRecordsRequest<HeartRateRecord>(
                            TimeRangeFilter.between(now.minus(Duration.ofDays(1)), now),
                            ascendingOrder = false,
                            pageSize = 1
                        )
                    ).records.firstOrNull()
                    if (record != null) {
                        recordCount += 1
                        dataSources.add(record.metadata.dataOrigin.packageName)
                    }
                    val sample = record?.samples?.maxByOrNull { it.time }
                    heartRate = sample?.beatsPerMinute
                    heartRateAt = sample?.time?.toString()
                }

                val summary = mapOf(
                    "steps" to steps,
                    "activeMinutes" to exerciseMinutes,
                    "exerciseMinutes" to exerciseMinutes,
                    "distanceKilometers" to distanceKm,
                    "calories" to calories,
                    "lastSleepMinutes" to sleepMinutes,
                    "latestHeartRate" to heartRate,
                    "latestHeartRateAt" to heartRateAt,
                    "lastReadAt" to now.toString(),
                    "lastReadAttempt" to now.toString(),
                    "recordCount" to recordCount,
                    "dataSources" to dataSources.toList().sorted(),
                    "requestedTypes" to requestedTypes,
                    "grantedTypes" to grantedTypes,
                    "requestedPermissions" to requestedTypes.mapNotNull { healthPermissionTypes()[it] },
                    "grantedPermissions" to granted.toList(),
                    "backgroundAccessEnabled" to false
                )
                withContext(Dispatchers.Main) { result.success(summary) }
            } catch (error: Exception) {
                withContext(Dispatchers.Main) {
                    result.error("health_read_failed", error.message, null)
                }
            }
        }
    }

    private fun healthPermissionTypes(): Map<String, String> = mapOf(
        "steps" to HealthPermission.getReadPermission(StepsRecord::class),
        "exercise" to HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        "distance" to HealthPermission.getReadPermission(DistanceRecord::class),
        "heart_rate" to HealthPermission.getReadPermission(HeartRateRecord::class),
        "sleep" to HealthPermission.getReadPermission(SleepSessionRecord::class),
        "calories" to HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)
    )

    private fun healthStatusFor(requestedTypes: List<String>, grantedTypes: List<String>): String {
        if (grantedTypes.isEmpty()) return "permission_declined"
        if (requestedTypes.isNotEmpty() && !grantedTypes.containsAll(requestedTypes)) {
            return "partially_connected"
        }
        return "connected"
    }

    private fun healthResultMap(
        status: String,
        requestedTypes: List<String> = emptyList(),
        grantedTypes: List<String> = emptyList(),
        requestedPermissions: List<String> = emptyList(),
        grantedPermissions: List<String> = emptyList(),
        permissionResult: String
    ): Map<String, Any?> {
        val sdkStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            HealthConnectClient.getSdkStatus(this)
        } else {
            HealthConnectClient.SDK_UNAVAILABLE
        }
        return mapOf(
            "healthConnect" to status,
            "huawei" to "unavailable",
            "requestedTypes" to requestedTypes,
            "grantedTypes" to grantedTypes,
            "requestedPermissions" to requestedPermissions,
            "grantedPermissions" to grantedPermissions,
            "manifestDeclaredPermissions" to declaredHealthPermissions(),
            "sdkStatus" to sdkStatus,
            "healthConnectPackageStatus" to status,
            "lastPermissionResult" to permissionResult
        )
    }

    private fun declaredHealthPermissions(): List<String> {
        return try {
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            }
            info.requestedPermissions
                ?.filter { it.startsWith("android.permission.health.") }
                ?.sorted()
                ?: emptyList()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun healthCachePreferences() =
        getSharedPreferences("taskmasterpro_health_cache", Context.MODE_PRIVATE)

    private fun healthCacheKey(userId: String): String =
        "summary_" + userId.replace(Regex("[^A-Za-z0-9_-]"), "_")

    private fun healthCacheSecretKey(): SecretKey {
        val alias = "taskmasterpro_health_cache_v1"
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = keyStore.getKey(alias, null) as? SecretKey
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore"
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    private fun writeEncryptedHealthSummary(userId: String, plainText: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, healthCacheSecretKey())
        val encrypted = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val payload = ByteArray(cipher.iv.size + encrypted.size)
        System.arraycopy(cipher.iv, 0, payload, 0, cipher.iv.size)
        System.arraycopy(encrypted, 0, payload, cipher.iv.size, encrypted.size)
        healthCachePreferences().edit()
            .putString(healthCacheKey(userId), Base64.encodeToString(payload, Base64.NO_WRAP))
            .apply()
    }

    private fun readEncryptedHealthSummary(userId: String): String? {
        val encoded = healthCachePreferences().getString(healthCacheKey(userId), null)
            ?: return null
        return try {
            val payload = Base64.decode(encoded, Base64.NO_WRAP)
            if (payload.size <= 12) return null
            val iv = payload.copyOfRange(0, 12)
            val encrypted = payload.copyOfRange(12, payload.size)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                healthCacheSecretKey(),
                GCMParameterSpec(128, iv)
            )
            String(cipher.doFinal(encrypted), Charsets.UTF_8)
        } catch (_: Exception) {
            null
        }
    }

    private fun deleteEncryptedHealthSummary(userId: String) {
        healthCachePreferences().edit().remove(healthCacheKey(userId)).apply()
    }

    private fun extractDeepLink(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) {
            return null
        }
        return intent.dataString
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode
        )
    }

    private fun notificationStatus(): Map<String, Any?> {
        val notificationsAllowed =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
            } else {
                true
            }
        val alarmManager = getSystemService(AlarmManager::class.java)
        val exactAvailable =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                alarmManager.canScheduleExactAlarms()
            } else {
                true
            }
        val preferences = getSharedPreferences("taskmasterpro_notifications", Context.MODE_PRIVATE)
        val notificationManager = getSystemService(NotificationManager::class.java)
        val focusChannel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.getNotificationChannel(TaskReminderReceiver.CHANNEL_FOCUS_ALARM)
        } else {
            null
        }
        val audioManager = getSystemService(AudioManager::class.java)
        return mapOf(
            "notificationsAllowed" to notificationsAllowed,
            "exactSchedulingAvailable" to exactAvailable,
            "activeTimerRunning" to preferences.getBoolean("active_timer_running", false),
            "channelId" to TaskReminderReceiver.CHANNEL_FOCUS_ALARM,
            "selectedSound" to "critical_alarm",
            "soundAssetExists" to (resources.getIdentifier("critical_alarm", "raw", packageName) != 0),
            "channelSoundEnabled" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusChannel?.sound != null
            } else {
                true
            },
            "alarmVolume" to audioManager.getStreamVolume(AudioManager.STREAM_ALARM),
            "vibrationEnabled" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusChannel?.shouldVibrate() ?: false
            } else {
                true
            },
            "lastNotificationResult" to preferences.getString("last_notification_result", null),
            "lastNotificationAt" to preferences.getString("last_notification_at", null),
            "nextScheduledAt" to TaskReminderReceiver.nextScheduledAt(this)
        )
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
            }
        }
        startActivity(intent)
    }

    private fun startActiveSessionService(title: String, text: String) {
        val serviceIntent = Intent(this, ActiveSessionService::class.java).apply {
            action = ActiveSessionService.ACTION_START_OR_UPDATE
            putExtra(ActiveSessionService.EXTRA_TITLE, title)
            putExtra(ActiveSessionService.EXTRA_TEXT, text)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopActiveSessionService() {
        val serviceIntent = Intent(this, ActiveSessionService::class.java).apply {
            action = ActiveSessionService.ACTION_STOP
        }
        startService(serviceIntent)
    }

    private fun pickAvatarImage(result: MethodChannel.Result) {
        if (avatarImageResult != null) {
            result.error("avatar_picker_busy", "Another image picker is already open.", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        avatarImageResult = result
        try {
            startActivityForResult(
                Intent.createChooser(intent, "Choose profile picture"),
                avatarImageRequestCode
            )
        } catch (error: Exception) {
            avatarImageResult = null
            result.error("avatar_picker_unavailable", error.message, null)
        }
    }

    private fun initializeClickSound(bytes: ByteArray) {
        if (soundPool == null) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            soundPool = SoundPool.Builder()
                .setMaxStreams(1)
                .setAudioAttributes(attributes)
                .build()
            soundPool?.setOnLoadCompleteListener { _, sampleId, status ->
                if (sampleId == clickSoundId && status == 0) {
                    clickSoundLoaded = true
                }
            }
        }

        val file = File(cacheDir, "taskmasterpro_ui_click_sound.mp3")
        file.writeBytes(bytes)
        clickSoundLoaded = false
        clickSoundId = soundPool?.load(file.absolutePath, 1) ?: 0
    }

    private fun playClickSound() {
        val pool = soundPool ?: return
        if (!clickSoundLoaded || clickSoundId == 0) {
            return
        }
        if (clickStreamId != 0) {
            pool.stop(clickStreamId)
        }
        clickStreamId = pool.play(clickSoundId, clickVolume, clickVolume, 1, 0, 1.0f)
    }

    private fun openExternalUrl(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
        startActivity(intent)
    }
}

private class TaskBrowserViewFactory(
    private val messenger: BinaryMessenger,
    private val views: MutableMap<String, TaskBrowserPlatformView>,
    private val openExternalUrl: (String) -> Unit
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *>
        val browserId = params?.get("browserId")?.toString() ?: viewId.toString()
        val initialUrl = params?.get("initialUrl")?.toString() ?: "https://developer.mozilla.org/"
        val profileId = params?.get("profileId")?.toString() ?: "signed-out"
        TaskBrowserProfile.configure(profileId)
        return TaskBrowserPlatformView(
            context,
            messenger,
            browserId,
            initialUrl,
            openExternalUrl,
            onDispose = { views.remove(browserId) }
        ).also { views[browserId] = it }
    }
}

private class TaskBrowserPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    private val browserId: String,
    initialUrl: String,
    private val openExternalUrl: (String) -> Unit,
    private val onDispose: () -> Unit
) : PlatformView {
    private val channel = MethodChannel(messenger, "taskmasterpro/task_browser")
    private val webView = WebView(context)

    init {
        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.databaseEnabled = true
        webView.settings.mediaPlaybackRequiresUserGesture = false
        webView.settings.javaScriptCanOpenWindowsAutomatically = true
        webView.settings.setSupportMultipleWindows(true)
        CookieManager.getInstance().setAcceptCookie(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                sendEvent(
                    mapOf(
                        "loading" to (newProgress < 100),
                        "url" to (view?.url ?: ""),
                        "progress" to newProgress
                    )
                )
            }

            override fun onReceivedTitle(view: WebView?, title: String?) {
                sendEvent(
                    mapOf(
                        "loading" to false,
                        "url" to (view?.url ?: ""),
                        "title" to (title ?: "")
                    )
                )
            }

            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                val popup = WebView(view?.context ?: webView.context)
                popup.webViewClient = object : WebViewClient() {
                    override fun shouldOverrideUrlLoading(
                        popupView: WebView?,
                        request: WebResourceRequest?
                    ): Boolean {
                        val url = request?.url?.toString() ?: return false
                        sendEvent(mapOf("newTabUrl" to url, "loading" to false))
                        return true
                    }

                    override fun onPageStarted(
                        popupView: WebView?,
                        url: String?,
                        favicon: android.graphics.Bitmap?
                    ) {
                        if (!url.isNullOrBlank()) {
                            sendEvent(mapOf("newTabUrl" to url, "loading" to false))
                            popup.stopLoading()
                        }
                    }
                }
                val transport = resultMsg?.obj as? WebView.WebViewTransport
                transport?.webView = popup
                resultMsg?.sendToTarget()
                return true
            }
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                val url = request?.url?.toString() ?: return false
                val scheme = request.url.scheme ?: return false
                if (scheme == "http" || scheme == "https") {
                    return false
                }
                openExternalUrl(url)
                return true
            }

            override fun onPageStarted(view: WebView?, url: String?, favicon: android.graphics.Bitmap?) {
                sendEvent(mapOf("loading" to true, "url" to (url ?: ""), "error" to ""))
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                sendEvent(mapOf("loading" to false, "url" to (url ?: ""), "error" to ""))
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                if (request?.isForMainFrame == true) {
                    sendEvent(
                        mapOf(
                            "loading" to false,
                            "url" to (request.url?.toString() ?: ""),
                            "error" to (error?.description?.toString() ?: "Page failed to load")
                        )
                    )
                }
            }
        }
        navigate(initialUrl)
    }

    override fun getView(): View = webView

    override fun dispose() {
        CookieManager.getInstance().flush()
        webView.stopLoading()
        webView.destroy()
        onDispose()
    }

    fun navigate(url: String) {
        webView.visibility = View.VISIBLE
        webView.alpha = 1f
        webView.loadUrl(url)
    }

    fun hide() {
        webView.stopLoading()
        webView.visibility = View.GONE
        webView.alpha = 0f
    }

    fun goBack() {
        if (webView.canGoBack()) {
            webView.goBack()
        }
    }

    fun goForward() {
        if (webView.canGoForward()) {
            webView.goForward()
        }
    }

    fun reload() {
        webView.reload()
    }

    fun stop() {
        webView.stopLoading()
    }

    private fun sendEvent(event: Map<String, Any>) {
        channel.invokeMethod(
            "browserEvent",
            mapOf("browserId" to browserId) + event
        )
    }
}

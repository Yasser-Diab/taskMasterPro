package pro.taskmaster.taskmaster_pro

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.security.MessageDigest
import java.util.UUID
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64

class MainActivity : FlutterFragmentActivity() {
    private val activityChannel = "taskmasterpro/activity"
    private val notificationChannel = "taskmasterpro/notifications"
    private val resourceChannel = "taskmasterpro/resources"
    private val homeWidgetChannel = "taskmasterpro/home_widget"
    private val bleChannel = "taskmasterpro/ble"
    private val vaultChannel = "taskmasterpro/vault"
    private var homeWidgetMethodChannel: MethodChannel? = null
    private var pendingHomeWidgetAction: Map<String, Any>? = null
    private val heartRateServiceUuid =
        UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
    private val heartRateMeasurementUuid =
        UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
    private val batteryServiceUuid =
        UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb")
    private val batteryLevelUuid =
        UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
    private val runningSpeedCadenceServiceUuid =
        UUID.fromString("00001814-0000-1000-8000-00805f9b34fb")
    private val runningSpeedCadenceMeasurementUuid =
        UUID.fromString("00002a53-0000-1000-8000-00805f9b34fb")
    private val cyclingSpeedCadenceServiceUuid =
        UUID.fromString("00001816-0000-1000-8000-00805f9b34fb")
    private val cyclingSpeedCadenceMeasurementUuid =
        UUID.fromString("00002a5b-0000-1000-8000-00805f9b34fb")
    private val pulseOximeterServiceUuid =
        UUID.fromString("00001822-0000-1000-8000-00805f9b34fb")
    private val pulseOximeterContinuousMeasurementUuid =
        UUID.fromString("00002a5f-0000-1000-8000-00805f9b34fb")
    private val pulseOximeterSpotCheckMeasurementUuid =
        UUID.fromString("00002a5e-0000-1000-8000-00805f9b34fb")
    private val clientCharacteristicConfigurationUuid =
        UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private val healthWearableNameTokens = setOf(
        "watch",
        "band",
        "fitbit",
        "garmin",
        "amazfit",
        "huawei",
        "honor",
        "mi band",
        "xiaomi",
        "zepp",
        "samsung fit",
        "galaxy fit",
        "galaxy watch",
        "pixel watch",
        "vivosmart",
        "vivoactive",
        "forerunner",
        "fenix",
        "instinct",
        "suunto",
        "polar",
        "coros",
        "whoop",
        "versa",
        "charge",
    )
    private val excludedBluetoothDeviceTokens = setOf(
        "buds",
        "earbud",
        "headphone",
        "headset",
        "speaker",
        "keyboard",
        "mouse",
        "television",
        " tv",
        "car",
    )
    private val healthBluetoothDeviceClasses = setOf(
        BluetoothClass.Device.HEALTH_BLOOD_PRESSURE,
        BluetoothClass.Device.HEALTH_DATA_DISPLAY,
        BluetoothClass.Device.HEALTH_GLUCOSE,
        BluetoothClass.Device.HEALTH_PULSE_OXIMETER,
        BluetoothClass.Device.HEALTH_PULSE_RATE,
        BluetoothClass.Device.HEALTH_THERMOMETER,
        BluetoothClass.Device.HEALTH_UNCATEGORIZED,
        BluetoothClass.Device.HEALTH_WEIGHING,
    )
    private var pendingRingtoneResult: MethodChannel.Result? = null
    private var previewRingtone: Ringtone? = null
    private val vaultPreferences by lazy {
        getSharedPreferences("taskmaster.vault.device_keys", Context.MODE_PRIVATE)
    }
    private val vaultKeyStore by lazy {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    }
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingGattResult: MethodChannel.Result? = null
    private var inspectedGattAddress: String? = null
    private var inspectedGatt: BluetoothGatt? = null
    private val stopGattInspection = Runnable {
        finishGattInspection(
            state = "unknown",
            errorCode = "inspection_timeout",
        )
    }

    private val ringtonePicker = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { activityResult ->
        val pending = pendingRingtoneResult ?: return@registerForActivityResult
        pendingRingtoneResult = null
        if (activityResult.resultCode != Activity.RESULT_OK) {
            pending.success(null)
            return@registerForActivityResult
        }
        val data = activityResult.data
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data?.getParcelableExtra(
                RingtoneManager.EXTRA_RINGTONE_PICKED_URI,
                Uri::class.java,
            )
        } else {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }
        if (uri == null) {
            pending.success(null)
            return@registerForActivityResult
        }
        runCatching {
            contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
        val title = runCatching {
            RingtoneManager.getRingtone(applicationContext, uri)
                ?.getTitle(applicationContext)
        }.getOrNull()
        pending.success(
            mapOf(
                "uri" to uri.toString(),
                "title" to (title ?: "Device sound"),
            ),
        )
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(
            gatt: BluetoothGatt,
            status: Int,
            newState: Int,
        ) {
            if (gatt !== inspectedGatt) return
            if (
                status == BluetoothGatt.GATT_SUCCESS &&
                newState == BluetoothProfile.STATE_CONNECTED
            ) {
                if (!runCatching { gatt.discoverServices() }.getOrDefault(false)) {
                    finishGattInspection(
                        state = "unknown",
                        errorCode = "service_discovery_failed",
                    )
                }
                return
            }
            if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                finishGattInspection(
                    state = "unknown",
                    errorCode = "gatt_disconnected",
                )
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (gatt !== inspectedGatt) return
            if (status != BluetoothGatt.GATT_SUCCESS) {
                finishGattInspection(
                    state = "unknown",
                    errorCode = "service_discovery_failed",
                )
                return
            }
            val services = gatt.services.orEmpty()
            val heartRateMeasurement = services
                .firstOrNull { it.uuid == heartRateServiceUuid }
                ?.getCharacteristic(heartRateMeasurementUuid)
            val supportsLiveHeartRate =
                supportsGattUpdates(heartRateMeasurement)
            val batteryLevel = services
                .firstOrNull { it.uuid == batteryServiceUuid }
                ?.getCharacteristic(batteryLevelUuid)
            val supportsBattery =
                batteryLevel != null &&
                    batteryLevel.properties and (
                        BluetoothGattCharacteristic.PROPERTY_READ or
                            BluetoothGattCharacteristic.PROPERTY_NOTIFY
                    ) != 0
            val runningMeasurement = services
                .firstOrNull { it.uuid == runningSpeedCadenceServiceUuid }
                ?.getCharacteristic(runningSpeedCadenceMeasurementUuid)
            val cyclingMeasurement = services
                .firstOrNull { it.uuid == cyclingSpeedCadenceServiceUuid }
                ?.getCharacteristic(cyclingSpeedCadenceMeasurementUuid)
            val pulseOximeterService = services.firstOrNull {
                it.uuid == pulseOximeterServiceUuid
            }
            val pulseOximeterMeasurement =
                pulseOximeterService?.getCharacteristic(
                    pulseOximeterContinuousMeasurementUuid,
                ) ?: pulseOximeterService?.getCharacteristic(
                    pulseOximeterSpotCheckMeasurementUuid,
                )
            val capabilities = buildList {
                if (supportsLiveHeartRate) add("live_heart_rate")
                if (supportsBattery) add("battery")
                if (supportsGattUpdates(runningMeasurement)) {
                    add("running_speed_cadence")
                }
                if (supportsGattUpdates(cyclingMeasurement)) {
                    add("cycling_speed_cadence")
                }
                if (supportsGattUpdates(pulseOximeterMeasurement)) {
                    add("pulse_oximetry")
                }
            }
            finishGattInspection(
                state = if (capabilities.isNotEmpty()) {
                    "direct_supported"
                } else {
                    "no_direct_health_service"
                },
                capabilities = capabilities,
                discoveredServiceUuids = services
                    .map { it.uuid.toString().lowercase() }
                    .distinct(),
            )
        }
    }

    private fun supportsGattUpdates(
        characteristic: BluetoothGattCharacteristic?,
    ): Boolean {
        if (characteristic == null) return false
        val updateProperties =
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or
                BluetoothGattCharacteristic.PROPERTY_INDICATE
        return characteristic.properties and updateProperties != 0 &&
            characteristic.getDescriptor(clientCharacteristicConfigurationUuid) != null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureHomeWidgetAction(intent)
        deliverPendingHomeWidgetAction()
    }

    private fun captureHomeWidgetAction(source: Intent?) {
        if (source?.action != TaskMasterWidgetIntent.commandAction) return
        val id = source.getStringExtra(TaskMasterWidgetIntent.actionIdExtra)
            ?.trim()
            .orEmpty()
        val taskId = source.getStringExtra(TaskMasterWidgetIntent.taskIdExtra)
            ?.trim()
            .orEmpty()
        val sessionId = source.getStringExtra(TaskMasterWidgetIntent.sessionIdExtra)
            ?.trim()
            .orEmpty()
        val runtimeRevision = source.getIntExtra(
            TaskMasterWidgetIntent.runtimeRevisionExtra,
            -1,
        )
        if (id.isBlank() || taskId.isBlank() || sessionId.isBlank() || runtimeRevision < 0) {
            clearHomeWidgetActionIntent(source)
            return
        }
        pendingHomeWidgetAction = mapOf(
            "id" to id,
            "taskId" to taskId,
            "sessionId" to sessionId,
            "runtimeRevision" to runtimeRevision,
        )
    }

    private fun takePendingHomeWidgetAction(): Map<String, Any>? {
        val action = pendingHomeWidgetAction ?: return null
        pendingHomeWidgetAction = null
        clearHomeWidgetActionIntent(intent)
        return action
    }

    private fun deliverPendingHomeWidgetAction() {
        val channel = homeWidgetMethodChannel ?: return
        val action = pendingHomeWidgetAction ?: return
        channel.invokeMethod(
            "widgetAction",
            action,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true && pendingHomeWidgetAction == action) {
                        pendingHomeWidgetAction = null
                        clearHomeWidgetActionIntent(intent)
                    }
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) = Unit

                override fun notImplemented() = Unit
            },
        )
    }

    private fun clearHomeWidgetActionIntent(target: Intent?) {
        if (target?.action != TaskMasterWidgetIntent.commandAction) return
        target.action = "pro.taskmaster.app.action.OPEN_FROM_WIDGET"
        target.removeExtra(TaskMasterWidgetIntent.actionIdExtra)
        target.removeExtra(TaskMasterWidgetIntent.taskIdExtra)
        target.removeExtra(TaskMasterWidgetIntent.sessionIdExtra)
        target.removeExtra(TaskMasterWidgetIntent.runtimeRevisionExtra)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureHomeWidgetAction(intent)
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
                "recentForegroundActivityPeriods" -> {
                    if (!hasUsageAccess()) {
                        result.success(emptyList<Map<String, Any?>>())
                    } else {
                        result.success(
                            recentForegroundActivityPeriods(
                                call.argument<Number>("sinceMillis")?.toLong(),
                            ),
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
        homeWidgetMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            homeWidgetChannel,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val arguments = call.arguments as? Map<*, *>
                    if (arguments == null) {
                        result.error(
                            "invalid_widget_state",
                            "Android widget state must be a map",
                            null,
                        )
                    } else {
                        TaskMasterWidgetStore.save(applicationContext, arguments)
                        TaskMasterWidgetProvider.updateAll(applicationContext)
                        val pinRequested =
                            arguments["requestPinIfMissing"] == true &&
                                TaskMasterWidgetProvider.requestPin(
                                    applicationContext,
                                    automatic = true,
                                )
                        result.success(
                            mapOf(
                                "widgetCount" to TaskMasterWidgetProvider.widgetCount(
                                    applicationContext,
                                ),
                                "pinRequested" to pinRequested,
                            ),
                        )
                    }
                }
                "requestPin" -> result.success(
                    TaskMasterWidgetProvider.requestPin(
                        applicationContext,
                        automatic = false,
                    ),
                )
                "takeAction" -> result.success(takePendingHomeWidgetAction())
                "clear" -> {
                    TaskMasterWidgetStore.clearState(applicationContext)
                    TaskMasterWidgetProvider.updateAll(applicationContext)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            resourceChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openResourceUrl" -> {
                    val url = call.argument<String>("url")
                    val target = call.argument<String>("target") ?: "browser"
                    val preferredPackage =
                        call.argument<String>("preferredPackage")
                    if (url.isNullOrBlank()) {
                        result.error(
                            "missing_url",
                            "A resource URL is required",
                            null,
                        )
                    } else {
                        result.success(
                            openResourceUrl(
                                url,
                                target,
                                preferredPackage,
                            ),
                        )
                    }
                }
                "listInstalledApplications" -> {
                    result.success(installedLauncherApplications())
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickSystemSound" -> {
                    if (pendingRingtoneResult != null) {
                        result.error(
                            "picker_active",
                            "A device sound picker is already open",
                            null,
                        )
                    } else {
                        pendingRingtoneResult = result
                        val ringtoneType = when (
                            call.argument<String>("type")
                        ) {
                            "alarm" -> RingtoneManager.TYPE_ALARM
                            "ringtone" -> RingtoneManager.TYPE_RINGTONE
                            else -> RingtoneManager.TYPE_NOTIFICATION
                        }
                        ringtonePicker.launch(
                            Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_TYPE,
                                    ringtoneType,
                                )
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT,
                                    true,
                                )
                                putExtra(
                                    RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,
                                    false,
                                )
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
                                )
                            },
                        )
                    }
                }
                "previewSystemSound" -> {
                    val uri = call.argument<String>("uri")
                    if (uri.isNullOrBlank()) {
                        result.error("missing_uri", "A sound URI is required", null)
                    } else {
                        runCatching {
                            previewRingtone?.stop()
                            previewRingtone = RingtoneManager.getRingtone(
                                applicationContext,
                                Uri.parse(uri),
                            )?.also {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    it.isLooping = false
                                }
                                it.play()
                            }
                        }.onSuccess {
                            result.success(null)
                        }.onFailure {
                            result.error(
                                "preview_failed",
                                it.message ?: "The device sound could not be played",
                                null,
                            )
                        }
                    }
                }
                "previewDefaultSound" -> {
                    val ringtoneType = when (
                        call.argument<String>("type")
                    ) {
                        "alarm" -> RingtoneManager.TYPE_ALARM
                        "ringtone" -> RingtoneManager.TYPE_RINGTONE
                        else -> RingtoneManager.TYPE_NOTIFICATION
                    }
                    runCatching {
                        previewRingtone?.stop()
                        previewRingtone = RingtoneManager.getRingtone(
                            applicationContext,
                            RingtoneManager.getDefaultUri(ringtoneType),
                        )?.also {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                it.isLooping = false
                            }
                            it.play()
                        }
                    }.onSuccess {
                        result.success(null)
                    }.onFailure {
                        result.error(
                            "preview_failed",
                            it.message ?: "The default sound could not be played",
                            null,
                        )
                    }
                }
                "stopSoundPreview" -> {
                    previewRingtone?.stop()
                    previewRingtone = null
                    result.success(null)
                }
                "verifyNotificationChannel" -> {
                    val channelId = call.argument<String>("channelId")
                    if (
                        channelId.isNullOrBlank() ||
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                    ) {
                        result.success(
                            mapOf("matches" to true, "actualUri" to null),
                        )
                    } else {
                        val manager = getSystemService(
                            Context.NOTIFICATION_SERVICE,
                        ) as NotificationManager
                        val actual = manager
                            .getNotificationChannel(channelId)
                            ?.sound
                            ?.toString()
                        val kind = call.argument<String>("kind") ?: "system"
                        val expectedUri = call.argument<String>("uri")
                        val resource = call.argument<String>("resource")
                        val matches = when (kind) {
                            "silent" -> actual == null
                            "device" -> actual == expectedUri
                            "raw" ->
                                actual != null &&
                                    resource != null &&
                                    actual.endsWith("/raw/$resource")
                            else -> actual != null
                        }
                        result.success(
                            mapOf("matches" to matches, "actualUri" to actual),
                        )
                    }
                }
                "writeExecutionAlarmLedger" -> {
                    val ownerId = call.argument<String>("ownerId")
                    val ledgerJson = call.argument<String>("ledgerJson")
                    if (ownerId.isNullOrBlank() || ledgerJson.isNullOrBlank()) {
                        result.error(
                            "missing_ledger",
                            "An owner and execution ledger are required",
                            null,
                        )
                    } else {
                        getSharedPreferences(
                            "taskmaster.execution_alarm_ledger.v0028",
                            Context.MODE_PRIVATE,
                        ).edit()
                            .putString(ownerId, ledgerJson)
                            .apply()
                        result.success(null)
                    }
                }
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
                "openAppNotificationSettings" -> {
                    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                    startActivity(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            vaultChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "storeWrappedVaultKey" -> storeWrappedVaultKey(
                    userId = call.argument<String>("userId"),
                    encodedKey = call.argument<String>("key"),
                    localizedReason = call.argument<String>("localizedReason"),
                    result = result,
                )
                "unlockWrappedVaultKey" -> unlockWrappedVaultKey(
                    userId = call.argument<String>("userId"),
                    localizedReason = call.argument<String>("localizedReason"),
                    result = result,
                )
                "hasWrappedVaultKey" -> {
                    result.success(hasWrappedVaultKey(call.argument<String>("userId")))
                }
                "clearWrappedVaultKey" -> {
                    clearWrappedVaultKey(call.argument<String>("userId"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            bleChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> result.success(bluetoothState())
                "openSettings" -> {
                    startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(null)
                }
                "pairedHealthDevices" -> listPairedHealthDevices(result)
                "inspectPairedHealthDevice" -> inspectPairedHealthDevice(
                    address = call.argument<String>("address"),
                    result = result,
                    timeoutMillis =
                        (call.argument<Number>("timeoutMillis")?.toLong()
                            ?: 12_000L).coerceIn(5_000L, 20_000L),
                )
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Vault convenience unlock deliberately has a narrower trust boundary than
     * FlutterSecureStorage.  A 32-byte vault key is encrypted with an Android
     * Keystore AES key that cannot be exported and is invalidated when the
     * enrolled biometric set changes.  Every unwrap is performed inside a
     * BiometricPrompt CryptoObject, not by checking an unrelated prompt first.
     */
    private fun storeWrappedVaultKey(
        userId: String?,
        encodedKey: String?,
        localizedReason: String?,
        result: MethodChannel.Result,
    ) {
        val accountToken = vaultAccountToken(userId)
        if (accountToken == null || encodedKey.isNullOrBlank()) {
            result.error("invalid_vault_key", "A vault key is required", null)
            return
        }
        val rawKey = decodeVaultBytes(encodedKey)
        if (rawKey == null || rawKey.size != 32) {
            rawKey?.fill(0)
            result.error("invalid_vault_key", "Invalid vault key material", null)
            return
        }
        val cipher = runCatching {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(Cipher.ENCRYPT_MODE, vaultWrappingKey(accountToken))
            }
        }.getOrElse {
            rawKey.fill(0)
            result.error("keystore_unavailable", "Secure device storage is unavailable", null)
            return
        }
        authenticateVaultCipher(
            cipher = cipher,
            localizedReason = localizedReason,
            result = result,
            onFailure = {
                rawKey.fill(0)
            },
            onAuthenticated = { authenticatedCipher ->
                try {
                    val encrypted = authenticatedCipher.doFinal(rawKey)
                    vaultPreferences.edit()
                        .putString(
                            vaultCiphertextPreferenceKey(accountToken),
                            encodeVaultBytes(encrypted),
                        )
                        .putString(
                            vaultIvPreferenceKey(accountToken),
                            encodeVaultBytes(authenticatedCipher.iv),
                        )
                        .apply()
                    rawKey.fill(0)
                    encrypted.fill(0)
                    result.success(true)
                } catch (error: Exception) {
                    rawKey.fill(0)
                    clearWrappedVaultKeyForToken(accountToken)
                    result.error(
                        "keystore_store_failed",
                        error.message ?: "Could not protect the vault key",
                        null,
                    )
                }
            },
        )
    }

    private fun unlockWrappedVaultKey(
        userId: String?,
        localizedReason: String?,
        result: MethodChannel.Result,
    ) {
        val accountToken = vaultAccountToken(userId)
        if (accountToken == null) {
            result.error("invalid_vault_key", "A vault account is required", null)
            return
        }
        val encrypted = vaultPreferences.getString(
            vaultCiphertextPreferenceKey(accountToken),
            null,
        )?.let(::decodeVaultBytes)
        val iv = vaultPreferences.getString(
            vaultIvPreferenceKey(accountToken),
            null,
        )?.let(::decodeVaultBytes)
        if (encrypted == null || iv == null) {
            encrypted?.fill(0)
            iv?.fill(0)
            result.success(null)
            return
        }
        val cipher = runCatching {
            Cipher.getInstance("AES/GCM/NoPadding").apply {
                init(
                    Cipher.DECRYPT_MODE,
                    vaultWrappingKey(accountToken),
                    GCMParameterSpec(128, iv),
                )
            }
        }.getOrElse {
            encrypted.fill(0)
            iv.fill(0)
            clearWrappedVaultKeyForToken(accountToken)
            result.error(
                "keystore_unavailable",
                "Secure device storage is unavailable",
                null,
            )
            return
        }
        authenticateVaultCipher(
            cipher = cipher,
            localizedReason = localizedReason,
            result = result,
            onFailure = {
                encrypted.fill(0)
                iv.fill(0)
            },
            onAuthenticated = { authenticatedCipher ->
                try {
                    val rawKey = authenticatedCipher.doFinal(encrypted)
                    encrypted.fill(0)
                    iv.fill(0)
                    if (rawKey.size != 32) {
                        rawKey.fill(0)
                        clearWrappedVaultKeyForToken(accountToken)
                        result.error(
                            "invalid_vault_key",
                            "Invalid vault key material",
                            null,
                        )
                        return@authenticateVaultCipher
                    }
                    result.success(encodeVaultBytes(rawKey))
                    rawKey.fill(0)
                } catch (error: Exception) {
                    encrypted.fill(0)
                    iv.fill(0)
                    clearWrappedVaultKeyForToken(accountToken)
                    result.error(
                        "keystore_unlock_failed",
                        error.message ?: "Could not unlock the vault key",
                        null,
                    )
                }
            },
        )
    }

    private fun hasWrappedVaultKey(userId: String?): Boolean {
        val accountToken = vaultAccountToken(userId) ?: return false
        return vaultPreferences.contains(vaultCiphertextPreferenceKey(accountToken)) &&
            vaultPreferences.contains(vaultIvPreferenceKey(accountToken)) &&
            runCatching {
                vaultKeyStore.containsAlias(vaultKeyAlias(accountToken))
            }.getOrDefault(false)
    }

    private fun clearWrappedVaultKey(userId: String?) {
        val accountToken = vaultAccountToken(userId) ?: return
        clearWrappedVaultKeyForToken(accountToken)
    }

    private fun clearWrappedVaultKeyForToken(accountToken: String) {
        vaultPreferences.edit()
            .remove(vaultCiphertextPreferenceKey(accountToken))
            .remove(vaultIvPreferenceKey(accountToken))
            .apply()
        runCatching {
            vaultKeyStore.deleteEntry(vaultKeyAlias(accountToken))
        }
    }

    private fun vaultWrappingKey(accountToken: String): SecretKey {
        val alias = vaultKeyAlias(accountToken)
        (vaultKeyStore.getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        ).setKeySize(256)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        generator.init(builder.build())
        return generator.generateKey()
    }

    private fun authenticateVaultCipher(
        cipher: Cipher,
        localizedReason: String?,
        result: MethodChannel.Result,
        onFailure: () -> Unit,
        onAuthenticated: (Cipher) -> Unit,
    ) {
        val executor = ContextCompat.getMainExecutor(this)
        val prompt = BiometricPrompt(
            this,
            executor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    onFailure()
                    result.error(
                        "biometric_auth_failed",
                        errString.toString(),
                        errorCode,
                    )
                }

                override fun onAuthenticationSucceeded(
                    authenticationResult: BiometricPrompt.AuthenticationResult,
                ) {
                    val authenticatedCipher = authenticationResult.cryptoObject?.cipher
                    if (authenticatedCipher == null) {
                        onFailure()
                        result.error(
                            "biometric_auth_failed",
                            "Biometric authentication did not return a cipher",
                            null,
                        )
                        return
                    }
                    onAuthenticated(authenticatedCipher)
                }
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.vault_biometric_title))
            .setSubtitle(
                localizedReason?.trim()?.takeIf { it.isNotBlank() }
                    ?: getString(R.string.vault_biometric_unlock),
            )
            .setNegativeButtonText(getString(R.string.vault_biometric_cancel))
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
    }

    private fun vaultAccountToken(userId: String?): String? {
        if (userId.isNullOrBlank() || userId.length > 256) return null
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(userId.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { byte ->
            "%02x".format(byte.toInt() and 0xff)
        }
    }

    private fun vaultKeyAlias(accountToken: String): String =
        "taskmaster.vault.wrap.$accountToken"

    private fun vaultCiphertextPreferenceKey(accountToken: String): String =
        "vault_ciphertext_$accountToken"

    private fun vaultIvPreferenceKey(accountToken: String): String =
        "vault_iv_$accountToken"

    private fun decodeVaultBytes(value: String): ByteArray? =
        runCatching {
            Base64.decode(value, Base64.URL_SAFE or Base64.NO_WRAP)
        }.getOrNull()

    private fun encodeVaultBytes(value: ByteArray): String =
        Base64.encodeToString(value, Base64.URL_SAFE or Base64.NO_WRAP)

    /**
     * Opens a learning URL with an explicit kind of handler.
     *
     * `app` first selects the platform's preferred non-browser deep-link
     * handler. Some learning apps claim their origin but not every website
     * path, so it retries the origin before conservatively matching one visible
     * launcher application to the site's normalized base-domain token.
     * `browser` always selects a real browser package. Dart performs the final
     * browser fallback when no installed application claims the resource.
     */
    private fun openResourceUrl(
        rawUrl: String,
        target: String,
        preferredPackage: String?,
    ): Map<String, Any?> {
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull()
        if (
            uri == null ||
            (
                !uri.scheme.equals("http", ignoreCase = true) &&
                    !uri.scheme.equals("https", ignoreCase = true)
            ) ||
            uri.host.isNullOrBlank()
        ) {
            return mapOf(
                "opened" to false,
                "reason" to "invalid_url",
            )
        }
        val resourceIntent = resourceViewIntent(uri)
        val resourceHandlers = queryIntentHandlers(resourceIntent)
            .filter { it.activityInfo?.packageName != packageName }
        val genericBrowserIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse("https://www.example.com/"),
        ).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val browserPackages = queryIntentHandlers(genericBrowserIntent)
            .mapNotNull { it.activityInfo?.packageName }
            .toSet()

        if (target == "app") {
            val exactIntent = resourceViewIntent(uri)
            val exactHandler = preferredNonBrowserHandler(
                exactIntent,
                browserPackages,
                preferredPackage,
            )
            if (exactHandler != null) {
                return launchResourceHandler(
                    handler = exactHandler,
                    intent = exactIntent,
                    target = target,
                    resolution = "exact_deep_link",
                    originalUri = uri,
                    launchedUri = uri,
                )
            }

            val origin = uri.buildUpon()
                .path("/")
                .clearQuery()
                .fragment(null)
                .build()
            if (origin != uri) {
                val originIntent = resourceViewIntent(origin)
                val originHandler = preferredNonBrowserHandler(
                    originIntent,
                    browserPackages,
                    preferredPackage,
                )
                if (originHandler != null) {
                    return launchResourceHandler(
                        handler = originHandler,
                        intent = originIntent,
                        target = target,
                        resolution = "origin_deep_link",
                        originalUri = uri,
                        launchedUri = origin,
                    )
                }
            }

            if (!preferredPackage.isNullOrBlank()) {
                val linkedLauncher =
                    launcherHandlerForPackage(preferredPackage)
                if (linkedLauncher != null) {
                    val activity = linkedLauncher.activityInfo
                    val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_LAUNCHER)
                        setClassName(activity.packageName, activity.name)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    return launchResourceHandler(
                        handler = linkedLauncher,
                        intent = launcherIntent,
                        target = target,
                        resolution = "task_linked_application",
                        originalUri = uri,
                        launchedUri = null,
                    )
                }
            }

            val launcherHandler = matchingLauncherHandler(uri.host.orEmpty())
            if (launcherHandler != null) {
                val activity = launcherHandler.activityInfo
                val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    setClassName(activity.packageName, activity.name)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                return launchResourceHandler(
                    handler = launcherHandler,
                    intent = launcherIntent,
                    target = target,
                    resolution = "launcher_domain_token",
                    originalUri = uri,
                    launchedUri = null,
                )
            }

            return mapOf(
                "opened" to false,
                "reason" to "no_installed_app_handler",
            )
        }

        val defaultBrowserPackage = resolveIntentHandler(genericBrowserIntent)
            ?.activityInfo
            ?.packageName
        val selectedBrowser = resourceHandlers.firstOrNull {
            it.activityInfo?.packageName == defaultBrowserPackage
        } ?: resourceHandlers.firstOrNull {
            it.activityInfo?.packageName in browserPackages
        } ?: queryIntentHandlers(genericBrowserIntent).firstOrNull()
        val selectedPackage = selectedBrowser?.activityInfo?.packageName
            ?: return mapOf(
                "opened" to false,
                "reason" to "no_browser_handler",
            )
        return launchResourceHandler(
            handler = selectedBrowser,
            intent = Intent(resourceIntent).apply {
                setPackage(selectedPackage)
            },
            target = target,
            resolution = "external_browser",
            originalUri = uri,
            launchedUri = uri,
        )
    }

    private fun resourceViewIntent(uri: Uri): Intent =
        Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun preferredNonBrowserHandler(
        intent: Intent,
        browserPackages: Set<String>,
        preferredPackage: String?,
    ): ResolveInfo? {
        val handlers = queryIntentHandlers(intent)
            .filter {
                val handlerPackage = it.activityInfo?.packageName
                handlerPackage != null &&
                    handlerPackage != packageName &&
                    handlerPackage !in browserPackages
            }
            .distinctBy { it.activityInfo.packageName }
        handlers.firstOrNull {
            it.activityInfo.packageName == preferredPackage
        }?.let { return it }
        val resolvedPreferredPackage = resolveIntentHandler(intent)
            ?.activityInfo
            ?.packageName
        handlers.firstOrNull {
            it.activityInfo.packageName == resolvedPreferredPackage
        }?.let { return it }
        // Do not silently choose between unrelated applications. One exact
        // candidate is safe; multiple candidates should fall back to a browser
        // where Android can use the user's established default.
        return handlers.singleOrNull()
    }

    private fun installedLauncherApplications(): List<Map<String, Any?>> {
        return launcherHandlers()
            .map { handler ->
                val activity = handler.activityInfo
                mapOf(
                    "identifier" to activity.packageName,
                    "displayName" to
                        handler.loadLabel(packageManager).toString(),
                    "platform" to "android",
                )
            }
            .sortedBy {
                (it["displayName"] as String).lowercase()
            }
    }

    private fun launcherHandlers(): List<ResolveInfo> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        // Launcher activities are not required to also declare CATEGORY_DEFAULT.
        // MATCH_DEFAULT_ONLY silently drops valid installed applications, so
        // enumerate the bounded launcher-visible set without that extra filter.
        return queryIntentHandlers(launcherIntent, defaultOnly = false)
            .filter {
                it.activityInfo?.packageName != null &&
                    it.activityInfo.packageName != packageName
            }
            .distinctBy { it.activityInfo.packageName }
    }

    private fun launcherHandlerForPackage(
        preferredPackage: String,
    ): ResolveInfo? {
        return launcherHandlers().firstOrNull {
            it.activityInfo.packageName == preferredPackage
        }
    }

    private fun matchingLauncherHandler(host: String): ResolveInfo? {
        val domainToken = baseDomainToken(host) ?: return null
        val matches = launcherHandlers()
            .filter {
                handlerTokens(it).contains(domainToken)
            }
        return matches.singleOrNull()
    }

    private fun baseDomainToken(host: String): String? {
        val normalizedHost = host.lowercase().trim('.')
        // A hosted page is not proof that the platform provider's app owns the
        // resource. Avoid mapping arbitrary tenants to GitHub, Firebase, etc.
        val sharedHostingSuffixes = setOf(
            "blogspot.com",
            "firebaseapp.com",
            "github.io",
            "netlify.app",
            "notion.site",
            "pages.dev",
            "vercel.app",
            "web.app",
            "wordpress.com",
        )
        if (
            sharedHostingSuffixes.any {
                normalizedHost == it || normalizedHost.endsWith(".$it")
            }
        ) {
            return null
        }
        val labels = normalizedHost
            .split('.')
            .filter { it.isNotBlank() }
        if (labels.size < 2) return null
        val publicSuffix = labels.takeLast(2).joinToString(".")
        val twoPartPublicSuffixes = setOf(
            "co.uk",
            "org.uk",
            "com.au",
            "com.br",
            "com.eg",
            "com.tr",
            "co.in",
            "co.jp",
            "co.nz",
            "co.za",
        )
        val source = if (
            publicSuffix in twoPartPublicSuffixes &&
            labels.size >= 3
        ) {
            labels[labels.lastIndex - 2]
        } else {
            labels[labels.lastIndex - 1]
        }
        val token = source.replace(Regex("[^a-z0-9]"), "")
        val rejected = setOf(
            "account",
            "app",
            "education",
            "learn",
            "learning",
            "login",
            "online",
            "portal",
            "school",
            "site",
            "web",
        )
        return token.takeIf {
            it.length in 5..40 &&
                it !in rejected
        }
    }

    private fun handlerTokens(handler: ResolveInfo): Set<String> {
        val packageTokens = handler.activityInfo.packageName
            .lowercase()
            .split('.')
            .map { it.replace(Regex("[^a-z0-9]"), "") }
        val label = handler.loadLabel(packageManager).toString().lowercase()
        val labelTokens = label
            .split(Regex("[^a-z0-9]+"))
            .map { it.replace(Regex("[^a-z0-9]"), "") }
        val normalizedLabel = label.replace(Regex("[^a-z0-9]"), "")
        return (packageTokens + labelTokens + normalizedLabel)
            .filter { it.isNotBlank() }
            .toSet()
    }

    private fun launchResourceHandler(
        handler: ResolveInfo,
        intent: Intent,
        target: String,
        resolution: String,
        originalUri: Uri,
        launchedUri: Uri?,
    ): Map<String, Any?> {
        val selectedPackage = handler.activityInfo.packageName
        return runCatching {
            startActivity(
                Intent(intent).apply {
                    if (component == null) setPackage(selectedPackage)
                },
            )
            mapOf(
                "opened" to true,
                "handlerPackage" to selectedPackage,
                "handlerLabel" to handler.loadLabel(packageManager).toString(),
                "target" to target,
                "resolution" to resolution,
                "usedFallback" to (resolution != "exact_deep_link"),
                "originalUrl" to originalUri.toString(),
                "launchedUrl" to launchedUri?.toString(),
            )
        }.getOrElse {
            mapOf(
                "opened" to false,
                "reason" to "handler_launch_failed",
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun queryIntentHandlers(
        intent: Intent,
        defaultOnly: Boolean = true,
    ): List<ResolveInfo> {
        val flags = if (defaultOnly) {
            PackageManager.MATCH_DEFAULT_ONLY.toLong()
        } else {
            0L
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(flags),
            )
        } else {
            packageManager.queryIntentActivities(
                intent,
                flags.toInt(),
            )
        }
    }

    @Suppress("DEPRECATION")
    private fun resolveIntentHandler(intent: Intent): ResolveInfo? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.resolveActivity(
                intent,
                PackageManager.ResolveInfoFlags.of(
                    PackageManager.MATCH_DEFAULT_ONLY.toLong(),
                ),
            )
        } else {
            packageManager.resolveActivity(
                intent,
                PackageManager.MATCH_DEFAULT_ONLY,
            )
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

    private fun bluetoothState(): Map<String, Any?> {
        val supported = packageManager.hasSystemFeature(
            PackageManager.FEATURE_BLUETOOTH_LE,
        )
        if (!supported) {
            return mapOf("supported" to false, "enabled" to false)
        }
        return try {
            val manager = getSystemService(Context.BLUETOOTH_SERVICE)
                as BluetoothManager
            mapOf(
                "supported" to true,
                "enabled" to (manager.adapter?.isEnabled == true),
            )
        } catch (_: SecurityException) {
            mapOf(
                "supported" to true,
                "enabled" to false,
                "permissionRequired" to true,
            )
        }
    }

    private fun hasBluetoothConnectPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED

    /**
     * Returns only health wearables that the user has already paired.  We do
     * not start a BLE scan here: a nearby device is neither user-selected nor
     * evidence that it is a health source.
     */
    private fun listPairedHealthDevices(result: MethodChannel.Result) {
        if (!hasBluetoothConnectPermission()) {
            result.error(
                "bluetooth_permission",
                "Bluetooth connect permission is required",
                null,
            )
            return
        }
        val manager = getSystemService(Context.BLUETOOTH_SERVICE)
            as BluetoothManager
        val adapter = manager.adapter
        if (adapter == null) {
            result.error("bluetooth_unavailable", "Bluetooth is unavailable", null)
            return
        }
        if (!adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth is turned off", null)
            return
        }
        try {
            result.success(pairedHealthDevices(adapter, manager))
        } catch (error: SecurityException) {
            result.error(
                "bluetooth_permission",
                error.message ?: "Bluetooth connect permission is required",
                null,
            )
        }
    }

    private fun pairedHealthDevices(
        adapter: BluetoothAdapter,
        manager: BluetoothManager,
    ): List<Map<String, Any?>> {
        val connectedAddresses = connectedGattAddresses(manager)
        val bondedDevices = runCatching { adapter.bondedDevices }.getOrNull()
            ?: emptySet()
        return bondedDevices
            .asSequence()
            .filter(::isPairedHealthWearable)
            .mapNotNull { device ->
                val address = runCatching { device.address }.getOrNull()
                    ?.takeIf { it.isNotBlank() }
                    ?: return@mapNotNull null
                mapOf(
                    "name" to runCatching { device.name }.getOrNull(),
                    "address" to address,
                    "bonded" to true,
                    "connected" to connectedAddresses.contains(address),
                    "healthDevice" to true,
                    // A health name/class is only a discovery filter.  A
                    // direct capability is never claimed until successful
                    // GATT service + characteristic inspection.
                    "capabilityState" to "not_checked",
                    "capabilities" to emptyList<String>(),
                )
            }
            .sortedWith(
                compareByDescending<Map<String, Any?>> {
                    it["connected"] == true
                }.thenBy {
                    (it["name"] as? String)?.lowercase(Locale.ROOT) ?: ""
                },
            )
            .toList()
    }

    private fun connectedGattAddresses(manager: BluetoothManager): Set<String> =
        runCatching { manager.getConnectedDevices(BluetoothProfile.GATT) }
            .getOrDefault(emptyList())
            .mapNotNull { device ->
                runCatching { device.address }.getOrNull()
            }
            .toSet()

    /**
     * A paired device is accepted only when Android identifies a health class
     * or wrist watch, or its already-paired name identifies a well-known
     * watch/band family. BLE advertisements and RSSI are intentionally not
     * part of this decision.
     */
    private fun isPairedHealthWearable(device: BluetoothDevice): Boolean {
        if (device.bondState != BluetoothDevice.BOND_BONDED) return false
        val name = runCatching { device.name }.getOrNull()
            ?.trim()
            ?.lowercase(Locale.ROOT)
            .orEmpty()
        if (excludedBluetoothDeviceTokens.any(name::contains)) return false
        val deviceClass = runCatching {
            device.bluetoothClass?.deviceClass
        }.getOrNull()
        if (
            deviceClass == BluetoothClass.Device.WEARABLE_WRIST_WATCH ||
                deviceClass in healthBluetoothDeviceClasses
        ) {
            return true
        }
        return healthWearableNameTokens.any(name::contains)
    }

    private fun pairedHealthWearableForAddress(
        adapter: BluetoothAdapter,
        address: String,
    ): BluetoothDevice? = runCatching { adapter.bondedDevices }
        .getOrDefault(emptySet())
        .firstOrNull { device ->
            runCatching { device.address.equals(address, ignoreCase = true) }
                .getOrDefault(false) && isPairedHealthWearable(device)
        }

    private fun inspectPairedHealthDevice(
        address: String?,
        result: MethodChannel.Result,
        timeoutMillis: Long,
    ) {
        if (pendingGattResult != null) {
            result.error(
                "inspection_active",
                "A Bluetooth capability inspection is already active",
                null,
            )
            return
        }
        if (address.isNullOrBlank()) {
            result.error("missing_address", "A Bluetooth address is required", null)
            return
        }
        if (!hasBluetoothConnectPermission()) {
            result.error(
                "bluetooth_permission",
                "Bluetooth connect permission is required",
                null,
            )
            return
        }
        val adapter = (
            getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        ).adapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("bluetooth_disabled", "Bluetooth is turned off", null)
            return
        }
        val device = pairedHealthWearableForAddress(adapter, address)
        if (device == null) {
            result.error(
                "not_paired_health_device",
                "The device is not a paired health wearable",
                null,
            )
            return
        }
        pendingGattResult = result
        inspectedGattAddress = address
        mainHandler.removeCallbacks(stopGattInspection)
        mainHandler.postDelayed(stopGattInspection, timeoutMillis)
        try {
            inspectedGatt = device.connectGatt(
                this,
                false,
                gattCallback,
                BluetoothDevice.TRANSPORT_LE,
            )
            if (inspectedGatt == null) {
                finishGattInspection(
                    state = "unknown",
                    errorCode = "gatt_connection_failed",
                )
            }
        } catch (error: SecurityException) {
            finishGattInspection(
                state = "unknown",
                errorCode = "bluetooth_permission",
            )
        } catch (error: Exception) {
            finishGattInspection(
                state = "unknown",
                errorCode = "gatt_connection_failed",
            )
        }
    }

    private fun finishGattInspection(
        state: String,
        capabilities: List<String> = emptyList(),
        discoveredServiceUuids: List<String> = emptyList(),
        errorCode: String? = null,
    ) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post {
                finishGattInspection(
                    state = state,
                    capabilities = capabilities,
                    discoveredServiceUuids = discoveredServiceUuids,
                    errorCode = errorCode,
                )
            }
            return
        }
        val pending = pendingGattResult ?: return
        val address = inspectedGattAddress
        val gatt = inspectedGatt
        pendingGattResult = null
        inspectedGattAddress = null
        inspectedGatt = null
        mainHandler.removeCallbacks(stopGattInspection)
        runCatching {
            gatt?.disconnect()
            gatt?.close()
        }
        pending.success(
            mapOf(
                "address" to address,
                "capabilityState" to state,
                "capabilities" to capabilities,
                "discoveredServiceUuids" to discoveredServiceUuids,
                "inspectionError" to errorCode,
            ),
        )
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

    /**
     * Returns completed foreground periods since [requestedSinceMillis].
     *
     * Android deliberately suspends most app work while an app is in the
     * background, so a Dart timer alone cannot observe every app switch.  On
     * returning to TaskMaster we read the platform's UsageEvents history and
     * return compact, completed periods.  We never return titles, URLs, or
     * polling samples; the Dart layer stores only normalized local segments.
     */
    private fun recentForegroundActivityPeriods(
        requestedSinceMillis: Long?,
    ): List<Map<String, Any?>> {
        val manager =
            getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        // A bounded first catch-up prevents an unusually long running task
        // from repeatedly scanning an unbounded UsageEvents history.
        val sixHoursAgo = now - 6 * 60 * 60 * 1000L
        val since = maxOf(requestedSinceMillis ?: now - 10 * 60 * 1000L, sixHoursAgo)
        val events = manager.queryEvents(since, now)
        val event = UsageEvents.Event()
        val periods = mutableListOf<Map<String, Any?>>()
        var foregroundPackage: String? = null
        var foregroundStartedAt = 0L

        fun labelFor(targetPackage: String): String =
            try {
                val info = packageManager.getApplicationInfo(targetPackage, 0)
                packageManager.getApplicationLabel(info).toString()
            } catch (_: Exception) {
                targetPackage
            }

        fun closeForeground(endedAt: Long) {
            val targetPackage = foregroundPackage ?: return
            if (
                targetPackage != packageName &&
                    endedAt - foregroundStartedAt >= 900L
            ) {
                periods.add(
                    mapOf(
                        "applicationName" to labelFor(targetPackage),
                        "packageName" to targetPackage,
                        "startedAt" to foregroundStartedAt,
                        "endedAt" to endedAt,
                        "windowTitle" to null,
                        "idleSeconds" to 0,
                        "isTaskMasterWindow" to false,
                    ),
                )
            }
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (
                event.eventType != UsageEvents.Event.ACTIVITY_RESUMED &&
                    event.eventType != UsageEvents.Event.MOVE_TO_FOREGROUND
            ) {
                continue
            }
            val nextPackage = event.packageName ?: continue
            val nextStartedAt = event.timeStamp
            // Some Android versions emit both event kinds for the same
            // foreground transition.  Treat the pair as one period.
            if (nextPackage == foregroundPackage) continue
            closeForeground(nextStartedAt)
            foregroundPackage = nextPackage
            foregroundStartedAt = nextStartedAt
        }
        return periods
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(stopGattInspection)
        runCatching {
            inspectedGatt?.disconnect()
            inspectedGatt?.close()
        }
        inspectedGatt = null
        pendingGattResult = null
        previewRingtone?.stop()
        previewRingtone = null
        super.onDestroy()
    }
}

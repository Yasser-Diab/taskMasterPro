package pro.taskmaster.taskmaster_pro

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Reads the canonical ExerciseSessionRecord rows without the optional
 * distance/calorie/step enrichment performed by the third-party health
 * plugin. Some Health Connect providers expose valid exercise sessions while
 * one of those auxiliary queries returns no result. Workouts must still be
 * visible in DayVector in that case.
 */
class DayVectorHealthWorkoutBridge(
    context: Context,
    messenger: BinaryMessenger,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val healthConnectClient = HealthConnectClient.getOrCreate(
        context.applicationContext,
    )
    private val channel = MethodChannel(messenger, CHANNEL_NAME)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "readWorkoutSessions" -> {
                    val startMillis = call.argument<Number>("startMillis")?.toLong()
                    val endMillis = call.argument<Number>("endMillis")?.toLong()
                    if (
                        startMillis == null ||
                            endMillis == null ||
                            startMillis >= endMillis
                    ) {
                        result.error(
                            "invalid_workout_window",
                            "A valid workout time window is required",
                            null,
                        )
                    } else {
                        readWorkoutSessions(startMillis, endMillis, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readWorkoutSessions(
        startMillis: Long,
        endMillis: Long,
        result: MethodChannel.Result,
    ) {
        scope.launch {
            try {
                val permission = HealthPermission.getReadPermission(
                    ExerciseSessionRecord::class,
                )
                val granted = healthConnectClient.permissionController
                    .getGrantedPermissions()
                    .contains(permission)
                if (!granted) {
                    Log.w(TAG, "Exercise permission is not granted")
                    postSuccess(result, emptyList<Map<String, Any?>>())
                    return@launch
                }

                val records = mutableListOf<ExerciseSessionRecord>()
                var pageToken: String? = null
                do {
                    val response = healthConnectClient.readRecords(
                        ReadRecordsRequest(
                            recordType = ExerciseSessionRecord::class,
                            timeRangeFilter = TimeRangeFilter.between(
                                Instant.ofEpochMilli(startMillis),
                                Instant.ofEpochMilli(endMillis),
                            ),
                            pageToken = pageToken,
                        ),
                    )
                    records.addAll(response.records)
                    pageToken = response.pageToken
                } while (!pageToken.isNullOrEmpty())

                Log.i(
                    TAG,
                    "Read ${records.size} exercise sessions between " +
                        "$startMillis and $endMillis",
                )

                postSuccess(
                    result,
                    records.map { record ->
                        mapOf(
                            "uuid" to record.metadata.id,
                            "startMillis" to record.startTime.toEpochMilli(),
                            "endMillis" to record.endTime.toEpochMilli(),
                            "sourcePackage" to
                                record.metadata.dataOrigin.packageName,
                            "recordingMethod" to
                                record.metadata.recordingMethod,
                            "exerciseType" to record.exerciseType,
                        )
                    },
                )
            } catch (error: Exception) {
                Log.e(TAG, "Exercise session read failed", error)
                mainHandler.post {
                    result.error(
                        "workout_read_failed",
                        error.message ?: "Health Connect workout read failed",
                        error.javaClass.name,
                    )
                }
            }
        }
    }

    private fun postSuccess(
        result: MethodChannel.Result,
        value: List<Map<String, Any?>>,
    ) {
        mainHandler.post { result.success(value) }
    }

    fun close() {
        channel.setMethodCallHandler(null)
        scope.cancel()
    }

    private companion object {
        const val TAG = "DAYVECTOR_HEALTH"
        const val CHANNEL_NAME = "dayvector/health_workouts"
    }
}

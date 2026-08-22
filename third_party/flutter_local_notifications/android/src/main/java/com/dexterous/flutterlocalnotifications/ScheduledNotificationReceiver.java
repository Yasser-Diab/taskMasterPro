package com.dexterous.flutterlocalnotifications;

import android.app.Notification;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import androidx.annotation.Keep;
import androidx.core.app.NotificationManagerCompat;

import com.dexterous.flutterlocalnotifications.models.NotificationDetails;
import com.dexterous.flutterlocalnotifications.utils.StringUtils;
import com.google.gson.Gson;
import com.google.gson.reflect.TypeToken;

import org.json.JSONObject;

import java.lang.reflect.Type;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.concurrent.TimeUnit;

/** Created by michaelbui on 24/3/18. */
@Keep
public class ScheduledNotificationReceiver extends BroadcastReceiver {

  private static final String TAG = "ScheduledNotifReceiver";
  private static final int TASKMASTER_SLEEP_REMINDER_ID = 820026;
  private static final long TASKMASTER_SLEEP_MAX_OVERDUE_MILLIS =
      TimeUnit.HOURS.toMillis(2);

  @Override
  @SuppressWarnings("deprecation")
  public void onReceive(final Context context, Intent intent) {
    String notificationDetailsJson =
        intent.getStringExtra(FlutterLocalNotificationsPlugin.NOTIFICATION_DETAILS);
    if (StringUtils.isNullOrEmpty(notificationDetailsJson)) {
      // This logic is needed for apps that used the plugin prior to 0.3.4

      Notification notification;
      int notificationId = intent.getIntExtra("notification_id", 0);

      if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
        notification = intent.getParcelableExtra("notification", Notification.class);
      } else {
        notification = intent.getParcelableExtra("notification");
      }

      if (notification == null) {
        // This means the notification is corrupt
        FlutterLocalNotificationsPlugin.removeNotificationFromCache(context, notificationId);
        Log.e(TAG, "Failed to parse a notification from  Intent. ID: " + notificationId);
        return;
      }

      notification.when = System.currentTimeMillis();
      NotificationManagerCompat notificationManager = NotificationManagerCompat.from(context);
      notificationManager.notify(notificationId, notification);
      boolean repeat = intent.getBooleanExtra("repeat", false);
      if (!repeat) {
        FlutterLocalNotificationsPlugin.removeNotificationFromCache(context, notificationId);
      }
    } else {
      Gson gson = FlutterLocalNotificationsPlugin.buildGson();
      Type type = new TypeToken<NotificationDetails>() {}.getType();
      NotificationDetails notificationDetails = gson.fromJson(notificationDetailsJson, type);

      if (taskMasterSleepReminderIsGrosslyOverdue(notificationDetails)) {
        // Android can retain a pre-update AlarmManager entry and deliver it as
        // soon as ACTION_MY_PACKAGE_REPLACED reschedules the plugin cache. Do
        // not turn that several-days-old boundary into a misleading wellbeing
        // alert. Advance the normal daily recurrence from the current clock.
        FlutterLocalNotificationsPlugin.scheduleNextNotification(context, notificationDetails);
        Log.i(TAG, "Suppressed overdue TaskMaster sleep reminder");
        return;
      }

      if (!executionIdentityIsCurrent(context, notificationDetails)) {
        FlutterLocalNotificationsPlugin.removeNotificationFromCache(
            context, notificationDetails.id);
        Log.i(TAG, "Suppressed stale TaskMaster execution notification ID: "
            + notificationDetails.id);
        return;
      }

      FlutterLocalNotificationsPlugin.showNotification(context, notificationDetails);
      FlutterLocalNotificationsPlugin.scheduleNextNotification(context, notificationDetails);
    }
  }

  /**
   * TaskMaster's daily sleep reminder is the only recurring notification for
   * which a package-replacement catch-up is actively harmful. Keep this guard
   * scoped to its stable ID and owned route so ordinary reminders and exact
   * task execution boundaries retain upstream plugin behavior.
   */
  private boolean taskMasterSleepReminderIsGrosslyOverdue(
      NotificationDetails notificationDetails) {
    if (notificationDetails == null
        || notificationDetails.id == null
        || notificationDetails.id != TASKMASTER_SLEEP_REMINDER_ID
        || StringUtils.isNullOrEmpty(notificationDetails.payload)
        || StringUtils.isNullOrEmpty(notificationDetails.scheduledDateTime)
        || StringUtils.isNullOrEmpty(notificationDetails.timeZoneName)) {
      return false;
    }
    try {
      JSONObject payload = new JSONObject(notificationDetails.payload);
      if (!"settings/wellbeing".equals(payload.optString("route"))) return false;
      long scheduledAtMillis = ZonedDateTime.of(
              LocalDateTime.parse(notificationDetails.scheduledDateTime),
              ZoneId.of(notificationDetails.timeZoneName))
          .toInstant()
          .toEpochMilli();
      return System.currentTimeMillis() - scheduledAtMillis
          > TASKMASTER_SLEEP_MAX_OVERDUE_MILLIS;
    } catch (Exception exception) {
      // A malformed non-execution reminder keeps the plugin's established
      // behavior. This guard suppresses only a positively identified stale
      // TaskMaster sleep occurrence.
      Log.w(TAG, "Could not validate TaskMaster sleep reminder age", exception);
      return false;
    }
  }

  /**
   * TaskMaster extension: validates a focus/break/task-duration boundary before
   * Android displays it. Non-execution notifications keep upstream behavior.
   * This reads only an app-private local mirror; no Flutter engine or network
   * call runs from the receiver.
   */
  private boolean executionIdentityIsCurrent(
      Context context, NotificationDetails notificationDetails) {
    if (StringUtils.isNullOrEmpty(notificationDetails.payload)
        || !notificationDetails.payload.startsWith("{")) {
      return true;
    }
    try {
      JSONObject payload = new JSONObject(notificationDetails.payload);
      String eventType = payload.optString("event_type");
      if (StringUtils.isNullOrEmpty(eventType)) return true;

      String ownerId = payload.optString("owner_id");
      String route = payload.optString("route");
      String notificationId = payload.optString("notification_id");
      String sessionId = payload.optString("session_id");
      String intervalId = payload.optString("interval_id");
      String boundaryAt = payload.optString("boundary_at");
      if (StringUtils.isNullOrEmpty(ownerId)
          || StringUtils.isNullOrEmpty(route)
          || !route.startsWith("task/")
          || StringUtils.isNullOrEmpty(notificationId)
          || StringUtils.isNullOrEmpty(sessionId)
          || StringUtils.isNullOrEmpty(intervalId)
          || StringUtils.isNullOrEmpty(boundaryAt)
          || !payload.has("runtime_revision")) {
        return false;
      }

      String taskId = route.substring("task/".length());
      String ledgerJson = context
          .getSharedPreferences(
              "taskmaster.execution_alarm_ledger.v0028", Context.MODE_PRIVATE)
          .getString(ownerId, null);
      if (StringUtils.isNullOrEmpty(ledgerJson)) return false;
      JSONObject row = new JSONObject(ledgerJson).optJSONObject(taskId);
      if (row == null) return false;
      String state = row.optString("state");
      return (state.equals("scheduled") || state.equals("delivered"))
          && row.optString("task_id").equals(taskId)
          && row.optString("notification_id").equals(notificationId)
          && row.optString("session_id").equals(sessionId)
          && row.optLong("runtime_revision", Long.MIN_VALUE)
              == payload.optLong("runtime_revision", Long.MAX_VALUE)
          && row.optString("interval_id").equals(intervalId)
          && row.optString("boundary_at").equals(boundaryAt);
    } catch (Exception exception) {
      // Execution payloads fail closed. Ordinary reminders and app cards never
      // enter this branch because they do not carry event_type.
      Log.w(TAG, "Could not validate TaskMaster execution notification", exception);
      return false;
    }
  }
}

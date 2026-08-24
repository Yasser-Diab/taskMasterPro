import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android manifest exposes one responsive TaskMaster widget provider',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final providerInfo = File(
        'android/app/src/main/res/xml/taskmaster_widget_info.xml',
      ).readAsStringSync();
      final nativeProvider = File(
        'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/'
        'TaskMasterWidgetProvider.kt',
      ).readAsStringSync();

      expect(manifest, contains('.TaskMasterWidgetProvider'));
      expect(manifest, contains('android.appwidget.action.APPWIDGET_UPDATE'));
      expect(
        providerInfo,
        contains('android:resizeMode="horizontal|vertical"'),
      );
      expect(providerInfo, contains('android:minResizeWidth="110dp"'));
      expect(nativeProvider, contains('OPTION_APPWIDGET_MIN_WIDTH'));
      expect(nativeProvider, contains('taskmaster_widget_compact'));
      expect(nativeProvider, contains('taskmaster_widget_medium'));
      expect(nativeProvider, contains('taskmaster_widget_expanded'));
      expect(nativeProvider, contains('setChronometerCountDown'));
      expect(nativeProvider, contains('TaskMasterWidgetIntent.commandAction'));
      expect(
        nativeProvider,
        contains('TaskMasterWidgetActionReceiver::class.java'),
      );
      expect(nativeProvider, contains('PendingIntent.getBroadcast'));
      expect(nativeProvider, contains('commandIdentityUri'));
      expect(nativeProvider, contains('FLAG_CANCEL_CURRENT'));
      expect(nativeProvider, contains('runtimeRevision'));
      expect(nativeProvider, contains('runtimeUpdatedAtEpochMs'));
      expect(
        nativeProvider,
        contains('incomingRuntimeRevision < storedRuntimeRevision'),
      );
      expect(
        nativeProvider,
        contains('incomingRuntimeRevision == storedRuntimeRevision'),
      );
      expect(
        nativeProvider,
        contains('incomingRuntimeUpdatedAt <= storedRuntimeUpdatedAt'),
      );
      expect(nativeProvider, contains('return false'));
      expect(
        nativeProvider,
        contains('TaskMasterExecutionNotificationCleaner'),
      );
      expect(nativeProvider, contains('manager.activeNotifications'));
      expect(nativeProvider, contains('manager.cancel(notification.tag'));

      final controls = nativeProvider.substring(
        nativeProvider.indexOf('private fun renderControls('),
        nativeProvider.indexOf('private fun renderTimer('),
      );
      expect(controls, isNot(contains('PendingIntent.getActivity')));
      expect(manifest, contains('.TaskMasterWidgetActionReceiver'));
      expect(manifest, contains('.TaskMasterBackgroundActionService'));
      expect(
        manifest,
        contains('android:foregroundServiceType="shortService"'),
      );
    },
  );

  test('notification mutations use the explicit headless receiver', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final plugin = File(
      'third_party/flutter_local_notifications/android/src/main/java/com/'
      'dexterous/flutterlocalnotifications/FlutterLocalNotificationsPlugin.java',
    ).readAsStringSync();
    final service = File(
      'android/app/src/main/kotlin/pro/taskmaster/taskmaster_pro/'
      'TaskMasterWidgetActionService.kt',
    ).readAsStringSync();

    expect(
      manifest,
      contains('com.dexterous.flutterlocalnotifications.ACTION_RECEIVER'),
    );
    expect(manifest, contains('.TaskMasterNotificationActionReceiver'));
    expect(plugin, contains('getBackgroundActionIntent(context)'));
    expect(service, contains('taskMasterBackgroundActionMain'));
    expect(service, contains('kind = "notification"'));
    expect(service, contains('if (accepted)'));
  });

  test('all responsive layouts expose the shared rendering contract', () {
    const layouts = [
      'taskmaster_widget_compact.xml',
      'taskmaster_widget_medium.xml',
      'taskmaster_widget_expanded.xml',
    ];
    for (final layout in layouts) {
      final source = File(
        'android/app/src/main/res/layout/$layout',
      ).readAsStringSync();
      for (final id in const [
        'widget_root',
        'widget_header',
        'widget_status',
        'widget_title',
        'widget_message',
        'widget_timer_text',
        'widget_timer_chronometer',
        'widget_progress',
        'widget_action',
        'widget_controls',
        'widget_control_1',
        'widget_control_2',
        'widget_control_3',
        'widget_suggestions',
        'widget_suggestion_1',
        'widget_suggestion_2',
        'widget_suggestion_3',
      ]) {
        expect(source, contains('@+id/$id'), reason: '$layout must expose $id');
      }
    }
  });
}

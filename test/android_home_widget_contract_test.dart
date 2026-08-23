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
      expect(nativeProvider, contains('runtimeRevision'));
    },
  );

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

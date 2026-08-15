import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';

void main() {
  group('narrow phone presentation contracts', () {
    for (final locale in AppLocalizations.supportedLocales) {
      test(
        'essential compact labels remain concise in ${locale.languageCode}',
        () {
          final l10n = AppLocalizations(locale);
          for (final key in const [
            'dashboard_no_active_task',
            'add_task',
            'synchronization',
            'sync_now',
            'add_application',
            'add_website',
            'continue',
          ]) {
            expect(l10n.text(key), isNot(contains('⟦')));
            expect(l10n.text(key).trim(), isNotEmpty);
          }
        },
      );
    }

    test('dashboard gives copy full width before the independent action', () {
      final source = File(
        'lib/features/dashboard/presentation/dashboard_screen.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('dashboard-no-active-task-card')"));
      expect(source, contains('if (constraints.maxWidth < 430)'));
      expect(source, contains('Expanded(child: title)'));
      expect(source, contains('description,'));
      expect(source, contains('alignment: AlignmentDirectional.centerStart'));
    });

    test('sync dialog is viewport bound and actions can wrap', () {
      final source = File(
        'lib/features/sync/presentation/synchronization_panel.dart',
      ).readAsStringSync();

      expect(source, contains('final compact = viewport.width < 430'));
      expect(source, contains("ValueKey('synchronization-status-card')"));
      expect(source, contains('child: Wrap('));
      expect(source, contains('keyboardDismissBehavior:'));
      expect(source, contains('getSnapshot(checkRemoteDevices: false)'));
      expect(source, isNot(contains('showConnectedDevices')));
      expect(source, isNot(contains("text('connected_devices')")));
      expect(source, contains('final compact = viewport.width < 600'));
      expect(
        source,
        contains(
          'height: (viewport.height - (compact ? 32 : 48)).clamp(320.0, 760.0)',
        ),
      );
      expect(
        source,
        contains('context.l10n.locale.toLanguageTag()'),
        reason: 'Sync dates must follow the selected language.',
      );
    });

    test('connected devices has a dedicated responsive route', () {
      final source = File(
        'lib/features/settings/presentation/connected_devices_screen.dart',
      ).readAsStringSync();
      final settings = File(
        'lib/features/settings/presentation/settings_screen.dart',
      ).readAsStringSync();

      expect(source, contains('class ConnectedDevicesScreen'));
      expect(source, contains("ValueKey('connected-devices-list')"));
      expect(source, contains('getSnapshot(checkRemoteDevices: true)'));
      expect(source, contains('Expanded('));
      expect(source, contains('Wrap('));
      expect(settings, contains('const ConnectedDevicesScreen()'));
      expect(settings, isNot(contains('showConnectedDevices')));
    });

    test('connection cards stack their action below readable copy', () {
      final source = File(
        'lib/features/tasks/presentation/task_workspace_screen.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('connection-card-\$title')"));
      expect(source, contains('final compact = constraints.maxWidth < 420'));
      expect(source, contains('Expanded(child: copy)'));
      expect(source, contains('child: add'));
    });

    test('schedule editor is keyboard safe with a wrapping compact footer', () {
      final source = File(
        'lib/features/tasks/presentation/task_editor_dialog.dart',
      ).readAsStringSync();

      expect(source, contains('final compact = viewport.width < 520'));
      expect(source, contains('if (constraints.maxWidth < 390)'));
      expect(source, contains('keyboardDismissBehavior:'));
      expect(
        source,
        contains('_CalculatedDurationField(window: scheduleWindow)'),
      );
      expect(source, contains('minimum: _minimumPlannedEnd'));
    });

    test('browser chrome separates tab, timer, and address on phones', () {
      final source = File(
        'lib/features/tasks/presentation/task_browser_workspace.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('final phone = MediaQuery.sizeOf(context).width < 520'),
      );
      expect(source, contains('fillAvailableWidth: true'));
      expect(
        source,
        contains('final veryCompact = constraints.maxWidth < 380'),
      );
      expect(source, contains('compact: true'));
    });

    test(
      'tasks replace the stacked phone form with one compact filter path',
      () {
        final source = File(
          'lib/features/tasks/presentation/tasks_screen.dart',
        ).readAsStringSync();

        expect(
          source,
          contains('final compact = MediaQuery.sizeOf(context).width < 600'),
        );
        expect(source, contains("ValueKey('mobile-task-filter-header')"));
        expect(source, contains("ValueKey('mobile-task-filter-button')"));
        expect(source, contains("ValueKey('mobile-task-status-strip')"));
        expect(source, contains("ValueKey('task-filter-sheet')"));
        expect(source, contains('if (!compact)'));
        expect(
          source,
          isNot(contains('_EmptyTasks(\n                    onAdd:')),
        );
      },
    );

    test('roadmaps use a content-sized phone list instead of a fixed grid', () {
      final source = File(
        'lib/features/roadmaps/presentation/roadmaps_screen.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('mobile-roadmap-add')"));
      expect(source, contains('SliverList.separated('));
      expect(source, contains('if (constraints.maxWidth < 380)'));
      expect(source, contains('if (constraints.maxWidth < 420)'));
      expect(source, contains('Directionality.of(context)'));
    });

    test('report controls replace desktop segments with phone dropdowns', () {
      final source = File(
        'lib/features/reports/presentation/performance_report_screen.dart',
      ).readAsStringSync();

      expect(source, contains("ValueKey('mobile-report-controls')"));
      expect(source, contains('if (constraints.maxWidth < 600)'));
      expect(source, contains('DropdownButtonFormField<String>'));
      expect(
        RegExp('DropdownButtonFormField<bool>').allMatches(source).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('settings reduce phone padding and let long headings wrap', () {
      final source = File(
        'lib/features/settings/presentation/settings_screen.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('final compact = MediaQuery.sizeOf(context).width < 600'),
      );
      expect(source, contains('padding: EdgeInsets.all(compact ? 16 : 20)'));
      expect(source, contains('if (constraints.maxWidth < 420)'));
      expect(source, contains('constraints.maxWidth >= 360'));
      expect(
        source,
        contains(
          'Expanded(\n                  child: Text(\n                    title,',
        ),
      );
    });
  });
}

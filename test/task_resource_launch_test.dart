import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/tasks/data/task_resource_service.dart';
import 'package:taskmaster_pro/features/tasks/domain/task_resource_launch.dart';
import 'package:taskmaster_pro/features/tasks/presentation/task_start_flow.dart';

void main() {
  final url = Uri.parse('https://www.duolingo.com/learn');

  test('in-app is the safe default for missing task configuration', () {
    expect(TaskResourceLaunchMode.fromKey(null), TaskResourceLaunchMode.inApp);
    expect(
      TaskResourceLaunchMode.fromKey('unknown'),
      TaskResourceLaunchMode.inApp,
    );
  });

  test(
    'task and resource launch defaults are honored by ordinary URL taps',
    () {
      LocalTask task(String dataJson) => LocalTask(
        id: 'task-1',
        userId: 'owner',
        title: 'German lesson',
        description: '',
        status: 'ready',
        priority: 2,
        executionMode: 'continuous',
        estimatedDurationMs: 40 * 60 * 1000,
        activeDurationMs: 0,
        pausedDurationMs: 0,
        idleDurationMs: 0,
        progress: 0,
        dataJson: dataJson,
        revision: 1,
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
      );

      final externalApp = task('{"resource_launch_mode":"external_app"}');
      expect(
        configuredTaskResourceLaunchMode(externalApp),
        TaskResourceLaunchMode.externalApp,
      );
      expect(
        configuredTaskResourceLaunchMode(externalApp, const {
          'launch_mode': 'external_browser',
        }),
        TaskResourceLaunchMode.externalBrowser,
      );
      expect(
        configuredTaskResourceLaunchMode(task('not-json')),
        TaskResourceLaunchMode.inApp,
      );
    },
  );

  test(
    'installed app handler is preferred without touching the browser',
    () async {
      var appAttempts = 0;
      var browserAttempts = 0;
      final outcome = await launchExternalResourceWithFallback(
        url: url,
        mode: TaskResourceLaunchMode.externalApp,
        openInstalledApp: (_) {
          appAttempts += 1;
          return true;
        },
        openBrowser: (_) {
          browserAttempts += 1;
          return true;
        },
      );

      expect(outcome.opened, isTrue);
      expect(outcome.usedFallback, isFalse);
      expect(appAttempts, 1);
      expect(browserAttempts, 0);
    },
  );

  test('missing learning app falls back to a browser once', () async {
    var browserAttempts = 0;
    final outcome = await launchExternalResourceWithFallback(
      url: url,
      mode: TaskResourceLaunchMode.externalApp,
      openInstalledApp: (_) => false,
      openBrowser: (_) {
        browserAttempts += 1;
        return true;
      },
    );

    expect(outcome.opened, isTrue);
    expect(outcome.usedFallback, isTrue);
    expect(browserAttempts, 1);
  });

  test(
    'browser-only mode never probes installed application handlers',
    () async {
      var appAttempts = 0;
      final outcome = await launchExternalResourceWithFallback(
        url: url,
        mode: TaskResourceLaunchMode.externalBrowser,
        openInstalledApp: (_) {
          appAttempts += 1;
          return true;
        },
        openBrowser: (_) => true,
      );

      expect(outcome.opened, isTrue);
      expect(appAttempts, 0);
    },
  );

  test('resource launch requires the selected canonical running session', () {
    final now = DateTime.utc(2026, 7, 28);
    LocalRuntime runtime({
      String? taskId = 'selected-task',
      String? sessionId = 'selected-session',
      String state = 'running',
    }) {
      return LocalRuntime(
        id: 'active',
        userId: 'owner',
        activeTaskId: taskId,
        sessionId: sessionId,
        state: state,
        accumulatedActiveMs: 0,
        accumulatedPausedMs: 0,
        dataJson: '{}',
        revision: 1,
        updatedAt: now,
      );
    }

    expect(taskRuntimeOwnsStartedTask(runtime(), 'selected-task'), isTrue);
    expect(
      taskRuntimeOwnsStartedTask(
        runtime(taskId: 'different-task'),
        'selected-task',
      ),
      isFalse,
    );
    expect(
      taskRuntimeOwnsStartedTask(runtime(sessionId: null), 'selected-task'),
      isFalse,
    );
    expect(
      taskRuntimeOwnsStartedTask(runtime(state: 'paused'), 'selected-task'),
      isFalse,
    );
    expect(taskRuntimeOwnsStartedTask(null, 'selected-task'), isFalse);
  });

  test('task Start waits for its durable publish pass', () async {
    final releasePublish = Completer<void>();
    var publishStarted = false;
    var returned = false;

    final startPublish = publishStartedTask(() async {
      publishStarted = true;
      await releasePublish.future;
    }).whenComplete(() => returned = true);

    await Future<void>.delayed(Duration.zero);
    expect(publishStarted, isTrue);
    expect(returned, isFalse);

    releasePublish.complete();
    await startPublish;
    expect(returned, isTrue);
  });
}

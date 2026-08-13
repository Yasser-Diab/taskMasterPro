import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmaster_pro/features/tasks/data/execution_exclusivity_coordinator.dart';
import 'package:taskmaster_pro/features/tasks/data/standalone_pomodoro_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('concurrent local starts deterministically leave one owner', () async {
    final runtimeChanges = StreamController<String?>.broadcast();
    final store = StandalonePomodoroStore(accountId: 'owner');
    String? activeTaskId;
    var taskStarts = 0;
    final coordinator = ExecutionExclusivityCoordinator(
      accountId: 'owner',
      standalone: store,
      readActiveTaskId: () async => activeTaskId,
      activeTaskIds: runtimeChanges.stream,
    );

    final standaloneStart = coordinator.startStandalone(
      () => store.startFocus(now: DateTime.utc(2026, 8, 13, 9)),
    );
    final taskStart = coordinator.startTask<String>(
      stopStandalone: false,
      start: () async {
        taskStarts += 1;
        activeTaskId = 'task-1';
        runtimeChanges.add(activeTaskId);
        return activeTaskId!;
      },
    );

    expect((await standaloneStart).started, isTrue);
    final taskResult = await taskStart;
    expect(taskResult.standaloneWasActive, isTrue);
    expect(taskStarts, 0);
    expect((await store.load()).isActive, isTrue);
    expect(activeTaskId, isNull);

    await coordinator.dispose();
    await runtimeChanges.close();
    store.dispose();
  });

  test('task claiming first prevents a concurrent standalone start', () async {
    final runtimeChanges = StreamController<String?>.broadcast();
    final store = StandalonePomodoroStore(accountId: 'owner');
    String? activeTaskId;
    var standaloneStarts = 0;
    final coordinator = ExecutionExclusivityCoordinator(
      accountId: 'owner',
      standalone: store,
      readActiveTaskId: () async => activeTaskId,
      activeTaskIds: runtimeChanges.stream,
    );

    final taskStart = coordinator.startTask<String>(
      stopStandalone: false,
      start: () async {
        activeTaskId = 'task-1';
        runtimeChanges.add(activeTaskId);
        return activeTaskId!;
      },
    );
    final standaloneStart = coordinator.startStandalone(() async {
      standaloneStarts += 1;
      await store.startFocus(now: DateTime.utc(2026, 8, 13, 9));
    });

    expect((await taskStart).value, 'task-1');
    final standaloneResult = await standaloneStart;
    expect(standaloneResult.started, isFalse);
    expect(standaloneResult.activeTaskId, 'task-1');
    expect(standaloneStarts, 0);
    expect((await store.load()).isActive, isFalse);

    await coordinator.dispose();
    await runtimeChanges.close();
    store.dispose();
  });

  test('remote canonical runtime activation stops standalone timer', () async {
    final runtimeChanges = StreamController<String?>.broadcast();
    final store = StandalonePomodoroStore(accountId: 'owner');
    String? activeTaskId;
    final coordinator = ExecutionExclusivityCoordinator(
      accountId: 'owner',
      standalone: store,
      readActiveTaskId: () async => activeTaskId,
      activeTaskIds: runtimeChanges.stream,
    );
    await coordinator.startStandalone(
      () => store.startFocus(now: DateTime.utc(2026, 8, 13, 9)),
    );
    expect((await store.load()).isActive, isTrue);

    activeTaskId = 'remote-task';
    runtimeChanges.add(activeTaskId);
    await pumpEventQueue(times: 20);

    expect((await store.load()).isActive, isFalse);
    await coordinator.dispose();
    await runtimeChanges.close();
    store.dispose();
  });

  test('failed transition does not poison the account gate', () async {
    final runtimeChanges = StreamController<String?>.broadcast();
    final store = StandalonePomodoroStore(accountId: 'owner');
    final coordinator = ExecutionExclusivityCoordinator(
      accountId: 'owner',
      standalone: store,
      readActiveTaskId: () async => null,
      activeTaskIds: runtimeChanges.stream,
    );

    await expectLater(
      coordinator.startTask<void>(
        stopStandalone: false,
        start: () => Future<void>.error(StateError('expected')),
      ),
      throwsStateError,
    );
    final next = await coordinator.startStandalone(
      () => store.startFocus(now: DateTime.utc(2026, 8, 13, 9)),
    );
    expect(next.started, isTrue);

    await coordinator.dispose();
    await runtimeChanges.close();
    store.dispose();
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskmaster_pro/features/tasks/data/standalone_pomodoro_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'persists boundaries and derives elapsed time without tick writes',
    () async {
      final store = StandalonePomodoroStore(accountId: 'owner');
      final startedAt = DateTime.utc(2026, 8, 13, 9);

      await store.configure(
        focus: const Duration(minutes: 25),
        rest: const Duration(minutes: 5),
      );
      await store.startFocus(now: startedAt);

      final afterNineMinutes = await store.load(
        now: startedAt.add(const Duration(minutes: 9)),
      );
      expect(afterNineMinutes.phase, StandalonePomodoroPhase.focusRunning);
      expect(
        afterNineMinutes.elapsedAt(startedAt.add(const Duration(minutes: 9))),
        const Duration(minutes: 9).inMilliseconds,
      );

      await store.pause(now: startedAt.add(const Duration(minutes: 10)));
      final paused = await store.load(
        now: startedAt.add(const Duration(hours: 1)),
      );
      expect(paused.phase, StandalonePomodoroPhase.focusPaused);
      expect(paused.accumulatedMs, const Duration(minutes: 10).inMilliseconds);
      expect(paused.segmentStartedAt, isNull);

      store.dispose();
    },
  );

  test(
    'is account isolated and advances completed focus exactly once',
    () async {
      final owner = StandalonePomodoroStore(accountId: 'owner');
      final other = StandalonePomodoroStore(accountId: 'other');
      final startedAt = DateTime.utc(2026, 8, 13, 9);

      await owner.configure(
        focus: const Duration(minutes: 15),
        rest: const Duration(minutes: 5),
      );
      await owner.startFocus(now: startedAt);

      final completed = await owner.load(
        now: startedAt.add(const Duration(minutes: 16)),
      );
      expect(completed.phase, StandalonePomodoroPhase.focusFinished);
      expect(completed.completedFocusCount, 1);
      expect(
        (await owner.load(
          now: startedAt.add(const Duration(hours: 2)),
        )).completedFocusCount,
        1,
      );
      expect((await other.load()).phase, StandalonePomodoroPhase.idle);

      owner.dispose();
      other.dispose();
    },
  );

  test('reset removes active mutual-exclusion state', () async {
    final store = StandalonePomodoroStore(accountId: 'owner');
    await store.configure(
      focus: const Duration(minutes: 30),
      rest: const Duration(minutes: 10),
    );
    await store.startFocus(now: DateTime.utc(2026, 8, 13, 9));
    expect(
      (await store.load(now: DateTime.utc(2026, 8, 13, 9))).isActive,
      isTrue,
    );

    await store.reset();

    final reset = await store.load();
    expect(reset.isActive, isFalse);
    expect(reset.focusDurationMs, const Duration(minutes: 30).inMilliseconds);
    expect(reset.breakDurationMs, const Duration(minutes: 10).inMilliseconds);
    store.dispose();
  });

  test('focus and break can be skipped in both directions', () async {
    final store = StandalonePomodoroStore(accountId: 'owner');
    final startedAt = DateTime.utc(2026, 8, 13, 9);
    await store.configure(
      focus: const Duration(minutes: 25),
      rest: const Duration(minutes: 5),
    );
    await store.startFocus(now: startedAt);

    await store.skipFocus(now: startedAt.add(const Duration(minutes: 4)));
    final rest = await store.load(
      now: startedAt.add(const Duration(minutes: 4)),
    );
    expect(rest.phase, StandalonePomodoroPhase.breakRunning);
    expect(
      rest.remainingAt(startedAt.add(const Duration(minutes: 4))),
      const Duration(minutes: 5).inMilliseconds,
    );

    await store.skipBreak(now: startedAt.add(const Duration(minutes: 5)));
    final nextFocus = await store.load(
      now: startedAt.add(const Duration(minutes: 5)),
    );
    expect(nextFocus.phase, StandalonePomodoroPhase.focusRunning);
    expect(
      nextFocus.remainingAt(startedAt.add(const Duration(minutes: 5))),
      const Duration(minutes: 25).inMilliseconds,
    );
    expect(nextFocus.completedFocusCount, 0);
    store.dispose();
  });

  test('break extension is one-off and works from its waiting state', () async {
    final store = StandalonePomodoroStore(accountId: 'owner');
    final startedAt = DateTime.utc(2026, 8, 13, 9);
    await store.configure(
      focus: const Duration(minutes: 1),
      rest: const Duration(minutes: 1),
    );
    await store.startFocus(now: startedAt);
    await store.advanceIfDue(now: startedAt.add(const Duration(minutes: 1)));
    await store.startBreak(now: startedAt.add(const Duration(minutes: 1)));
    await store.advanceIfDue(now: startedAt.add(const Duration(minutes: 2)));

    expect(
      (await store.load(now: startedAt.add(const Duration(minutes: 2)))).phase,
      StandalonePomodoroPhase.breakFinished,
    );
    await store.extendBreak(
      by: const Duration(minutes: 5),
      now: startedAt.add(const Duration(minutes: 2)),
    );
    final extended = await store.load(
      now: startedAt.add(const Duration(minutes: 2)),
    );
    expect(extended.phase, StandalonePomodoroPhase.breakRunning);
    expect(
      extended.intervalExtensionMs,
      const Duration(minutes: 5).inMilliseconds,
    );
    expect(
      extended.remainingAt(startedAt.add(const Duration(minutes: 2))),
      const Duration(minutes: 5).inMilliseconds,
    );

    await store.skipBreak(now: startedAt.add(const Duration(minutes: 3)));
    final focus = await store.load(
      now: startedAt.add(const Duration(minutes: 3)),
    );
    expect(focus.phase, StandalonePomodoroPhase.focusRunning);
    expect(focus.intervalExtensionMs, 0);
    expect(focus.completedFocusCount, 1);
    store.dispose();
  });

  test('idle cannot jump directly into a break', () async {
    final store = StandalonePomodoroStore(accountId: 'owner');
    await store.startBreak(now: DateTime.utc(2026, 8, 13, 9));
    expect((await store.load()).phase, StandalonePomodoroPhase.idle);
    store.dispose();
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/activity/data/activity_repository.dart';

void main() {
  test('multi-task allocation permits an explicit total at or below 100%', () {
    final result = validateActivityTaskAllocations(const [
      ActivityTaskAllocation(targetTaskId: 'task-a', percentage: 60),
      ActivityTaskAllocation(targetTaskId: 'task-b', percentage: 40),
    ]);

    expect(result, hasLength(2));
    expect(result.fold<int>(0, (sum, item) => sum + item.percentage), 100);
  });

  test('multi-task allocation rejects credit above the source interval', () {
    expect(
      () => validateActivityTaskAllocations(const [
        ActivityTaskAllocation(targetTaskId: 'task-a', percentage: 70),
        ActivityTaskAllocation(targetTaskId: 'task-b', percentage: 31),
      ]),
      throwsArgumentError,
    );
  });

  test('duration allocation rounds down and cannot inflate physical time', () {
    final source = const Duration(minutes: 1).inMilliseconds;
    final first = activityAllocatedDurationMs(
      physicalDurationMs: source,
      percentage: 33,
    );
    final second = activityAllocatedDurationMs(
      physicalDurationMs: source,
      percentage: 67,
    );

    expect(first + second, lessThanOrEqualTo(source));
  });
}

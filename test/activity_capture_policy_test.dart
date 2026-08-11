import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/activity/data/activity_capture_service.dart';

void main() {
  test('a running task captures locally when broad tracking is disabled', () {
    expect(
      shouldCaptureActivity(
        broadTrackingEnabled: false,
        activeTaskId: 'task-1',
        runtimeState: 'running',
      ),
      isTrue,
    );
  });

  test('untracked out-of-task device use remains disabled', () {
    expect(
      shouldCaptureActivity(
        broadTrackingEnabled: false,
        activeTaskId: null,
        runtimeState: 'idle',
      ),
      isFalse,
    );
  });

  test('a paused task does not keep collecting task Activity', () {
    expect(
      shouldCaptureActivity(
        broadTrackingEnabled: false,
        activeTaskId: 'task-1',
        runtimeState: 'paused',
      ),
      isFalse,
    );
  });
}

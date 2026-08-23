import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/platform/android_home_widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('taskmasterpro/home_widget.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('widget state clamps progress and limits suggestions to three', () {
    final boundary = DateTime.parse('2026-08-23T15:30:00+03:00');
    final state = AndroidHomeWidgetState(
      mode: AndroidHomeWidgetMode.breakTime,
      localeCode: 'ar',
      statusLabel: 'استراحة',
      title: 'Programming study',
      message: 'استعد نشاطك',
      timerLabel: '05:00',
      timerMode: AndroidHomeWidgetTimerMode.countdown,
      timerBoundary: boundary,
      progress: 1.4,
      actionLabel: 'فتح المهمة',
      completionLabel: 'اكتملت الاستراحة',
      taskId: 'task-1',
      sessionId: 'session-1',
      runtimeRevision: 7,
      suggestions: const [
        AndroidHomeWidgetSuggestion(id: '1', title: 'One'),
        AndroidHomeWidgetSuggestion(id: '2', title: 'Two'),
        AndroidHomeWidgetSuggestion(id: '3', title: 'Three'),
        AndroidHomeWidgetSuggestion(id: '4', title: 'Four'),
      ],
      controls: const [
        AndroidHomeWidgetControl(id: 'start_focus', label: 'Focus'),
        AndroidHomeWidgetControl(id: 'extend_break', label: '+5 min'),
        AndroidHomeWidgetControl(id: 'review_break', label: 'Review'),
        AndroidHomeWidgetControl(id: 'finish_task', label: 'Finish'),
      ],
    );

    final payload = state.toMap(requestPinIfMissing: true);

    expect(payload['mode'], 'break');
    expect(payload['progressPercent'], 100);
    expect(
      payload['timerBoundaryEpochMs'],
      boundary.toUtc().millisecondsSinceEpoch,
    );
    expect(payload['requestPinIfMissing'], isTrue);
    expect(payload['suggestions'], hasLength(3));
    expect(payload['controls'], hasLength(3));
    expect(payload['taskId'], 'task-1');
    expect(payload['sessionId'], 'session-1');
    expect(payload['runtimeRevision'], 7);
  });

  test('service sends state and reports native widget result', () async {
    MethodCall? invocation;
    messenger.setMockMethodCallHandler(channel, (call) async {
      invocation = call;
      return <String, Object?>{'widgetCount': 1, 'pinRequested': true};
    });
    final service = AndroidHomeWidgetService(
      channel: channel,
      supportedPlatform: true,
    );

    final result = await service.update(
      AndroidHomeWidgetState(
        mode: AndroidHomeWidgetMode.idle,
        localeCode: 'en',
        statusLabel: 'TaskMaster Pro',
        title: 'What will you move forward?',
        message: 'Choose a task.',
        timerLabel: '2 tasks ready',
        timerMode: AndroidHomeWidgetTimerMode.fixed,
        actionLabel: 'Open app',
        completionLabel: 'Choose your next step.',
      ),
      requestPinIfMissing: true,
    );

    expect(invocation?.method, 'update');
    expect(invocation?.arguments, containsPair('requestPinIfMissing', true));
    expect(result.widgetCount, 1);
    expect(result.pinRequested, isTrue);
  });

  test('unsupported platforms do not invoke the native channel', () async {
    var invoked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      invoked = true;
      return null;
    });
    final service = AndroidHomeWidgetService(
      channel: channel,
      supportedPlatform: false,
    );

    final result = await service.update(
      AndroidHomeWidgetState(
        mode: AndroidHomeWidgetMode.idle,
        localeCode: 'en',
        statusLabel: 'TaskMaster Pro',
        title: 'Ready',
        message: 'Ready',
        timerLabel: 'Ready',
        timerMode: AndroidHomeWidgetTimerMode.fixed,
        actionLabel: 'Open',
        completionLabel: 'Ready',
      ),
    );

    expect(invoked, isFalse);
    expect(result.widgetCount, 0);
  });

  test('service takes a revision-bound launch action exactly once', () async {
    var takeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'takeAction') return null;
      takeCalls += 1;
      return takeCalls == 1
          ? <String, Object?>{
              'id': 'pause',
              'taskId': 'task-1',
              'sessionId': 'session-1',
              'runtimeRevision': 9,
            }
          : null;
    });
    final service = AndroidHomeWidgetService(
      channel: channel,
      supportedPlatform: true,
    );

    final first = await service.takeLaunchAction();
    final second = await service.takeLaunchAction();

    expect(first?.id, 'pause');
    expect(first?.taskId, 'task-1');
    expect(first?.sessionId, 'session-1');
    expect(first?.runtimeRevision, 9);
    expect(second, isNull);
  });
}

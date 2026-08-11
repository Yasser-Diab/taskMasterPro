import 'dart:async';

enum TaskResourceLaunchMode {
  inApp('in_app'),
  externalApp('external_app'),
  externalBrowser('external_browser'),
  disabled('disabled');

  const TaskResourceLaunchMode(this.key);

  final String key;

  static TaskResourceLaunchMode fromKey(Object? value) {
    return TaskResourceLaunchMode.values.firstWhere(
      (mode) => mode.key == value,
      orElse: () => TaskResourceLaunchMode.inApp,
    );
  }
}

class TaskResourceLaunchRequest {
  const TaskResourceLaunchRequest({
    required this.taskId,
    required this.resourceId,
    required this.title,
    required this.url,
    required this.mode,
  });

  final String taskId;
  final String resourceId;
  final String title;
  final Uri url;
  final TaskResourceLaunchMode mode;
}

class TaskResourceLaunchOutcome {
  const TaskResourceLaunchOutcome({
    required this.opened,
    required this.mode,
    this.usedFallback = false,
    this.handlerPackage,
  });

  final bool opened;
  final TaskResourceLaunchMode mode;
  final bool usedFallback;
  final String? handlerPackage;
}

typedef ResourceLaunchAttempt = FutureOr<bool> Function(Uri url);

/// Runs an external resource handoff in a deterministic order.
///
/// Android app links are attempted with a non-browser handler first. When the
/// learning app is not installed, the URL falls back to a browser instead of
/// turning a successful task start into an error. Browser-only mode never
/// attempts an app handler.
Future<TaskResourceLaunchOutcome> launchExternalResourceWithFallback({
  required Uri url,
  required TaskResourceLaunchMode mode,
  required ResourceLaunchAttempt openInstalledApp,
  required ResourceLaunchAttempt openBrowser,
}) async {
  if (mode == TaskResourceLaunchMode.disabled ||
      mode == TaskResourceLaunchMode.inApp) {
    return TaskResourceLaunchOutcome(opened: false, mode: mode);
  }
  if (mode == TaskResourceLaunchMode.externalBrowser) {
    return TaskResourceLaunchOutcome(
      opened: await openBrowser(url),
      mode: mode,
    );
  }
  if (await openInstalledApp(url)) {
    return TaskResourceLaunchOutcome(opened: true, mode: mode);
  }
  return TaskResourceLaunchOutcome(
    opened: await openBrowser(url),
    mode: mode,
    usedFallback: true,
  );
}

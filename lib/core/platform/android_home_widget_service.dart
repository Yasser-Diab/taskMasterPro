import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AndroidHomeWidgetMode { idle, running, paused, breakTime }

enum AndroidHomeWidgetTimerMode { fixed, countdown, countup }

const _supportedAndroidHomeWidgetActions = <String>{
  'pause',
  'start_break',
  'finish_task',
  'resume',
  'start_focus',
  'extend_break',
  'review_break',
};

@immutable
class AndroidHomeWidgetControl {
  const AndroidHomeWidgetControl({required this.id, required this.label});

  final String id;
  final String label;

  bool get isValid =>
      _supportedAndroidHomeWidgetActions.contains(id) &&
      label.trim().isNotEmpty;

  Map<String, Object?> toMap() => {'id': id, 'label': label};
}

@immutable
class AndroidHomeWidgetAction {
  const AndroidHomeWidgetAction({
    required this.id,
    required this.ownerId,
    required this.taskId,
    required this.sessionId,
    required this.runtimeRevision,
    this.deliveryId,
  });

  final String id;
  final String ownerId;
  final String taskId;
  final String sessionId;
  final int runtimeRevision;
  final String? deliveryId;

  static AndroidHomeWidgetAction? fromMap(Map<Object?, Object?>? values) {
    if (values == null) return null;
    final id = values['id']?.toString().trim() ?? '';
    final ownerId = values['ownerId']?.toString().trim() ?? '';
    final taskId = values['taskId']?.toString().trim() ?? '';
    final sessionId = values['sessionId']?.toString().trim() ?? '';
    final runtimeRevision = (values['runtimeRevision'] as num?)?.toInt();
    if (!_supportedAndroidHomeWidgetActions.contains(id) ||
        ownerId.isEmpty ||
        taskId.isEmpty ||
        sessionId.isEmpty ||
        runtimeRevision == null ||
        runtimeRevision < 0) {
      return null;
    }
    return AndroidHomeWidgetAction(
      id: id,
      ownerId: ownerId,
      taskId: taskId,
      sessionId: sessionId,
      runtimeRevision: runtimeRevision,
      deliveryId: values['deliveryId']?.toString().trim(),
    );
  }
}

@immutable
class AndroidHomeWidgetSuggestion {
  const AndroidHomeWidgetSuggestion({required this.id, required this.title});

  final String id;
  final String title;

  Map<String, Object?> toMap() => {'id': id, 'title': title};
}

@immutable
class AndroidHomeWidgetState {
  AndroidHomeWidgetState({
    required this.mode,
    required this.localeCode,
    required this.statusLabel,
    required this.title,
    required this.message,
    required this.timerLabel,
    required this.timerMode,
    required this.actionLabel,
    required this.completionLabel,
    this.ownerId,
    this.taskId,
    this.sessionId,
    this.runtimeRevision,
    this.runtimeUpdatedAt,
    this.timerBoundary,
    this.progress = 0,
    List<AndroidHomeWidgetSuggestion> suggestions = const [],
    List<AndroidHomeWidgetControl> controls = const [],
  }) : suggestions = List.unmodifiable(
         suggestions
             .where(
               (suggestion) =>
                   suggestion.id.trim().isNotEmpty &&
                   suggestion.title.trim().isNotEmpty,
             )
             .take(3),
       ),
       controls = List.unmodifiable(
         controls.where((control) => control.isValid).take(3),
       );

  final AndroidHomeWidgetMode mode;
  final String localeCode;
  final String statusLabel;
  final String title;
  final String message;
  final String timerLabel;
  final AndroidHomeWidgetTimerMode timerMode;
  final String actionLabel;
  final String completionLabel;
  final String? ownerId;
  final String? taskId;
  final String? sessionId;
  final int? runtimeRevision;
  final DateTime? runtimeUpdatedAt;
  final DateTime? timerBoundary;
  final double progress;
  final List<AndroidHomeWidgetSuggestion> suggestions;
  final List<AndroidHomeWidgetControl> controls;

  Map<String, Object?> toMap({required bool requestPinIfMissing}) => {
    'mode': switch (mode) {
      AndroidHomeWidgetMode.breakTime => 'break',
      _ => mode.name,
    },
    'localeCode': localeCode,
    'statusLabel': statusLabel,
    'title': title,
    'message': message,
    'timerLabel': timerLabel,
    'timerMode': timerMode.name,
    'timerBoundaryEpochMs': timerBoundary?.toUtc().millisecondsSinceEpoch,
    'progressPercent': (progress.clamp(0.0, 1.0) * 100).round(),
    'actionLabel': actionLabel,
    'completionLabel': completionLabel,
    'ownerId': ownerId,
    'taskId': taskId,
    'sessionId': sessionId,
    'runtimeRevision': runtimeRevision,
    'runtimeUpdatedAtEpochMs': runtimeUpdatedAt?.toUtc().millisecondsSinceEpoch,
    'suggestions': suggestions.map((item) => item.toMap()).toList(),
    'controls': controls.map((item) => item.toMap()).toList(),
    'requestPinIfMissing': requestPinIfMissing,
  };
}

@immutable
class AndroidHomeWidgetUpdateResult {
  const AndroidHomeWidgetUpdateResult({
    required this.widgetCount,
    required this.pinRequested,
  });

  final int widgetCount;
  final bool pinRequested;
}

/// Mirrors the minimum task/runtime projection required by an Android launcher
/// widget. Task details stay in the app's private preferences and are never
/// sent over the network by this service.
class AndroidHomeWidgetService {
  AndroidHomeWidgetService({MethodChannel? channel, bool? supportedPlatform})
    : _channel = channel ?? const MethodChannel('taskmasterpro/home_widget'),
      _supportedPlatform =
          supportedPlatform ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (_supportedPlatform) {
      _channel.setMethodCallHandler(_handleNativeMethodCall);
    }
  }

  static final instance = AndroidHomeWidgetService();

  final MethodChannel _channel;
  final bool _supportedPlatform;
  final StreamController<AndroidHomeWidgetAction> _actions =
      StreamController<AndroidHomeWidgetAction>.broadcast(sync: true);

  bool get isSupported => _supportedPlatform;
  Stream<AndroidHomeWidgetAction> get actions => _actions.stream;

  Future<Object?> _handleNativeMethodCall(MethodCall call) async {
    if (call.method != 'widgetAction') throw MissingPluginException();
    final raw = call.arguments;
    final action = AndroidHomeWidgetAction.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : null,
    );
    if (action == null) return false;
    _actions.add(action);
    return true;
  }

  Future<AndroidHomeWidgetAction?> takeLaunchAction() async {
    if (!_supportedPlatform) return null;
    final response = await _channel.invokeMapMethod<Object?, Object?>(
      'takeAction',
    );
    return AndroidHomeWidgetAction.fromMap(response);
  }

  Future<void> completeBackgroundAction(
    AndroidHomeWidgetAction action, {
    required bool handled,
  }) async {
    final deliveryId = action.deliveryId;
    if (!_supportedPlatform || deliveryId == null || deliveryId.isEmpty) return;
    await _channel.invokeMethod<void>('completeAction', {
      'deliveryId': deliveryId,
      'handled': handled,
    });
  }

  Future<AndroidHomeWidgetUpdateResult> update(
    AndroidHomeWidgetState state, {
    bool requestPinIfMissing = false,
  }) async {
    if (!_supportedPlatform) {
      return const AndroidHomeWidgetUpdateResult(
        widgetCount: 0,
        pinRequested: false,
      );
    }
    final response = await _channel.invokeMapMethod<String, Object?>(
      'update',
      state.toMap(requestPinIfMissing: requestPinIfMissing),
    );
    return AndroidHomeWidgetUpdateResult(
      widgetCount: (response?['widgetCount'] as num?)?.toInt() ?? 0,
      pinRequested: response?['pinRequested'] == true,
    );
  }

  Future<bool> requestPin() async {
    if (!_supportedPlatform) return false;
    return await _channel.invokeMethod<bool>('requestPin') ?? false;
  }

  Future<void> clear() async {
    if (!_supportedPlatform) return;
    await _channel.invokeMethod<void>('clear');
  }
}

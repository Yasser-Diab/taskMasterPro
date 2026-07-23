import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class DeepLinkService {
  DeepLinkService({List<String> commandLineArguments = const []})
    : _commandLineArguments = commandLineArguments;

  static const _methodChannel = MethodChannel('taskmasterpro/deep_links');
  static const _eventChannel = EventChannel('taskmasterpro/deep_links/events');

  final List<String> _commandLineArguments;
  final _linkController = StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _androidSubscription;
  bool _streamStarted = false;

  Future<List<String>> initialLinks() async {
    final links = <String>[
      ..._commandLineArguments.where(_looksLikeTaskMasterLink),
    ];

    if (Platform.isAndroid) {
      try {
        final androidLink = await _methodChannel.invokeMethod<String>(
          'initialLink',
        );
        if (androidLink != null && _looksLikeTaskMasterLink(androidLink)) {
          links.add(androidLink);
        }
      } on PlatformException {
        // The native channel is absent on non-Android test surfaces.
      } on MissingPluginException {
        // The native channel is absent on non-Android test surfaces.
      }
    }

    return links.toSet().toList();
  }

  Stream<String> get linkStream {
    _startNativeLinkStream();
    return _linkController.stream;
  }

  void dispose() {
    _androidSubscription?.cancel();
    _linkController.close();
  }

  void _startNativeLinkStream() {
    if (_streamStarted) {
      return;
    }
    _streamStarted = true;

    if (Platform.isAndroid) {
      _androidSubscription = _eventChannel
          .receiveBroadcastStream()
          .where((event) => event is String && _looksLikeTaskMasterLink(event))
          .listen((event) => _linkController.add(event as String));
      return;
    }

    if (Platform.isWindows) {
      _methodChannel.setMethodCallHandler((call) async {
        if (call.method == 'link' &&
            call.arguments is String &&
            _looksLikeTaskMasterLink(call.arguments as String)) {
          _linkController.add(call.arguments as String);
        }
      });
    }
  }

  static bool _looksLikeTaskMasterLink(String value) {
    final uri = Uri.tryParse(value);
    return uri?.scheme == 'taskmasterpro';
  }
}

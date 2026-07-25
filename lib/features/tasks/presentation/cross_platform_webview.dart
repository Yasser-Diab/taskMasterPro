import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

class TaskBrowserController {
  Future<void> Function(String)? _load;
  Future<void> Function()? _back;
  Future<void> Function()? _forward;
  Future<void> Function()? _reload;

  Future<void> load(String value) async {
    final target = _normalize(value);
    if (_load != null) await _load!(target);
  }

  Future<void> back() async => _back?.call();
  Future<void> forward() async => _forward?.call();
  Future<void> reload() async => _reload?.call();

  static String _normalize(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return parsed.toString();
    if (trimmed.contains('.') && !trimmed.contains(' ')) {
      return 'https://$trimmed';
    }
    return Uri.https('www.google.com', '/search', {'q': trimmed}).toString();
  }
}

class CrossPlatformWebView extends StatefulWidget {
  const CrossPlatformWebView({
    required this.controller,
    required this.initialUrl,
    required this.onUrlChanged,
    required this.onTitleChanged,
    super.key,
  });

  final TaskBrowserController controller;
  final String initialUrl;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onTitleChanged;

  @override
  State<CrossPlatformWebView> createState() => _CrossPlatformWebViewState();
}

class _CrossPlatformWebViewState extends State<CrossPlatformWebView> {
  win.WebviewController? _windows;
  mobile.WebViewController? _mobile;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _error;
  bool _ready = false;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (Platform.isWindows) {
        final controller = win.WebviewController();
        _windows = controller;
        _subscriptions.add(
          controller.url.listen((url) {
            widget.onUrlChanged(url);
          }),
        );
        _subscriptions.add(
          controller.title.listen((title) {
            widget.onTitleChanged(title);
          }),
        );
        await controller.initialize();
        await controller.setPopupWindowPolicy(
          win.WebviewPopupWindowPolicy.deny,
        );
        await controller.setDefaultContextMenusEnabled(true);
        widget.controller
          .._load = controller.loadUrl
          .._back = controller.goBack
          .._forward = controller.goForward
          .._reload = controller.reload;
        await controller.loadUrl(widget.initialUrl);
      } else if (Platform.isAndroid) {
        late final mobile.WebViewController controller;
        controller = mobile.WebViewController()
          ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            mobile.NavigationDelegate(
              onProgress: (progress) {
                if (mounted) setState(() => _progress = progress);
              },
              onPageFinished: (url) async {
                widget.onUrlChanged(url);
                widget.onTitleChanged(await controller.getTitle() ?? url);
              },
              onUrlChange: (change) {
                final url = change.url;
                if (url != null) widget.onUrlChanged(url);
              },
              onWebResourceError: (error) {
                if (error.isForMainFrame == true && mounted) {
                  setState(() => _error = error.description);
                }
              },
            ),
          );
        _mobile = controller;
        widget.controller._load = (url) =>
            controller.loadRequest(Uri.parse(url));
        widget.controller._back = () async {
          if (await controller.canGoBack()) await controller.goBack();
        };
        widget.controller._forward = () async {
          if (await controller.canGoForward()) {
            await controller.goForward();
          }
        };
        widget.controller._reload = controller.reload;
        await controller.loadRequest(Uri.parse(widget.initialUrl));
      } else {
        _error =
            'The embedded task browser is available on Windows and Android';
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _ready = true;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _windows?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.public_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(widget.initialUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open in system browser'),
              ),
            ],
          ),
        ),
      );
    }
    final child = Platform.isWindows
        ? win.Webview(_windows!)
        : mobile.WebViewWidget(controller: _mobile!);
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (!Platform.isWindows && _progress < 100)
          Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(value: _progress / 100),
          ),
      ],
    );
  }
}

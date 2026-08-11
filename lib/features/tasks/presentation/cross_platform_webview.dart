import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile;
import 'package:webview_flutter_windows/webview_flutter_windows.dart' as win;

import '../../../core/localization/app_localizations.dart';
import '../domain/browser_handoff.dart';
import '../domain/browser_workspace_checkpoint.dart';

/// A task workspace owns browser tabs, so only normal web URLs may be handed
/// back from a page as a request to open another tab.  Keeping this check at
/// the platform boundary prevents a page from using the bridge for local or
/// executable schemes.
bool isTaskBrowserWebUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.host.isNotEmpty &&
      const {'http', 'https'}.contains(uri.scheme.toLowerCase());
}

const _newTabBridgeScript = r'''
(() => {
  if (window.__taskmasterNewTabBridgeInstalled) return;
  window.__taskmasterNewTabBridgeInstalled = true;

  const normalWebUrl = (value) => {
    if (!value) return null;
    try {
      const url = new URL(String(value), window.location.href);
      return /^https?:$/i.test(url.protocol) ? url.href : null;
    } catch (_) {
      return null;
    }
  };

  const openTaskMasterTab = (value) => {
    const url = normalWebUrl(value);
    if (!url) return false;
    const message = JSON.stringify({
      type: 'taskmaster-open-new-tab',
      url: url,
    });
    if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(message);
      return true;
    }
    if (window.TaskMasterBrowserNewTab &&
        typeof window.TaskMasterBrowserNewTab.postMessage === 'function') {
      window.TaskMasterBrowserNewTab.postMessage(url);
      return true;
    }
    return false;
  };

  document.addEventListener('click', (event) => {
    const element = event.target;
    const link = element && element.closest
      ? element.closest('a[target="_blank"]')
      : null;
    if (link && openTaskMasterTab(link.href)) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);

  const originalOpen = window.open;
  window.open = function(url, target, features) {
    const opensNewWindow = target == null || target === '' || target === '_blank';
    if (opensNewWindow && openTaskMasterTab(url)) return null;
    return originalOpen.call(window, url, target, features);
  };
})();
''';

class TaskBrowserController {
  Future<void> Function(String)? _load;
  Future<void> Function()? _back;
  Future<void> Function()? _forward;
  Future<void> Function()? _reload;
  Future<bool> Function(String username, String password)? _fillCredentials;
  Future<BrowserWorkspaceCheckpoint?> Function()? _captureCheckpoint;
  Future<void> Function(BrowserWorkspaceCheckpoint)? _restoreCheckpoint;

  Future<void> load(String value) async {
    final target = normalizeBrowserAddress(value);
    if (_load != null) await _load!(target);
  }

  Future<void> back() async => _back?.call();
  Future<void> forward() async => _forward?.call();
  Future<void> reload() async => _reload?.call();

  Future<bool> fillCredentials({
    required String username,
    required String password,
  }) async {
    final fill = _fillCredentials;
    return fill == null ? false : fill(username, password);
  }

  /// The workspace, rather than a scroll listener, chooses the bounded
  /// capture cadence. This keeps page movement out of the sync hot path.
  Future<BrowserWorkspaceCheckpoint?> captureCheckpoint() async {
    return _captureCheckpoint?.call();
  }

  Future<void> restoreCheckpoint(BrowserWorkspaceCheckpoint checkpoint) async {
    await _restoreCheckpoint?.call(checkpoint);
  }
}

class CrossPlatformWebView extends StatefulWidget {
  const CrossPlatformWebView({
    required this.controller,
    required this.initialUrl,
    required this.profileId,
    required this.onUrlChanged,
    required this.onTitleChanged,
    this.restoreCheckpoint,
    this.onCheckpoint,
    this.onOpenNewTab,
    super.key,
  });

  final TaskBrowserController controller;
  final String initialUrl;
  final String profileId;
  final ValueChanged<String> onUrlChanged;
  final ValueChanged<String> onTitleChanged;
  final BrowserWorkspaceCheckpoint? restoreCheckpoint;
  final ValueChanged<BrowserWorkspaceCheckpoint>? onCheckpoint;
  final ValueChanged<String>? onOpenNewTab;

  @override
  State<CrossPlatformWebView> createState() => _CrossPlatformWebViewState();
}

class _CrossPlatformWebViewState extends State<CrossPlatformWebView> {
  static Future<void>? _windowsEnvironment;
  static String? _windowsProfileId;

  win.WebviewController? _windows;
  mobile.WebViewController? _mobile;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _error;
  bool _ready = false;
  int _progress = 0;
  BrowserWorkspaceCheckpoint? _restorePending;
  Timer? _restoreTimer;

  @override
  void initState() {
    super.initState();
    _restorePending = widget.restoreCheckpoint;
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (Platform.isWindows) {
        await _prepareWindowsProfile(widget.profileId);
        final controller = win.WebviewController();
        _windows = controller;
        _subscriptions.add(
          controller.url.listen((url) {
            widget.onUrlChanged(url);
            _scheduleCheckpointRestore(url);
          }),
        );
        _subscriptions.add(
          controller.title.listen((title) {
            widget.onTitleChanged(title);
            final pendingUrl = _restorePending?.url;
            if (pendingUrl != null) _scheduleCheckpointRestore(pendingUrl);
          }),
        );
        _subscriptions.add(controller.webMessage.listen(_forwardNewTabRequest));
        await controller.initialize();
        await controller.addScriptToExecuteOnDocumentCreated(
          _newTabBridgeScript,
        );
        await controller.setPopupWindowPolicy(
          // The bridge above turns ordinary target=_blank links into task
          // tabs.  Same-window is an intentional fallback for a popup the
          // page creates before the bridge can handle it; denying it made
          // links silently appear broken.
          win.WebviewPopupWindowPolicy.sameWindow,
        );
        await controller.setDefaultContextMenusEnabled(true);
        widget.controller
          .._load = controller.loadUrl
          .._back = controller.goBack
          .._forward = controller.goForward
          .._reload = controller.reload
          .._fillCredentials = (username, password) async {
            final result = await controller.executeScript(
              buildCredentialFillScript(username: username, password: password),
            );
            return result == true || result?.toString() == 'true';
          }
          .._captureCheckpoint = _captureCheckpoint
          .._restoreCheckpoint = _restoreCheckpointNow;
        await controller.loadUrl(widget.initialUrl);
      } else if (Platform.isAndroid) {
        late final mobile.WebViewController controller;
        controller = mobile.WebViewController()
          ..setJavaScriptMode(mobile.JavaScriptMode.unrestricted)
          ..addJavaScriptChannel(
            'TaskMasterBrowserNewTab',
            onMessageReceived: (message) =>
                _forwardNewTabRequest(message.message),
          )
          ..setNavigationDelegate(
            mobile.NavigationDelegate(
              onNavigationRequest: _handleMobileNavigationRequest,
              onProgress: (progress) {
                if (mounted) setState(() => _progress = progress);
              },
              onPageStarted: (_) =>
                  unawaited(_installMobileNewTabBridge(controller)),
              onPageFinished: (url) async {
                widget.onUrlChanged(url);
                widget.onTitleChanged(await controller.getTitle() ?? url);
                unawaited(_installMobileNewTabBridge(controller));
                await _restorePendingCheckpoint(url);
              },
              onUrlChange: (change) {
                final url = change.url;
                if (url != null) widget.onUrlChanged(url);
              },
              onWebResourceError: (error) {
                if (error.isForMainFrame == true && mounted) {
                  setState(() => _error = 'browser_page_failed');
                }
              },
            ),
          );
        await _prepareAndroidProfile(controller, widget.profileId);
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
        widget.controller._fillCredentials = (username, password) async {
          final result = await controller.runJavaScriptReturningResult(
            buildCredentialFillScript(username: username, password: password),
          );
          return result == true || result.toString() == 'true';
        };
        widget.controller
          .._captureCheckpoint = _captureCheckpoint
          .._restoreCheckpoint = _restoreCheckpointNow;
        await controller.loadRequest(Uri.parse(widget.initialUrl));
      } else {
        _error = 'browser_platform_unavailable';
      }
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'browser_page_failed';
          _ready = true;
        });
      }
    }
  }

  Future<mobile.NavigationDecision> _handleMobileNavigationRequest(
    mobile.NavigationRequest request,
  ) async {
    if (isTaskBrowserWebUrl(request.url)) {
      return mobile.NavigationDecision.navigate;
    }
    final uri = Uri.tryParse(request.url);
    if (uri == null || !uri.hasScheme || uri.scheme == 'about') {
      return mobile.NavigationDecision.navigate;
    }
    // Authentication, mail, phone and application links need a real platform
    // handler rather than an unsupported WebView navigation.
    unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
    return mobile.NavigationDecision.prevent;
  }

  Future<void> _installMobileNewTabBridge(
    mobile.WebViewController controller,
  ) async {
    try {
      await controller.runJavaScript(_newTabBridgeScript);
    } catch (_) {
      // A page may disappear during a redirect.  The next finished page gets
      // another bridge attempt, and normal same-window navigation still works.
    }
  }

  Future<BrowserWorkspaceCheckpoint?> _captureCheckpoint() async {
    try {
      final result = Platform.isWindows
          ? await _windows?.executeScript(
              browserWorkspaceCheckpointCaptureScript,
            )
          : await _mobile?.runJavaScriptReturningResult(
              browserWorkspaceCheckpointCaptureScript,
            );
      final checkpoint = BrowserWorkspaceCheckpoint.fromJavaScript(result);
      if (checkpoint.isEmpty) return null;
      final stamped = checkpoint.stamped(DateTime.now().toUtc());
      widget.onCheckpoint?.call(stamped);
      return stamped;
    } catch (_) {
      // A document can disappear during navigation or be a restricted page.
      // Resume state is best effort; normal browsing must remain usable.
      return null;
    }
  }

  void _scheduleCheckpointRestore(String pageUrl) {
    final checkpoint = _restorePending;
    if (checkpoint == null || !checkpoint.matchesPage(pageUrl)) return;
    _restoreTimer?.cancel();
    _restoreTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_restorePendingCheckpoint(pageUrl)),
    );
  }

  Future<void> _restoreCheckpointNow(
    BrowserWorkspaceCheckpoint checkpoint,
  ) async {
    _restorePending = checkpoint;
    final pageUrl = checkpoint.url;
    if (pageUrl != null) await _restorePendingCheckpoint(pageUrl);
  }

  Future<void> _restorePendingCheckpoint(String pageUrl) async {
    final checkpoint = _restorePending;
    if (checkpoint == null || !checkpoint.matchesPage(pageUrl)) return;
    try {
      if (Platform.isWindows && checkpoint.zoomScale != null) {
        // WebView2 has a native zoom setter. Android's public WebView API does
        // not expose a safe equivalent, so its captured viewport scale remains
        // metadata rather than mutating arbitrary page CSS on restore.
        await _windows?.setZoomFactor(checkpoint.zoomScale!);
      }
      final script = buildBrowserWorkspaceCheckpointRestoreScript(checkpoint);
      if (Platform.isWindows) {
        await _windows?.executeScript(script);
      } else if (Platform.isAndroid) {
        await _mobile?.runJavaScriptReturningResult(script);
      }
      _restorePending = null;
    } catch (_) {
      // Leave the marker pending for a title/URL event that may arrive after a
      // slow navigation. It is never applied to a different page because
      // [BrowserWorkspaceCheckpoint.matchesPage] is checked above.
    }
  }

  void _forwardNewTabRequest(dynamic rawMessage) {
    String? url;
    if (rawMessage is Map) {
      final type = rawMessage['type']?.toString();
      if (type == 'taskmaster-open-new-tab') {
        url = rawMessage['url']?.toString();
      }
    } else if (rawMessage is String) {
      try {
        final decoded = jsonDecode(rawMessage);
        if (decoded is Map &&
            decoded['type']?.toString() == 'taskmaster-open-new-tab') {
          url = decoded['url']?.toString();
        }
      } catch (_) {
        // Android sends the URL itself through its JavaScript channel.
        url = rawMessage;
      }
    }
    if (url == null || !isTaskBrowserWebUrl(url)) return;
    widget.onOpenNewTab?.call(normalizeBrowserAddress(url));
  }

  Future<void> _prepareWindowsProfile(String profileId) async {
    if (_windowsEnvironment != null && _windowsProfileId == profileId) {
      return _windowsEnvironment;
    }
    final digest = sha256.convert(utf8.encode(profileId)).toString();
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      '${support.path}${Platform.pathSeparator}browser-profiles'
      '${Platform.pathSeparator}${digest.substring(0, 24)}',
    );
    await directory.create(recursive: true);
    final initialization = win.WebviewController.initializeEnvironment(
      userDataPath: directory.path,
    );
    _windowsProfileId = profileId;
    _windowsEnvironment = initialization;
    await initialization;
  }

  Future<void> _prepareAndroidProfile(
    mobile.WebViewController controller,
    String profileId,
  ) async {
    final digest = sha256.convert(utf8.encode(profileId)).toString();
    final preferences = await SharedPreferences.getInstance();
    final previous = preferences.getString('taskmaster.browser.profile');
    if (previous != digest) {
      await mobile.WebViewCookieManager().clearCookies();
      await controller.clearCache();
      await controller.clearLocalStorage();
      await preferences.setString('taskmaster.browser.profile', digest);
    }
  }

  @override
  void dispose() {
    _restoreTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _windows?.dispose();
    widget.controller
      .._load = null
      .._back = null
      .._forward = null
      .._reload = null
      .._fillCredentials = null
      .._captureCheckpoint = null
      .._restoreCheckpoint = null;
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
              Text(context.l10n.text(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(widget.initialUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new),
                label: Text(context.l10n.text('browser_open_system')),
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

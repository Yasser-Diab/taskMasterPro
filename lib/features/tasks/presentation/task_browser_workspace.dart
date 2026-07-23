import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../app/app_services.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/widgets/app_controls.dart';
import '../domain/task_item.dart';
import '../domain/task_support_models.dart';
import '../domain/task_workspace_config.dart';

const _taskBrowserGoogleStartUrl = 'https://www.google.com';

String _restoreBrowserUrl(Object? value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == 'about:blank') {
    return _taskBrowserGoogleStartUrl;
  }
  return text;
}

class TaskBrowserWorkspace extends StatefulWidget {
  const TaskBrowserWorkspace({
    required this.task,
    required this.layoutMode,
    required this.trackingActive,
    this.resources = const [],
    required this.onCollapse,
    required this.onToggleFull,
    this.onEditTask,
    this.onAddNote,
    this.onStartWithoutWorkspace,
    this.onAddCurrentPage,
    this.onUsage,
    this.onCheckpoint,
    super.key,
  });

  final TaskItem task;
  final TaskBrowserLayoutMode layoutMode;
  final bool trackingActive;
  final List<TaskResource> resources;
  final VoidCallback onCollapse;
  final VoidCallback onToggleFull;
  final VoidCallback? onEditTask;
  final VoidCallback? onAddNote;
  final VoidCallback? onStartWithoutWorkspace;
  final void Function(String url, String? title)? onAddCurrentPage;
  final void Function(
    String url,
    String? title,
    DateTime startedAt,
    DateTime endedAt,
    int activeSeconds,
  )?
  onUsage;
  final void Function(List<Map<String, dynamic>> tabs, int selectedTab)?
  onCheckpoint;

  @override
  State<TaskBrowserWorkspace> createState() => _TaskBrowserWorkspaceState();
}

class _TaskBrowserWorkspaceState extends State<TaskBrowserWorkspace>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  static const _channel = MethodChannel('taskmasterpro/task_browser');
  static const _googleStartUrl = _taskBrowserGoogleStartUrl;

  final _surfaceKey = GlobalKey();
  late final TextEditingController _urlController;
  late final FocusNode _urlFocusNode;
  late final _TaskBrowserSessionStore _store;
  late final _BrowserSitePreferenceStore _sitePreferenceStore;
  final List<_BrowserTabState> _tabs = [];
  final List<_BrowserTabState> _closedTabs = [];

  String _currentLoadedUrl = _googleStartUrl;
  String _startingUrl = _googleStartUrl;
  String _profileId = 'signed-out';
  String? _title;
  String? _error;
  bool _loading = false;
  bool _detached = false;
  bool _addressDirty = false;
  bool _surfaceShown = false;
  int _selectedTab = 0;
  Rect? _lastSurfaceRect;
  Timer? _rectTimer;
  Timer? _saveTimer;
  Timer? _activityFlushTimer;
  DateTime _activityStartedAt = DateTime.now();

  String get _browserId => widget.task.id;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = _TaskBrowserSessionStore();
    _sitePreferenceStore = _BrowserSitePreferenceStore();
    _urlController = TextEditingController();
    _urlFocusNode = FocusNode();
    _urlFocusNode.addListener(_handleUrlFocusChanged);
    _channel.setMethodCallHandler(_handleNativeEvent);
    _activityFlushTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _flushActivity(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = AppServices.of(context).supabaseService.currentUser?.id;
    final nextProfile = _stableProfileId(userId ?? 'signed-out');
    if (_profileId != nextProfile || _tabs.isEmpty) {
      _profileId = nextProfile;
      unawaited(_restoreSession());
    }
  }

  @override
  void didUpdateWidget(TaskBrowserWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackingActive != widget.trackingActive ||
        oldWidget.layoutMode != widget.layoutMode) {
      _flushActivity();
    }
    if (!widget.layoutMode.isVisible) {
      _hidePlatformSurface(resetSurface: true);
    }
    if (oldWidget.task.id != widget.task.id) {
      _flushActivity();
      _surfaceShown = false;
      _lastSurfaceRect = null;
      unawaited(_restoreSession());
    }
  }

  @override
  void deactivate() {
    _hidePlatformSurface(resetSurface: true);
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && Platform.isWindows && state != AppLifecycleState.resumed) {
      _hidePlatformSurface(resetSurface: true);
    }
  }

  @override
  void dispose() {
    _flushActivity();
    _activityFlushTimer?.cancel();
    _saveTimer?.cancel();
    _rectTimer?.cancel();
    _urlFocusNode.removeListener(_handleUrlFocusChanged);
    _urlFocusNode.dispose();
    _urlController.dispose();
    _saveNow();
    WidgetsBinding.instance.removeObserver(this);
    _hidePlatformSurface(resetSurface: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncWindowsSurface());

    return Column(
      children: [
        _BrowserToolbar(
          urlController: _urlController,
          loading: _loading,
          detached: _detached,
          fullWorkspace: widget.layoutMode.isFull,
          onBack: () => _invoke('goBack'),
          onForward: () => _invoke('goForward'),
          onReload: () => _invoke('reload'),
          onStop: () => _invoke('stop'),
          onHome: _goHome,
          onResetWorkspace: _resetWorkspace,
          onAddressEdited: () => _addressDirty = true,
          onOpenUrl: () => _navigateFromAddressBar(),
          onOpenExternal: () => _openExternal(_urlController.text),
          onAddCurrentPage: () =>
              widget.onAddCurrentPage?.call(_currentLoadedUrl, _title),
          onDetach: _toggleDetached,
          onCollapse: widget.onCollapse,
          onToggleFullWorkspace: widget.onToggleFull,
        ),
        if (_tabs.isNotEmpty)
          _BrowserTabStrip(
            tabs: _tabs,
            selectedIndex: _selectedTab,
            onSelected: _selectTab,
            onClose: _closeTab,
            onRename: _renameTab,
            onAdd: _openBlankTab,
            onDuplicate: _duplicateSelectedTab,
            onReopenClosed: _closedTabs.isEmpty ? null : _reopenClosedTab,
          ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              IconButton(
                tooltip: context.text('close'),
                onPressed: () => setState(() => _error = null),
                icon: const Icon(Icons.close_outlined),
              ),
              TextButton(
                onPressed: () => _openExternal(_currentLoadedUrl),
                child: Text(context.text('openExternally')),
              ),
              TextButton(
                onPressed: () => _navigate(_currentLoadedUrl),
                child: Text(context.text('tryAgain')),
              ),
              TextButton(onPressed: _goHome, child: Text(context.text('home'))),
            ],
          ),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: _currentLoadedUrl == 'about:blank'
                ? _TaskBrowserStartPage(
                    task: widget.task,
                    recentTabs: _tabs,
                    resources: widget.resources,
                    onNavigate: _navigate,
                  )
                : _BrowserSurface(
                    key: ValueKey('browser-surface-$_browserId-$_profileId'),
                    surfaceKey: _surfaceKey,
                    browserId: _browserId,
                    profileId: _profileId,
                    initialUrl: _currentLoadedUrl,
                    detached: _detached,
                  ),
          ),
        ),
      ],
    );
  }

  void _hidePlatformSurface({bool resetSurface = false}) {
    if (kIsWeb || !(Platform.isWindows || Platform.isAndroid)) {
      return;
    }
    if (resetSurface) {
      _surfaceShown = false;
      _lastSurfaceRect = null;
    }
    unawaited(_channel.invokeMethod<void>('hide', {'browserId': _browserId}));
  }

  Future<void> _restoreSession() async {
    final starting = _normalizeUrl(
      widget.task.workspaceStartingUrl ??
          widget.task.learningResourceLink ??
          '',
      allowBlank: true,
    );
    _startingUrl = starting.isEmpty ? _googleStartUrl : starting;

    final saved = widget.task.workspaceRestoreBrowserSession
        ? await _store.load(_profileId, widget.task.id)
        : null;
    final savedTabs = widget.task.workspaceRestoreOpenTabs
        ? saved?.tabs
        : const <_BrowserTabState>[];
    final taskTabs = widget.task.workspaceRestoreOpenTabs
        ? [
            for (final item in widget.task.workspaceOpenTabs)
              _BrowserTabState.fromJson(item),
          ]
        : const <_BrowserTabState>[];

    final restoredTabs = savedTabs?.isNotEmpty == true
        ? savedTabs!
        : taskTabs.isNotEmpty
        ? taskTabs
        : <_BrowserTabState>[];
    final lastUrl = widget.task.workspaceRestoreLastPage
        ? saved?.selectedUrl ?? widget.task.workspaceLastUrl
        : null;
    var initialUrl = _firstUsableUrl([
      if (restoredTabs.isNotEmpty)
        restoredTabs[(saved?.selectedTab ??
                    widget.task.workspaceSelectedTabIndex)
                .clamp(0, restoredTabs.length - 1)]
            .url,
      lastUrl,
      _startingUrl,
      _googleStartUrl,
    ]);
    String? externalMessage;
    if (await _sitePreferenceStore.shouldOpenExternally(
      profileId: _profileId,
      url: initialUrl,
    )) {
      await _openExternal(_externalSiteEntryUrl(initialUrl));
      initialUrl = _googleStartUrl;
      externalMessage = mounted
          ? context.text('websiteOpenedExternally')
          : null;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _tabs
        ..clear()
        ..addAll(
          restoredTabs.isEmpty
              ? [
                  _BrowserTabState(
                    url: initialUrl,
                    title: _titleForUrl(initialUrl),
                  ),
                ]
              : restoredTabs,
        );
      _selectedTab =
          (saved?.selectedTab ?? widget.task.workspaceSelectedTabIndex).clamp(
            0,
            _tabs.length - 1,
          );
      _currentLoadedUrl = _tabs[_selectedTab].url;
      _title = _tabs[_selectedTab].title;
      _setAddressText(_currentLoadedUrl, force: true);
      _error = externalMessage;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncWindowsSurface(force: true, allowInitialNavigation: true),
    );
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    if (call.method != 'browserEvent' || call.arguments is! Map) {
      return null;
    }
    final event = Map<String, dynamic>.from(call.arguments as Map);
    final browserId = event['browserId']?.toString();
    if (browserId != null && browserId != _browserId) {
      return null;
    }
    final newTabUrl = event['newTabUrl']?.toString();
    if (newTabUrl != null && newTabUrl.isNotEmpty) {
      final popupUrl = _normalizeUrl(newTabUrl);
      if (_shouldOpenOriginalSiteExternally(popupUrl)) {
        await _promptForExternalSignIn(popupUrl);
      } else {
        _openTab(popupUrl, title: event['title']?.toString());
      }
      return null;
    }
    if (!mounted) {
      return null;
    }
    final nextUrl = event['url']?.toString();
    final error = event['error']?.toString();
    if (error != null &&
        error.isNotEmpty &&
        nextUrl != null &&
        _shouldOpenOriginalSiteExternally(nextUrl)) {
      await _promptForExternalSignIn(nextUrl);
      return null;
    }
    if (nextUrl != null && nextUrl.isNotEmpty && nextUrl != _currentLoadedUrl) {
      _flushActivity();
    }
    setState(() {
      _loading = event['loading'] == true;
      _detached = event['detached'] == true;
      _title = event['title']?.toString().trim().isNotEmpty == true
          ? event['title']?.toString()
          : _title;
      final url = event['url']?.toString();
      if (url != null && url.isNotEmpty) {
        _currentLoadedUrl = url;
        _updateSelectedTab(url: url, title: _title);
        _setAddressText(url);
      }
      _error = error == null || error.isEmpty ? null : error;
    });
    _scheduleSave();
    return null;
  }

  void _handleUrlFocusChanged() {
    if (!_urlFocusNode.hasFocus && !_addressDirty) {
      _setAddressText(_currentLoadedUrl, force: true);
    }
  }

  Future<void> _goHome() async {
    await _navigate(_startingUrl);
  }

  Future<void> _resetWorkspace() async {
    _tabs
      ..clear()
      ..add(
        _BrowserTabState(url: _startingUrl, title: _titleForUrl(_startingUrl)),
      );
    _selectedTab = 0;
    await _navigate(_startingUrl);
  }

  Future<void> _navigateFromAddressBar() async {
    await _navigate(_normalizeUrl(_urlController.text));
  }

  Future<void> _navigate(String rawUrl) async {
    final normalized = _normalizeUrl(rawUrl);
    if (!_isNavigable(normalized)) {
      setState(() => _error = context.text('invalidUrl'));
      return;
    }
    if (!_isNavigationAllowed(normalized)) {
      setState(() => _error = context.text('navigationBlocked'));
      return;
    }
    if (_shouldOpenOriginalSiteExternally(normalized)) {
      await _promptForExternalSignIn(normalized);
      return;
    }
    if (normalized != _currentLoadedUrl) {
      _flushActivity();
    }
    setState(() {
      _currentLoadedUrl = normalized;
      _addressDirty = false;
      _setAddressText(normalized, force: true);
      _updateSelectedTab(url: normalized);
      _error = null;
    });
    await _invoke('navigate', {'url': normalized});
    _scheduleSave();
  }

  Future<void> _openExternal(String rawUrl) async {
    await _invoke('openExternal', {'url': _normalizeUrl(rawUrl)});
  }

  Future<void> _toggleDetached() async {
    if (!kIsWeb && Platform.isWindows) {
      await _invoke(_detached ? 'dock' : 'detach', {
        'title': widget.task.title,
      });
      _scheduleSave();
      return;
    }
    widget.onToggleFull();
  }

  Future<void> _invoke(
    String method, [
    Map<String, Object?> extra = const {},
  ]) async {
    final args = <String, Object?>{
      'browserId': _browserId,
      'profileId': _profileId,
      ...extra,
    };
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _error = error.message ?? error.code);
      }
    }
  }

  void _syncWindowsSurface({
    bool force = false,
    bool allowInitialNavigation = false,
  }) {
    if (kIsWeb || !Platform.isWindows || _detached) {
      return;
    }
    final context = _surfaceKey.currentContext;
    if (context == null) {
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final offset = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    final rect = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    if (!force && _lastSurfaceRect == rect && _surfaceShown) {
      return;
    }
    _lastSurfaceRect = rect;
    final shouldSendInitialUrl = allowInitialNavigation && !_surfaceShown;
    _surfaceShown = true;
    final config = AppServices.of(context).config;
    unawaited(
      _channel.invokeMethod<void>('showDocked', {
        'browserId': _browserId,
        'profileId': _profileId,
        'url': shouldSendInitialUrl ? _currentLoadedUrl : '',
        'passwordAutosave': config.saveWebsitePasswords,
        'generalAutofill': config.formAutofill || config.passwordAutofill,
        'x': offset.dx,
        'y': offset.dy,
        'width': size.width,
        'height': size.height,
      }),
    );
    _rectTimer ??= Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => _syncWindowsSurface(),
    );
  }

  void _setAddressText(String url, {bool force = false}) {
    if (!force && (_urlFocusNode.hasFocus || _addressDirty)) {
      return;
    }
    _addressDirty = false;
    if (_urlController.text != url) {
      _urlController.text = url;
    }
  }

  void _updateSelectedTab({required String url, String? title}) {
    final cleanedTitle = title?.trim();
    final fallbackTitle = _titleForUrl(url);
    if (_tabs.isEmpty) {
      _tabs.add(
        _BrowserTabState(
          url: url,
          title: cleanedTitle?.isNotEmpty == true
              ? cleanedTitle!
              : fallbackTitle,
        ),
      );
      _selectedTab = 0;
      return;
    }
    final current = _tabs[_selectedTab];
    final nextTitle = cleanedTitle?.isNotEmpty == true
        ? cleanedTitle!
        : (current.title == null ||
                  current.title!.isEmpty ||
                  current.title == 'New tab' ||
                  current.title == current.host
              ? fallbackTitle
              : current.title);
    _tabs[_selectedTab] = _tabs[_selectedTab].copyWith(
      url: url,
      title: nextTitle,
    );
  }

  void _openBlankTab() {
    _openTab(_startingUrl);
  }

  void _openTab(String url, {String? title}) {
    final tabTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : _titleForUrl(url);
    setState(() {
      _tabs.add(_BrowserTabState(url: url, title: tabTitle));
      _selectedTab = _tabs.length - 1;
      _currentLoadedUrl = url;
      _title = tabTitle;
      _setAddressText(url, force: true);
      _error = null;
    });
    _scheduleSave();
    unawaited(_navigate(url));
  }

  void _selectTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _selectedTab) {
      return;
    }
    _flushActivity();
    final tab = _tabs[index];
    setState(() {
      _selectedTab = index;
      _currentLoadedUrl = tab.url;
      _title = tab.title;
      _setAddressText(tab.url, force: true);
    });
    _scheduleSave();
    unawaited(_navigate(tab.url));
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      _resetWorkspace();
      return;
    }
    _flushActivity();
    setState(() {
      _closedTabs.insert(0, _tabs[index]);
      if (_closedTabs.length > 12) _closedTabs.removeLast();
      _tabs.removeAt(index);
      _selectedTab = _selectedTab.clamp(0, _tabs.length - 1);
      _currentLoadedUrl = _tabs[_selectedTab].url;
      _setAddressText(_currentLoadedUrl, force: true);
    });
    _scheduleSave();
    unawaited(_navigate(_currentLoadedUrl));
  }

  void _duplicateSelectedTab() {
    if (_tabs.isEmpty) return;
    final current = _tabs[_selectedTab];
    setState(() {
      _tabs.add(
        _BrowserTabState(
          url: current.url,
          title: current.title,
          customTitle: current.customTitle,
        ),
      );
      _selectedTab = _tabs.length - 1;
      _currentLoadedUrl = current.url;
      _title = current.title;
      _setAddressText(current.url, force: true);
      _error = null;
    });
    _scheduleSave();
    unawaited(_navigate(current.url));
  }

  void _reopenClosedTab() {
    if (_closedTabs.isEmpty) return;
    final tab = _closedTabs.removeAt(0);
    setState(() {
      _tabs.add(tab);
      _selectedTab = _tabs.length - 1;
      _currentLoadedUrl = tab.url;
      _title = tab.title;
      _setAddressText(tab.url, force: true);
      _error = null;
    });
    _scheduleSave();
    unawaited(_navigate(tab.url));
  }

  Future<void> _renameTab(int index) async {
    if (index < 0 || index >= _tabs.length) {
      return;
    }
    final tab = _tabs[index];
    final controller = TextEditingController(text: tab.displayTitle);
    final result = await showDialog<_TabRenameResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.text('renameTab')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: context.text('tabName')),
          onSubmitted: (_) => Navigator.of(
            context,
          ).pop(_TabRenameResult.custom(controller.text.trim())),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _TabRenameResult.auto()),
            child: Text(context.text('usePageTitleAutomatically')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).pop(_TabRenameResult.custom(controller.text.trim())),
            child: Text(context.text('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      if (result.useAutomaticTitle) {
        _tabs[index] = _tabs[index].copyWith(clearCustomTitle: true);
      } else if (result.title != null && result.title!.isNotEmpty) {
        _tabs[index] = _tabs[index].copyWith(customTitle: result.title);
      }
    });
    _scheduleSave();
  }

  void _flushActivity() {
    final endedAt = DateTime.now();
    final startedAt = _activityStartedAt;
    _activityStartedAt = endedAt;
    if (!widget.trackingActive ||
        !widget.layoutMode.isVisible ||
        _currentLoadedUrl == 'about:blank') {
      return;
    }
    final activeSeconds = endedAt.difference(startedAt).inSeconds;
    if (activeSeconds <= 0) return;
    widget.onUsage?.call(
      _currentLoadedUrl,
      _title,
      startedAt,
      endedAt,
      activeSeconds,
    );
  }

  bool _isNavigable(String url) {
    if (url == 'about:blank') {
      return true;
    }
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool _isNavigationAllowed(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme == 'about') {
      return true;
    }
    return switch (widget.task.workspaceNavigationMode) {
      TaskWorkspaceNavigationMode.normalBrowsing => true,
      TaskWorkspaceNavigationMode.trustedDomainsOnly =>
        widget.task.workspaceAllowedDomains.isEmpty ||
            widget.task.workspaceAllowedDomains.any(
              (domain) => uri.host == domain || uri.host.endsWith('.$domain'),
            ),
      TaskWorkspaceNavigationMode.startingDomainOnly => () {
        final start = Uri.tryParse(_startingUrl);
        return start == null ||
            start.host.isEmpty ||
            uri.host == start.host ||
            uri.host.endsWith('.${start.host}');
      }(),
    };
  }

  String _normalizeUrl(String input, {bool allowBlank = false}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return allowBlank ? '' : _googleStartUrl;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https' || scheme == 'about') {
        return trimmed;
      }
      return _searchUrl(trimmed);
    }
    if (_looksLikeDomain(trimmed)) {
      return 'https://$trimmed';
    }
    return _searchUrl(trimmed);
  }

  bool _looksLikeDomain(String value) {
    if (value.contains(RegExp(r'\s'))) {
      return false;
    }
    final host = value.split('/').first.split(':').first;
    if (host == 'localhost') {
      return true;
    }
    final labels = host.split('.');
    if (labels.length < 2) {
      return false;
    }
    final labelPattern = RegExp(
      r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
    );
    if (!labels.every(labelPattern.hasMatch)) {
      return false;
    }
    final tld = labels.last;
    if (int.tryParse(tld) != null) {
      return true;
    }
    return RegExp(r'^[a-zA-Z]{2,63}$').hasMatch(tld);
  }

  String _titleForUrl(String url) {
    if (url == 'about:blank') {
      return 'Google';
    }
    final uri = Uri.tryParse(url);
    final host = uri?.host;
    if (host != null && host.isNotEmpty) {
      return host.replaceFirst(RegExp(r'^www\.'), '');
    }
    if (url.trim().isNotEmpty) {
      return url.trim();
    }
    return 'Google';
  }

  String _searchUrl(String query) {
    final config = AppServices.of(context).config;
    final encoded = Uri.encodeQueryComponent(query);
    return switch (config.defaultSearchEngine) {
      'bing' => 'https://www.bing.com/search?q=$encoded',
      'duckduckgo' => 'https://duckduckgo.com/?q=$encoded',
      'custom' when config.customSearchUrl.trim().isNotEmpty =>
        config.customSearchUrl.trim().replaceAll('{query}', encoded),
      _ => 'https://www.google.com/search?q=$encoded',
    };
  }

  String _firstUsableUrl(List<String?> urls) {
    for (final url in urls) {
      if (url != null && url.trim().isNotEmpty) {
        return _normalizeUrl(url);
      }
    }
    return _googleStartUrl;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  void _saveNow() {
    if (_tabs.isEmpty) {
      return;
    }
    final state = _TaskBrowserSessionState(
      selectedTab: _selectedTab,
      tabs: List<_BrowserTabState>.from(_tabs),
      selectedUrl: _currentLoadedUrl,
      title: _title,
      detached: _detached,
      fullWorkspace: widget.layoutMode.isFull,
      savedAt: DateTime.now(),
    );
    unawaited(_store.save(_profileId, widget.task.id, state));
    widget.onCheckpoint?.call([
      for (final tab in _tabs) tab.toJson(),
    ], _selectedTab);
  }

  String _stableProfileId(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash *= 0x100000001b3;
      hash &= 0x7fffffffffffffff;
    }
    return 'tm_${hash.toRadixString(16)}';
  }

  bool _shouldOpenOriginalSiteExternally(String requestedUrl) {
    final uri = Uri.tryParse(requestedUrl);
    if (uri == null) {
      return false;
    }
    final host = uri.host.toLowerCase();
    if (host == 'accounts.google.com' ||
        host == 'oauth2.googleapis.com' ||
        host == 'oauthaccountmanager.googleapis.com' ||
        host == 'appleid.apple.com' ||
        host == 'login.microsoftonline.com' ||
        host == 'login.live.com' ||
        ((host == 'www.facebook.com' || host == 'facebook.com') &&
            uri.path.contains('/dialog/oauth')) ||
        (host == 'github.com' && uri.path.startsWith('/login/oauth'))) {
      return true;
    }
    return false;
  }

  Future<void> _promptForExternalSignIn(String popupUrl) async {
    if (!mounted) {
      return;
    }
    var remember = false;
    final openerUrl = _currentLoadedUrl;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.text('googleSignInExternalTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.text('googleSignInExternalMessage')),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: remember,
                onChanged: (value) =>
                    setDialogState(() => remember = value ?? false),
                title: Text(context.text('alwaysOpenGoogleExternal')),
              ),
            ],
          ),
          actions: [
            AppButton.text(
              onPressed: () => Navigator.of(context).pop(false),
              label: Text(context.text('cancel')),
            ),
            AppButton.filled(
              onPressed: () => Navigator.of(context).pop(true),
              label: Text(context.text('openInBrowser')),
            ),
          ],
        ),
      ),
    );
    if (open != true) {
      return;
    }
    if (remember) {
      await _sitePreferenceStore.saveOpenExternally(
        profileId: _profileId,
        url: openerUrl,
      );
    }
    await _openExternal(_externalSiteEntryUrl(openerUrl, popupUrl: popupUrl));
    if (mounted) {
      setState(() => _error = context.text('websiteOpenedExternally'));
    }
  }

  String _externalSiteEntryUrl(String openerUrl, {String? popupUrl}) {
    final opener = Uri.tryParse(openerUrl);
    final popup = Uri.tryParse(popupUrl ?? '');
    if (popup != null &&
        (popup.scheme == 'http' || popup.scheme == 'https') &&
        popup.host.isNotEmpty &&
        _shouldOpenOriginalSiteExternally(popup.toString())) {
      return popup.toString();
    }
    if (opener != null &&
        (opener.scheme == 'http' || opener.scheme == 'https') &&
        opener.host.isNotEmpty) {
      return '${opener.scheme}://${opener.host}';
    }
    if (popup != null && popup.host.toLowerCase() == 'accounts.google.com') {
      return 'https://www.google.com';
    }
    return _startingUrl;
  }
}

class _BrowserToolbar extends StatelessWidget {
  const _BrowserToolbar({
    required this.urlController,
    required this.loading,
    required this.detached,
    required this.fullWorkspace,
    required this.onBack,
    required this.onForward,
    required this.onReload,
    required this.onStop,
    required this.onHome,
    required this.onResetWorkspace,
    required this.onAddressEdited,
    required this.onOpenUrl,
    required this.onOpenExternal,
    required this.onAddCurrentPage,
    required this.onDetach,
    required this.onCollapse,
    required this.onToggleFullWorkspace,
  });

  final TextEditingController urlController;
  final bool loading;
  final bool detached;
  final bool fullWorkspace;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final VoidCallback onReload;
  final VoidCallback onStop;
  final VoidCallback onHome;
  final VoidCallback onResetWorkspace;
  final VoidCallback onAddressEdited;
  final VoidCallback onOpenUrl;
  final VoidCallback onOpenExternal;
  final VoidCallback onAddCurrentPage;
  final VoidCallback onDetach;
  final VoidCallback onCollapse;
  final VoidCallback onToggleFullWorkspace;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            AppIconButton(
              tooltip: context.text('back'),
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_outlined),
            ),
            if (loading)
              AppIconButton(
                tooltip: context.text('stopLoading'),
                onPressed: onStop,
                icon: const Icon(Icons.close_outlined),
              ),
            AppIconButton(
              tooltip: context.text('forward'),
              onPressed: onForward,
              icon: const Icon(Icons.arrow_forward_outlined),
            ),
            AppIconButton(
              tooltip: context.text('reload'),
              onPressed: onReload,
              icon: loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_outlined),
            ),
            AppIconButton(
              tooltip: context.text('home'),
              onPressed: onHome,
              icon: const Icon(Icons.home_outlined),
            ),
            AppIconButton(
              tooltip: context.text('resetWorkspace'),
              onPressed: onResetWorkspace,
              icon: const Icon(Icons.restart_alt_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: urlController,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.public_outlined),
                  labelText: context.text('url'),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                onChanged: (_) => onAddressEdited(),
                onSubmitted: (_) => onOpenUrl(),
              ),
            ),
            const SizedBox(width: 8),
            AppIconButton(
              tooltip: context.text('openUrl'),
              onPressed: onOpenUrl,
              icon: const Icon(Icons.arrow_circle_right_outlined),
            ),
            AppIconButton(
              tooltip: context.text('openExternally'),
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_browser_outlined),
            ),
            AppIconButton(
              tooltip: context.text('addCurrentPageToResources'),
              onPressed: onAddCurrentPage,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
            AppIconButton(
              tooltip: detached
                  ? context.text('dockBack')
                  : context.text('detachWorkspace'),
              onPressed: onDetach,
              icon: Icon(
                detached
                    ? Icons.call_received_outlined
                    : Icons.open_in_new_outlined,
              ),
            ),
            AppIconButton(
              tooltip: context.text('collapseBrowser'),
              onPressed: onCollapse,
              icon: const Icon(Icons.close_outlined),
            ),
            AppIconButton(
              tooltip: context.text('fullWorkspace'),
              onPressed: onToggleFullWorkspace,
              icon: Icon(
                fullWorkspace
                    ? Icons.close_fullscreen_outlined
                    : Icons.open_in_full_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserTabStrip extends StatelessWidget {
  const _BrowserTabStrip({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.onClose,
    required this.onRename,
    required this.onAdd,
    required this.onDuplicate,
    required this.onReopenClosed,
  });

  final List<_BrowserTabState> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onClose;
  final ValueChanged<int> onRename;
  final VoidCallback onAdd;
  final VoidCallback onDuplicate;
  final VoidCallback? onReopenClosed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 42,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          children: [
            for (var i = 0; i < tabs.length; i += 1)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Tooltip(
                  message: tabs[i].displayTitle,
                  child: GestureDetector(
                    onDoubleTap: () => onRename(i),
                    onLongPress: () => onRename(i),
                    child: InputChip(
                      selected: i == selectedIndex,
                      avatar: const Icon(Icons.language_outlined, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          tabs[i].displayTitle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onPressed: () => onSelected(i),
                      onDeleted: () => onClose(i),
                    ),
                  ),
                ),
              ),
            IconButton(
              tooltip: context.text('renameTab'),
              onPressed: tabs.isEmpty ? null : () => onRename(selectedIndex),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: context.text('newTab'),
              onPressed: onAdd,
              icon: const Icon(Icons.add_outlined),
            ),
            IconButton(
              tooltip: context.text('duplicateTab'),
              onPressed: tabs.isEmpty ? null : onDuplicate,
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              tooltip: context.text('reopenClosedTab'),
              onPressed: onReopenClosed,
              icon: const Icon(Icons.restore_page_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrowserSurface extends StatelessWidget {
  const _BrowserSurface({
    required this.surfaceKey,
    required this.browserId,
    required this.profileId,
    required this.initialUrl,
    required this.detached,
    super.key,
  });

  final GlobalKey surfaceKey;
  final String browserId;
  final String profileId;
  final String initialUrl;
  final bool detached;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isAndroid) {
      return PlatformViewLink(
        key: ValueKey('android-browser-$browserId-$profileId'),
        viewType: 'taskmasterpro/task_browser',
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: 'taskmasterpro/task_browser',
              layoutDirection: Directionality.of(context),
              creationParams: {
                'browserId': browserId,
                'profileId': profileId,
                'initialUrl': initialUrl,
              },
              creationParamsCodec: const StandardMessageCodec(),
              onFocus: () => params.onFocusChanged(true),
            )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      );
    }
    if (!kIsWeb && Platform.isWindows) {
      return ColoredBox(
        key: surfaceKey,
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Text(
              detached
                  ? context.text('workspaceDetached')
                  : context.text('browserLoading'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      );
    }
    return _UnsupportedPlatform();
  }
}

class _TaskBrowserSessionStore {
  Future<_TaskBrowserSessionState?> load(
    String profileId,
    String taskId,
  ) async {
    try {
      final file = await _stateFile(profileId, taskId);
      if (!await file.exists()) {
        return null;
      }
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) {
        return _TaskBrowserSessionState.fromJson(json);
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<void> save(
    String profileId,
    String taskId,
    _TaskBrowserSessionState state,
  ) async {
    try {
      final file = await _stateFile(profileId, taskId);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(state.toJson()));
    } on Object {
      // Browser state is recoverable; losing a checkpoint should not disturb
      // the running timer or the WebView surface.
    }
  }

  Future<File> _stateFile(String profileId, String taskId) async {
    final base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : Directory.systemTemp.path;
    return File(
      '$base${Platform.pathSeparator}TaskMaster Pro${Platform.pathSeparator}BrowserState${Platform.pathSeparator}$profileId${Platform.pathSeparator}$taskId.json',
    );
  }
}

class _TaskBrowserSessionState {
  const _TaskBrowserSessionState({
    required this.selectedTab,
    required this.tabs,
    required this.selectedUrl,
    required this.savedAt,
    this.title,
    this.detached = false,
    this.fullWorkspace = false,
  });

  final int selectedTab;
  final List<_BrowserTabState> tabs;
  final String selectedUrl;
  final String? title;
  final bool detached;
  final bool fullWorkspace;
  final DateTime savedAt;

  factory _TaskBrowserSessionState.fromJson(Map<String, dynamic> json) {
    final rawTabs = json['tabs'];
    return _TaskBrowserSessionState(
      selectedTab: json['selectedTab'] is int ? json['selectedTab'] as int : 0,
      selectedUrl: _restoreBrowserUrl(json['selectedUrl']),
      title: json['title']?.toString(),
      detached: json['detached'] == true,
      fullWorkspace: json['fullWorkspace'] == true,
      savedAt:
          DateTime.tryParse(json['savedAt']?.toString() ?? '') ??
          DateTime.now(),
      tabs: rawTabs is List
          ? [
              for (final item in rawTabs)
                if (item is Map<String, dynamic>)
                  _BrowserTabState.fromJson(item)
                else if (item is Map)
                  _BrowserTabState.fromJson(Map<String, dynamic>.from(item)),
            ]
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selectedTab': selectedTab,
      'selectedUrl': selectedUrl,
      'title': title,
      'detached': detached,
      'fullWorkspace': fullWorkspace,
      'savedAt': savedAt.toIso8601String(),
      'tabs': [for (final tab in tabs) tab.toJson()],
    };
  }
}

const _customTitleUnchanged = Object();

class _BrowserTabState {
  _BrowserTabState({
    String? id,
    required this.url,
    this.title,
    this.customTitle,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String url;
  final String? title;
  final String? customTitle;

  String get host {
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : url;
  }

  String get displayTitle {
    final custom = customTitle?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final pageTitle = title?.trim();
    if (pageTitle != null && pageTitle.isNotEmpty) {
      return pageTitle;
    }
    return host.isNotEmpty ? host : 'Google';
  }

  _BrowserTabState copyWith({
    String? url,
    String? title,
    Object? customTitle = _customTitleUnchanged,
    bool clearCustomTitle = false,
  }) {
    final nextCustomTitle = clearCustomTitle
        ? null
        : identical(customTitle, _customTitleUnchanged)
        ? this.customTitle
        : customTitle as String?;
    return _BrowserTabState(
      id: id,
      url: url ?? this.url,
      title: title ?? this.title,
      customTitle: nextCustomTitle,
    );
  }

  factory _BrowserTabState.fromJson(Map<String, dynamic> json) {
    return _BrowserTabState(
      id: json['id']?.toString(),
      url: _restoreBrowserUrl(json['url']),
      title: json['title']?.toString(),
      customTitle: json['customTitle']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'customTitle': customTitle,
  };
}

class _TabRenameResult {
  const _TabRenameResult.custom(this.title) : useAutomaticTitle = false;
  const _TabRenameResult.auto() : title = null, useAutomaticTitle = true;

  final String? title;
  final bool useAutomaticTitle;
}

class _BrowserSitePreferenceStore {
  Future<bool> shouldOpenExternally({
    required String profileId,
    required String url,
  }) async {
    final domain = _domainFromUrl(url);
    if (domain == null) {
      return false;
    }
    final preferences = await _load(profileId);
    return preferences[domain] == 'external';
  }

  Future<void> saveOpenExternally({
    required String profileId,
    required String url,
  }) async {
    final domain = _domainFromUrl(url);
    if (domain == null) {
      return;
    }
    final preferences = await _load(profileId);
    preferences[domain] = 'external';
    final file = await _stateFile(profileId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(preferences));
  }

  Future<Map<String, String>> _load(String profileId) async {
    try {
      final file = await _stateFile(profileId);
      if (!await file.exists()) {
        return {};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value.toString(),
        };
      }
    } on Object {
      return {};
    }
    return {};
  }

  Future<File> _stateFile(String profileId) async {
    final base = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path)
        : Directory.systemTemp.path;
    return File(
      '$base${Platform.pathSeparator}TaskMaster Pro'
      '${Platform.pathSeparator}BrowserSitePreferences'
      '${Platform.pathSeparator}$profileId.json',
    );
  }

  static String? _domainFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    final host = uri.host.toLowerCase();
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

class _TaskBrowserStartPage extends StatefulWidget {
  const _TaskBrowserStartPage({
    required this.task,
    required this.recentTabs,
    required this.resources,
    required this.onNavigate,
  });

  final TaskItem task;
  final List<_BrowserTabState> recentTabs;
  final List<TaskResource> resources;
  final ValueChanged<String> onNavigate;

  @override
  State<_TaskBrowserStartPage> createState() => _TaskBrowserStartPageState();
}

class _TaskBrowserStartPageState extends State<_TaskBrowserStartPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = <String, _BrowserTabState>{};
    for (final tab in widget.recentTabs.reversed) {
      if (tab.url != 'about:blank') recent[tab.url] = tab;
    }
    final entries = recent.values.take(6).toList();
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.public_outlined, size: 48),
          const SizedBox(height: 12),
          Text(
            context.text('searchWebForTask'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: context.text('searchOrEnterAddress'),
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: IconButton(
                    tooltip: context.text('search'),
                    onPressed: _open,
                    icon: const Icon(Icons.arrow_forward_outlined),
                  ),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _open(),
              ),
            ),
          ),
          if (entries.isNotEmpty) ...[
            const SizedBox(height: 28),
            Text(
              context.text('recentlyUsedForTask'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tab in entries)
                  ActionChip(
                    avatar: const Icon(Icons.history_outlined, size: 16),
                    label: Text(tab.displayTitle),
                    onPressed: () => widget.onNavigate(tab.url),
                  ),
              ],
            ),
          ],
          if (widget.resources.isNotEmpty ||
              widget.task.workspaceStartingUrl?.isNotEmpty == true) ...[
            const SizedBox(height: 24),
            Text(
              context.text('savedTaskResources'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (widget.resources.isNotEmpty)
              for (final resource in widget.resources)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    resource.isDefault
                        ? Icons.home_outlined
                        : Icons.bookmark_outline,
                  ),
                  title: Text(resource.name),
                  subtitle: Text(
                    resource.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                  ),
                  onTap: () => widget.onNavigate(resource.url),
                )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home_outlined),
                title: Text(
                  widget.task.workspaceResourceTitle ?? widget.task.title,
                ),
                subtitle: Text(widget.task.workspaceStartingUrl!),
                onTap: () =>
                    widget.onNavigate(widget.task.workspaceStartingUrl!),
              ),
          ],
        ],
      ),
    );
  }

  void _open() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) widget.onNavigate(value);
  }
}

class _UnsupportedPlatform extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(child: Text(context.text('browserUnsupportedPlatform')));
  }
}

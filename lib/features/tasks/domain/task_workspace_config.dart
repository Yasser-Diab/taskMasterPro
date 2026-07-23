enum TaskWorkspaceType {
  none,
  inAppBrowser,
  externalBrowser,
  localFileOrFolder,
  applicationShortcut,
}

extension TaskWorkspaceTypeX on TaskWorkspaceType {
  String get storageValue => switch (this) {
    TaskWorkspaceType.none => 'none',
    TaskWorkspaceType.inAppBrowser => 'in_app_browser',
    TaskWorkspaceType.externalBrowser => 'external_browser',
    TaskWorkspaceType.localFileOrFolder => 'local_file_or_folder',
    TaskWorkspaceType.applicationShortcut => 'application_shortcut',
  };

  static TaskWorkspaceType fromStorage(String? value) {
    return switch (value) {
      'in_app_browser' => TaskWorkspaceType.inAppBrowser,
      'external_browser' => TaskWorkspaceType.externalBrowser,
      'local_file_or_folder' => TaskWorkspaceType.localFileOrFolder,
      'application_shortcut' => TaskWorkspaceType.applicationShortcut,
      _ => TaskWorkspaceType.none,
    };
  }
}

enum TaskTrackingMode { interactive, video, reading, manual }

extension TaskTrackingModeX on TaskTrackingMode {
  String get storageValue => name;

  static TaskTrackingMode fromStorage(String? value) {
    return switch (value) {
      'video' => TaskTrackingMode.video,
      'reading' => TaskTrackingMode.reading,
      'manual' => TaskTrackingMode.manual,
      _ => TaskTrackingMode.interactive,
    };
  }
}

enum TaskWorkspaceLayout { sideBySide, fullWidth }

extension TaskWorkspaceLayoutX on TaskWorkspaceLayout {
  String get storageValue => switch (this) {
    TaskWorkspaceLayout.sideBySide => 'side_by_side',
    TaskWorkspaceLayout.fullWidth => 'full_width',
  };

  static TaskWorkspaceLayout fromStorage(String? value) {
    return switch (value) {
      'full_width' => TaskWorkspaceLayout.fullWidth,
      _ => TaskWorkspaceLayout.sideBySide,
    };
  }
}

enum TaskBrowserLayoutMode { collapsed, split, full }

extension TaskBrowserLayoutModeX on TaskBrowserLayoutMode {
  String get storageValue => name;

  bool get isVisible => this != TaskBrowserLayoutMode.collapsed;
  bool get isFull => this == TaskBrowserLayoutMode.full;

  static TaskBrowserLayoutMode fromStorage(String? value) {
    return switch (value) {
      'split' || 'right_panel' => TaskBrowserLayoutMode.split,
      'full' || 'full_browser' => TaskBrowserLayoutMode.full,
      _ => TaskBrowserLayoutMode.collapsed,
    };
  }
}

enum TaskWorkspaceDockState { docked, detached }

extension TaskWorkspaceDockStateX on TaskWorkspaceDockState {
  String get storageValue => name;

  static TaskWorkspaceDockState fromStorage(String? value) {
    return switch (value) {
      'detached' => TaskWorkspaceDockState.detached,
      _ => TaskWorkspaceDockState.docked,
    };
  }
}

enum TaskWorkspaceNavigationMode {
  normalBrowsing,
  trustedDomainsOnly,
  startingDomainOnly,
}

extension TaskWorkspaceNavigationModeX on TaskWorkspaceNavigationMode {
  String get storageValue => switch (this) {
    TaskWorkspaceNavigationMode.normalBrowsing => 'normal',
    TaskWorkspaceNavigationMode.trustedDomainsOnly => 'trusted_domains_only',
    TaskWorkspaceNavigationMode.startingDomainOnly => 'starting_domain_only',
  };

  static TaskWorkspaceNavigationMode fromStorage(String? value) {
    return switch (value) {
      'trusted_domains_only' => TaskWorkspaceNavigationMode.trustedDomainsOnly,
      'starting_domain_only' => TaskWorkspaceNavigationMode.startingDomainOnly,
      _ => TaskWorkspaceNavigationMode.normalBrowsing,
    };
  }
}

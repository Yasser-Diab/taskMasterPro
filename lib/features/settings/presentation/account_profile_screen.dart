import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_tools;

import '../../../app/app_services.dart';
import '../../../core/config/supabase_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/widgets/app_controls.dart';
import '../../pomodoro/domain/pomodoro_controller.dart';
import '../../pomodoro/domain/pomodoro_models.dart';
import '../../tasks/application/task_action_controller.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    this.taskController,
    this.pomodoroController,
    this.onOpenDeleteAccount,
    super.key,
  });

  final TaskActionController? taskController;
  final PomodoroController? pomodoroController;
  final VoidCallback? onOpenDeleteAccount;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  static const _profileFilesChannel = MethodChannel(
    'taskmasterpro/profile_files',
  );

  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  String? _loadedProfileId;
  String _selectedSex = '';
  bool _cycleTrackingEnabled = false;
  bool _cycleDataSyncEnabled = false;
  bool _savingIdentity = false;
  bool _savingEmail = false;
  bool _avatarBusy = false;
  SupabaseService? _listeningService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = AppServices.of(context).supabaseService;
    if (_listeningService != service) {
      _listeningService?.removeListener(_handleProfileChanged);
      _listeningService = service;
      service.addListener(_handleProfileChanged);
    }
    _syncControllers(service.profile);
  }

  @override
  void dispose() {
    _listeningService?.removeListener(_handleProfileChanged);
    _displayNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final profile = services.supabaseService.profile;
    final colorScheme = Theme.of(context).colorScheme;
    final canSaveIdentity = _canSaveIdentity(profile);

    return Scaffold(
      appBar: AppBar(title: Text(context.text('profileTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ProfileCard(
              title: context.text('profileTitle'),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    final avatar = _ProfileAvatar(profile: profile);
                    final actions = Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        AppButton.outlined(
                          loading: _avatarBusy,
                          onPressed: _avatarBusy ? null : _changePhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(context.text('profilePhotoChange')),
                        ),
                        AppButton.text(
                          loading: _avatarBusy,
                          onPressed: profile?.avatarPath == null || _avatarBusy
                              ? null
                              : _removePhoto,
                          icon: const Icon(Icons.delete_outline),
                          label: Text(context.text('profilePhotoRemove')),
                        ),
                      ],
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [avatar, const SizedBox(height: 16), actions],
                      );
                    }
                    return Row(
                      children: [
                        avatar,
                        const SizedBox(width: 18),
                        Expanded(child: actions),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _displayNameController,
                  maxLength: 80,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.text('profileDisplayName'),
                    helperText: context.text('profileDisplayNameHelp'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  maxLength: 30,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.text('profileUsername'),
                    helperText: context.text('profileUsernameHelp'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSex,
                  decoration: InputDecoration(
                    labelText: context.text('profileSex'),
                    helperText: context.text('profileSexHelp'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(context.text('profileSexNotSet')),
                    ),
                    for (final sex in UserSex.values)
                      DropdownMenuItem(
                        value: sex.storageValue,
                        child: Text(context.text('profileSex_${sex.name}')),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSex = value ?? '';
                      if (_selectedSex != UserSex.female.storageValue &&
                          !_cycleTrackingEnabled) {
                        _cycleDataSyncEnabled = false;
                      }
                    });
                  },
                ),
                if (_selectedSex == UserSex.female.storageValue ||
                    _cycleTrackingEnabled) ...[
                  const SizedBox(height: 8),
                  AppSwitchListTile(
                    value: _cycleTrackingEnabled,
                    title: Text(context.text('enableCycleTracking')),
                    subtitle: Text(context.text('enableCycleTrackingHelp')),
                    onChanged: (value) {
                      setState(() {
                        _cycleTrackingEnabled = value;
                        if (!value) _cycleDataSyncEnabled = false;
                      });
                    },
                  ),
                  AppSwitchListTile(
                    value: _cycleDataSyncEnabled,
                    title: Text(context.text('syncCycleData')),
                    subtitle: Text(context.text('syncCycleDataHelp')),
                    onChanged: _cycleTrackingEnabled
                        ? (value) =>
                              setState(() => _cycleDataSyncEnabled = value)
                        : null,
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton.filled(
                    loading: _savingIdentity,
                    onPressed: canSaveIdentity ? _saveIdentity : null,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(context.text('profileSave')),
                  ),
                ),
              ],
            ),
            _ProfileCard(
              title: context.text('profileEmailAddress'),
              children: [
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.text('profileEmailCurrent'),
                  ),
                  child: SelectableText(
                    profile?.email ?? '',
                    textDirection: TextDirection.ltr,
                  ),
                ),
                if (profile?.pendingEmail != null &&
                    profile!.pendingEmail!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${context.text('profileEmailPending')}: ${profile.pendingEmail}',
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: context.text('profileEmailChange'),
                    helperText: context.text('profileEmailChangeHelp'),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: AppButton.outlined(
                    loading: _savingEmail,
                    onPressed: _savingEmail ? null : _requestEmailChange,
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: Text(context.text('profileEmailChange')),
                  ),
                ),
              ],
            ),
            _ProfileCard(
              title: context.text('accountSecurity'),
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.password_outlined),
                  title: Text(context.text('changePassword')),
                  subtitle: Text(context.text('changePasswordHelp')),
                  onTap: _requestPasswordReset,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.devices_outlined),
                  title: Text(context.text('activeSessions')),
                  subtitle: Text(context.text('activeSessionsHelp')),
                  onTap: _showActiveSessionsInfo,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_outlined),
                  title: Text(context.text('logoutThisDevice')),
                  onTap: _confirmAndSignOut,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: colorScheme.error,
                  ),
                  title: Text(context.text('deleteAccount')),
                  subtitle: Text(context.text('deleteAccountHelp')),
                  onTap:
                      widget.onOpenDeleteAccount ??
                      () => AppServices.of(context).notificationService
                          .showWarning(context.text('deleteAccountHelp')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveIdentity() async {
    final services = AppServices.of(context);
    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim();
    if (displayName.isEmpty || displayName.length > 80) {
      services.notificationService.showError(
        context.text('profileDisplayNameInvalid'),
      );
      return;
    }
    if (username.isNotEmpty &&
        (username.length < 3 ||
            username.length > 30 ||
            RegExp(r'\s').hasMatch(username))) {
      services.notificationService.showError(
        context.text('profileUsernameInvalid'),
      );
      return;
    }

    setState(() => _savingIdentity = true);
    final error = await services.supabaseService.updateProfileIdentity(
      displayName: displayName,
      username: username.isEmpty ? null : username,
      sex: UserSexX.fromStorage(_selectedSex),
      clearSex: _selectedSex.isEmpty,
      cycleTrackingEnabled: _cycleTrackingEnabled,
      cycleDataSyncEnabled: _cycleDataSyncEnabled,
    );
    if (!mounted) {
      return;
    }
    setState(() => _savingIdentity = false);
    if (error == null) {
      services.notificationService.showSuccess(context.text('profileSaved'));
    } else if (error.toLowerCase().contains('username')) {
      services.notificationService.showError(
        context.text('profileUsernameUnavailable'),
      );
      _syncControllers(services.supabaseService.profile, force: true);
    } else {
      services.notificationService.showError(error);
      _syncControllers(services.supabaseService.profile, force: true);
    }
  }

  bool _canSaveIdentity(AppUserProfile? profile) {
    if (_savingIdentity || profile == null) {
      return false;
    }
    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim();
    if (displayName.isEmpty || displayName.length > 80) {
      return false;
    }
    if (username.isNotEmpty &&
        (username.length < 3 ||
            username.length > 30 ||
            RegExp(r'\s').hasMatch(username))) {
      return false;
    }
    return displayName != profile.displayName.trim() ||
        username != (profile.username ?? '').trim() ||
        _selectedSex != (profile.sex?.storageValue ?? '') ||
        _cycleTrackingEnabled != profile.cycleTrackingEnabled ||
        _cycleDataSyncEnabled != profile.cycleDataSyncEnabled;
  }

  Future<void> _requestEmailChange() async {
    final services = AppServices.of(context);
    final newEmail = _emailController.text.trim();
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      services.notificationService.showError(
        context.text('validEmailRequired'),
      );
      return;
    }

    setState(() => _savingEmail = true);
    final error = await services.supabaseService.requestEmailChange(newEmail);
    if (!mounted) {
      return;
    }
    setState(() => _savingEmail = false);
    if (error == null) {
      _emailController.clear();
      services.notificationService.showSuccess(
        context.text('profileEmailRequested'),
      );
    } else {
      services.notificationService.showError(error);
    }
  }

  Future<void> _changePhoto() async {
    final services = AppServices.of(context);
    setState(() => _avatarBusy = true);
    try {
      final bytes = await _profileFilesChannel.invokeMethod<Uint8List>(
        'pickAvatarImage',
      );
      if (bytes == null) {
        if (mounted) {
          setState(() => _avatarBusy = false);
        }
        return;
      }

      if (bytes.length > 5 * 1024 * 1024) {
        if (!mounted) {
          return;
        }
        services.notificationService.showError(
          context.text('profileAvatarUploadFailed'),
        );
        setState(() => _avatarBusy = false);
        return;
      }

      final preparedBytes = _prepareAvatar(bytes);
      if (preparedBytes == null) {
        if (!mounted) {
          return;
        }
        services.notificationService.showError(
          context.text('profileAvatarUploadFailed'),
        );
        setState(() => _avatarBusy = false);
        return;
      }

      final error = await services.supabaseService.uploadAvatarBytes(
        bytes: preparedBytes,
        extension: 'jpg',
        contentType: 'image/jpeg',
      );
      if (!mounted) {
        return;
      }
      if (error == null) {
        services.notificationService.showSuccess(
          context.text('profilePictureUpdated'),
        );
      } else {
        services.notificationService.showError(
          context.text('profileAvatarUploadFailed'),
        );
      }
    } on Object {
      if (mounted) {
        services.notificationService.showError(
          context.text('profileAvatarUploadFailed'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _removePhoto() async {
    final services = AppServices.of(context);
    setState(() => _avatarBusy = true);
    final error = await services.supabaseService.removeAvatar();
    if (!mounted) {
      return;
    }
    setState(() => _avatarBusy = false);
    if (error == null) {
      services.notificationService.showSuccess(
        context.text('profilePictureRemoved'),
      );
    } else {
      services.notificationService.showError(error);
    }
  }

  Uint8List? _prepareAvatar(Uint8List input) {
    final decoded = image_tools.decodeImage(input);
    if (decoded == null) {
      return null;
    }
    final side = decoded.width < decoded.height
        ? decoded.width
        : decoded.height;
    final cropX = ((decoded.width - side) / 2).round();
    final cropY = ((decoded.height - side) / 2).round();
    final cropped = image_tools.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: side,
      height: side,
    );
    final resized = image_tools.copyResize(cropped, width: 512, height: 512);
    return Uint8List.fromList(image_tools.encodeJpg(resized, quality: 86));
  }

  Future<void> _requestPasswordReset() async {
    final services = AppServices.of(context);
    final email = services.supabaseService.currentUser?.email;
    if (email == null) {
      return;
    }
    final error = await services.supabaseService.resetPasswordForEmail(email);
    if (!mounted) {
      return;
    }
    if (error == null) {
      services.notificationService.showSuccess(
        context.text('resetPasswordSent'),
      );
    } else {
      services.notificationService.showError(error);
    }
  }

  Future<void> _showActiveSessionsInfo() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.text('activeSessions')),
        content: Text(context.text('activeSessionsBackendManaged')),
        actions: [
          AppButton.text(
            onPressed: () => Navigator.of(context).pop(),
            label: Text(context.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndSignOut() async {
    final services = AppServices.of(context);
    final action = await _resolveActiveSessionBeforeLogout();
    if (action == _ProfileLogoutAction.cancel) {
      return;
    }
    await services.supabaseService.signOut();
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<_ProfileLogoutAction> _resolveActiveSessionBeforeLogout() async {
    final activeTask = widget.taskController?.activeSession;
    final hasPomodoro =
        widget.pomodoroController != null &&
        !widget.pomodoroController!.state.isInactive;
    if (activeTask == null && !hasPomodoro) {
      return _ProfileLogoutAction.none;
    }

    final action = await showDialog<_ProfileLogoutAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.text('activeSessionRunning')),
        content: Text(context.text('activeSessionLogoutHelp')),
        actions: [
          AppButton.text(
            onPressed: () =>
                Navigator.of(context).pop(_ProfileLogoutAction.cancel),
            label: Text(context.text('cancel')),
          ),
          AppButton.outlined(
            onPressed: () =>
                Navigator.of(context).pop(_ProfileLogoutAction.discard),
            label: Text(context.text('discardSession')),
          ),
          AppButton.outlined(
            onPressed: () =>
                Navigator.of(context).pop(_ProfileLogoutAction.pause),
            label: Text(context.text('pauseSessionAndLogout')),
          ),
          AppButton.filled(
            onPressed: () =>
                Navigator.of(context).pop(_ProfileLogoutAction.end),
            label: Text(context.text('saveEndSession')),
          ),
        ],
      ),
    );

    final selected = action ?? _ProfileLogoutAction.cancel;
    final task = activeTask?.task;
    if (selected == _ProfileLogoutAction.end &&
        widget.taskController != null &&
        task != null) {
      await widget.taskController!.completeTask(task);
    } else if (selected == _ProfileLogoutAction.pause &&
        widget.taskController != null &&
        task != null) {
      await widget.taskController!.pauseTask(task);
    } else if (selected == _ProfileLogoutAction.discard &&
        widget.taskController != null &&
        task != null) {
      await widget.taskController!.cancelTask(task);
    }

    if (selected == _ProfileLogoutAction.end) {
      widget.pomodoroController?.stopAndSave();
    } else if (selected == _ProfileLogoutAction.discard) {
      widget.pomodoroController?.stopWithoutSaving();
    } else if (selected == _ProfileLogoutAction.pause &&
        widget.pomodoroController?.state.isRunning == true) {
      widget.pomodoroController?.pause();
    }

    return selected;
  }

  void _handleProfileChanged() {
    if (!mounted) {
      return;
    }
    _syncControllers(AppServices.of(context).supabaseService.profile);
    setState(() {});
  }

  void _syncControllers(AppUserProfile? profile, {bool force = false}) {
    if (profile == null) {
      _loadedProfileId = null;
      if (force) {
        _displayNameController.clear();
        _usernameController.clear();
        _selectedSex = '';
        _cycleTrackingEnabled = false;
        _cycleDataSyncEnabled = false;
      }
      return;
    }
    final key =
        '${profile.id}:${profile.displayName}:${profile.username ?? ''}:'
        '${profile.sex?.storageValue ?? ''}:${profile.cycleTrackingEnabled}:'
        '${profile.cycleDataSyncEnabled}';
    if (!force && _loadedProfileId == key) {
      return;
    }
    _loadedProfileId = key;
    _displayNameController.text = profile.displayName;
    _usernameController.text = profile.username ?? '';
    _selectedSex = profile.sex?.storageValue ?? '';
    _cycleTrackingEnabled = profile.cycleTrackingEnabled;
    _cycleDataSyncEnabled = profile.cycleDataSyncEnabled;
  }
}

enum _ProfileLogoutAction { none, end, pause, discard, cancel }

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile});

  final AppUserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final email = profile?.email.trim();
    final label =
        profile?.preferredName ??
        ((email != null && email.isNotEmpty) ? email : context.text('profile'));
    final signedUrl = profile?.avatarSignedUrl;
    final initials = profile?.initials ?? _initials(label);

    return Semantics(
      label: context.text('profilePicture'),
      child: CircleAvatar(
        key: ValueKey(profile?.avatarPath ?? profile?.id ?? 'profile'),
        radius: 46,
        backgroundImage: signedUrl == null || signedUrl.isEmpty
            ? null
            : NetworkImage(signedUrl),
        child: signedUrl == null || signedUrl.isEmpty
            ? Text(initials, style: Theme.of(context).textTheme.headlineSmall)
            : null,
      ),
    );
  }

  String _initials(String label) {
    final words = label
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return 'TP';
    }
    if (words.length == 1) {
      final end = words.first.length < 2 ? words.first.length : 2;
      return words.first.substring(0, end).toUpperCase();
    }
    return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

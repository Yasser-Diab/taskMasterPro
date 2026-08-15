import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/app_localizations.dart';
import 'app_update_service.dart';

Future<void> showAppUpdateDialog(
  BuildContext context, {
  required AppUpdateService service,
  required AppRelease release,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(service: service, release: release),
  );
}

Future<void> showWhatsNewDialog(
  BuildContext context, {
  required AppUpdateService service,
  bool automatic = false,
  bool freshInstall = false,
}) async {
  final localeCode = Localizations.localeOf(context).languageCode;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WhatsNewLoadingDialog(
      service: service,
      localeCode: localeCode,
      automatic: automatic,
      freshInstall: freshInstall,
    ),
  );
}

class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({required this.child, super.key});

  final Widget child;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  final _service = AppUpdateService();
  bool _checked = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    await _showInstalledReleaseNotesIfNeeded();
    await _checkForNewerRelease();
    if (Supabase.instance.client.auth.currentSession == null) {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (state.session != null) {
              unawaited(_showInstalledReleaseNotesIfNeeded());
            }
          });
    }
  }

  Future<void> _showInstalledReleaseNotesIfNeeded() async {
    if (Supabase.instance.client.auth.currentSession == null) return;
    final preferences = await SharedPreferences.getInstance();
    final version = await _service.currentVersion();
    final acknowledged = preferences.getString(
      'taskmaster.release_notes.acknowledged',
    );
    if (acknowledged == version || !mounted) return;
    final previous = preferences.getString('taskmaster.installed_version');
    final hadExistingInstallation =
        previous != null || preferences.containsKey('taskmaster.device_id');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await showWhatsNewDialog(
      context,
      service: _service,
      automatic: true,
      freshInstall: !hadExistingInstallation,
    );
    await preferences.setString('taskmaster.installed_version', version);
  }

  Future<void> _checkForNewerRelease() async {
    try {
      final release = await _service.checkForUpdate();
      if (!mounted || release == null) return;
      await showAppUpdateDialog(context, service: _service, release: release);
    } catch (_) {
      // Update checks are helpful but must never block app startup or offline use.
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WhatsNewDialog extends StatefulWidget {
  const _WhatsNewDialog({
    required this.release,
    required this.automatic,
    required this.freshInstall,
  });

  final AppRelease release;
  final bool automatic;
  final bool freshInstall;

  @override
  State<_WhatsNewDialog> createState() => _WhatsNewDialogState();
}

class _WhatsNewLoadingDialog extends StatefulWidget {
  const _WhatsNewLoadingDialog({
    required this.service,
    required this.localeCode,
    required this.automatic,
    required this.freshInstall,
  });

  final AppUpdateService service;
  final String localeCode;
  final bool automatic;
  final bool freshInstall;

  @override
  State<_WhatsNewLoadingDialog> createState() => _WhatsNewLoadingDialogState();
}

class _WhatsNewLoadingDialogState extends State<_WhatsNewLoadingDialog> {
  late Future<AppRelease> _release;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _release = widget.service.releaseNotesForInstalledVersion(
      localeCode: widget.localeCode,
    );
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (widget.automatic) {
      final version = await widget.service.currentVersion();
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'taskmaster.release_notes.acknowledged',
        version,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppRelease>(
      future: _release,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return _WhatsNewDialog(
            release: snapshot.requireData,
            automatic: widget.automatic,
            freshInstall: widget.freshInstall,
          );
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) unawaited(_close());
          },
          child: Dialog(
            insetPadding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 12, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.text('loading'),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.text('update_close_notes'),
                          onPressed: _close,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (!snapshot.hasError)
                      const LinearProgressIndicator()
                    else ...[
                      Text(
                        context.l10n.text('update_notes_unavailable'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: () => setState(_load),
                            child: Text(context.l10n.text('retry')),
                          ),
                          FilledButton(
                            onPressed: _close,
                            child: Text(context.l10n.text('done')),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WhatsNewDialogState extends State<_WhatsNewDialog> {
  bool _closing = false;

  Future<void> _acknowledge() async {
    if (_closing) return;
    _closing = true;
    if (widget.automatic) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'taskmaster.release_notes.acknowledged',
        widget.release.version,
      );
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final heading = widget.freshInstall
        ? context.l10n.text('update_welcome')
        : context.l10n.text('update_installed');
    final screen = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_acknowledge());
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: screen.width >= 700 ? 520 : 0,
            maxWidth: 800,
            maxHeight: screen.height - 40,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            context.l10n.format('update_version', {
                              'version': widget.release.version,
                            }),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.l10n.text('update_close_notes'),
                      onPressed: _acknowledge,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Markdown(
                  data: widget.release.notes.trim().isEmpty
                      ? '# TaskMaster Pro v${widget.release.version}\n\n'
                            '${context.l10n.text('update_notes_unavailable')}'
                      : widget.release.notes,
                  selectable: true,
                  onTapLink: (_, href, _) async {
                    final uri = Uri.tryParse(href ?? '');
                    if (uri != null &&
                        (uri.scheme == 'https' || uri.scheme == 'http')) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final primary = FilledButton(
                          onPressed: _acknowledge,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: Text(context.l10n.text('update_got_it')),
                          ),
                        );
                        final secondary = widget.release.isComingSoon
                            ? const SizedBox.shrink()
                            : TextButton(
                                onPressed: () => launchUrl(
                                  widget.release.pageUrl,
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: Text(
                                  context.l10n.text('update_view_full_notes'),
                                ),
                              );
                        final copy = widget.release.isComingSoon
                            ? const SizedBox.shrink()
                            : IconButton(
                                tooltip: context.l10n.text(
                                  'update_copy_notes_link',
                                ),
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(
                                    text: widget.release.pageUrl.toString(),
                                  ),
                                ),
                                icon: const Icon(Icons.link),
                              );
                        if (constraints.maxWidth < 560) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              primary,
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [secondary, copy],
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: [secondary, copy, const Spacer(), primary],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service, required this.release});

  final AppUpdateService service;
  final AppRelease release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;

  Future<void> _install() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      await widget.service.downloadAndOpenInstaller(
        widget.release,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = context.l10n.text('update_open_failed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.release.installerForCurrentPlatform();
    return AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded, size: 34),
      title: Text(
        context.l10n.format('update_ready', {
          'version': widget.release.version,
        }),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.release.notes.trim().isEmpty
                  ? context.l10n.text('update_newer_available')
                  : _shortNotes(widget.release.notes),
            ),
            const SizedBox(height: 14),
            if (asset != null)
              Text(
                '${context.l10n.text(Platform.isWindows ? 'update_windows_installer' : 'update_android_installer')} · ${_fileSize(asset.size)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                context.l10n.format('update_download_progress', {
                  'percent': ((_progress ?? 0) * 100).round(),
                }),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _progress == null
              ? () => Navigator.of(context).pop()
              : null,
          child: Text(context.l10n.text('not_now')),
        ),
        TextButton(
          onPressed: _progress == null
              ? () => launchUrl(
                  widget.release.pageUrl,
                  mode: LaunchMode.externalApplication,
                )
              : null,
          child: Text(context.l10n.text('release_notes')),
        ),
        FilledButton.icon(
          onPressed: _progress == null && asset != null ? _install : null,
          icon: const Icon(Icons.download_rounded),
          label: Text(context.l10n.text('download_update')),
        ),
      ],
    );
  }

  String _shortNotes(String notes) {
    final clean = notes
        .replaceAll(RegExp(r'[#*_`]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return clean.length <= 320 ? clean : '${clean.substring(0, 317)}…';
  }

  String _fileSize(int bytes) {
    if (bytes <= 0) return context.l10n.text('update_size_unavailable');
    final megabytes = bytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(megabytes >= 10 ? 0 : 1)} MB';
  }
}

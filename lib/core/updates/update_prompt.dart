import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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

class UpdatePrompt extends StatefulWidget {
  const UpdatePrompt({required this.child, super.key});

  final Widget child;

  @override
  State<UpdatePrompt> createState() => _UpdatePromptState();
}

class _UpdatePromptState extends State<UpdatePrompt> {
  final _service = AppUpdateService();
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    try {
      final release = await _service.checkForUpdate();
      if (!mounted || release == null) return;
      await showAppUpdateDialog(context, service: _service, release: release);
    } catch (_) {
      // Update checks are helpful but must never block app startup or offline use.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
          _error =
              'The update could not be opened. You can still download it from the release page';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.release.installerForCurrentPlatform();
    return AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded, size: 34),
      title: Text('TaskMaster Pro ${widget.release.version} is ready'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.release.notes.trim().isEmpty
                  ? 'A newer release is available for this device'
                  : _shortNotes(widget.release.notes),
            ),
            const SizedBox(height: 14),
            if (asset != null)
              Text(
                '${asset.name} · ${_fileSize(asset.size)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_progress != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 6),
              Text(
                'Downloading ${((_progress ?? 0) * 100).round()}%',
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
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: _progress == null
              ? () => launchUrl(
                  widget.release.pageUrl,
                  mode: LaunchMode.externalApplication,
                )
              : null,
          child: const Text('Release notes'),
        ),
        FilledButton.icon(
          onPressed: _progress == null && asset != null ? _install : null,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download update'),
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
    if (bytes <= 0) return 'Size shown on GitHub';
    final megabytes = bytes / (1024 * 1024);
    return '${megabytes.toStringAsFixed(megabytes >= 10 ? 0 : 1)} MB';
  }
}

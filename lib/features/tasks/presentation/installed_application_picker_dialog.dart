import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../data/installed_application_service.dart';

Future<InstalledApplication?> showInstalledApplicationPicker(
  BuildContext context, {
  required Future<List<InstalledApplication>> applications,
}) {
  return showDialog<InstalledApplication>(
    context: context,
    builder: (context) =>
        _InstalledApplicationPickerDialog(applications: applications),
  );
}

class _InstalledApplicationPickerDialog extends StatefulWidget {
  const _InstalledApplicationPickerDialog({required this.applications});

  final Future<List<InstalledApplication>> applications;

  @override
  State<_InstalledApplicationPickerDialog> createState() =>
      _InstalledApplicationPickerDialogState();
}

class _InstalledApplicationPickerDialogState
    extends State<_InstalledApplicationPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.apps_rounded, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.text('choose_installed_application'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.text('cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: context.l10n.text('clear_search'),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  hintText: context.l10n.text('search_installed_applications'),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: FutureBuilder<List<InstalledApplication>>(
                  future: widget.applications,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final applications = filterInstalledApplications(
                      snapshot.data ?? const [],
                      _query,
                    );
                    if (applications.isEmpty) {
                      return _ApplicationPickerEmptyState(
                        message: context.l10n.text(
                          _query.trim().isEmpty
                              ? 'no_installed_applications'
                              : 'no_applications_match',
                        ),
                      );
                    }
                    return Scrollbar(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: applications.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final application = applications[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            leading: _ApplicationMonogram(
                              name: application.displayName,
                            ),
                            title: Text(application.displayName),
                            subtitle: Text(
                              application.identifier,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).pop(application),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.text('cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApplicationPickerEmptyState extends StatelessWidget {
  const _ApplicationPickerEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.apps_outage_outlined,
              size: 42,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ApplicationMonogram extends StatelessWidget {
  const _ApplicationMonogram({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.characters.first;
    return CircleAvatar(
      backgroundColor: theme.colorScheme.primaryContainer,
      foregroundColor: theme.colorScheme.onPrimaryContainer,
      child: Text(letter.toUpperCase()),
    );
  }
}

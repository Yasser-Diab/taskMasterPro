import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_services.dart';
import '../../../core/config/build_info.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/platform/external_url_launcher.dart';
import '../../../core/theme/app_brand.dart';
import '../../../core/theme/app_theme.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _privacyUrl =
      'https://yasser-diab.github.io/taskMasterPro/privacy-policy/';
  static const _termsUrl = 'https://yasser-diab.github.io/taskMasterPro/terms/';

  bool _developerMode = false;
  bool _showSensitive = false;

  @override
  Widget build(BuildContext context) {
    final services = AppServices.of(context);
    final diagnostics = services.supabaseService.startupDiagnostics ?? {};
    return Scaffold(
      appBar: AppBar(title: Text(context.text('about'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            AppBrand.logoAssetForTheme(
                              services.config.themeChoice,
                            ),
                            height: 140,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 18),
                          Text(
                            AppBrand.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.text('aboutText'),
                            style: TextStyle(
                              color: context.appColors.mutedText,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.text('buildInformation'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _BuildInfoRow(
                            label: context.text('appVersion'),
                            value: BuildInfo.version,
                          ),
                          _BuildInfoRow(
                            label: context.text('buildNumber'),
                            value: BuildInfo.buildNumber,
                          ),
                          _BuildInfoRow(
                            label: context.text('gitCommit'),
                            value: BuildInfo.gitCommit,
                          ),
                          _BuildInfoRow(
                            label: context.text('buildDate'),
                            value: BuildInfo.buildDate,
                          ),
                          _BuildInfoRow(
                            label: context.text('databaseMigrationVersion'),
                            value: BuildInfo.migrationVersion,
                          ),
                          _BuildInfoRow(
                            label: context.text('flutterEnvironment'),
                            value: BuildInfo.flutterEnvironment,
                          ),
                          _BuildInfoRow(
                            label: context.text('platform'),
                            value: BuildInfo.platform,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: Text(context.text('privacyPolicy')),
                          onTap: () => ExternalUrlLauncher.open(_privacyUrl),
                        ),
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(context.text('termsOfService')),
                          onTap: () => ExternalUrlLauncher.open(_termsUrl),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: SwitchListTile(
                      value: _developerMode,
                      onChanged: (value) => setState(() {
                        _developerMode = value;
                        if (!value) _showSensitive = false;
                      }),
                      title: Text(context.text('developerMode')),
                      subtitle: Text(context.text('developerModeHelp')),
                    ),
                  ),
                  if (_developerMode) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.text('startupDiagnostics'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _showSensitive,
                              onChanged: (value) =>
                                  setState(() => _showSensitive = value),
                              title: Text(context.text('showSensitiveValues')),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              diagnostics.isEmpty
                                  ? context.text('noDiagnosticsYet')
                                  : _formatDiagnostics(
                                      diagnostics,
                                      redact: !_showSensitive,
                                    ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: FilledButton.icon(
                                onPressed: diagnostics.isEmpty
                                    ? null
                                    : () {
                                        Clipboard.setData(
                                          ClipboardData(
                                            text: _formatDiagnostics(
                                              diagnostics,
                                              redact: !_showSensitive,
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.copy_outlined),
                                label: Text(context.text('copyDiagnostics')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDiagnostics(
    Map<String, dynamic> diagnostics, {
    required bool redact,
  }) {
    return diagnostics.entries
        .map((entry) {
          final value = redact
              ? _redactValue(entry.key, entry.value)
              : entry.value;
          return '${entry.key}: $value';
        })
        .join('\n');
  }

  Object? _redactValue(String key, Object? value) {
    final lower = key.toLowerCase();
    if (lower.contains('email')) return _redactEmail('$value');
    if (lower.contains('uuid') || lower.endsWith('_id') || lower == 'user_id') {
      final text = '$value';
      if (text.length <= 8) return 'redacted';
      return '${text.substring(0, 4)}…${text.substring(text.length - 4)}';
    }
    return value;
  }

  String _redactEmail(String value) {
    final at = value.indexOf('@');
    if (at <= 1) return 'redacted';
    return '${value.substring(0, 1)}…${value.substring(at)}';
  }
}

class _BuildInfoRow extends StatelessWidget {
  const _BuildInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(
              label,
              style: TextStyle(color: context.appColors.mutedText),
            ),
          ),
          Expanded(
            child: SelectableText(value, textDirection: TextDirection.ltr),
          ),
        ],
      ),
    );
  }
}

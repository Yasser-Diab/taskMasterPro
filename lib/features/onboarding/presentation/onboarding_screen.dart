import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/account/owner_bootstrap.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({required this.user, super.key});

  final User user;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final TextEditingController _displayName;
  String _language = 'en';
  String _theme = 'system';
  String _goal = 'work_performance';
  String _executionStyle = 'mixed';
  String _coaching = 'standard';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController(
      text:
          widget.user.userMetadata?['display_name'] as String? ??
          widget.user.userMetadata?['full_name'] as String? ??
          '',
    );
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_displayName.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final settings = ref.read(settingsRepositoryProvider);
      await settings.updateLocale(_language);
      await settings.updateTheme(_theme);
      if (mayBootstrapOwnerContent(widget.user.id)) {
        await ref.read(taskRepositoryProvider).seedStarterDomains();
        await ref
            .read(roadmapRepositoryProvider)
            .createStarterRoadmap(
              userId: widget.user.id,
              title: AppLocalizations(
                Locale(_language),
              ).text('onboarding_goal_$_goal'),
            );
      }
      await settings.completeOnboarding(
        userId: widget.user.id,
        displayName: _displayName.text,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeKey = TaskMasterThemeKey.fromKey(_theme);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  BrandLogo(themeKey: themeKey, height: 82),
                  const SizedBox(height: 20),
                  Text(
                    context.l10n.text('onboarding_title'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.text('onboarding_subtitle'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 680;
                          final left = [
                            TextField(
                              controller: _displayName,
                              decoration: InputDecoration(
                                labelText: context.l10n.text('display_name'),
                                prefixIcon: const Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _language,
                              decoration: InputDecoration(
                                labelText: context.l10n.text('language'),
                                prefixIcon: const Icon(Icons.language),
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: 'en',
                                  child: Text(
                                    context.l10n.text('language_english'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'ar',
                                  child: Text(
                                    context.l10n.text('language_arabic'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'de',
                                  child: Text(
                                    context.l10n.text('language_german'),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: 'pl',
                                  child: Text(
                                    context.l10n.text('language_polish'),
                                  ),
                                ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                setState(() => _language = value);
                                await ref
                                    .read(settingsRepositoryProvider)
                                    .updateLocale(value);
                              },
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _theme,
                              decoration: InputDecoration(
                                labelText: context.l10n.text('theme'),
                                prefixIcon: const Icon(Icons.palette_outlined),
                              ),
                              items: [
                                for (final value in const [
                                  'system',
                                  'light',
                                  'dark',
                                  'golden',
                                ])
                                  DropdownMenuItem(
                                    value: value,
                                    child: Text(context.l10n.text(value)),
                                  ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                setState(() => _theme = value);
                                await ref
                                    .read(settingsRepositoryProvider)
                                    .updateTheme(value);
                              },
                            ),
                          ];
                          final right = [
                            DropdownButtonFormField<String>(
                              initialValue: _goal,
                              decoration: InputDecoration(
                                labelText: context.l10n.text('goal'),
                                prefixIcon: const Icon(Icons.flag_outlined),
                              ),
                              items: [
                                for (final goal in const [
                                  'work_performance',
                                  'programming',
                                  'language_learning',
                                  'reading',
                                  'exercise',
                                  'personal_organization',
                                ])
                                  DropdownMenuItem(
                                    value: goal,
                                    child: Text(
                                      context.l10n.text(
                                        'onboarding_goal_$goal',
                                      ),
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _goal = value ?? _goal),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _executionStyle,
                              decoration: InputDecoration(
                                labelText: context.l10n.text(
                                  'onboarding_preferred_execution',
                                ),
                                prefixIcon: const Icon(
                                  Icons.play_circle_outline,
                                ),
                              ),
                              items: [
                                for (final style in const [
                                  'pomodoro',
                                  'continuous',
                                  'checklist',
                                  'manual',
                                  'mixed',
                                  'unsure',
                                ])
                                  DropdownMenuItem(
                                    value: style,
                                    child: Text(
                                      context.l10n.text(
                                        'onboarding_execution_$style',
                                      ),
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setState(
                                () =>
                                    _executionStyle = value ?? _executionStyle,
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue: _coaching,
                              decoration: InputDecoration(
                                labelText: context.l10n.text(
                                  'onboarding_coaching_preference',
                                ),
                                prefixIcon: const Icon(
                                  Icons.psychology_outlined,
                                ),
                              ),
                              items: [
                                for (final mode in const [
                                  'quiet',
                                  'standard',
                                  'active',
                                  'persistent',
                                ])
                                  DropdownMenuItem(
                                    value: mode,
                                    child: Text(
                                      context.l10n.text('coaching_$mode'),
                                    ),
                                  ),
                              ],
                              onChanged: (value) => setState(
                                () => _coaching = value ?? _coaching,
                              ),
                            ),
                          ];
                          if (!columns) {
                            return Column(
                              children: [
                                ...left,
                                const SizedBox(height: 16),
                                ...right,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: Column(children: left)),
                              const SizedBox(width: 20),
                              Expanded(child: Column(children: right)),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _finish,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward_rounded),
                      label: Text(context.l10n.text('finish_setup')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

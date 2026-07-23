import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/config/app_config.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/widgets/app_controls.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_category.dart';

class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  final _controller = PageController();
  final _goalController = TextEditingController();
  final _customAreaController = TextEditingController();
  final _customResponsibilityController = TextEditingController();
  final Set<String> _selectedAreas = {
    'Work',
    'Learning',
    'Family',
    'Household',
    'Health',
  };
  final Set<String> _responsibilities = {'Laundry', 'Shopping', 'Exercise'};
  int _step = 0;
  bool _busy = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    _goalController.dispose();
    _customAreaController.dispose();
    _customResponsibilityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSteps = 6;
    return Scaffold(
      appBar: AppBar(title: Text(context.text('onboarding'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: LinearProgressIndicator(value: (_step + 1) / totalSteps),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) => setState(() => _step = index),
                children: [
                  _ScheduleStep(),
                  _LifeAreasStep(
                    selectedAreas: _selectedAreas,
                    customAreaController: _customAreaController,
                    onChanged: () => setState(() {}),
                  ),
                  _GoalsStep(goalController: _goalController),
                  _ResponsibilitiesStep(
                    selectedResponsibilities: _responsibilities,
                    customResponsibilityController:
                        _customResponsibilityController,
                    onChanged: () => setState(() {}),
                  ),
                  _PreferencesStep(),
                  _ProposedPlanStep(
                    selectedAreas: _selectedAreas,
                    responsibilities: _responsibilities,
                    goal: _goalController.text,
                  ),
                ],
              ),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  _status!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  if (_step > 0)
                    AppButton.outlined(
                      onPressed: _busy ? null : _previous,
                      label: Text(context.text('back')),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    child: AppButton.filled(
                      loading: _busy,
                      onPressed: _busy
                          ? null
                          : _step == totalSteps - 1
                          ? _finish
                          : _next,
                      label: Text(
                        _step == totalSteps - 1
                            ? context.text('approvePlan')
                            : context.text('next'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _previous() {
    _controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    if (_selectedAreas.isEmpty) {
      setState(() => _status = context.text('chooseAtLeastOneArea'));
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final services = AppServices.of(context);
    final repository = TaskRepository(services.supabaseService);
    final selectedTemplates = [
      for (final template in defaultLifeAreaTemplates)
        if (_selectedAreas.contains(template.name)) template,
      for (final area in _selectedAreas)
        if (!defaultLifeAreaTemplates.any((template) => template.name == area))
          TaskCategory(name: area, colorSeed: 0xFF64748B),
    ];
    try {
      await repository.upsertCategories(selectedTemplates);
      final error = await services.supabaseService.markOnboardingComplete();
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = error;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _status = context.text('onboardingSaveFailed');
      });
    }
  }
}

class _ScheduleStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final config = AppServices.of(context).config;
    return _StepShell(
      title: context.text('personalSchedule'),
      children: [
        _OnboardingGrid(
          children: [
            _OnboardingTimeField(
              label: context.text('wakeUpTime'),
              value: config.wakeUpTime,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(wakeUpTime: value),
              ),
            ),
            _OnboardingTimeField(
              label: context.text('bedtime'),
              value: config.bedtime,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(bedtime: value),
              ),
            ),
            _OnboardingTimeField(
              label: context.text('workStartTime'),
              value: config.workStartTime,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(workStartTime: value),
              ),
            ),
            _OnboardingTimeField(
              label: context.text('workEndTime'),
              value: config.workEndTime,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(workEndTime: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(context.text('workdays')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final day in _dayOptions)
              FilterChip(
                selected: config.workdays.contains(day.value),
                label: Text(context.text(day.labelKey)),
                onSelected: (selected) {
                  final next = [...config.workdays];
                  if (selected) {
                    next.add(day.value);
                  } else {
                    next.remove(day.value);
                  }
                  next.sort();
                  _updateOnboardingConfig(
                    context,
                    (config) => config.copyWith(workdays: next),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        _OnboardingGrid(
          children: [
            _OnboardingNumberField(
              label: context.text('lunchDuration'),
              value: config.lunchDurationMinutes,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(lunchDurationMinutes: value),
              ),
            ),
            _OnboardingNumberField(
              label: context.text('commuteToWork'),
              value: config.commuteToWorkMinutes,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(commuteToWorkMinutes: value),
              ),
            ),
            _OnboardingNumberField(
              label: context.text('commuteHome'),
              value: config.commuteHomeMinutes,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(commuteHomeMinutes: value),
              ),
            ),
            _OnboardingNumberField(
              label: context.text('maxDailyStudy'),
              value: config.maxDailyStudyMinutes,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(maxDailyStudyMinutes: value),
              ),
            ),
            _OnboardingNumberField(
              label: context.text('maxWeeklyStudy'),
              value: config.maxWeeklyStudyMinutes,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(maxWeeklyStudyMinutes: value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _OnboardingGrid(
          children: [
            _OnboardingTimeField(
              label: context.text('quietHoursStart'),
              value: config.quietHoursStart,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(quietHoursStart: value),
              ),
            ),
            _OnboardingTimeField(
              label: context.text('quietHoursEnd'),
              value: config.quietHoursEnd,
              onChanged: (value) => _updateOnboardingConfig(
                context,
                (config) => config.copyWith(quietHoursEnd: value),
              ),
            ),
          ],
        ),
        if (_sleepMinutes(config) < 420) ...[
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.nights_stay_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(context.text('sleepWarningTitle')),
            subtitle: Text(context.text('sleepWarningText')),
          ),
        ],
      ],
    );
  }
}

class _LifeAreasStep extends StatelessWidget {
  const _LifeAreasStep({
    required this.selectedAreas,
    required this.customAreaController,
    required this.onChanged,
  });

  final Set<String> selectedAreas;
  final TextEditingController customAreaController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: context.text('mainLifeAreas'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final template in defaultLifeAreaTemplates)
              FilterChip(
                selected: selectedAreas.contains(template.name),
                label: Text(template.name),
                onSelected: (selected) {
                  AppServices.of(context).feedbackService.playUiClick();
                  selected
                      ? selectedAreas.add(template.name)
                      : selectedAreas.remove(template.name);
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: customAreaController,
                decoration: InputDecoration(
                  labelText: context.text('customArea'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppButton.outlined(
              onPressed: () {
                final value = customAreaController.text.trim();
                if (value.isEmpty) {
                  return;
                }
                selectedAreas.add(value);
                customAreaController.clear();
                onChanged();
              },
              icon: const Icon(Icons.add_outlined),
              label: Text(context.text('add')),
            ),
          ],
        ),
      ],
    );
  }
}

class _GoalsStep extends StatelessWidget {
  const _GoalsStep({required this.goalController});

  final TextEditingController goalController;

  @override
  Widget build(BuildContext context) {
    return _StepShell(
      title: context.text('goals'),
      children: [
        TextField(
          controller: goalController,
          minLines: 4,
          maxLines: 7,
          decoration: InputDecoration(
            labelText: context.text('currentGoalsQuestion'),
          ),
        ),
      ],
    );
  }
}

class _ResponsibilitiesStep extends StatelessWidget {
  const _ResponsibilitiesStep({
    required this.selectedResponsibilities,
    required this.customResponsibilityController,
    required this.onChanged,
  });

  final Set<String> selectedResponsibilities;
  final TextEditingController customResponsibilityController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = [
      'Laundry',
      'Shopping',
      'Exercise',
      'Cleaning',
      'Family visits',
      'Bills',
      'Medication',
      'Appointments',
      'Study',
    ];
    return _StepShell(
      title: context.text('recurringResponsibilities'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in presets)
              FilterChip(
                selected: selectedResponsibilities.contains(item),
                label: Text(item),
                onSelected: (selected) {
                  AppServices.of(context).feedbackService.playUiClick();
                  selected
                      ? selectedResponsibilities.add(item)
                      : selectedResponsibilities.remove(item);
                  onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: customResponsibilityController,
                decoration: InputDecoration(
                  labelText: context.text('customResponsibility'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppButton.outlined(
              onPressed: () {
                final value = customResponsibilityController.text.trim();
                if (value.isEmpty) {
                  return;
                }
                selectedResponsibilities.add(value);
                customResponsibilityController.clear();
                onChanged();
              },
              icon: const Icon(Icons.add_outlined),
              label: Text(context.text('add')),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProposedPlanStep extends StatelessWidget {
  const _ProposedPlanStep({
    required this.selectedAreas,
    required this.responsibilities,
    required this.goal,
  });

  final Set<String> selectedAreas;
  final Set<String> responsibilities;
  final String goal;

  @override
  Widget build(BuildContext context) {
    final config = AppServices.of(context).config;
    return _StepShell(
      title: context.text('proposedPlan'),
      children: [
        _InfoLine(
          label: context.text('lifeAreas'),
          value: selectedAreas.join(', '),
        ),
        _InfoLine(
          label: context.text('recurringResponsibilities'),
          value: responsibilities.join(', '),
        ),
        _InfoLine(
          label: context.text('weeklyCapacity'),
          value: '${config.maxWeeklyStudyMinutes ~/ 60} h',
        ),
        _InfoLine(
          label: context.text('protectedSleep'),
          value: '${config.bedtime} - ${config.wakeUpTime}',
        ),
        if (goal.trim().isNotEmpty)
          _InfoLine(label: context.text('goals'), value: goal.trim()),
        Text(context.text('approvePlanHelp')),
      ],
    );
  }
}

class _PreferencesStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final config = AppServices.of(context).config;
    return _StepShell(
      title: context.text('applicationSettings'),
      children: [
        DropdownButtonFormField<String>(
          initialValue: config.coachingIntensity,
          decoration: InputDecoration(
            labelText: context.text('coachingIntensity'),
          ),
          items: [
            _dropdownItem(context, 'quiet', 'quiet'),
            _dropdownItem(context, 'standard', 'standard'),
            _dropdownItem(context, 'active', 'activeCoach'),
            _dropdownItem(context, 'persistent', 'persistentCoach'),
            _dropdownItem(context, 'custom', 'custom'),
          ],
          onChanged: (value) {
            if (value == null) return;
            _updateOnboardingConfig(
              context,
              (config) => config.copyWith(coachingIntensity: value),
            );
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: config.defaultSearchEngine,
          decoration: InputDecoration(
            labelText: context.text('defaultSearchEngine'),
          ),
          items: [
            _dropdownItem(context, 'google', 'searchEngine_google'),
            _dropdownItem(context, 'bing', 'searchEngine_bing'),
            _dropdownItem(context, 'duckduckgo', 'searchEngine_duckduckgo'),
            _dropdownItem(context, 'brave', 'searchEngine_brave'),
            _dropdownItem(context, 'custom', 'custom'),
          ],
          onChanged: (value) {
            if (value == null) return;
            _updateOnboardingConfig(
              context,
              (config) => config.copyWith(defaultSearchEngine: value),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(context.text('soundsFeedback')),
        AppSwitchListTile(
          value: config.uiClickSounds,
          title: Text(context.text('uiClickSounds')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(uiClickSounds: value),
          ),
        ),
        AppSwitchListTile(
          value: config.notificationSounds,
          title: Text(context.text('notificationSounds')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(notificationSounds: value),
          ),
        ),
        AppSwitchListTile(
          value: config.pomodoroSounds,
          title: Text(context.text('pomodoroSounds')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(pomodoroSounds: value),
          ),
        ),
        AppSwitchListTile(
          value: config.completionSounds,
          title: Text(context.text('completionSounds')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(completionSounds: value),
          ),
        ),
        AppSwitchListTile(
          value: config.hapticFeedback,
          title: Text(context.text('hapticFeedback')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(hapticFeedback: value),
          ),
        ),
        const SizedBox(height: 16),
        Text(context.text('browserPrivacy')),
        AppSwitchListTile(
          value: config.saveCookiesAndSessions,
          title: Text(context.text('saveCookiesSessions')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(saveCookiesAndSessions: value),
          ),
        ),
        AppSwitchListTile(
          value: config.syncBrowserTabsAndUrls,
          title: Text(context.text('syncBrowserTabsUrls')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(syncBrowserTabsAndUrls: value),
          ),
        ),
        AppSwitchListTile(
          value: config.trackBrowserActivity,
          title: Text(context.text('trackBrowserActivity')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(trackBrowserActivity: value),
          ),
        ),
        const SizedBox(height: 16),
        Text(context.text('timer')),
        AppSwitchListTile(
          value: config.askBreakActivityReview,
          title: Text(context.text('askBreakActivityReview')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(askBreakActivityReview: value),
          ),
        ),
        AppSwitchListTile(
          value: config.continueTimersAfterClose,
          title: Text(context.text('continueTimersAfterClose')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(continueTimersAfterClose: value),
          ),
        ),
        AppSwitchListTile(
          value: config.runReminderServiceInBackground,
          title: Text(context.text('runReminderServiceInBackground')),
          onChanged: (value) => _updateOnboardingConfig(
            context,
            (config) => config.copyWith(runReminderServiceInBackground: value),
          ),
        ),
      ],
    );
  }
}

class _StepShell extends StatelessWidget {
  const _StepShell({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        ...children,
      ],
    );
  }
}

class _OnboardingGrid extends StatelessWidget {
  const _OnboardingGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 2 : 1;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: columns == 1 ? 5.6 : 4.2,
          children: children,
        );
      },
    );
  }
}

class _OnboardingTimeField extends StatelessWidget {
  const _OnboardingTimeField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(text: value),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.schedule_outlined),
      ),
      onTap: () => _pickTime(context),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDayFromStorage(value),
    );
    if (picked == null) return;
    onChanged(_formatTimeStorage(picked));
  }
}

class _OnboardingNumberField extends StatelessWidget {
  const _OnboardingNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) {
        final parsed = int.tryParse(value);
        if (parsed != null && parsed >= 0) {
          onChanged(parsed);
        }
      },
    );
  }
}

DropdownMenuItem<String> _dropdownItem(
  BuildContext context,
  String value,
  String key,
) {
  return DropdownMenuItem(value: value, child: Text(context.text(key)));
}

void _updateOnboardingConfig(
  BuildContext context,
  AppConfig Function(AppConfig config) buildConfig,
) {
  final services = AppServices.of(context);
  services.feedbackService.playUiClick();
  services.updateConfig(buildConfig(services.config));
}

int _sleepMinutes(AppConfig config) {
  final start = _minutesFromTime(config.bedtime);
  final end = _minutesFromTime(config.wakeUpTime);
  if (start == null || end == null) {
    return 999;
  }
  return end >= start ? end - start : (24 * 60 - start) + end;
}

int? _minutesFromTime(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return null;
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }
  return hour * 60 + minute;
}

TimeOfDay _timeOfDayFromStorage(String value) {
  final parts = value.split(':');
  final hour = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
  return TimeOfDay(
    hour: (hour ?? 9).clamp(0, 23),
    minute: (minute ?? 0).clamp(0, 59),
  );
}

String _formatTimeStorage(TimeOfDay time) {
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

class _DayOption {
  const _DayOption(this.value, this.labelKey);

  final int value;
  final String labelKey;
}

const _dayOptions = [
  _DayOption(1, 'monday'),
  _DayOption(2, 'tuesday'),
  _DayOption(3, 'wednesday'),
  _DayOption(4, 'thursday'),
  _DayOption(5, 'friday'),
  _DayOption(6, 'saturday'),
  _DayOption(7, 'sunday'),
];

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value.isEmpty ? '-' : value),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
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
    final totalSteps = 5;
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
        _InfoLine(label: context.text('wakeUpTime'), value: config.wakeUpTime),
        _InfoLine(label: context.text('bedtime'), value: config.bedtime),
        _InfoLine(
          label: context.text('workStartTime'),
          value: config.workStartTime,
        ),
        _InfoLine(
          label: context.text('workEndTime'),
          value: config.workEndTime,
        ),
        Text(context.text('adjustScheduleInSettings')),
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

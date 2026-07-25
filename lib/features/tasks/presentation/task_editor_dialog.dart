import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/task_repository.dart';

class TaskEditorDialog extends ConsumerStatefulWidget {
  const TaskEditorDialog({this.task, this.initialDate, super.key});

  final LocalTask? task;
  final DateTime? initialDate;

  static Future<void> show(
    BuildContext context, {
    LocalTask? task,
    DateTime? initialDate,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskEditorDialog(task: task, initialDate: initialDate),
    );
  }

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _stepScrollController = ScrollController();
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _duration;
  late final TextEditingController _minimumDuration;
  late final TextEditingController _maximumDuration;
  late final TextEditingController _preparationDuration;
  late final TextEditingController _pomodoroFocus;
  late final TextEditingController _shortBreak;
  late final TextEditingController _longBreak;
  String? _domainId;
  String? _roadmapId;
  String? _roadmapPhaseId;
  String _executionMode = 'manual';
  String _completionMethod = 'manual';
  String _idleBehavior = 'detect';
  String _overtimeBehavior = 'ask';
  int _priority = 2;
  DateTime _scheduledDate = DateTime.now();
  DateTime? _plannedStart;
  DateTime? _plannedEnd;
  DateTime? _dueAt;
  String _recurrence = 'none';
  final Set<int> _weekdays = {};
  DateTime? _recurrenceEnd;
  bool _automaticTransitions = false;
  bool _busy = false;
  int _step = 0;

  bool get _editing => widget.task != null;

  void _setStep(int value) {
    setState(() => _step = value.clamp(0, 4));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stepScrollController.hasClients) return;
      final target = (_step * 145.0).clamp(
        0.0,
        _stepScrollController.position.maxScrollExtent,
      );
      _stepScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    final config = _decodeConfiguration(task?.dataJson);
    _title = TextEditingController(text: task?.title ?? '');
    _description = TextEditingController(text: task?.description ?? '');
    _duration = TextEditingController(
      text: ((task?.estimatedDurationMs ?? 1800000) ~/ 60000).toString(),
    );
    _minimumDuration = TextEditingController(
      text: ((config['minimum_useful_duration_ms'] as num?)?.toInt() ?? 0) == 0
          ? ''
          : (((config['minimum_useful_duration_ms'] as num).toInt()) ~/ 60000)
                .toString(),
    );
    _maximumDuration = TextEditingController(
      text:
          ((config['maximum_intended_duration_ms'] as num?)?.toInt() ?? 0) == 0
          ? ''
          : (((config['maximum_intended_duration_ms'] as num).toInt()) ~/ 60000)
                .toString(),
    );
    _preparationDuration = TextEditingController(
      text: ((config['preparation_duration_ms'] as num?)?.toInt() ?? 0) == 0
          ? ''
          : (((config['preparation_duration_ms'] as num).toInt()) ~/ 60000)
                .toString(),
    );
    _pomodoroFocus = TextEditingController(
      text:
          (((config['pomodoro_focus_ms'] as num?)?.toInt() ?? 1500000) ~/ 60000)
              .toString(),
    );
    _shortBreak = TextEditingController(
      text: (((config['short_break_ms'] as num?)?.toInt() ?? 300000) ~/ 60000)
          .toString(),
    );
    _longBreak = TextEditingController(
      text: (((config['long_break_ms'] as num?)?.toInt() ?? 900000) ~/ 60000)
          .toString(),
    );
    _domainId = task?.domainId;
    _roadmapId = task?.roadmapId;
    _roadmapPhaseId = task?.roadmapPhaseId;
    _executionMode = task?.executionMode ?? 'manual';
    _priority = task?.priority ?? 2;
    _scheduledDate =
        task?.scheduledDate?.toLocal() ?? widget.initialDate ?? DateTime.now();
    _plannedStart = task?.plannedStart?.toLocal();
    _plannedEnd = task?.plannedEnd?.toLocal();
    _dueAt = task?.dueAt?.toLocal();
    _completionMethod = config['completion_method'] as String? ?? 'manual';
    _idleBehavior = config['idle_behavior'] as String? ?? 'detect';
    _overtimeBehavior = config['overtime_behavior'] as String? ?? 'ask';
    _automaticTransitions = config['automatic_transitions'] == true;
  }

  @override
  void dispose() {
    _stepScrollController.dispose();
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _minimumDuration.dispose();
    _maximumDuration.dispose();
    _preparationDuration.dispose();
    _pomodoroFocus.dispose();
    _shortBreak.dispose();
    _longBreak.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    setState(() => _busy = true);
    try {
      final configuration = <String, Object?>{
        'minimum_useful_duration_ms': _minutes(_minimumDuration.text),
        'maximum_intended_duration_ms': _minutes(_maximumDuration.text),
        'preparation_duration_ms': _minutes(_preparationDuration.text),
        'completion_method': _completionMethod,
        'idle_behavior': _idleBehavior,
        'overtime_behavior': _overtimeBehavior,
        'pomodoro_focus_ms': _minutes(_pomodoroFocus.text),
        'short_break_ms': _minutes(_shortBreak.text),
        'long_break_ms': _minutes(_longBreak.text),
        'automatic_transitions': _automaticTransitions,
        'time_zone_behavior': 'user_local',
      };
      final draft = TaskDraft(
        title: _title.text,
        description: _description.text,
        domainId: _domainId,
        priority: _priority,
        executionMode: _executionMode,
        scheduledDate: _scheduledDate,
        plannedStart: _plannedStart,
        plannedEnd: _plannedEnd,
        dueAt: _dueAt,
        estimatedDuration: Duration(
          minutes: int.tryParse(_duration.text) ?? 30,
        ),
        roadmapId: _roadmapId,
        roadmapPhaseId: _roadmapPhaseId,
        configuration: configuration,
      );
      late final String taskId;
      if (_editing) {
        taskId = widget.task!.id;
        await ref.read(taskRepositoryProvider).updateTask(widget.task!, draft);
      } else {
        taskId = await ref.read(taskRepositoryProvider).createTask(draft);
      }
      if (_recurrence != 'none') {
        await _saveRecurrence(taskId);
      }
      unawaited(ref.read(syncServiceProvider).drainOutbox());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveRecurrence(String taskId) async {
    final entities = ref.read(entityRecordRepositoryProvider);
    final savedTask = await ref.read(taskRepositoryProvider).getTask(taskId);
    if (savedTask == null) return;
    final now = DateTime.now();
    final starts = DateTime(
      _scheduledDate.year,
      _scheduledDate.month,
      _scheduledDate.day,
    );
    var templateId = savedTask.templateId;
    LocalEntityRecord? template;
    if (templateId != null) template = await entities.get(templateId);
    if (template == null) {
      templateId = await entities.create(
        EntityRecordDraft(
          entityType: 'task_templates',
          parentId: taskId,
          title: savedTask.title,
          status: 'active',
          data: {
            'source_task_occurrence_id': taskId,
            'title': savedTask.title,
            'description': savedTask.description,
            'domain_id': savedTask.domainId,
            'priority': savedTask.priority,
            'execution_mode': savedTask.executionMode,
            'default_duration_ms': savedTask.estimatedDurationMs,
            'roadmap_id': savedTask.roadmapId,
            'roadmap_phase_id': savedTask.roadmapPhaseId,
            'execution_settings': _decodeConfiguration(savedTask.dataJson),
          },
          syncPayload: {
            'title': savedTask.title,
            'description': savedTask.description,
            'domain_id': savedTask.domainId,
            'category_id': null,
            'priority': savedTask.priority,
            'execution_mode': savedTask.executionMode,
            'default_duration_ms': savedTask.estimatedDurationMs,
            'minimum_duration_ms': _minutes(_minimumDuration.text),
            'maximum_duration_ms': _minutes(_maximumDuration.text),
            'recurrence_rule_id': null,
            'roadmap_id': savedTask.roadmapId,
            'roadmap_phase_id': savedTask.roadmapPhaseId,
            'reminder_defaults': <Object?>[],
            'execution_settings': _decodeConfiguration(savedTask.dataJson),
            'progress_settings': {'completion_method': _completionMethod},
            'data': {'source_task_occurrence_id': taskId},
          },
        ),
      );
      template = await entities.get(templateId);
    }
    final ruleData = <String, Object?>{
      'template_id': templateId,
      'source_task_occurrence_id': taskId,
      'frequency': _recurrence,
      'interval_value': 1,
      'weekdays': _weekdays.toList()..sort(),
      'starts_on': _dateOnly(starts),
      'ends_on': _recurrenceEnd == null ? null : _dateOnly(_recurrenceEnd!),
      'created_from_occurrence': true,
      'local_time': _plannedStart == null
          ? null
          : '${_plannedStart!.hour.toString().padLeft(2, '0')}:'
                '${_plannedStart!.minute.toString().padLeft(2, '0')}',
      'created_at': now.toUtc().toIso8601String(),
    };
    final rulePayload = <String, Object?>{
      'frequency': _recurrence,
      'interval_value': 1,
      'weekdays': _weekdays.toList()..sort(),
      'starts_on': _dateOnly(starts),
      'ends_on': _recurrenceEnd == null ? null : _dateOnly(_recurrenceEnd!),
      'maximum_occurrences': null,
      'paused_at': null,
      'rule_data': {
        'template_id': templateId,
        'source_task_occurrence_id': taskId,
        'created_from_occurrence': true,
        'local_time': _plannedStart == null
            ? null
            : '${_plannedStart!.hour.toString().padLeft(2, '0')}:'
                  '${_plannedStart!.minute.toString().padLeft(2, '0')}',
      },
    };
    final allRules = await entities.list(entityType: 'recurrence_rules');
    final existingRule = allRules.where((record) {
      final data = entities.decode(record);
      final remoteRuleData = data['rule_data'];
      final remoteTemplateId = remoteRuleData is Map
          ? remoteRuleData['template_id']
          : data['template_id'];
      return record.parentId == templateId || remoteTemplateId == templateId;
    }).firstOrNull;
    late final String ruleId;
    if (existingRule == null) {
      ruleId = await entities.create(
        EntityRecordDraft(
          entityType: 'recurrence_rules',
          parentId: templateId,
          secondaryParentId: taskId,
          title: '${_titleCase(_recurrence)} recurrence',
          status: 'active',
          data: ruleData,
          syncPayload: rulePayload,
        ),
      );
    } else {
      ruleId = existingRule.id;
      await entities.update(
        existingRule,
        title: '${_titleCase(_recurrence)} recurrence',
        status: 'active',
        data: ruleData,
        syncPayload: rulePayload,
      );
    }
    if (template != null) {
      final templateData = entities.decode(template);
      templateData['recurrence_rule_id'] = ruleId;
      await entities.update(
        template,
        data: templateData,
        syncPayload: {'recurrence_rule_id': ruleId},
      );
    }
    await ref
        .read(taskRepositoryProvider)
        .attachTemplate(
          taskId: taskId,
          templateId: templateId!,
          occurrenceKey: _dateOnly(starts),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 820),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing ? 'Edit task' : context.l10n.text('add_task'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 62,
              child: SingleChildScrollView(
                controller: _stepScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    for (final (index, label) in const [
                      (0, 'Basics'),
                      (1, 'Schedule'),
                      (2, 'Execution'),
                      (3, 'Roadmap'),
                      (4, 'Repeat'),
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          selected: _step == index,
                          avatar: CircleAvatar(
                            radius: 11,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          label: Text(label),
                          onSelected: (_) => _setStep(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: switch (_step) {
                    0 => _basics(),
                    1 => _schedule(),
                    2 => _execution(),
                    3 => _roadmap(),
                    _ => _repeat(),
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton.icon(
                      onPressed: () => _setStep(_step - 1),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text(context.l10n.text('cancel')),
                  ),
                  const SizedBox(width: 10),
                  if (_step < 4)
                    FilledButton.icon(
                      onPressed: () => _setStep(_step + 1),
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Continue'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(context.l10n.text('save')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _basics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _title,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: context.l10n.text('task_title'),
            prefixIcon: const Icon(Icons.task_alt),
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) ? 'A task needs a title' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _description,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: context.l10n.text('description'),
            alignLabelWithHint: true,
            prefixIcon: const Icon(Icons.notes),
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<LocalDomain>>(
          stream: ref.watch(taskRepositoryProvider).watchDomains(),
          builder: (context, snapshot) {
            final domains = snapshot.data ?? const [];
            return DropdownButtonFormField<String?>(
              initialValue: domains.any((domain) => domain.id == _domainId)
                  ? _domainId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Domain',
                prefixIcon: Icon(Icons.folder_outlined),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No domain')),
                for (final domain in domains)
                  DropdownMenuItem(value: domain.id, child: Text(domain.name)),
              ],
              onChanged: (value) => setState(() => _domainId = value),
            );
          },
        ),
        const SizedBox(height: 16),
        Text('Priority', style: Theme.of(context).textTheme.labelLarge),
        Slider(
          value: _priority.toDouble(),
          min: 0,
          max: 4,
          divisions: 4,
          label: const [
            'Low',
            'Normal',
            'Important',
            'High',
            'Critical',
          ][_priority],
          onChanged: (value) => setState(() => _priority = value.round()),
        ),
      ],
    );
  }

  Widget _schedule() {
    return Column(
      children: [
        _DateTimeField(
          label: 'Scheduled day',
          icon: Icons.calendar_today_outlined,
          value: _scheduledDate,
          dateOnly: true,
          onChanged: (value) {
            if (value != null) setState(() => _scheduledDate = value);
          },
        ),
        const SizedBox(height: 12),
        _DateTimeField(
          label: 'Planned start (local time)',
          icon: Icons.play_circle_outline,
          value: _plannedStart,
          allowClear: true,
          onChanged: (value) => setState(() => _plannedStart = value),
        ),
        const SizedBox(height: 12),
        _DateTimeField(
          label: 'Planned end (local time)',
          icon: Icons.stop_circle_outlined,
          value: _plannedEnd,
          allowClear: true,
          onChanged: (value) => setState(() => _plannedEnd = value),
        ),
        const SizedBox(height: 12),
        _DateTimeField(
          label: 'Due date and time',
          icon: Icons.event_available_outlined,
          value: _dueAt,
          allowClear: true,
          onChanged: (value) => setState(() => _dueAt = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MinutesField(
                controller: _duration,
                label: 'Estimated duration',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MinutesField(
                controller: _minimumDuration,
                label: 'Minimum useful',
                optional: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MinutesField(
                controller: _maximumDuration,
                label: 'Maximum intended',
                optional: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MinutesField(
                controller: _preparationDuration,
                label: 'Preparation',
                optional: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.public),
          title: Text('Local-time scheduling'),
          subtitle: Text(
            'You choose times in local time. Exact instants are normalized to '
            'UTC for synchronization and converted back on each device.',
          ),
        ),
      ],
    );
  }

  Widget _execution() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _executionMode,
          decoration: InputDecoration(
            labelText: context.l10n.text('execution_mode'),
            prefixIcon: const Icon(Icons.play_circle_outline),
          ),
          items: const [
            DropdownMenuItem(value: 'manual', child: Text('Manual')),
            DropdownMenuItem(value: 'pomodoro', child: Text('Pomodoro focus')),
            DropdownMenuItem(
              value: 'continuous',
              child: Text('Continuous timer'),
            ),
            DropdownMenuItem(value: 'checklist', child: Text('Checklist')),
            DropdownMenuItem(value: 'reading', child: Text('Reading')),
            DropdownMenuItem(value: 'habit', child: Text('Habit')),
            DropdownMenuItem(value: 'event', child: Text('Event')),
            DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
          ],
          onChanged: (value) =>
              setState(() => _executionMode = value ?? _executionMode),
        ),
        if (_executionMode == 'pomodoro' || _executionMode == 'hybrid') ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MinutesField(
                  controller: _pomodoroFocus,
                  label: 'Focus length',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MinutesField(
                  controller: _shortBreak,
                  label: 'Short break',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MinutesField(
                  controller: _longBreak,
                  label: 'Long break',
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _automaticTransitions,
            title: const Text('Automatic transitions'),
            subtitle: const Text('Disabled by default'),
            onChanged: (value) => setState(() => _automaticTransitions = value),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _completionMethod,
          decoration: const InputDecoration(
            labelText: 'Completion rule',
            prefixIcon: Icon(Icons.fact_check_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 'manual', child: Text('Manual approval')),
            DropdownMenuItem(
              value: 'all_required',
              child: Text('All required checklist items'),
            ),
            DropdownMenuItem(
              value: 'duration',
              child: Text('Required useful duration'),
            ),
            DropdownMenuItem(
              value: 'evidence',
              child: Text('Evidence required'),
            ),
          ],
          onChanged: (value) =>
              setState(() => _completionMethod = value ?? _completionMethod),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final idle = DropdownButtonFormField<String>(
              initialValue: _idleBehavior,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Idle behavior'),
              items: const [
                DropdownMenuItem(
                  value: 'detect',
                  child: Text('Detect and ask'),
                ),
                DropdownMenuItem(
                  value: 'count',
                  child: Text('Count with session'),
                ),
                DropdownMenuItem(
                  value: 'ignore',
                  child: Text('Exclude from active work'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _idleBehavior = value ?? _idleBehavior),
            );
            final overtime = DropdownButtonFormField<String>(
              initialValue: _overtimeBehavior,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Overtime behavior'),
              items: const [
                DropdownMenuItem(value: 'ask', child: Text('Notify and ask')),
                DropdownMenuItem(
                  value: 'continue',
                  child: Text('Continue recording'),
                ),
                DropdownMenuItem(
                  value: 'stop',
                  child: Text('Stop at planned duration'),
                ),
              ],
              onChanged: (value) => setState(
                () => _overtimeBehavior = value ?? _overtimeBehavior,
              ),
            );
            if (constraints.maxWidth < 560) {
              return Column(
                children: [idle, const SizedBox(height: 12), overtime],
              );
            }
            return Row(
              children: [
                Expanded(child: idle),
                const SizedBox(width: 10),
                Expanded(child: overtime),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _roadmap() {
    return StreamBuilder<List<LocalRoadmap>>(
      stream: ref.watch(roadmapRepositoryProvider).watchRoadmaps(),
      builder: (context, snapshot) {
        final roadmaps = snapshot.data ?? const [];
        final current = roadmaps
            .where((roadmap) => roadmap.id == _roadmapId)
            .firstOrNull;
        return Column(
          children: [
            DropdownButtonFormField<String?>(
              initialValue: current?.id,
              decoration: const InputDecoration(
                labelText: 'Roadmap',
                prefixIcon: Icon(Icons.route_outlined),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('No roadmap')),
                for (final roadmap in roadmaps)
                  DropdownMenuItem(
                    value: roadmap.id,
                    child: Text(roadmap.title),
                  ),
              ],
              onChanged: (value) => setState(() {
                _roadmapId = value;
                _roadmapPhaseId = null;
              }),
            ),
            if (current != null) ...[
              const SizedBox(height: 12),
              StreamBuilder<List<LocalEntityRecord>>(
                stream: ref
                    .watch(roadmapRepositoryProvider)
                    .watchPhases(current.id),
                builder: (context, phaseSnapshot) {
                  final phases = phaseSnapshot.data ?? const [];
                  return DropdownButtonFormField<String?>(
                    initialValue:
                        phases.any((phase) => phase.id == _roadmapPhaseId)
                        ? _roadmapPhaseId
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Phase',
                      prefixIcon: Icon(Icons.view_timeline_outlined),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Roadmap level'),
                      ),
                      for (final phase in phases)
                        DropdownMenuItem(
                          value: phase.id,
                          child: Text(phase.title),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _roadmapPhaseId = value),
                  );
                },
              ),
            ],
            const SizedBox(height: 18),
            const Card(
              child: ListTile(
                leading: Icon(Icons.sync_alt),
                title: Text('Bidirectional relationship'),
                subtitle: Text(
                  'This task appears in the selected roadmap and phase. '
                  'Accepted effort only changes roadmap progress when a '
                  'configured progress rule permits that contribution type.',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _repeat() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _recurrence,
          decoration: const InputDecoration(
            labelText: 'Recurrence',
            prefixIcon: Icon(Icons.repeat),
          ),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
            DropdownMenuItem(value: 'daily', child: Text('Daily')),
            DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
            DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
          ],
          onChanged: (value) =>
              setState(() => _recurrence = value ?? _recurrence),
        ),
        if (_recurrence == 'weekly') ...[
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              'Selected weekdays',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  selected: _weekdays.contains(day),
                  label: Text(
                    const [
                      'Mon',
                      'Tue',
                      'Wed',
                      'Thu',
                      'Fri',
                      'Sat',
                      'Sun',
                    ][day - 1],
                  ),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      _weekdays.add(day);
                    } else {
                      _weekdays.remove(day);
                    }
                  }),
                ),
            ],
          ),
        ],
        if (_recurrence != 'none') ...[
          const SizedBox(height: 16),
          _DateTimeField(
            label: 'Recurrence end (optional)',
            icon: Icons.event_busy_outlined,
            value: _recurrenceEnd,
            dateOnly: true,
            allowClear: true,
            onChanged: (value) => setState(() => _recurrenceEnd = value),
          ),
          const SizedBox(height: 14),
          const Card(
            child: ListTile(
              leading: Icon(Icons.history),
              title: Text('Occurrence history is preserved'),
              subtitle: Text(
                'Future generation uses this rule. Past task occurrences are '
                'not silently rewritten when the recurrence changes.',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MinutesField extends StatelessWidget {
  const _MinutesField({
    required this.controller,
    required this.label,
    this.optional = false,
  });

  final TextEditingController controller;
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, suffixText: 'min'),
      validator: (value) {
        if (optional && (value == null || value.trim().isEmpty)) return null;
        final number = int.tryParse(value ?? '');
        return number == null || number <= 0 ? 'Enter minutes' : null;
      },
    );
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    this.allowClear = false,
    this.dateOnly = false,
  });

  final String label;
  final IconData icon;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final initial = value ?? DateTime.now();
        final day = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime.now().subtract(const Duration(days: 3650)),
          lastDate: DateTime.now().add(const Duration(days: 7300)),
        );
        if (day == null || !context.mounted) return;
        if (dateOnly) {
          onChanged(day);
          return;
        }
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initial),
        );
        if (time == null) return;
        onChanged(
          DateTime(day.year, day.month, day.day, time.hour, time.minute),
        );
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: allowClear && value != null
              ? IconButton(
                  tooltip: 'Clear',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.clear),
                )
              : null,
        ),
        child: Text(
          value == null
              ? 'Not set'
              : dateOnly
              ? local.formatMediumDate(value!)
              : '${local.formatMediumDate(value!)} · '
                    '${local.formatTimeOfDay(TimeOfDay.fromDateTime(value!))}',
        ),
      ),
    );
  }
}

Map<String, Object?> _decodeConfiguration(String? value) {
  if (value == null || value.isEmpty) return <String, Object?>{};
  final decoded = jsonDecode(value);
  return decoded is Map
      ? Map<String, Object?>.from(decoded)
      : <String, Object?>{};
}

int _minutes(String value) => (int.tryParse(value.trim()) ?? 0) * 60000;

String _dateOnly(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _titleCase(String input) {
  if (input.isEmpty) return input;
  return '${input[0].toUpperCase()}${input.substring(1)}';
}

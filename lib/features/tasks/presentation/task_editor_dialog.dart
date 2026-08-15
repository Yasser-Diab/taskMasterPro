import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/task_repository.dart';
import '../data/task_resource_service.dart';
import '../domain/task_domain_catalog.dart';
import '../domain/task_resource_launch.dart';
import '../domain/task_schedule_policy.dart';

class TaskEditorDialog extends ConsumerStatefulWidget {
  const TaskEditorDialog({
    this.task,
    this.initialDate,
    this.initialRoadmapId,
    this.initialRoadmapPhaseId,
    super.key,
  });

  final LocalTask? task;
  final DateTime? initialDate;
  final String? initialRoadmapId;
  final String? initialRoadmapPhaseId;

  static Future<void> show(
    BuildContext context, {
    LocalTask? task,
    DateTime? initialDate,
    String? initialRoadmapId,
    String? initialRoadmapPhaseId,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TaskEditorDialog(
        task: task,
        initialDate: initialDate,
        initialRoadmapId: initialRoadmapId,
        initialRoadmapPhaseId: initialRoadmapPhaseId,
      ),
    );
  }

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _stepScrollController = ScrollController();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final _DurationParts _duration;
  late final _DurationParts _minimumDuration;
  late final _DurationParts _maximumDuration;
  late final _DurationParts _preparationDuration;
  late final _DurationParts _pomodoroFocus;
  late final _DurationParts _shortBreak;
  late final _DurationParts _longBreak;
  late final TextEditingController _longBreakAfter;
  String? _domainId;
  String? _roadmapId;
  String? _roadmapPhaseId;
  String? _roadmapMilestoneId;
  String? _roadmapCheckpointId;
  String _roadmapContributionRule = 'completion_only';
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
  bool _automaticFocus = false;
  bool _busy = false;
  int _step = 0;
  final List<_UrlResourceDraft> _resources = [];
  final List<_UrlResourceDraft> _discardedResources = [];
  final Set<String> _removedResourceIds = {};
  Future<void>? _resourceLoad;

  bool get _editing => widget.task != null;
  TaskScheduleWindow? get _scheduleWindow =>
      TaskSchedulePolicy.resolve(_plannedStart, _plannedEnd);
  Duration get _effectiveEstimatedDuration =>
      _scheduleWindow?.duration ??
      Duration(milliseconds: _duration.milliseconds);

  DateTime? get _minimumPlannedEnd => _plannedStart == null
      ? null
      : TaskSchedulePolicy.minimumPlannedEnd(_plannedStart!);

  DateTime? get _suggestedPlannedEnd {
    final start = _plannedStart;
    if (start == null) return null;
    final estimate = Duration(milliseconds: _duration.milliseconds);
    final minimum = TaskSchedulePolicy.minimumPlannedEnd(start);
    final suggested = start.add(estimate);
    return suggested.isBefore(minimum) ? minimum : suggested;
  }

  void _onPlannedStartChanged(DateTime? value) {
    setState(() {
      _plannedStart = value;
      if (value == null) return;
      _scheduledDate = DateTime(value.year, value.month, value.day);
      if (_plannedEnd != null) {
        _plannedEnd = TaskSchedulePolicy.normalizePlannedEnd(
          start: value,
          end: _plannedEnd!,
        );
      }
    });
  }

  void _onPlannedEndChanged(DateTime? value) {
    final start = _plannedStart;
    setState(() {
      _plannedEnd = value == null || start == null
          ? value
          : TaskSchedulePolicy.normalizePlannedEnd(start: start, end: value);
    });
  }

  TaskDurationBoundsViolation? get _durationBoundsViolation =>
      TaskSchedulePolicy.validateDurationBounds(
        plannedDuration: _effectiveEstimatedDuration,
        minimumUsefulDuration: Duration(
          milliseconds: _minimumDuration.milliseconds,
        ),
        maximumIntendedDuration: Duration(
          milliseconds: _maximumDuration.milliseconds,
        ),
      );

  String? _minimumDurationValidationMessage() {
    switch (_durationBoundsViolation) {
      case TaskDurationBoundsViolation.minimumExceedsPlanned:
        return context.l10n.text('task_minimum_duration_exceeds_planned');
      case TaskDurationBoundsViolation.minimumExceedsMaximum:
        return context.l10n.text('task_minimum_duration_exceeds_maximum');
      case null:
      case TaskDurationBoundsViolation.maximumBelowPlanned:
        return null;
    }
  }

  String? _maximumDurationValidationMessage() {
    switch (_durationBoundsViolation) {
      case TaskDurationBoundsViolation.maximumBelowPlanned:
        return context.l10n.text('task_maximum_duration_below_planned');
      case TaskDurationBoundsViolation.minimumExceedsMaximum:
        return context.l10n.text('task_minimum_duration_exceeds_maximum');
      case null:
      case TaskDurationBoundsViolation.minimumExceedsPlanned:
        return null;
    }
  }

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
    // `description` is the established synchronized task column. It is
    // presented as a short Note/subheading so it stays distinct from the
    // versioned entries in the task workspace Notes section.
    _note = TextEditingController(text: task?.description ?? '');
    _duration = _DurationParts.fromMilliseconds(
      task?.estimatedDurationMs ?? 1800000,
    );
    _minimumDuration = _DurationParts.fromMilliseconds(
      (config['minimum_useful_duration_ms'] as num?)?.toInt() ?? 0,
    );
    _maximumDuration = _DurationParts.fromMilliseconds(
      (config['maximum_intended_duration_ms'] as num?)?.toInt() ?? 0,
    );
    _preparationDuration = _DurationParts.fromMilliseconds(
      (config['preparation_duration_ms'] as num?)?.toInt() ?? 0,
    );
    _pomodoroFocus = _DurationParts.fromMilliseconds(
      (config['pomodoro_focus_ms'] as num?)?.toInt() ?? 1500000,
    );
    _shortBreak = _DurationParts.fromMilliseconds(
      (config['short_break_ms'] as num?)?.toInt() ?? 300000,
    );
    _longBreak = _DurationParts.fromMilliseconds(
      (config['long_break_ms'] as num?)?.toInt() ?? 900000,
    );
    _longBreakAfter = TextEditingController(
      text: ((config['long_break_after'] as num?)?.toInt() ?? 4).toString(),
    );
    _domainId = task?.domainId;
    _roadmapId = task?.roadmapId ?? widget.initialRoadmapId;
    _roadmapPhaseId = task?.roadmapPhaseId ?? widget.initialRoadmapPhaseId;
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
    _automaticTransitions =
        config['pomodoro_auto_start_breaks'] == true ||
        config['automatic_transitions'] == true;
    _automaticFocus = config['pomodoro_auto_start_focus'] == true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadRoadmapHierarchyLink());
    });
    _resourceLoad = _loadResources();
  }

  Future<void> _loadResources() async {
    final task = widget.task;
    if (task == null) return;
    final entities = ref.read(entityRecordRepositoryProvider);
    final resources = await entities.list(
      entityType: 'task_resources',
      parentId: task.id,
    );
    if (!mounted) return;
    final drafts = <_UrlResourceDraft>[];
    for (final resource in resources) {
      final data = entities.decode(resource);
      final url = taskWebsiteResourceUrl(data);
      if (url == null) continue;
      drafts.add(
        _UrlResourceDraft(
          id: resource.id,
          record: resource,
          label: resource.title,
          url: url,
          launchMode: configuredTaskResourceLaunchMode(task, data),
          position:
              (data['position'] as num?)?.toDouble() ??
              drafts.length.toDouble(),
        ),
      );
    }
    drafts.sort((left, right) => left.position.compareTo(right.position));
    setState(() => _resources.addAll(drafts));
  }

  Future<void> _loadRoadmapHierarchyLink() async {
    final task = widget.task;
    final roadmapId = task?.roadmapId;
    if (task == null || roadmapId == null) return;
    final links = await ref
        .read(roadmapRepositoryProvider)
        .watchTaskLinks(roadmapId)
        .first;
    final entities = ref.read(entityRecordRepositoryProvider);
    final link = links.where((record) {
      final data = entities.decode(record);
      return record.secondaryParentId == task.id || data['task_id'] == task.id;
    }).firstOrNull;
    if (link == null || !mounted) return;
    final data = entities.decode(link);
    setState(() {
      _roadmapMilestoneId = data['milestone_id'] as String?;
      _roadmapCheckpointId = data['checkpoint_id'] as String?;
      _roadmapContributionRule =
          data['contribution_rule'] as String? ?? 'completion_only';
    });
  }

  @override
  void dispose() {
    _stepScrollController.dispose();
    _title.dispose();
    _note.dispose();
    _duration.dispose();
    _minimumDuration.dispose();
    _maximumDuration.dispose();
    _preparationDuration.dispose();
    _pomodoroFocus.dispose();
    _shortBreak.dispose();
    _longBreak.dispose();
    _longBreakAfter.dispose();
    for (final resource in _resources) {
      resource.dispose();
    }
    for (final resource in _discardedResources) {
      resource.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    if (_plannedStart != null &&
        _plannedEnd != null &&
        _scheduleWindow == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('task_time_window_invalid'))),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _resourceLoad;
      final scheduleWindow = _scheduleWindow;
      final configuration = <String, Object?>{
        'minimum_useful_duration_ms': _minimumDuration.milliseconds,
        'maximum_intended_duration_ms': _maximumDuration.milliseconds,
        'preparation_duration_ms': _preparationDuration.milliseconds,
        'completion_method': _completionMethod,
        'idle_behavior': _idleBehavior,
        'overtime_behavior': _overtimeBehavior,
        'pomodoro_focus_ms': _pomodoroFocus.milliseconds,
        'short_break_ms': _shortBreak.milliseconds,
        'long_break_ms': _longBreak.milliseconds,
        'long_break_after':
            int.tryParse(_longBreakAfter.text.trim())?.clamp(2, 12) ?? 4,
        'automatic_transitions': _automaticTransitions,
        'pomodoro_auto_start_breaks': _automaticTransitions,
        'pomodoro_auto_start_focus': _automaticFocus,
        'time_zone_behavior': 'user_local',
        'duration_source': scheduleWindow == null
            ? 'manual_estimate'
            : 'planned_window',
        'crosses_midnight': scheduleWindow?.crossesMidnight ?? false,
      };
      final draft = TaskDraft(
        title: _title.text,
        description: _note.text,
        domainId: _domainId,
        priority: _priority,
        executionMode: _executionMode,
        scheduledDate: _scheduledDate,
        plannedStart: _plannedStart,
        plannedEnd: _plannedEnd,
        dueAt: _dueAt,
        estimatedDuration:
            scheduleWindow?.duration ??
            Duration(milliseconds: _duration.milliseconds),
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
      final previousRoadmapId = widget.task?.roadmapId;
      if (previousRoadmapId != null && previousRoadmapId != _roadmapId) {
        await ref
            .read(roadmapRepositoryProvider)
            .unlinkTask(roadmapId: previousRoadmapId, taskId: taskId);
      }
      if (_roadmapId != null) {
        await ref
            .read(roadmapRepositoryProvider)
            .upsertTaskLink(
              roadmapId: _roadmapId!,
              taskId: taskId,
              phaseId: _roadmapPhaseId,
              milestoneId: _roadmapMilestoneId,
              checkpointId: _roadmapCheckpointId,
              contributionRule: _roadmapContributionRule,
            );
        await ref
            .read(roadmapRepositoryProvider)
            .recalculateProgress(_roadmapId!);
      }
      if (_recurrence != 'none') {
        await _saveRecurrence(taskId);
      }
      await _saveResources(taskId);
      unawaited(ref.read(syncServiceProvider).drainOutbox());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveResources(String taskId) async {
    final service = ref.read(taskResourceServiceProvider);
    final entities = ref.read(entityRecordRepositoryProvider);
    for (var index = 0; index < _resources.length; index++) {
      final resource = _resources[index];
      final rawUrl = resource.url.text.trim();
      if (rawUrl.isEmpty) continue;
      if (resource.record == null) {
        await service.addUrl(
          taskId: taskId,
          url: rawUrl,
          title: resource.label.text,
          launchMode: resource.launchMode,
          position: index.toDouble(),
        );
      } else {
        await service.updateUrl(
          resource: resource.record!,
          url: rawUrl,
          title: resource.label.text,
          launchMode: resource.launchMode,
          position: index.toDouble(),
        );
      }
    }
    for (final resourceId in _removedResourceIds) {
      final record = await entities.get(resourceId);
      if (record != null) await entities.softDelete(record);
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
            'minimum_duration_ms': _minimumDuration.milliseconds,
            'maximum_duration_ms': _maximumDuration.milliseconds,
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
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 520;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 16,
        vertical: compact ? 12 : 16,
      ),
      child: SizedBox(
        width: 860,
        height: (viewport.height - (compact ? 24 : 32)).clamp(360.0, 820.0),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                compact ? 16 : 24,
                compact ? 12 : 18,
                compact ? 6 : 14,
                8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing
                          ? context.l10n.text('task_edit')
                          : context.l10n.text('add_task'),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.text('close'),
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
                    for (final (index, key) in const [
                      (0, 'task_editor_basics'),
                      (1, 'task_editor_schedule'),
                      (2, 'task_editor_execution'),
                      (3, 'roadmaps'),
                      (4, 'task_editor_repeat'),
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
                          label: Text(context.l10n.text(key)),
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
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.all(compact ? 16 : 24),
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
              padding: EdgeInsets.all(compact ? 10 : 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final previous = _step > 0
                      ? TextButton.icon(
                          onPressed: () => _setStep(_step - 1),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(context.l10n.text('back')),
                        )
                      : null;
                  final cancel = TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: Text(context.l10n.text('cancel')),
                  );
                  final primary = _step < 4
                      ? FilledButton.icon(
                          onPressed: () => _setStep(_step + 1),
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(context.l10n.text('continue')),
                        )
                      : FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(context.l10n.text('save')),
                        );
                  if (constraints.maxWidth < 390) {
                    return Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      runSpacing: 4,
                      children: [?previous, cancel, primary],
                    );
                  }
                  return Row(
                    children: [
                      ?previous,
                      const Spacer(),
                      cancel,
                      const SizedBox(width: 10),
                      primary,
                    ],
                  );
                },
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
          validator: (value) => (value?.trim().isEmpty ?? true)
              ? context.l10n.text('task_title_required')
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _note,
          minLines: 2,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.text('task_subheading_note'),
            hintText: context.l10n.text('task_subheading_note_hint'),
            helperText: context.l10n.text('task_subheading_note_detail'),
            alignLabelWithHint: true,
            prefixIcon: const Icon(Icons.short_text_rounded),
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
              decoration: InputDecoration(
                labelText: context.l10n.text('task_domain'),
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l10n.text('task_no_domain')),
                ),
                for (final domain in domains)
                  DropdownMenuItem(
                    value: domain.id,
                    child: Text(_domainDisplayName(domain)),
                  ),
              ],
              onChanged: (value) => setState(() => _domainId = value),
            );
          },
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: _showCreateDomainDialog,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: Text(context.l10n.text('task_domain_create')),
          ),
        ),
        const Divider(height: 28),
        _resourcesEditor(),
        const SizedBox(height: 16),
        Text(
          context.l10n.text('priority'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Slider(
          value: _priority.toDouble(),
          min: 0,
          max: 4,
          divisions: 4,
          label: context.l10n.text(
            const [
              'priority_low',
              'priority_normal',
              'priority_important',
              'priority_high',
              'priority_critical',
            ][_priority],
          ),
          onChanged: (value) => setState(() => _priority = value.round()),
        ),
      ],
    );
  }

  String _domainDisplayName(LocalDomain domain) {
    final userId =
        ref.read(supabaseClientProvider).auth.currentUser?.id ?? 'local';
    final key = TaskDomainCatalog.builtInKeyForId(userId, domain.id);
    return key == null
        ? domain.name
        : context.l10n.text(TaskDomainCatalog.localizationKey(key));
  }

  Future<void> _showCreateDomainDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.text('task_domain_create')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.text('task_domain_name'),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.l10n.text('create')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final id = await ref
        .read(taskRepositoryProvider)
        .createCustomDomain(name: name);
    if (mounted) setState(() => _domainId = id);
  }

  Widget _resourcesEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.link),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.text('task_resources'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    context.l10n.text('task_resources_editor_detail'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: context.l10n.text('add_url'),
              onPressed: () =>
                  setState(() => _resources.add(_UrlResourceDraft.empty())),
              icon: const Icon(Icons.add_link),
            ),
          ],
        ),
        for (var index = 0; index < _resources.length; index++) ...[
          const SizedBox(height: 12),
          _UrlResourceEditor(
            key: ValueKey(_resources[index].identity),
            resource: _resources[index],
            canMoveUp: index > 0,
            canMoveDown: index < _resources.length - 1,
            onMoveUp: () => setState(() {
              final item = _resources.removeAt(index);
              _resources.insert(index - 1, item);
            }),
            onMoveDown: () => setState(() {
              final item = _resources.removeAt(index);
              _resources.insert(index + 1, item);
            }),
            onDelete: () => setState(() {
              final removed = _resources.removeAt(index);
              if (removed.id != null) _removedResourceIds.add(removed.id!);
              _discardedResources.add(removed);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.text('task_resource_removed_pending'),
                    ),
                    action: SnackBarAction(
                      label: context.l10n.text('undo'),
                      onPressed: () {
                        if (!mounted) return;
                        setState(() {
                          _discardedResources.remove(removed);
                          _removedResourceIds.remove(removed.id);
                          _resources.insert(
                            index.clamp(0, _resources.length),
                            removed,
                          );
                        });
                      },
                    ),
                  ),
                );
            }),
          ),
        ],
      ],
    );
  }

  Widget _schedule() {
    final scheduleWindow = _scheduleWindow;
    return Column(
      children: [
        _DateTimeField(
          label: context.l10n.text('task_scheduled_day'),
          icon: Icons.calendar_today_outlined,
          value: _scheduledDate,
          dateOnly: true,
          onChanged: (value) {
            if (value != null) setState(() => _scheduledDate = value);
          },
        ),
        const SizedBox(height: 12),
        _DateTimeField(
          label: context.l10n.text('task_planned_start_local'),
          icon: Icons.play_circle_outline,
          value: _plannedStart,
          allowClear: true,
          onChanged: _onPlannedStartChanged,
        ),
        const SizedBox(height: 12),
        _DateTimeField(
          label: context.l10n.text('task_planned_end_local'),
          icon: Icons.stop_circle_outlined,
          value: _plannedEnd,
          allowClear: true,
          minimum: _minimumPlannedEnd,
          suggestedValue: _suggestedPlannedEnd,
          onChanged: _onPlannedEndChanged,
        ),
        const SizedBox(height: 12),
        _DateTimeField(
          label: context.l10n.text('task_due_date_time'),
          icon: Icons.event_available_outlined,
          value: _dueAt,
          allowClear: true,
          onChanged: (value) => setState(() => _dueAt = value),
        ),
        const SizedBox(height: 12),
        _durationRow(
          context,
          scheduleWindow == null
              ? _DurationField(
                  parts: _duration,
                  label: context.l10n.text('task_estimated_duration'),
                )
              : _CalculatedDurationField(window: scheduleWindow),
          _DurationField(
            parts: _minimumDuration,
            label: context.l10n.text('task_minimum_useful'),
            optional: true,
            semanticValidator: _minimumDurationValidationMessage,
          ),
        ),
        const SizedBox(height: 12),
        _durationRow(
          context,
          _DurationField(
            parts: _maximumDuration,
            label: context.l10n.text('task_maximum_intended'),
            optional: true,
            semanticValidator: _maximumDurationValidationMessage,
          ),
          _DurationField(
            parts: _preparationDuration,
            label: context.l10n.text('task_preparation'),
            optional: true,
          ),
        ),
        const SizedBox(height: 14),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.public),
          title: Text(context.l10n.text('task_local_scheduling')),
          subtitle: Text(context.l10n.text('task_local_scheduling_detail')),
        ),
      ],
    );
  }

  Widget _durationRow(BuildContext context, Widget first, Widget second) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 10),
            Expanded(child: second),
          ],
        );
      },
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
          items: [
            for (final mode in const [
              'manual',
              'pomodoro',
              'continuous',
              'checklist',
              'reading',
              'habit',
              'event',
              'hybrid',
            ])
              DropdownMenuItem(
                value: mode,
                child: Text(context.l10n.executionMode(mode)),
              ),
          ],
          onChanged: (value) =>
              setState(() => _executionMode = value ?? _executionMode),
        ),
        if (_executionMode == 'pomodoro' || _executionMode == 'hybrid') ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final fields = [
                _DurationField(
                  parts: _pomodoroFocus,
                  label: context.l10n.text('task_focus_length'),
                ),
                _DurationField(
                  parts: _shortBreak,
                  label: context.l10n.text('task_short_break'),
                ),
                _DurationField(
                  parts: _longBreak,
                  label: context.l10n.text('task_long_break'),
                ),
              ];
              if (constraints.maxWidth < 680) {
                return Column(
                  children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1],
                    const SizedBox(height: 12),
                    fields[2],
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[2]),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _longBreakAfter,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.text('pomodoro_long_break_after'),
              helperText: context.l10n.text('pomodoro_long_break_after_help'),
              prefixIcon: const Icon(Icons.repeat_rounded),
            ),
            validator: (value) {
              final count = int.tryParse(value?.trim() ?? '');
              if (count == null || count < 2 || count > 12) {
                return context.l10n.text('pomodoro_long_break_after_error');
              }
              return null;
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _automaticTransitions,
            title: Text(context.l10n.text('pomodoro_auto_start_breaks')),
            subtitle: Text(
              context.l10n.text('pomodoro_auto_start_breaks_detail'),
            ),
            onChanged: (value) => setState(() => _automaticTransitions = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _automaticFocus,
            title: Text(context.l10n.text('pomodoro_auto_start_focus')),
            subtitle: Text(
              context.l10n.text('pomodoro_auto_start_focus_detail'),
            ),
            onChanged: (value) => setState(() => _automaticFocus = value),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _completionMethod,
          decoration: InputDecoration(
            labelText: context.l10n.text('task_completion_rule'),
            prefixIcon: const Icon(Icons.fact_check_outlined),
          ),
          items: [
            DropdownMenuItem(
              value: 'manual',
              child: Text(context.l10n.text('task_manual_approval')),
            ),
            DropdownMenuItem(
              value: 'all_required',
              child: Text(context.l10n.text('task_all_required_items')),
            ),
            DropdownMenuItem(
              value: 'duration',
              child: Text(context.l10n.text('task_required_duration')),
            ),
            DropdownMenuItem(
              value: 'evidence',
              child: Text(context.l10n.text('task_evidence_required')),
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
              decoration: InputDecoration(
                labelText: context.l10n.text('task_idle_behavior'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'detect',
                  child: Text(context.l10n.text('task_idle_detect')),
                ),
                DropdownMenuItem(
                  value: 'count',
                  child: Text(context.l10n.text('task_idle_count')),
                ),
                DropdownMenuItem(
                  value: 'ignore',
                  child: Text(context.l10n.text('task_idle_exclude')),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _idleBehavior = value ?? _idleBehavior),
            );
            final overtime = DropdownButtonFormField<String>(
              initialValue: _overtimeBehavior,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.text('task_overtime_behavior'),
              ),
              items: [
                DropdownMenuItem(
                  value: 'ask',
                  child: Text(context.l10n.text('task_overtime_ask')),
                ),
                DropdownMenuItem(
                  value: 'continue',
                  child: Text(context.l10n.text('task_overtime_continue')),
                ),
                DropdownMenuItem(
                  value: 'stop',
                  child: Text(context.l10n.text('task_overtime_stop')),
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
              isExpanded: true,
              initialValue: current?.id,
              decoration: InputDecoration(
                labelText: context.l10n.text('roadmap_title'),
                prefixIcon: const Icon(Icons.route_outlined),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: _dropdownLabel(context.l10n.text('task_no_roadmap')),
                ),
                for (final roadmap in roadmaps)
                  DropdownMenuItem(
                    value: roadmap.id,
                    child: _dropdownLabel(roadmap.title),
                  ),
              ],
              onChanged: (value) => setState(() {
                _roadmapId = value;
                _roadmapPhaseId = null;
                _roadmapMilestoneId = null;
                _roadmapCheckpointId = null;
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
                    isExpanded: true,
                    initialValue:
                        phases.any((phase) => phase.id == _roadmapPhaseId)
                        ? _roadmapPhaseId
                        : null,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('task_roadmap_phase'),
                      prefixIcon: const Icon(Icons.view_timeline_outlined),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: _dropdownLabel(
                          context.l10n.text('task_roadmap_level'),
                        ),
                      ),
                      for (final phase in phases)
                        DropdownMenuItem(
                          value: phase.id,
                          child: _dropdownLabel(phase.title),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _roadmapPhaseId = value;
                      _roadmapMilestoneId = null;
                      _roadmapCheckpointId = null;
                    }),
                  );
                },
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<LocalEntityRecord>>(
                stream: ref
                    .watch(roadmapRepositoryProvider)
                    .watchMilestones(current.id),
                builder: (context, milestoneSnapshot) {
                  final milestones = (milestoneSnapshot.data ?? const [])
                      .where(
                        (milestone) =>
                            milestone.secondaryParentId == null ||
                            milestone.secondaryParentId == _roadmapPhaseId,
                      )
                      .toList();
                  return DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue:
                        milestones.any(
                          (milestone) => milestone.id == _roadmapMilestoneId,
                        )
                        ? _roadmapMilestoneId
                        : null,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('roadmap_milestone'),
                      prefixIcon: const Icon(Icons.flag_outlined),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: _dropdownLabel(
                          context.l10n.text('roadmap_no_milestone'),
                        ),
                      ),
                      for (final milestone in milestones)
                        DropdownMenuItem(
                          value: milestone.id,
                          child: _dropdownLabel(milestone.title),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _roadmapMilestoneId = value),
                  );
                },
              ),
              const SizedBox(height: 12),
              StreamBuilder<List<LocalEntityRecord>>(
                stream: ref
                    .watch(roadmapRepositoryProvider)
                    .watchCheckpoints(current.id),
                builder: (context, checkpointSnapshot) {
                  final checkpoints = (checkpointSnapshot.data ?? const [])
                      .where(
                        (checkpoint) =>
                            checkpoint.secondaryParentId == null ||
                            checkpoint.secondaryParentId == _roadmapPhaseId,
                      )
                      .toList();
                  return DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue:
                        checkpoints.any(
                          (checkpoint) => checkpoint.id == _roadmapCheckpointId,
                        )
                        ? _roadmapCheckpointId
                        : null,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('roadmap_checkpoint'),
                      prefixIcon: const Icon(Icons.fact_check_outlined),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: _dropdownLabel(
                          context.l10n.text('roadmap_no_checkpoint'),
                        ),
                      ),
                      for (final checkpoint in checkpoints)
                        DropdownMenuItem(
                          value: checkpoint.id,
                          child: _dropdownLabel(checkpoint.title),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _roadmapCheckpointId = value),
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _roadmapContributionRule,
                decoration: InputDecoration(
                  labelText: context.l10n.text('roadmap_contribution_rule'),
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                ),
                items: [
                  for (final rule in const [
                    'none',
                    'completion_only',
                    'approved_effort',
                    'configured_percentage',
                    'manual_review',
                  ])
                    DropdownMenuItem(
                      value: rule,
                      child: _dropdownLabel(
                        context.l10n.text('roadmap_contribution_rule_$rule'),
                      ),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _roadmapContributionRule =
                      value ?? _roadmapContributionRule,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync_alt),
                title: Text(
                  context.l10n.text('task_bidirectional_relationship'),
                ),
                subtitle: Text(context.l10n.text('task_bidirectional_detail')),
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
          decoration: InputDecoration(
            labelText: context.l10n.text('task_recurrence'),
            prefixIcon: const Icon(Icons.repeat),
          ),
          items: [
            for (final recurrence in const [
              'none',
              'daily',
              'weekly',
              'monthly',
            ])
              DropdownMenuItem(
                value: recurrence,
                child: Text(context.l10n.text('task_recurrence_$recurrence')),
              ),
          ],
          onChanged: (value) =>
              setState(() => _recurrence = value ?? _recurrence),
        ),
        if (_recurrence == 'weekly') ...[
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.l10n.text('task_selected_weekdays'),
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
                    context.l10n.text(
                      const [
                        'weekday_mon',
                        'weekday_tue',
                        'weekday_wed',
                        'weekday_thu',
                        'weekday_fri',
                        'weekday_sat',
                        'weekday_sun',
                      ][day - 1],
                    ),
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
            label: context.l10n.text('task_recurrence_end'),
            icon: Icons.event_busy_outlined,
            value: _recurrenceEnd,
            dateOnly: true,
            allowClear: true,
            onChanged: (value) => setState(() => _recurrenceEnd = value),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: Text(context.l10n.text('task_history_preserved')),
              subtitle: Text(
                context.l10n.text('task_history_preserved_detail'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _UrlResourceDraft {
  _UrlResourceDraft({
    required this.id,
    required this.record,
    required String label,
    required String url,
    required this.launchMode,
    required this.position,
  }) : identity = Object(),
       label = TextEditingController(text: label),
       url = TextEditingController(text: url);

  factory _UrlResourceDraft.empty() => _UrlResourceDraft(
    id: null,
    record: null,
    label: '',
    url: '',
    launchMode: TaskResourceLaunchMode.inApp,
    position: 0,
  );

  final Object identity;
  final String? id;
  final LocalEntityRecord? record;
  final TextEditingController label;
  final TextEditingController url;
  TaskResourceLaunchMode launchMode;
  final double position;

  void dispose() {
    label.dispose();
    url.dispose();
  }
}

class _UrlResourceEditor extends StatefulWidget {
  const _UrlResourceEditor({
    required this.resource,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    super.key,
  });

  final _UrlResourceDraft resource;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  State<_UrlResourceEditor> createState() => _UrlResourceEditorState();
}

class _UrlResourceEditorState extends State<_UrlResourceEditor> {
  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextFormField(
              controller: widget.resource.label,
              decoration: InputDecoration(
                labelText: context.l10n.text('resource_label'),
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: widget.resource.url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: context.l10n.text('url'),
                hintText: 'https://www.freecodecamp.org/learn/',
                prefixIcon: const Icon(Icons.link),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return context.l10n.text('resource_url_required');
                }
                try {
                  normalizeTaskResourceUrl(value);
                  return null;
                } on FormatException {
                  return context.l10n.text('resource_invalid_website_url');
                }
              },
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final launchMode =
                    DropdownButtonFormField<TaskResourceLaunchMode>(
                      initialValue: widget.resource.launchMode,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.l10n.text(
                          'resource_launch_behavior',
                        ),
                      ),
                      items: [
                        for (final mode in const [
                          TaskResourceLaunchMode.inApp,
                          TaskResourceLaunchMode.externalApp,
                          TaskResourceLaunchMode.externalBrowser,
                        ])
                          DropdownMenuItem(
                            value: mode,
                            child: Text(
                              context.l10n.text(switch (mode) {
                                TaskResourceLaunchMode.inApp =>
                                  'resource_open_in_app',
                                TaskResourceLaunchMode.externalApp =>
                                  'resource_open_installed_app',
                                _ => 'resource_open_external_browser',
                              }),
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => widget.resource.launchMode = value);
                      },
                    );
                final actions = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: context.l10n.text('move_up'),
                      onPressed: widget.canMoveUp ? widget.onMoveUp : null,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: context.l10n.text('move_down'),
                      onPressed: widget.canMoveDown ? widget.onMoveDown : null,
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      tooltip: context.l10n.text('delete'),
                      onPressed: widget.onDelete,
                      icon: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 480) {
                  return Column(
                    children: [
                      launchMode,
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: actions,
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: launchMode),
                    actions,
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationParts {
  _DurationParts({required int milliseconds})
    : hours = TextEditingController(text: '${milliseconds ~/ 3600000}'),
      minutes = TextEditingController(
        text: '${(milliseconds % 3600000) ~/ 60000}',
      );

  factory _DurationParts.fromMilliseconds(int milliseconds) =>
      _DurationParts(milliseconds: milliseconds.clamp(0, 0x7fffffff).toInt());

  final TextEditingController hours;
  final TextEditingController minutes;

  int get milliseconds {
    final hourValue = int.tryParse(hours.text.trim()) ?? 0;
    final minuteValue = int.tryParse(minutes.text.trim()) ?? 0;
    return ((hourValue.clamp(0, 100000).toInt() * 60) +
            minuteValue.clamp(0, 59).toInt()) *
        60000;
  }

  void dispose() {
    hours.dispose();
    minutes.dispose();
  }
}

class _CalculatedDurationField extends StatelessWidget {
  const _CalculatedDurationField({required this.window});

  final TaskScheduleWindow window;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: context.l10n.text('task_estimated_duration'),
        prefixIcon: const Icon(Icons.calculate_outlined),
        helperText: window.crossesMidnight
            ? context.l10n.text('task_crosses_midnight')
            : context.l10n.text('task_calculated_duration_help'),
      ),
      child: Text(
        context.l10n.duration(window.duration),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DurationField extends StatelessWidget {
  const _DurationField({
    required this.parts,
    required this.label,
    this.optional = false,
    this.semanticValidator,
  });

  final _DurationParts parts;
  final String label;
  final bool optional;
  final String? Function()? semanticValidator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: parts.hours,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.text('unit_hours'),
                ),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');
                  return value != null &&
                          value.trim().isNotEmpty &&
                          (number == null || number < 0)
                      ? context.l10n.text('task_enter_duration')
                      : null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: parts.minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.text('unit_minutes_short'),
                ),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');
                  if (value != null &&
                      value.trim().isNotEmpty &&
                      (number == null || number < 0 || number > 59)) {
                    return context.l10n.text('task_minutes_range');
                  }
                  final totalIsEmpty =
                      parts.hours.text.trim().isEmpty &&
                      parts.minutes.text.trim().isEmpty;
                  if (!optional && totalIsEmpty) {
                    return context.l10n.text('task_enter_duration');
                  }
                  if (!optional && parts.milliseconds <= 0) {
                    return context.l10n.text('task_enter_duration');
                  }
                  return semanticValidator?.call();
                },
              ),
            ),
          ],
        ),
      ],
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
    this.minimum,
    this.suggestedValue,
  });

  final String label;
  final IconData icon;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool allowClear;
  final bool dateOnly;
  final DateTime? minimum;
  final DateTime? suggestedValue;

  @override
  Widget build(BuildContext context) {
    final local = MaterialLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final initial = _atLeast(value ?? suggestedValue ?? DateTime.now());
        final day = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate:
              _dateOnlyMinimum ??
              DateTime.now().subtract(const Duration(days: 3650)),
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
          _atLeast(
            DateTime(day.year, day.month, day.day, time.hour, time.minute),
          ),
        );
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: allowClear && value != null
              ? IconButton(
                  tooltip: context.l10n.text('clear'),
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.clear),
                )
              : null,
        ),
        child: Text(
          value == null
              ? context.l10n.text('not_set')
              : dateOnly
              ? local.formatMediumDate(value!)
              : '${local.formatMediumDate(value!)} · '
                    '${local.formatTimeOfDay(TimeOfDay.fromDateTime(value!))}',
        ),
      ),
    );
  }

  DateTime? get _dateOnlyMinimum {
    final value = minimum;
    if (value == null) return null;
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _atLeast(DateTime value) {
    final lowerBound = minimum;
    if (lowerBound == null || !value.isBefore(lowerBound)) return value;
    return lowerBound;
  }
}

Map<String, Object?> _decodeConfiguration(String? value) {
  if (value == null || value.isEmpty) return <String, Object?>{};
  final decoded = jsonDecode(value);
  return decoded is Map
      ? Map<String, Object?>.from(decoded)
      : <String, Object?>{};
}

Widget _dropdownLabel(String value) {
  return Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
}

String _dateOnly(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _titleCase(String input) {
  if (input.isEmpty) return input;
  return '${input[0].toUpperCase()}${input.substring(1)}';
}

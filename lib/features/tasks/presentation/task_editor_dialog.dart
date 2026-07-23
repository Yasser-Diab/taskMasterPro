import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/time/time_zone_service.dart';
import '../domain/task_category.dart';
import '../domain/task_item.dart';
import '../domain/task_support_models.dart';
import '../domain/task_workspace_config.dart';

class TaskEditorResult {
  const TaskEditorResult({
    required this.task,
    required this.resources,
    required this.reminders,
    required this.scope,
  });

  final TaskItem task;
  final List<TaskResource> resources;
  final List<TaskReminder> reminders;
  final RecurrenceEditScope scope;
}

class TaskEditorDialog extends StatefulWidget {
  const TaskEditorDialog({
    required this.categories,
    this.task,
    this.resources = const [],
    this.reminders = const [],
    this.editorLinks = const TaskEditorLinks(),
    super.key,
  });

  final List<TaskCategory> categories;
  final TaskItem? task;
  final List<TaskResource> resources;
  final List<TaskReminder> reminders;
  final TaskEditorLinks editorLinks;

  @override
  State<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends State<TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;
  late final TextEditingController _locationController;
  late final TextEditingController _recurrenceRuleController;
  late final TextEditingController _timezoneController;
  late final TextEditingController _dependenciesController;
  late final TextEditingController _attachmentsController;
  late final TextEditingController _completionRulesController;
  late final TextEditingController _checklistController;

  late TaskType _taskType;
  late TaskStatus _status;
  late TaskPriority _priority;
  late TaskTrackingMode _trackingMode;
  late TaskWorkspaceType _workspaceType;
  late String _category;
  String? _projectId;
  String? _roadmapId;
  String? _phaseId;
  String? _milestoneId;
  late int _estimatedMinutes;
  late int _estimatedPomodoros;
  late bool _recurring;
  late String _recurrenceFrequency;
  late int _recurrenceInterval;
  late Set<int> _recurrenceWeekdays;
  late String _recurrenceEndType;
  late int _recurrenceCount;
  late bool _adaptiveReminders;
  late bool _calendarIntegration;
  late bool _timerEnabled;
  late DateTime? _plannedStart;
  late DateTime? _plannedEnd;
  late DateTime? _dueAt;
  late DateTime? _recurrenceEndAt;
  late List<TaskResource> _resources;
  late Set<int> _reminderOffsets;
  RecurrenceEditScope _scope = RecurrenceEditScope.occurrence;

  List<TaskCategory> get _categories =>
      widget.categories.isEmpty ? defaultLifeAreaTemplates : widget.categories;

  bool get _isEditing => widget.task != null;
  bool get _isRecurringOccurrence =>
      widget.task?.recurrenceId != null || widget.task?.seriesTaskId != null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    _notesController = TextEditingController(text: task?.notes ?? '');
    _tagsController = TextEditingController(text: task?.tags.join(', ') ?? '');
    _locationController = TextEditingController(text: task?.location ?? '');
    _recurrenceRuleController = TextEditingController(
      text: task?.recurrenceRule ?? '',
    );
    _timezoneController = TextEditingController(
      text: task?.recurrenceTimezone ?? task?.timeZoneId ?? '',
    );
    _dependenciesController = TextEditingController(
      text: task?.dependencies.join(', ') ?? '',
    );
    _attachmentsController = TextEditingController(
      text: task?.attachments.join(', ') ?? '',
    );
    _completionRulesController = TextEditingController(
      text: task?.completionRules['summary']?.toString() ?? '',
    );
    _checklistController = TextEditingController(
      text: task?.checklist.map((item) => item.title).join('\n') ?? '',
    );
    _taskType = task?.taskType ?? TaskType.focus;
    _status = task?.status ?? TaskStatus.notStarted;
    _priority = task?.priority ?? TaskPriority.normal;
    _trackingMode = task?.workspaceBrowserMode ?? TaskTrackingMode.interactive;
    _workspaceType = task?.workspaceType ?? TaskWorkspaceType.none;
    _category = _categories.any((item) => item.name == task?.category)
        ? task!.category
        : _categories.first.name;
    _projectId = _matchingProjectId(task);
    _roadmapId = _matchingRoadmapId(task?.roadmapId);
    _phaseId = _matchingPhaseId(task?.roadmapPhaseId, _roadmapId);
    _milestoneId = _matchingMilestoneId(task?.milestoneId, _roadmapId);
    _estimatedMinutes = task?.estimatedMinutes ?? 25;
    _estimatedPomodoros = task?.estimatedPomodoros ?? 1;
    _recurring =
        task?.recurrenceRule?.isNotEmpty == true ||
        task?.recurrence?.isNotEmpty == true;
    final recurrenceParts = _parseRrule(
      task?.recurrenceRule ?? task?.recurrence ?? '',
    );
    _recurrenceFrequency = switch (recurrenceParts['FREQ']) {
      'DAILY' => 'daily',
      'MONTHLY' => 'monthly',
      'YEARLY' => 'yearly',
      'WEEKLY' => 'weekly',
      _ => _recurring ? 'custom' : 'weekly',
    };
    _recurrenceInterval =
        int.tryParse(recurrenceParts['INTERVAL'] ?? '')?.clamp(1, 99) ?? 1;
    _recurrenceWeekdays = _weekdayNumbers(recurrenceParts['BYDAY']);
    _recurrenceEndType = task?.recurrenceEndType ?? 'never';
    _recurrenceCount = task?.recurrenceMaximumOccurrences ?? 10;
    _adaptiveReminders = task?.adaptiveRemindersEnabled ?? false;
    _calendarIntegration = task?.calendarIntegration ?? false;
    _timerEnabled = task?.timerEnabled ?? _taskType != TaskType.manual;
    _plannedStart = task?.plannedStartAt ?? task?.scheduledStartAt;
    if (_recurrenceWeekdays.isEmpty) {
      _recurrenceWeekdays.add(_plannedStart?.weekday ?? DateTime.now().weekday);
    }
    _plannedEnd = task?.plannedEndAt ?? task?.scheduledEndAt;
    _dueAt = task?.dueAt ?? task?.dueDate;
    _recurrenceEndAt = task?.recurrenceEndAt;
    _resources = widget.resources.isNotEmpty
        ? List<TaskResource>.of(widget.resources)
        : _legacyResources(task);
    _reminderOffsets = widget.reminders
        .map((reminder) => reminder.offsetMinutes)
        .whereType<int>()
        .toSet();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _locationController.dispose();
    _recurrenceRuleController.dispose();
    _timezoneController.dispose();
    _dependenciesController.dispose();
    _attachmentsController.dispose();
    _completionRulesController.dispose();
    _checklistController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timezoneController.text.trim().isEmpty) {
      final service = AppServices.of(context).timeZoneService;
      _timezoneController.text = service.validatedZoneId(
        service.effectiveTimeZoneId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.text(_isEditing ? 'editTask' : 'createTask'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.text('close'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_outlined),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _detailsSection(context),
                    const SizedBox(height: 12),
                    _relationshipsSection(context),
                    const SizedBox(height: 12),
                    _scheduleSection(context),
                    const SizedBox(height: 12),
                    _recurrenceSection(context),
                    const SizedBox(height: 12),
                    _resourcesSection(context),
                    const SizedBox(height: 12),
                    _remindersSection(context),
                    const SizedBox(height: 12),
                    _moreSection(context),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.text('cancel')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(context.text('saveTask')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _relationshipsSection(BuildContext context) {
    final phases =
        widget.editorLinks.phases
            .where((phase) => phase.roadmapId == _roadmapId)
            .toList()
          ..sort((a, b) => a.phaseOrder.compareTo(b.phaseOrder));
    final milestones = widget.editorLinks.milestones.where((milestone) {
      if (milestone.roadmapId != _roadmapId) return false;
      return _phaseId == null || milestone.phaseId == _phaseId;
    }).toList();

    return _EditorSection(
      title: context.text('taskRelationships'),
      icon: Icons.account_tree_outlined,
      children: [
        if (widget.editorLinks.projects.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _projectId ?? '',
            decoration: InputDecoration(labelText: context.text('project')),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(context.text('notLinked')),
              ),
              for (final project in widget.editorLinks.projects)
                DropdownMenuItem(value: project.id, child: Text(project.name)),
            ],
            onChanged: (value) => setState(
              () => _projectId = value == null || value.isEmpty ? null : value,
            ),
          ),
        if (widget.editorLinks.projects.isNotEmpty) const SizedBox(height: 12),
        if (widget.editorLinks.roadmaps.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _roadmapId ?? '',
            decoration: InputDecoration(labelText: context.text('roadmap')),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(context.text('notLinked')),
              ),
              for (final roadmap in widget.editorLinks.roadmaps)
                DropdownMenuItem(value: roadmap.id, child: Text(roadmap.title)),
            ],
            onChanged: (value) {
              setState(() {
                _roadmapId = value == null || value.isEmpty ? null : value;
                _phaseId = null;
                _milestoneId = null;
              });
            },
          ),
        if (_roadmapId != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('phase-$_roadmapId'),
            initialValue: _phaseId ?? '',
            decoration: InputDecoration(labelText: context.text('phase')),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(context.text('notLinked')),
              ),
              for (final phase in phases)
                DropdownMenuItem(
                  value: phase.id,
                  child: Text(
                    '${context.text('phase')} ${phase.phaseOrder} - ${phase.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _phaseId = value == null || value.isEmpty ? null : value;
                _milestoneId = null;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('milestone-$_roadmapId-$_phaseId'),
            initialValue: _milestoneId ?? '',
            decoration: InputDecoration(labelText: context.text('milestone')),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(context.text('notLinked')),
              ),
              for (final milestone in milestones)
                DropdownMenuItem(
                  value: milestone.id,
                  child: Text(milestone.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (value) => setState(
              () =>
                  _milestoneId = value == null || value.isEmpty ? null : value,
            ),
          ),
        ],
        if (widget.editorLinks.projects.isEmpty &&
            widget.editorLinks.roadmaps.isEmpty)
          Text(context.text('noTaskRelationships')),
      ],
    );
  }

  Widget _detailsSection(BuildContext context) {
    return _EditorSection(
      title: context.text('taskDetails'),
      icon: Icons.edit_note_outlined,
      initiallyExpanded: true,
      children: [
        TextFormField(
          controller: _titleController,
          autofocus: !_isEditing,
          decoration: InputDecoration(labelText: context.text('taskTitle')),
          validator: (value) => value?.trim().isEmpty == true
              ? context.text('taskTitleRequired')
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _descriptionController,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(labelText: context.text('description')),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<TaskType>(
                initialValue: _taskType,
                decoration: InputDecoration(
                  labelText: context.text('taskType'),
                ),
                items: [
                  for (final type in TaskType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(context.text('taskType_${type.name}')),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _taskType = value;
                    if (value == TaskType.habit || value == TaskType.manual) {
                      _timerEnabled = false;
                    }
                  });
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<TaskStatus>(
                initialValue: _status,
                decoration: InputDecoration(labelText: context.text('status')),
                items: [
                  for (final status in TaskStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(context, status)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<TaskPriority>(
                initialValue: _priority,
                decoration: InputDecoration(
                  labelText: context.text('priority'),
                ),
                items: [
                  for (final priority in TaskPriority.values)
                    DropdownMenuItem(
                      value: priority,
                      child: Text(context.text('priority_${priority.name}')),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: context.text('category'),
                ),
                items: [
                  for (final category in _categories)
                    DropdownMenuItem(
                      value: category.name,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scheduleSection(BuildContext context) {
    final showPomodoros = _taskType == TaskType.focus;
    return _EditorSection(
      title: context.text('schedule'),
      icon: Icons.calendar_month_outlined,
      initiallyExpanded: true,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DateTimeButton(
              label: context.text('plannedStart'),
              value: _plannedStart,
              onChanged: (value) => setState(() => _plannedStart = value),
            ),
            _DateTimeButton(
              label: context.text('plannedEnd'),
              value: _plannedEnd,
              onChanged: (value) => setState(() => _plannedEnd = value),
            ),
            _DateTimeButton(
              label: context.text('dueDate'),
              value: _dueAt,
              onChanged: (value) => setState(() => _dueAt = value),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text(context.text('estimatedDuration'))),
            IconButton(
              tooltip: context.text('decrease'),
              onPressed: _estimatedMinutes > 5
                  ? () => setState(() => _estimatedMinutes -= 5)
                  : null,
              icon: const Icon(Icons.remove_outlined),
            ),
            SizedBox(
              width: 92,
              child: Text(
                '$_estimatedMinutes ${context.text('minutes')}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: context.text('increase'),
              onPressed: () => setState(() => _estimatedMinutes += 5),
              icon: const Icon(Icons.add_outlined),
            ),
          ],
        ),
        if (showPomodoros)
          Row(
            children: [
              Expanded(child: Text(context.text('estimatedPomodoros'))),
              IconButton(
                onPressed: _estimatedPomodoros > 1
                    ? () => setState(() => _estimatedPomodoros -= 1)
                    : null,
                icon: const Icon(Icons.remove_outlined),
              ),
              Text('$_estimatedPomodoros'),
              IconButton(
                onPressed: () => setState(() => _estimatedPomodoros += 1),
                icon: const Icon(Icons.add_outlined),
              ),
            ],
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _timerEnabled,
          title: Text(context.text('enableTimer')),
          onChanged: (value) => setState(() => _timerEnabled = value),
        ),
        if (_taskType == TaskType.event)
          TextField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: context.text('location'),
              prefixIcon: const Icon(Icons.location_on_outlined),
            ),
          ),
      ],
    );
  }

  Widget _recurrenceSection(BuildContext context) {
    return _EditorSection(
      title: context.text('recurrence'),
      icon: Icons.repeat_outlined,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _recurring,
          title: Text(context.text('recurringTask')),
          onChanged: (value) => setState(() => _recurring = value),
        ),
        if (_recurring) ...[
          DropdownButtonFormField<String>(
            initialValue: _recurrenceFrequency,
            decoration: InputDecoration(
              labelText: context.text('repeatFrequency'),
            ),
            items: [
              for (final value in const [
                'daily',
                'weekly',
                'monthly',
                'yearly',
                'custom',
              ])
                DropdownMenuItem(
                  value: value,
                  child: Text(context.text('repeatFrequency_$value')),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _recurrenceFrequency = value);
              }
            },
          ),
          Row(
            children: [
              Expanded(child: Text(context.text('repeatEvery'))),
              IconButton(
                onPressed: _recurrenceInterval > 1
                    ? () => setState(() => _recurrenceInterval -= 1)
                    : null,
                icon: const Icon(Icons.remove_outlined),
              ),
              Text('$_recurrenceInterval'),
              IconButton(
                onPressed: () => setState(() => _recurrenceInterval += 1),
                icon: const Icon(Icons.add_outlined),
              ),
            ],
          ),
          if (_recurrenceFrequency == 'weekly') ...[
            Text(context.text('repeatOnDays')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final weekday in const [
                  DateTime.monday,
                  DateTime.tuesday,
                  DateTime.wednesday,
                  DateTime.thursday,
                  DateTime.friday,
                  DateTime.saturday,
                  DateTime.sunday,
                ])
                  FilterChip(
                    selected: _recurrenceWeekdays.contains(weekday),
                    label: Text(_weekdayLabel(context, weekday)),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _recurrenceWeekdays.add(weekday);
                      } else {
                        _recurrenceWeekdays.remove(weekday);
                      }
                    }),
                  ),
              ],
            ),
          ],
          if (_recurrenceFrequency == 'custom') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _recurrenceRuleController,
              decoration: InputDecoration(
                labelText: context.text('customRecurrenceRule'),
                hintText: 'FREQ=WEEKLY;BYDAY=MO,WE,SA',
              ),
              validator: (value) => value!.trim().isEmpty
                  ? context.text('recurrenceRuleRequired')
                  : null,
            ),
          ],
          const SizedBox(height: 12),
          _TimeZonePickerField(
            value: _timezoneController.text.trim(),
            instant: _plannedStart ?? _dueAt ?? DateTime.now(),
            onTap: _pickTimeZone,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _recurrenceEndType,
            decoration: InputDecoration(labelText: context.text('repeatEnds')),
            items: [
              for (final value in const ['never', 'on_date', 'after_count'])
                DropdownMenuItem(
                  value: value,
                  child: Text(context.text('repeatEnd_$value')),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _recurrenceEndType = value);
            },
          ),
          if (_recurrenceEndType == 'on_date') ...[
            const SizedBox(height: 12),
            _DateTimeButton(
              label: context.text('recurrenceEndDate'),
              value: _recurrenceEndAt,
              dateOnly: true,
              onChanged: (value) => setState(() => _recurrenceEndAt = value),
            ),
          ],
          if (_recurrenceEndType == 'after_count')
            Row(
              children: [
                Expanded(child: Text(context.text('occurrenceCount'))),
                IconButton(
                  onPressed: _recurrenceCount > 1
                      ? () => setState(() => _recurrenceCount -= 1)
                      : null,
                  icon: const Icon(Icons.remove_outlined),
                ),
                Text('$_recurrenceCount'),
                IconButton(
                  onPressed: () => setState(() => _recurrenceCount += 1),
                  icon: const Icon(Icons.add_outlined),
                ),
              ],
            ),
        ],
        if (_isRecurringOccurrence) ...[
          const Divider(),
          Text(context.text('applyChangesTo')),
          RadioGroup<RecurrenceEditScope>(
            groupValue: _scope,
            onChanged: (value) {
              if (value != null) setState(() => _scope = value);
            },
            child: Column(
              children: [
                for (final scope in RecurrenceEditScope.values)
                  RadioListTile<RecurrenceEditScope>(
                    value: scope,
                    title: Text(context.text('recurrenceScope_${scope.name}')),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _resourcesSection(BuildContext context) {
    return _EditorSection(
      title: context.text('urlsAndResources'),
      icon: Icons.link_outlined,
      children: [
        if (_resources.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(context.text('noTaskResources')),
          ),
        for (var index = 0; index < _resources.length; index += 1)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              _resources[index].isDefault
                  ? Icons.home_outlined
                  : Icons.link_outlined,
            ),
            title: Text(_resources[index].name),
            subtitle: Text(
              '${_resources[index].domain} · ${context.text('openMode_${_resources[index].openMode.name}')}',
            ),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: context.text('moveUp'),
                  onPressed: index == 0 ? null : () => _moveResource(index, -1),
                  icon: const Icon(Icons.arrow_upward_outlined),
                ),
                IconButton(
                  tooltip: context.text('edit'),
                  onPressed: () => _editResource(index),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: context.text('remove'),
                  onPressed: () => setState(() => _resources.removeAt(index)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _editResource(null),
            icon: const Icon(Icons.add_link_outlined),
            label: Text(context.text('addResource')),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TaskWorkspaceType>(
          initialValue: _workspaceType,
          decoration: InputDecoration(labelText: context.text('workspaceType')),
          items: [
            for (final type in TaskWorkspaceType.values)
              DropdownMenuItem(
                value: type,
                child: Text(context.text('workspaceType_${type.name}')),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _workspaceType = value);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<TaskTrackingMode>(
          initialValue: _trackingMode,
          decoration: InputDecoration(labelText: context.text('trackingMode')),
          items: [
            for (final mode in TaskTrackingMode.values)
              DropdownMenuItem(
                value: mode,
                child: Text(context.text('trackingMode_${mode.name}')),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _trackingMode = value);
          },
        ),
      ],
    );
  }

  Widget _remindersSection(BuildContext context) {
    const offsets = <int>[0, 5, 10, 15, 30, 60, 120, 1440];
    return _EditorSection(
      title: context.text('reminders'),
      icon: Icons.notifications_active_outlined,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final offset in offsets)
              FilterChip(
                selected: _reminderOffsets.contains(offset),
                label: Text(_reminderLabel(context, offset)),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _reminderOffsets.add(offset);
                    } else {
                      _reminderOffsets.remove(offset);
                    }
                  });
                },
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _adaptiveReminders,
          title: Text(context.text('adaptiveReminders')),
          subtitle: Text(context.text('adaptiveRemindersHelp')),
          onChanged: (value) => setState(() => _adaptiveReminders = value),
        ),
      ],
    );
  }

  Widget _moreSection(BuildContext context) {
    return _EditorSection(
      title: context.text('moreOptions'),
      icon: Icons.tune_outlined,
      children: [
        TextField(
          controller: _notesController,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(labelText: context.text('notes')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _checklistController,
          minLines: 2,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: context.text('checklistItems'),
            helperText: context.text('oneChecklistItemPerLine'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _tagsController,
          decoration: InputDecoration(labelText: context.text('tags')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _dependenciesController,
          decoration: InputDecoration(labelText: context.text('dependencies')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _attachmentsController,
          decoration: InputDecoration(labelText: context.text('attachments')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _completionRulesController,
          decoration: InputDecoration(
            labelText: context.text('completionRules'),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _calendarIntegration,
          title: Text(context.text('calendarIntegration')),
          onChanged: (value) => setState(() => _calendarIntegration = value),
        ),
      ],
    );
  }

  Future<void> _editResource(int? index) async {
    final existing = index == null ? null : _resources[index];
    final result = await showDialog<TaskResource>(
      context: context,
      builder: (context) => _ResourceDialog(
        taskId: widget.task?.id ?? existing?.taskId ?? '',
        resource: existing,
        makeDefault: _resources.isEmpty,
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.isDefault) {
        _resources = [
          for (final resource in _resources)
            resource.copyWith(isDefault: false),
        ];
      }
      if (index == null) {
        _resources.add(result.copyWith(sortOrder: _resources.length));
      } else {
        _resources[index] = result.copyWith(sortOrder: index);
      }
    });
  }

  void _moveResource(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _resources.length) return;
    setState(() {
      final item = _resources.removeAt(index);
      _resources.insert(target, item);
    });
  }

  Future<void> _pickTimeZone() async {
    final service = AppServices.of(context).timeZoneService;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _TimeZonePickerDialog(
        service: service,
        selectedZoneId: _timezoneController.text.trim(),
        instant: _plannedStart ?? _dueAt ?? DateTime.now(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _timezoneController.text = picked);
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    final original = widget.task;
    final base = original ?? TaskItem(title: _titleController.text.trim());
    final normalizedResources = <TaskResource>[];
    for (var index = 0; index < _resources.length; index += 1) {
      final resource = _resources[index];
      final inheritedOccurrenceResource =
          _isRecurringOccurrence &&
          _scope == RecurrenceEditScope.occurrence &&
          resource.taskId != base.id;
      normalizedResources.add(
        TaskResource(
          id: inheritedOccurrenceResource ? null : resource.id,
          taskId: base.id,
          name: resource.name,
          url: resource.url,
          type: resource.type,
          openMode: resource.openMode,
          description: resource.description,
          sortOrder: index,
          isDefault:
              resource.isDefault ||
              (_resources.every((item) => !item.isDefault) && index == 0),
          isRequired: resource.isRequired,
          isFavorite: resource.isFavorite,
          openAutomatically: resource.openAutomatically,
          seriesResourceId: inheritedOccurrenceResource
              ? resource.id
              : resource.seriesResourceId,
          isOccurrenceOverride:
              inheritedOccurrenceResource || resource.isOccurrenceOverride,
          isHidden: resource.isHidden,
          createdAt: resource.createdAt,
        ),
      );
    }
    if (_isRecurringOccurrence && _scope == RecurrenceEditScope.occurrence) {
      final retainedIds = _resources.map((resource) => resource.id).toSet();
      for (final originalResource in widget.resources) {
        if (originalResource.taskId == base.id ||
            retainedIds.contains(originalResource.id)) {
          continue;
        }
        normalizedResources.add(
          TaskResource(
            taskId: base.id,
            name: originalResource.name,
            url: originalResource.url,
            type: originalResource.type,
            openMode: originalResource.openMode,
            description: originalResource.description,
            sortOrder: normalizedResources.length,
            seriesResourceId: originalResource.id,
            isOccurrenceOverride: true,
            isHidden: true,
          ),
        );
      }
    }
    final defaultResource = normalizedResources
        .where((resource) => resource.isDefault)
        .firstOrNull;
    final selectedProject = widget.editorLinks.projects
        .where((project) => project.id == _projectId)
        .firstOrNull;
    final selectedPhase = widget.editorLinks.phases
        .where((phase) => phase.id == _phaseId)
        .firstOrNull;
    final selectedTimeZone = AppServices.of(
      context,
    ).timeZoneService.validatedZoneId(_timezoneController.text.trim());
    final task = base.copyWith(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      taskType: _taskType,
      status: _status,
      priority: _priority,
      category: _category,
      projectId:
          _projectId ??
          (widget.editorLinks.projects.isEmpty ? base.projectId : null),
      project:
          selectedProject?.name ??
          (widget.editorLinks.projects.isEmpty ? base.project : null),
      clearProject:
          widget.editorLinks.projects.isNotEmpty && _projectId == null,
      roadmapId:
          _roadmapId ??
          (widget.editorLinks.roadmaps.isEmpty ? base.roadmapId : null),
      roadmapPhaseId:
          _phaseId ??
          (widget.editorLinks.phases.isEmpty ? base.roadmapPhaseId : null),
      roadmapPhase:
          selectedPhase?.phaseOrder ??
          (widget.editorLinks.phases.isEmpty ? base.roadmapPhase : null),
      milestoneId:
          _milestoneId ??
          (widget.editorLinks.milestones.isEmpty ? base.milestoneId : null),
      clearRoadmap:
          widget.editorLinks.roadmaps.isNotEmpty && _roadmapId == null,
      clearMilestone:
          widget.editorLinks.milestones.isNotEmpty && _milestoneId == null,
      plannedDate: _plannedStart == null
          ? null
          : DateTime(
              _plannedStart!.year,
              _plannedStart!.month,
              _plannedStart!.day,
            ),
      plannedStartAt: _plannedStart,
      plannedEndAt: _plannedEnd,
      scheduledStartAt: _plannedStart,
      scheduledEndAt: _plannedEnd,
      timeZoneId: selectedTimeZone,
      timeZoneBehavior: 'keep_local_clock',
      dueAt: _dueAt,
      dueDate: _dueAt,
      estimatedMinutes: _estimatedMinutes,
      estimatedPomodoros: _taskType == TaskType.focus ? _estimatedPomodoros : 0,
      recurrence: _recurring ? _buildRrule() : null,
      recurrenceRule: _recurring ? _buildRrule() : null,
      recurrenceTimezone: _recurring
          ? selectedTimeZone
          : base.recurrenceTimezone,
      recurrenceEndAt: _recurring && _recurrenceEndType == 'on_date'
          ? _recurrenceEndAt
          : null,
      recurrenceEndType: _recurring ? _recurrenceEndType : 'never',
      recurrenceMaximumOccurrences:
          _recurring && _recurrenceEndType == 'after_count'
          ? _recurrenceCount
          : null,
      clearRecurrence: !_recurring,
      reminderRules: {
        'offsets': _reminderOffsets.toList()..sort(),
        'adaptive': _adaptiveReminders,
      },
      adaptiveRemindersEnabled: _adaptiveReminders,
      defaultResourceId: defaultResource?.id,
      clearDefaultResource: defaultResource == null,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      clearLocation: _locationController.text.trim().isEmpty,
      calendarIntegration: _calendarIntegration,
      completionRules: {
        if (_completionRulesController.text.trim().isNotEmpty)
          'summary': _completionRulesController.text.trim(),
      },
      timerEnabled: _timerEnabled,
      workspaceEnabled:
          normalizedResources.isNotEmpty ||
          _workspaceType != TaskWorkspaceType.none,
      workspaceType: _workspaceType,
      workspaceStartingUrl: defaultResource?.url,
      workspaceResourceTitle: defaultResource?.name,
      learningResourceLink: defaultResource?.url,
      workspaceBrowserMode: _trackingMode,
      notes: _notesController.text.trim(),
      checklist: [
        for (final title in _lines(_checklistController.text))
          TaskChecklistItem(
            title: title,
            done:
                original?.checklist
                    .where((item) => item.title == title)
                    .firstOrNull
                    ?.done ??
                false,
          ),
      ],
      tags: _csv(_tagsController.text),
      dependencies: _csv(_dependenciesController.text),
      attachments: _csv(_attachmentsController.text),
    );
    final reminders = [
      for (final offset in _reminderOffsets)
        TaskReminder(
          taskId: task.id,
          offsetMinutes: offset,
          isAdaptive: false,
          scheduledAt: _plannedStart?.subtract(Duration(minutes: offset)),
        ),
      if (_adaptiveReminders)
        TaskReminder(
          taskId: task.id,
          isAdaptive: true,
          reason: context.text('adaptiveReminderReason'),
          scheduledAt: _plannedStart?.subtract(const Duration(minutes: 20)),
        ),
    ];
    Navigator.of(context).pop(
      TaskEditorResult(
        task: task,
        resources: normalizedResources,
        reminders: reminders,
        scope: _scope,
      ),
    );
  }

  static List<TaskResource> _legacyResources(TaskItem? task) {
    final url = task?.workspaceStartingUrl ?? task?.learningResourceLink;
    if (task == null || url == null || url.trim().isEmpty) return const [];
    return [
      TaskResource(
        taskId: task.id,
        name: task.workspaceResourceTitle ?? task.title,
        url: url,
        isDefault: true,
      ),
    ];
  }

  String? _matchingProjectId(TaskItem? task) {
    if (task == null) return null;
    for (final project in widget.editorLinks.projects) {
      if (project.id == task.projectId || project.name == task.project) {
        return project.id;
      }
    }
    return null;
  }

  String? _matchingRoadmapId(String? value) {
    return widget.editorLinks.roadmaps.any((roadmap) => roadmap.id == value)
        ? value
        : null;
  }

  String? _matchingPhaseId(String? value, String? roadmapId) {
    return widget.editorLinks.phases.any(
          (phase) => phase.id == value && phase.roadmapId == roadmapId,
        )
        ? value
        : null;
  }

  String? _matchingMilestoneId(String? value, String? roadmapId) {
    return widget.editorLinks.milestones.any(
          (milestone) =>
              milestone.id == value && milestone.roadmapId == roadmapId,
        )
        ? value
        : null;
  }

  String _buildRrule() {
    if (_recurrenceFrequency == 'custom') {
      return _recurrenceRuleController.text.trim();
    }
    final parts = <String>[
      'FREQ=${_recurrenceFrequency.toUpperCase()}',
      'INTERVAL=$_recurrenceInterval',
    ];
    if (_recurrenceFrequency == 'weekly' && _recurrenceWeekdays.isNotEmpty) {
      final days = _recurrenceWeekdays.toList()..sort();
      parts.add('BYDAY=${days.map(_weekdayCode).join(',')}');
    }
    if (_recurrenceEndType == 'after_count') {
      parts.add('COUNT=$_recurrenceCount');
    }
    return parts.join(';');
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      children: children,
    );
  }
}

class _TimeZonePickerField extends StatelessWidget {
  const _TimeZonePickerField({
    required this.value,
    required this.instant,
    required this.onTap,
  });

  final String value;
  final DateTime instant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final service = AppServices.of(context).timeZoneService;
    final zoneId = service.validatedZoneId(value);
    final city = _zoneCityLabel(zoneId);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: context.text('timeZone'),
          suffixIcon: const Icon(Icons.search_outlined),
        ),
        child: Text('(${service.offsetLabel(zoneId, instant: instant)}) $city'),
      ),
    );
  }
}

class _TimeZonePickerDialog extends StatefulWidget {
  const _TimeZonePickerDialog({
    required this.service,
    required this.selectedZoneId,
    required this.instant,
  });

  final TimeZoneService service;
  final String selectedZoneId;
  final DateTime instant;

  @override
  State<_TimeZonePickerDialog> createState() => _TimeZonePickerDialogState();
}

class _TimeZonePickerDialogState extends State<_TimeZonePickerDialog> {
  final _searchController = TextEditingController();
  late final List<String> _zones;

  @override
  void initState() {
    super.initState();
    _zones = widget.service.availableZoneIds();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final selected = widget.service.validatedZoneId(widget.selectedZoneId);
    final matches = _zones
        .where((zone) {
          if (query.isEmpty) {
            return zone == selected ||
                zone.startsWith('Africa/') ||
                zone.startsWith('Europe/') ||
                zone.startsWith('America/');
          }
          final normalized = zone.toLowerCase().replaceAll('_', ' ');
          final city = _zoneCityLabel(zone).toLowerCase();
          return normalized.contains(query) || city.contains(query);
        })
        .take(80)
        .toList(growable: false);

    return AlertDialog(
      title: Text(context.text('timeZone')),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.text('searchTimeZones'),
                prefixIcon: const Icon(Icons.search_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final zone = matches[index];
                  final label =
                      '(${widget.service.offsetLabel(zone, instant: widget.instant)}) ${_zoneCityLabel(zone)}';
                  return ListTile(
                    selected: zone == selected,
                    title: Text(label),
                    subtitle: Text(zone),
                    onTap: () => Navigator.of(context).pop(zone),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.text('cancel')),
        ),
      ],
    );
  }
}

String _zoneCityLabel(String zoneId) {
  final normalized = zoneId.split('/').last.replaceAll('_', ' ');
  if (normalized == 'UTC') return 'UTC';
  return normalized;
}

class _DateTimeButton extends StatelessWidget {
  const _DateTimeButton({
    required this.label,
    required this.value,
    required this.onChanged,
    this.dateOnly = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool dateOnly;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final formatted = value == null
        ? context.text('notSet')
        : dateOnly
        ? localizations.formatMediumDate(value!)
        : '${localizations.formatMediumDate(value!)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value!))}';
    return OutlinedButton.icon(
      onPressed: () => _pick(context),
      icon: const Icon(Icons.schedule_outlined),
      label: Text('$label: $formatted'),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = value ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !context.mounted) return;
    if (dateOnly) {
      onChanged(date);
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return;
    onChanged(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
  }
}

class _ResourceDialog extends StatefulWidget {
  const _ResourceDialog({
    required this.taskId,
    required this.resource,
    required this.makeDefault,
  });

  final String taskId;
  final TaskResource? resource;
  final bool makeDefault;

  @override
  State<_ResourceDialog> createState() => _ResourceDialogState();
}

class _ResourceDialogState extends State<_ResourceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _descriptionController;
  late TaskResourceType _type;
  late TaskResourceOpenMode _openMode;
  late bool _isDefault;

  @override
  void initState() {
    super.initState();
    final resource = widget.resource;
    _nameController = TextEditingController(text: resource?.name ?? '');
    _urlController = TextEditingController(text: resource?.url ?? '');
    _descriptionController = TextEditingController(
      text: resource?.description ?? '',
    );
    _type = resource?.type ?? TaskResourceType.custom;
    _openMode = resource?.openMode ?? TaskResourceOpenMode.inApp;
    _isDefault = resource?.isDefault ?? widget.makeDefault;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        context.text(widget.resource == null ? 'addResource' : 'editResource'),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.text('resourceName'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'URL'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskResourceType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: context.text('resourceType'),
                ),
                items: [
                  for (final type in TaskResourceType.values)
                    DropdownMenuItem(value: type, child: Text(type.name)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskResourceOpenMode>(
                initialValue: _openMode,
                decoration: InputDecoration(
                  labelText: context.text('openBehavior'),
                ),
                items: [
                  for (final mode in TaskResourceOpenMode.values)
                    DropdownMenuItem(
                      value: mode,
                      child: Text(context.text('openMode_${mode.name}')),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _openMode = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.text('description'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _isDefault,
                title: Text(context.text('setAsStartingPage')),
                onChanged: (value) =>
                    setState(() => _isDefault = value ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.text('cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(context.text('save'))),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    final raw = _urlController.text.trim();
    if (name.isEmpty || raw.isEmpty) return;
    final normalized = _normalizeUrl(raw);
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.text('invalidUrl'))));
      return;
    }
    final previous = widget.resource;
    Navigator.of(context).pop(
      TaskResource(
        id: previous?.id,
        taskId: widget.taskId,
        name: name,
        url: uri.toString(),
        type: _type,
        openMode: _openMode,
        description: _descriptionController.text.trim(),
        sortOrder: previous?.sortOrder ?? 0,
        isDefault: _isDefault,
        isRequired: previous?.isRequired ?? false,
        isFavorite: previous?.isFavorite ?? false,
        openAutomatically: previous?.openAutomatically ?? false,
        seriesResourceId: previous?.seriesResourceId,
        isOccurrenceOverride: previous?.isOccurrenceOverride ?? false,
        createdAt: previous?.createdAt,
      ),
    );
  }
}

String _normalizeUrl(String raw) {
  final trimmed = raw.trim();
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('javascript:') ||
      lower.startsWith('data:') ||
      lower.startsWith('vbscript:')) {
    return '';
  }
  return Uri.tryParse(trimmed)?.hasScheme == true
      ? trimmed
      : 'https://$trimmed';
}

String _statusLabel(BuildContext context, TaskStatus status) {
  return context.text('taskStatus_${status.name}');
}

String _reminderLabel(BuildContext context, int offset) {
  if (offset == 0) return context.text('atStartTime');
  if (offset == 1440) return context.text('oneDayBefore');
  if (offset >= 60) return '${offset ~/ 60} ${context.text('hoursBefore')}';
  return '$offset ${context.text('minutesBefore')}';
}

List<String> _csv(String value) {
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

List<String> _lines(String value) {
  return value
      .split(RegExp(r'[\r\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _parseRrule(String rule) {
  final result = <String, String>{};
  for (final token in rule.split(';')) {
    final separator = token.indexOf('=');
    if (separator <= 0) continue;
    result[token.substring(0, separator).trim().toUpperCase()] = token
        .substring(separator + 1)
        .trim()
        .toUpperCase();
  }
  return result;
}

Set<int> _weekdayNumbers(String? value) {
  if (value == null) return <int>{};
  return value
      .split(',')
      .map((code) {
        return switch (code.trim().toUpperCase()) {
          'MO' => DateTime.monday,
          'TU' => DateTime.tuesday,
          'WE' => DateTime.wednesday,
          'TH' => DateTime.thursday,
          'FR' => DateTime.friday,
          'SA' => DateTime.saturday,
          'SU' => DateTime.sunday,
          _ => 0,
        };
      })
      .where((day) => day > 0)
      .toSet();
}

String _weekdayCode(int weekday) => switch (weekday) {
  DateTime.monday => 'MO',
  DateTime.tuesday => 'TU',
  DateTime.wednesday => 'WE',
  DateTime.thursday => 'TH',
  DateTime.friday => 'FR',
  DateTime.saturday => 'SA',
  _ => 'SU',
};

String _weekdayLabel(BuildContext context, int weekday) => switch (weekday) {
  DateTime.monday => context.text('monday'),
  DateTime.tuesday => context.text('tuesday'),
  DateTime.wednesday => context.text('wednesday'),
  DateTime.thursday => context.text('thursday'),
  DateTime.friday => context.text('friday'),
  DateTime.saturday => context.text('saturday'),
  _ => context.text('sunday'),
};

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

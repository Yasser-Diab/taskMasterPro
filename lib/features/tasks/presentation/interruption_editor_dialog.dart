import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';

Map<String, Object?> _existingData(LocalEntityRecord? record) {
  if (record == null) return const {};
  try {
    final decoded = jsonDecode(record.dataJson);
    return decoded is Map
        ? decoded.map((key, value) => MapEntry(key.toString(), value))
        : const {};
  } catch (_) {
    return const {};
  }
}

class InterruptionEditorDialog extends ConsumerStatefulWidget {
  const InterruptionEditorDialog({
    required this.task,
    this.sessionId,
    this.existing,
    super.key,
  });

  final LocalTask task;
  final String? sessionId;
  final LocalEntityRecord? existing;

  static Future<bool> show(
    BuildContext context, {
    required LocalTask task,
    String? sessionId,
    LocalEntityRecord? existing,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => InterruptionEditorDialog(
            task: task,
            sessionId: sessionId,
            existing: existing,
          ),
        ) ??
        false;
  }

  @override
  ConsumerState<InterruptionEditorDialog> createState() =>
      _InterruptionEditorDialogState();
}

class _InterruptionEditorDialogState
    extends ConsumerState<InterruptionEditorDialog> {
  static const _types = <String>[
    'phone_call',
    'family_need',
    'work_problem',
    'visitor',
    'meeting',
    'personal_need',
    'device_internet_problem',
    'emergency',
    'distraction',
    'other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _customType = TextEditingController();
  final _responsibility = TextEditingController();
  final _hours = TextEditingController(text: '0');
  final _minutes = TextEditingController(text: '5');
  String _type = _types.first;
  DateTime _startedAt = DateTime.now();
  DateTime _endedAt = DateTime.now().add(const Duration(minutes: 5));
  bool _useEndTime = false;
  bool _necessary = true;
  bool _countsTowardCurrentTask = false;
  bool _saving = false;
  String? _relatedTaskId;
  String? _activitySegmentId;
  List<LocalTask> _tasks = const [];
  List<LocalActivitySegment> _activity = const [];

  @override
  void initState() {
    super.initState();
    _loadExisting();
    unawaited(_loadChoices());
  }

  void _loadExisting() {
    final existing = widget.existing;
    if (existing == null) return;
    final data = _existingData(existing);
    final storedType =
        data['interruption_type']?.toString().trim() ?? _types.first;
    if (_types.contains(storedType)) {
      _type = storedType;
    } else {
      _type = 'other';
      _customType.text = storedType;
    }
    _notes.text = data['notes']?.toString() ?? '';
    _responsibility.text = data['related_responsibility']?.toString() ?? '';
    _necessary = data['necessity']?.toString() != 'avoidable';
    _countsTowardCurrentTask = data['counts_toward_current_task'] == true;
    _relatedTaskId =
        existing.secondaryParentId ?? data['target_task_id']?.toString();
    _activitySegmentId = data['activity_segment_id']?.toString();
    _startedAt =
        DateTime.tryParse(data['started_at']?.toString() ?? '')?.toLocal() ??
        existing.createdAt.toLocal();
    final durationMs =
        (data['duration_ms'] as num?)?.toInt() ??
        ((data['duration_seconds'] as num?)?.toInt() ?? 0) * 1000;
    _endedAt =
        DateTime.tryParse(data['ended_at']?.toString() ?? '')?.toLocal() ??
        _startedAt.add(Duration(milliseconds: durationMs));
    final duration = Duration(
      milliseconds: durationMs > 0
          ? durationMs
          : _endedAt.difference(_startedAt).inMilliseconds,
    );
    _hours.text = duration.inHours.toString();
    _minutes.text = (duration.inMinutes.remainder(60)).toString();
  }

  @override
  void dispose() {
    _notes.dispose();
    _customType.dispose();
    _responsibility.dispose();
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Future<void> _loadChoices() async {
    final database = ref.read(databaseProvider);
    final values = await Future.wait<Object>([
      ref.read(taskRepositoryProvider).watchTasks().first,
      (database.select(database.localActivitySegments)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
            ..limit(30))
          .get(),
    ]);
    if (!mounted) return;
    setState(() {
      _tasks = (values[0] as List<LocalTask>)
          .where((task) => task.id != widget.task.id)
          .toList(growable: false);
      _activity = values[1] as List<LocalActivitySegment>;
    });
  }

  int get _durationMs {
    if (_useEndTime) {
      return _endedAt.difference(_startedAt).inMilliseconds;
    }
    final hours = int.tryParse(_hours.text.trim()) ?? 0;
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    return Duration(hours: hours, minutes: minutes).inMilliseconds;
  }

  DateTime get _effectiveEnd => _useEndTime
      ? _endedAt
      : _startedAt.add(Duration(milliseconds: _durationMs));

  Future<void> _pickDateTime({required bool start}) async {
    final initial = start ? _startedAt : _endedAt;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: initial,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final value = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _startedAt = value;
        if (_endedAt.isBefore(value)) {
          _endedAt = value.add(const Duration(minutes: 5));
        }
      } else {
        _endedAt = value;
      }
    });
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final duration = _durationMs;
    if (duration <= 0 || _effectiveEnd.isBefore(_startedAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('interruption_duration_error')),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final type = _type == 'other' && _customType.text.trim().isNotEmpty
        ? _customType.text.trim()
        : _type;
    final now = DateTime.now().toUtc();
    final startedAt = _startedAt.toUtc();
    final endedAt = _effectiveEnd.toUtc();
    final details = <String, Object?>{
      'necessity': _necessary ? 'necessary' : 'avoidable',
      'counts_toward_current_task': _countsTowardCurrentTask,
      'related_responsibility': _responsibility.text.trim().isEmpty
          ? null
          : _responsibility.text.trim(),
      'activity_segment_id': _activitySegmentId,
      'duration_ms': duration,
      'recorded_at':
          _existingData(widget.existing)['recorded_at'] ??
          now.toIso8601String(),
    };
    final repository = ref.read(entityRecordRepositoryProvider);
    final data = <String, Object?>{
      'task_occurrence_id': widget.task.id,
      'session_id':
          widget.sessionId ??
          _existingData(widget.existing)['session_id']?.toString(),
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'interruption_type': type,
      'target_task_id': _relatedTaskId,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ...details,
    };
    final syncPayload = <String, Object?>{
      'session_id': data['session_id'],
      'task_occurrence_id': widget.task.id,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'interruption_type': type,
      'target_task_id': _relatedTaskId,
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'duration_ms': duration,
      'necessity': _necessary ? 'necessary' : 'avoidable',
      'counts_toward_current_task': _countsTowardCurrentTask,
      'related_responsibility': _responsibility.text.trim().isEmpty
          ? null
          : _responsibility.text.trim(),
      'activity_segment_id': _activitySegmentId,
      'data': details,
    };
    final existing = widget.existing;
    if (existing == null) {
      await repository.create(
        EntityRecordDraft(
          entityType: 'interruptions',
          parentId: widget.task.id,
          secondaryParentId: _relatedTaskId,
          title: _displayType(context, type),
          status: 'recorded',
          data: data,
          syncPayload: syncPayload,
        ),
      );
    } else {
      await repository.update(
        existing,
        title: _displayType(context, type),
        data: data,
        syncPayload: syncPayload,
      );
    }
    unawaited(ref.read(syncServiceProvider).drainOutbox());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return AlertDialog(
      title: Text(
        l10n.text(
          widget.existing == null ? 'add_interruption' : 'edit_interruption',
        ),
      ),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.task.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: InputDecoration(
                    labelText: l10n.text('interruption_type'),
                  ),
                  items: [
                    for (final type in _types)
                      DropdownMenuItem(
                        value: type,
                        child: Text(_displayType(context, type)),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _type = value ?? _types.first),
                ),
                if (_type == 'other') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _customType,
                    decoration: InputDecoration(
                      labelText: l10n.text('interruption_custom_type'),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? l10n.text('required_field')
                        : null,
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _pickDateTime(start: true),
                  icon: const Icon(Icons.play_circle_outline),
                  label: Text(
                    '${l10n.text('interruption_start')}: '
                    '${DateFormat.yMMMd(locale).add_jm().format(_startedAt)}',
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(l10n.text('interruption_enter_duration')),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(l10n.text('interruption_enter_end')),
                    ),
                  ],
                  selected: {_useEndTime},
                  onSelectionChanged: (value) =>
                      setState(() => _useEndTime = value.first),
                ),
                const SizedBox(height: 10),
                if (_useEndTime)
                  OutlinedButton.icon(
                    onPressed: () => _pickDateTime(start: false),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      '${l10n.text('interruption_end')}: '
                      '${DateFormat.yMMMd(locale).add_jm().format(_endedAt)}',
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _hours,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.text('hours'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _minutes,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.text('minutes'),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: true,
                      icon: const Icon(Icons.shield_outlined),
                      label: Text(l10n.text('interruption_necessary')),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: const Icon(Icons.do_not_disturb_alt_outlined),
                      label: Text(l10n.text('interruption_avoidable')),
                    ),
                  ],
                  selected: {_necessary},
                  onSelectionChanged: (value) =>
                      setState(() => _necessary = value.first),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _countsTowardCurrentTask,
                  onChanged: (value) =>
                      setState(() => _countsTowardCurrentTask = value),
                  title: Text(l10n.text('interruption_counts_current_task')),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: _relatedTaskId,
                  decoration: InputDecoration(
                    labelText: l10n.text('interruption_related_task'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.text('none')),
                    ),
                    if (_relatedTaskId != null &&
                        !_tasks.any((task) => task.id == _relatedTaskId))
                      DropdownMenuItem(
                        value: _relatedTaskId,
                        child: Text(l10n.text('report_task_unavailable')),
                      ),
                    for (final task in _tasks)
                      DropdownMenuItem(value: task.id, child: Text(task.title)),
                  ],
                  onChanged: (value) => setState(() => _relatedTaskId = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _responsibility,
                  decoration: InputDecoration(
                    labelText: l10n.text('interruption_related_responsibility'),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _activitySegmentId,
                  decoration: InputDecoration(
                    labelText: l10n.text('interruption_activity_link'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.text('none')),
                    ),
                    if (_activitySegmentId != null &&
                        !_activity.any(
                          (activity) => activity.id == _activitySegmentId,
                        ))
                      DropdownMenuItem(
                        value: _activitySegmentId,
                        child: Text(l10n.text('report_record_unavailable')),
                      ),
                    for (final activity in _activity)
                      DropdownMenuItem(
                        value: activity.id,
                        child: Text(
                          activity.pageTitle ??
                              activity.windowTitle ??
                              activity.processName ??
                              activity.domain ??
                              activity.sourceType,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _activitySegmentId = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: l10n.text('notes')),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(l10n.text('cancel')),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(l10n.text('save')),
        ),
      ],
    );
  }

  static String _displayType(BuildContext context, String type) {
    final key = switch (type) {
      'phone_call' => 'interruption_type_phone_call',
      'family_need' => 'interruption_type_family_need',
      'work_problem' => 'interruption_type_work_problem',
      'visitor' => 'interruption_type_visitor',
      'meeting' => 'interruption_type_meeting',
      'personal_need' => 'interruption_type_personal_need',
      'device_internet_problem' => 'interruption_type_device_problem',
      'emergency' => 'interruption_type_emergency',
      'distraction' => 'interruption_type_distraction',
      'other' => 'interruption_type_other',
      _ => null,
    };
    return key == null ? type : context.l10n.text(key);
  }
}

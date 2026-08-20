import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../domain/vacation_period.dart';

class VacationSettingsScreen extends ConsumerStatefulWidget {
  const VacationSettingsScreen({super.key});

  @override
  ConsumerState<VacationSettingsScreen> createState() =>
      _VacationSettingsScreenState();
}

class _VacationSettingsScreenState
    extends ConsumerState<VacationSettingsScreen> {
  bool _saving = false;

  Future<void> _edit(
    List<LocalEntityRecord> templates, [
    VacationPeriod? period,
  ]) async {
    if (_saving) return;
    final draft = await showDialog<VacationPeriodDraft>(
      context: context,
      builder: (context) =>
          _VacationEditorDialog(templates: templates, period: period),
    );
    if (draft == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(vacationRepositoryProvider);
      if (period == null) {
        await repository.create(draft);
      } else {
        await repository.update(period, draft);
      }
      await _rebuildFutureSchedule();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('vacation_saved'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggle(VacationPeriod period, bool enabled) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(vacationRepositoryProvider).setEnabled(period, enabled);
      await _rebuildFutureSchedule();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(VacationPeriod period) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('vacation_delete_question')),
        content: Text(context.l10n.text('vacation_delete_explanation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(vacationRepositoryProvider).delete(period);
      await _rebuildFutureSchedule();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rebuildFutureSchedule() async {
    await ref.read(vacationScheduleCoordinatorProvider).runNow();
  }

  @override
  Widget build(BuildContext context) {
    final vacations = ref.watch(vacationRepositoryProvider);
    final entities = ref.watch(entityRecordRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('routine_and_vacations'))),
      body: StreamBuilder<List<LocalEntityRecord>>(
        stream: entities.watch(entityType: 'task_templates'),
        builder: (context, templateSnapshot) {
          final templates = templateSnapshot.data ?? const [];
          return StreamBuilder<List<VacationPeriod>>(
            stream: vacations.watch(),
            builder: (context, snapshot) {
              final periods = snapshot.data ?? const [];
              return ListView(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                ),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.beach_access_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.text('vacations_title'),
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  context.l10n.text('vacations_description'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData)
                    const Center(child: CircularProgressIndicator())
                  else if (periods.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Center(
                          child: Text(context.l10n.text('vacation_empty')),
                        ),
                      ),
                    )
                  else
                    for (final period in periods) ...[
                      _VacationCard(
                        period: period,
                        enabled: !_saving,
                        onEnabled: (value) => _toggle(period, value),
                        onEdit: () => _edit(templates, period),
                        onDelete: () => _delete(period),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      key: const ValueKey('vacation-add'),
                      onPressed: _saving ? null : () => _edit(templates),
                      icon: const Icon(Icons.add),
                      label: Text(context.l10n.text('vacation_add')),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _VacationCard extends StatelessWidget {
  const _VacationCard({
    required this.period,
    required this.enabled,
    required this.onEnabled,
    required this.onEdit,
    required this.onDelete,
  });

  final VacationPeriod period;
  final bool enabled;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    final repeat = context.l10n.text(
      'vacation_repeat_${period.recurrence.name}',
    );
    final handling = context.l10n.text(
      'vacation_handling_${period.taskPolicy.name}',
    );
    final scope = period.taskScope == VacationTaskScope.allRecurring
        ? context.l10n.text('vacation_scope_all')
        : context.l10n.format('vacation_selected_count', {
            'count': period.selectedTemplateIds.length,
          });
    return Card(
      key: ValueKey('vacation-${period.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    period.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${dates.formatMediumDate(period.startsOn)} – '
                    '${dates.formatMediumDate(period.endsOn)}',
                  ),
                  const SizedBox(height: 4),
                  Text('$repeat · $handling · $scope'),
                ],
              ),
            ),
            Switch(
              value: period.enabled,
              onChanged: enabled ? onEnabled : null,
            ),
            PopupMenuButton<String>(
              enabled: enabled,
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(context.l10n.text('edit')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(context.l10n.text('delete')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _VacationEditorDialog extends StatefulWidget {
  const _VacationEditorDialog({required this.templates, this.period});

  final List<LocalEntityRecord> templates;
  final VacationPeriod? period;

  @override
  State<_VacationEditorDialog> createState() => _VacationEditorDialogState();
}

class _VacationEditorDialogState extends State<_VacationEditorDialog> {
  late final TextEditingController _title;
  late DateTime _startsOn;
  late DateTime _endsOn;
  late VacationRecurrence _recurrence;
  late VacationTaskPolicy _taskPolicy;
  late VacationTaskScope _taskScope;
  late Set<String> _selectedTemplates;
  late bool _enabled;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    final period = widget.period;
    final today = dateOnly(DateTime.now());
    _title = TextEditingController(text: period?.title ?? '');
    _startsOn = period?.startsOn ?? today;
    _endsOn = period?.endsOn ?? today;
    _recurrence = period?.recurrence ?? VacationRecurrence.none;
    _taskPolicy = period?.taskPolicy ?? VacationTaskPolicy.postpone;
    _taskScope = period?.taskScope ?? VacationTaskScope.allRecurring;
    _selectedTemplates = {...?period?.selectedTemplateIds};
    _enabled = period?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: start ? _startsOn : _endsOn,
      firstDate: DateTime(2000),
      lastDate: DateTime(2200),
    );
    if (selected == null) return;
    setState(() {
      if (start) {
        _startsOn = selected;
        if (_endsOn.isBefore(selected)) _endsOn = selected;
      } else {
        _endsOn = selected;
      }
      _errorKey = null;
    });
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _errorKey = 'vacation_name');
      return;
    }
    if (_endsOn.isBefore(_startsOn)) {
      setState(() => _errorKey = 'vacation_invalid_range');
      return;
    }
    if (_taskScope == VacationTaskScope.selectedTemplates &&
        _selectedTemplates.isEmpty) {
      setState(() => _errorKey = 'vacation_select_one_task');
      return;
    }
    Navigator.pop(
      context,
      VacationPeriodDraft(
        title: _title.text,
        startsOn: _startsOn,
        endsOn: _endsOn,
        recurrence: _recurrence,
        taskPolicy: _taskPolicy,
        taskScope: _taskScope,
        selectedTemplateIds: _selectedTemplates,
        enabled: _enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dates = MaterialLocalizations.of(context);
    final templates = [...widget.templates]
      ..sort((a, b) => a.title.compareTo(b.title));
    return AlertDialog(
      title: Text(
        context.l10n.text(
          widget.period == null ? 'vacation_add' : 'vacation_edit',
        ),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('vacation-name'),
                controller: _title,
                decoration: InputDecoration(
                  labelText: context.l10n.text('vacation_name'),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flight_takeoff_outlined),
                title: Text(context.l10n.text('vacation_starts')),
                trailing: Text(dates.formatMediumDate(_startsOn)),
                onTap: () => _pickDate(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flight_land_outlined),
                title: Text(context.l10n.text('vacation_ends')),
                trailing: Text(dates.formatMediumDate(_endsOn)),
                onTap: () => _pickDate(false),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<VacationRecurrence>(
                initialValue: _recurrence,
                decoration: InputDecoration(
                  labelText: context.l10n.text('vacation_repeats'),
                ),
                items: [
                  for (final value in VacationRecurrence.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        context.l10n.text('vacation_repeat_${value.name}'),
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _recurrence = value ?? _recurrence),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VacationTaskPolicy>(
                initialValue: _taskPolicy,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('vacation_handling'),
                ),
                items: [
                  for (final value in VacationTaskPolicy.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(
                        context.l10n.text('vacation_handling_${value.name}'),
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _taskPolicy = value ?? _taskPolicy),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<VacationTaskScope>(
                initialValue: _taskScope,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.text('vacation_scope'),
                ),
                items: [
                  DropdownMenuItem(
                    value: VacationTaskScope.allRecurring,
                    child: Text(context.l10n.text('vacation_scope_all')),
                  ),
                  DropdownMenuItem(
                    value: VacationTaskScope.selectedTemplates,
                    child: Text(context.l10n.text('vacation_scope_selected')),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _taskScope = value ?? _taskScope),
              ),
              if (_taskScope == VacationTaskScope.selectedTemplates) ...[
                const SizedBox(height: 12),
                Text(
                  context.l10n.text('vacation_choose_tasks'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                if (templates.isEmpty)
                  Text(context.l10n.text('vacation_select_one_task'))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final template in templates)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: _selectedTemplates.contains(template.id),
                            title: Text(template.title),
                            onChanged: (selected) => setState(() {
                              selected == true
                                  ? _selectedTemplates.add(template.id)
                                  : _selectedTemplates.remove(template.id);
                            }),
                          ),
                      ],
                    ),
                  ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                title: Text(context.l10n.text('enabled')),
                onChanged: (value) => setState(() => _enabled = value),
              ),
              if (_errorKey != null)
                Text(
                  context.l10n.text(_errorKey!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(
          key: const ValueKey('vacation-save'),
          onPressed: _save,
          child: Text(context.l10n.text('save')),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../data/task_repository.dart';

class TaskEditorDialog extends ConsumerStatefulWidget {
  const TaskEditorDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const TaskEditorDialog(),
    );
  }

  @override
  ConsumerState<TaskEditorDialog> createState() => _TaskEditorDialogState();
}

class _TaskEditorDialogState extends ConsumerState<TaskEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String? _domainId;
  String _executionMode = 'manual';
  int _priority = 2;
  int _durationMinutes = 30;
  DateTime _scheduledDate = DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(taskRepositoryProvider)
          .createTask(
            TaskDraft(
              title: _title.text,
              description: _description.text,
              domainId: _domainId,
              priority: _priority,
              executionMode: _executionMode,
              scheduledDate: _scheduledDate,
              estimatedDuration: Duration(minutes: _durationMinutes),
            ),
          );
      unawaited(ref.read(syncServiceProvider).drainOutbox());
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.text('add_task'),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _title,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('task_title'),
                    prefixIcon: const Icon(Icons.task_alt),
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'A task needs a title.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
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
                      initialValue: _domainId,
                      decoration: const InputDecoration(
                        labelText: 'Domain',
                        prefixIcon: Icon(Icons.folder_outlined),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No domain'),
                        ),
                        for (final domain in domains)
                          DropdownMenuItem(
                            value: domain.id,
                            child: Text(domain.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _domainId = value),
                    );
                  },
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 500;
                    final mode = DropdownButtonFormField<String>(
                      initialValue: _executionMode,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('execution_mode'),
                        prefixIcon: const Icon(Icons.play_circle_outline),
                      ),
                      items:
                          const [
                                ('manual', 'Manual'),
                                ('pomodoro', 'Pomodoro'),
                                ('continuous', 'Continuous timer'),
                                ('checklist', 'Checklist'),
                                ('reading', 'Reading'),
                                ('habit', 'Habit'),
                                ('event', 'Event'),
                                ('hybrid', 'Hybrid'),
                              ]
                              .map(
                                (mode) => DropdownMenuItem(
                                  value: mode.$1,
                                  child: Text(mode.$2),
                                ),
                              )
                              .toList(),
                      onChanged: (value) => setState(
                        () => _executionMode = value ?? _executionMode,
                      ),
                    );
                    final duration = DropdownButtonFormField<int>(
                      initialValue: _durationMinutes,
                      decoration: InputDecoration(
                        labelText: context.l10n.text('duration'),
                        prefixIcon: const Icon(Icons.timer_outlined),
                      ),
                      items: const [10, 15, 25, 30, 45, 60, 90, 120]
                          .map(
                            (minutes) => DropdownMenuItem(
                              value: minutes,
                              child: Text('$minutes min'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(
                        () => _durationMinutes = value ?? _durationMinutes,
                      ),
                    );
                    if (!wide) {
                      return Column(
                        children: [mode, const SizedBox(height: 12), duration],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: mode),
                        const SizedBox(width: 12),
                        Expanded(child: duration),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: _scheduledDate,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (chosen != null) setState(() => _scheduledDate = chosen);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Scheduled date',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(_scheduledDate),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  context.l10n.text('priority'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Slider(
                  value: _priority.toDouble(),
                  min: 0,
                  max: 4,
                  divisions: 4,
                  label: [
                    'Low',
                    'Normal',
                    'Important',
                    'High',
                    'Critical',
                  ][_priority],
                  onChanged: (value) =>
                      setState(() => _priority = value.round()),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(context.l10n.text('cancel')),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_task),
                      label: Text(context.l10n.text('save')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

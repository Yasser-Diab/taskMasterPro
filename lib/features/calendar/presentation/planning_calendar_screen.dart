import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/database/app_database.dart';
import '../../../core/data/entity_record_repository.dart';
import '../../../core/providers.dart';
import '../../tasks/presentation/task_card.dart';
import '../../tasks/presentation/task_editor_dialog.dart';
import '../data/cycle_crypto_service.dart';

class PlanningCalendarScreen extends ConsumerStatefulWidget {
  const PlanningCalendarScreen({required this.user, super.key});

  final User user;

  @override
  ConsumerState<PlanningCalendarScreen> createState() =>
      _PlanningCalendarScreenState();
}

class _PlanningCalendarScreenState
    extends ConsumerState<PlanningCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).value;
    final taskStream = ref.watch(taskRepositoryProvider).watchTasks();
    final cycleStream = ref
        .watch(entityRecordRepositoryProvider)
        .watch(entityType: 'cycle_records');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar and history'),
        actions: [
          IconButton(
            tooltip: 'Today',
            onPressed: () => setState(() {
              _focusedDay = DateTime.now();
              _selectedDay = DateTime.now();
            }),
            icon: const Icon(Icons.today_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<LocalTask>>(
        stream: taskStream,
        builder: (context, taskSnapshot) {
          final tasks = taskSnapshot.data ?? const [];
          return StreamBuilder<List<LocalEntityRecord>>(
            stream: cycleStream,
            builder: (context, cycleSnapshot) {
              final cycleRecords = cycleSnapshot.data ?? const [];
              final selectedTasks = _tasksForDay(tasks, _selectedDay).where((
                task,
              ) {
                return settings?.calendarShowCompleted != false ||
                    task.status != 'completed';
              }).toList();
              final selectedCycle = cycleRecords
                  .where(
                    (record) => isSameDay(_cycleDate(record), _selectedDay),
                  )
                  .toList();

              return LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 980;
                  final calendar = _CalendarCard(
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    format: _format,
                    tasks: tasks,
                    cycleRecords: cycleRecords,
                    cycleEnabled: settings?.cycleTrackingEnabled ?? false,
                    onDaySelected: (selected, focused) => setState(() {
                      _selectedDay = selected;
                      _focusedDay = focused;
                    }),
                    onPageChanged: (day) => _focusedDay = day,
                    onFormatChanged: (format) =>
                        setState(() => _format = format),
                  );
                  final agenda = _Agenda(
                    selectedDay: _selectedDay,
                    tasks: selectedTasks,
                    cycleRecords: selectedCycle,
                    showCompleted: settings?.calendarShowCompleted ?? true,
                    cycleEnabled: settings?.cycleTrackingEnabled ?? false,
                    onShowCompleted: (value) => ref
                        .read(settingsRepositoryProvider)
                        .updateCalendarShowCompleted(value),
                    onAddTask: () => TaskEditorDialog.show(
                      context,
                      initialDate: _selectedDay,
                    ),
                    onAddCycle: () => _showCycleEditor(
                      storageMode: settings?.cycleStorageMode ?? 'local_only',
                    ),
                    onDeleteCycle: _deleteCycle,
                  );
                  if (wide) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: calendar),
                          const SizedBox(width: 20),
                          Expanded(flex: 6, child: agenda),
                        ],
                      ),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [calendar, const SizedBox(height: 16), agenda],
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: settings?.cycleTrackingEnabled == true
          ? FloatingActionButton.extended(
              onPressed: () => _showCycleEditor(
                storageMode: settings?.cycleStorageMode ?? 'local_only',
              ),
              icon: const Icon(Icons.water_drop_outlined),
              label: const Text('Cycle entry'),
            )
          : null,
    );
  }

  List<LocalTask> _tasksForDay(List<LocalTask> tasks, DateTime day) {
    return tasks.where((task) {
      final scheduled = task.scheduledDate;
      final finished = task.actualFinish?.toLocal();
      return (scheduled != null && isSameDay(scheduled.toLocal(), day)) ||
          (finished != null && isSameDay(finished, day));
    }).toList()..sort((a, b) {
      final aTime =
          a.plannedStart?.toLocal() ??
          a.actualFinish?.toLocal() ??
          a.scheduledDate?.toLocal() ??
          day;
      final bTime =
          b.plannedStart?.toLocal() ??
          b.actualFinish?.toLocal() ??
          b.scheduledDate?.toLocal() ??
          day;
      return aTime.compareTo(bTime);
    });
  }

  DateTime? _cycleDate(LocalEntityRecord record) {
    final data = ref.read(entityRecordRepositoryProvider).decode(record);
    return DateTime.tryParse(data['record_date'] as String? ?? '');
  }

  Future<void> _showCycleEditor({required String storageMode}) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CycleEntryDialog(
        userId: widget.user.id,
        date: _selectedDay,
        storageMode: storageMode,
      ),
    );
  }

  Future<void> _deleteCycle(LocalEntityRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete cycle entry?'),
        content: const Text(
          'This removes the selected cycle data without deleting tasks or account data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete entry'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final data = ref.read(entityRecordRepositoryProvider).decode(record);
    await ref
        .read(entityRecordRepositoryProvider)
        .softDelete(
          record,
          synchronize: data['storage_mode'] == 'encrypted_sync',
        );
    unawaited(ref.read(syncServiceProvider).drainOutbox());
  }
}

class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.focusedDay,
    required this.selectedDay,
    required this.format,
    required this.tasks,
    required this.cycleRecords,
    required this.cycleEnabled,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.onFormatChanged,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final CalendarFormat format;
  final List<LocalTask> tasks;
  final List<LocalEntityRecord> cycleRecords;
  final bool cycleEnabled;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final ValueChanged<CalendarFormat> onFormatChanged;

  @override
  Widget build(BuildContext context) {
    final eventDays = <DateTime, List<Object>>{};
    for (final task in tasks) {
      for (final date in [task.scheduledDate, task.actualFinish]) {
        if (date == null) continue;
        final local = date.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        eventDays.putIfAbsent(day, () => []).add(task);
      }
    }
    if (cycleEnabled) {
      for (final record in cycleRecords) {
        final match = RegExp(
          r'"record_date":"([^"]+)"',
        ).firstMatch(record.dataJson);
        final date = DateTime.tryParse(match?.group(1) ?? '');
        if (date != null) {
          eventDays
              .putIfAbsent(DateTime(date.year, date.month, date.day), () => [])
              .add(record);
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TableCalendar<Object>(
          firstDay: DateTime.utc(2020),
          lastDay: DateTime.utc(2045, 12, 31),
          focusedDay: focusedDay,
          selectedDayPredicate: (day) => isSameDay(selectedDay, day),
          calendarFormat: format,
          availableCalendarFormats: const {
            CalendarFormat.month: 'Month',
            CalendarFormat.twoWeeks: '2 weeks',
            CalendarFormat.week: 'Week',
          },
          eventLoader: (day) =>
              eventDays[DateTime(day.year, day.month, day.day)] ?? const [],
          onDaySelected: onDaySelected,
          onPageChanged: onPageChanged,
          onFormatChanged: onFormatChanged,
          startingDayOfWeek: StartingDayOfWeek.monday,
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiary,
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: const HeaderStyle(
            titleCentered: false,
            formatButtonVisible: true,
          ),
        ),
      ),
    );
  }
}

class _Agenda extends StatelessWidget {
  const _Agenda({
    required this.selectedDay,
    required this.tasks,
    required this.cycleRecords,
    required this.showCompleted,
    required this.cycleEnabled,
    required this.onShowCompleted,
    required this.onAddTask,
    required this.onAddCycle,
    required this.onDeleteCycle,
  });

  final DateTime selectedDay;
  final List<LocalTask> tasks;
  final List<LocalEntityRecord> cycleRecords;
  final bool showCompleted;
  final bool cycleEnabled;
  final ValueChanged<bool> onShowCompleted;
  final VoidCallback onAddTask;
  final VoidCallback onAddCycle;
  final ValueChanged<LocalEntityRecord> onDeleteCycle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE').format(selectedDay),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        DateFormat.yMMMMd().format(selectedDay),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: showCompleted,
                  onSelected: onShowCompleted,
                  avatar: const Icon(Icons.history, size: 18),
                  label: const Text('History'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onAddTask,
                  icon: const Icon(Icons.add_task),
                  label: const Text('Task'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (tasks.isEmpty && cycleRecords.isEmpty)
              const _EmptyAgenda()
            else ...[
              if (tasks.isNotEmpty) ...[
                const _AgendaHeading(
                  icon: Icons.task_alt_outlined,
                  title: 'Tasks and execution history',
                ),
                const SizedBox(height: 10),
                for (final task in tasks) ...[
                  TaskCard(task: task, compact: true),
                  const SizedBox(height: 8),
                ],
              ],
              if (cycleRecords.isNotEmpty) ...[
                const SizedBox(height: 14),
                const _AgendaHeading(
                  icon: Icons.water_drop_outlined,
                  title: 'Cycle calendar',
                ),
                const SizedBox(height: 10),
                for (final record in cycleRecords)
                  _CycleRecordCard(
                    record: record,
                    onDelete: () => onDeleteCycle(record),
                  ),
              ],
            ],
            if (cycleEnabled) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAddCycle,
                icon: const Icon(Icons.add),
                label: const Text('Add cycle entry for this day'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgendaHeading extends StatelessWidget {
  const _AgendaHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EmptyAgenda extends StatelessWidget {
  const _EmptyAgenda();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.event_available_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 10),
            const Text('No scheduled work or recorded history for this day'),
          ],
        ),
      ),
    );
  }
}

class _CycleRecordCard extends ConsumerWidget {
  const _CycleRecordCard({required this.record, required this.onDelete});

  final LocalEntityRecord record;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.read(entityRecordRepositoryProvider).decode(record);
    final started = data['period_started'] == true;
    final ended = data['period_ended'] == true;
    final flow = data['flow'] as String? ?? 'Not recorded';
    final energy = data['energy'] as String? ?? 'Not recorded';
    final symptoms = data['symptoms'] as String? ?? '';
    return Card(
      color: Theme.of(
        context,
      ).colorScheme.secondaryContainer.withValues(alpha: 0.46),
      child: ListTile(
        leading: const Icon(Icons.water_drop_outlined),
        title: Text(
          started
              ? 'Period started'
              : ended
              ? 'Period ended'
              : 'Cycle note',
        ),
        subtitle: Text(
          [
            'Flow: $flow',
            'Energy: $energy',
            if (symptoms.trim().isNotEmpty) symptoms.trim(),
          ].join(' · '),
        ),
        trailing: IconButton(
          tooltip: 'Delete cycle entry',
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _CycleEntryDialog extends ConsumerStatefulWidget {
  const _CycleEntryDialog({
    required this.userId,
    required this.date,
    required this.storageMode,
  });

  final String userId;
  final DateTime date;
  final String storageMode;

  @override
  ConsumerState<_CycleEntryDialog> createState() => _CycleEntryDialogState();
}

class _CycleEntryDialogState extends ConsumerState<_CycleEntryDialog> {
  bool _started = false;
  bool _ended = false;
  String _flow = 'not_recorded';
  String _energy = 'not_recorded';
  final _symptoms = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _symptoms.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<String?> _askPassphrase() async {
    final first = TextEditingController();
    final second = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Protect synchronized cycle data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose a passphrase used only to encrypt and decrypt cycle data on your devices. It is never uploaded.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: first,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: second,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm passphrase',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text.length >= 10 && first.text == second.text) {
                Navigator.pop(context, first.text);
              }
            },
            child: const Text('Enable encryption'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    return value;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final date = DateFormat('yyyy-MM-dd').format(widget.date);
      final data = <String, Object?>{
        'storage_mode': widget.storageMode,
        'record_date': date,
        'period_started': _started,
        'period_ended': _ended,
        'flow': _flow,
        'energy': _energy,
        'symptoms': _symptoms.text.trim(),
        'notes': _notes.text.trim(),
      };
      Map<String, Object?>? syncPayload;
      var synchronize = false;
      if (widget.storageMode == 'encrypted_sync') {
        final crypto = CycleCryptoService();
        if (!await crypto.hasKey(widget.userId)) {
          final passphrase = await _askPassphrase();
          if (passphrase == null) return;
          await crypto.setPassphrase(
            userId: widget.userId,
            passphrase: passphrase,
          );
        }
        final encrypted = await crypto.encrypt(
          userId: widget.userId,
          data: data,
        );
        syncPayload = {
          'storage_mode': 'encrypted_sync',
          'record_date': date,
          'ciphertext': encrypted.ciphertext,
          'nonce': encrypted.nonce,
        };
        synchronize = true;
      }
      await ref
          .read(entityRecordRepositoryProvider)
          .create(
            EntityRecordDraft(
              entityType: 'cycle_records',
              title: 'Cycle entry',
              status: 'recorded',
              data: data,
              syncPayload: syncPayload,
              synchronize: synchronize,
            ),
          );
      if (synchronize) {
        unawaited(ref.read(syncServiceProvider).drainOutbox());
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Cycle entry · ${DateFormat.yMMMd().format(widget.date)}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _started,
                title: const Text('Period started'),
                onChanged: (value) => setState(() => _started = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _ended,
                title: const Text('Period ended'),
                onChanged: (value) => setState(() => _ended = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _flow,
                decoration: const InputDecoration(labelText: 'Flow'),
                items: const [
                  DropdownMenuItem(
                    value: 'not_recorded',
                    child: Text('Not recorded'),
                  ),
                  DropdownMenuItem(value: 'light', child: Text('Light')),
                  DropdownMenuItem(value: 'medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'heavy', child: Text('Heavy')),
                ],
                onChanged: (value) => setState(() => _flow = value ?? _flow),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _energy,
                decoration: const InputDecoration(labelText: 'Energy'),
                items: const [
                  DropdownMenuItem(
                    value: 'not_recorded',
                    child: Text('Not recorded'),
                  ),
                  DropdownMenuItem(value: 'low', child: Text('Low')),
                  DropdownMenuItem(value: 'steady', child: Text('Steady')),
                  DropdownMenuItem(value: 'high', child: Text('High')),
                ],
                onChanged: (value) =>
                    setState(() => _energy = value ?? _energy),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _symptoms,
                decoration: const InputDecoration(
                  labelText: 'Symptoms',
                  hintText: 'Optional, separate with commas',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Private notes'),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.storageMode == 'encrypted_sync'
                      ? 'This entry is encrypted before synchronization'
                      : 'This entry stays on this device',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save entry'),
        ),
      ],
    );
  }
}

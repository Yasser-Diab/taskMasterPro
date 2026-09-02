import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';

enum _PostponeChoice { tomorrow, week, month, custom }

Future<bool> postponeTaskWithChoices(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final choice = await showModalBottomSheet<_PostponeChoice>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  sheetContext.l10n.text('task_postpone_title'),
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _PostponeOption(
                  icon: Icons.today_outlined,
                  label: sheetContext.l10n.text('task_postpone_tomorrow'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PostponeChoice.tomorrow),
                ),
                _PostponeOption(
                  icon: Icons.date_range_outlined,
                  label: sheetContext.l10n.text('task_postpone_week'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PostponeChoice.week),
                ),
                _PostponeOption(
                  icon: Icons.calendar_view_month_outlined,
                  label: sheetContext.l10n.text('task_postpone_month'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PostponeChoice.month),
                ),
                _PostponeOption(
                  icon: Icons.edit_calendar_outlined,
                  label: sheetContext.l10n.text('task_postpone_pick_date'),
                  onTap: () =>
                      Navigator.pop(sheetContext, _PostponeChoice.custom),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return false;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  DateTime? target = switch (choice) {
    _PostponeChoice.tomorrow => today.add(const Duration(days: 1)),
    _PostponeChoice.week => today.add(const Duration(days: 7)),
    _PostponeChoice.month => _oneMonthAfter(today),
    _PostponeChoice.custom => null,
  };
  if (choice == _PostponeChoice.custom) {
    target = await showDatePicker(
      context: context,
      initialDate: today.add(const Duration(days: 1)),
      firstDate: today.add(const Duration(days: 1)),
      lastDate: DateTime(today.year + 10, today.month, today.day),
    );
  }
  if (target == null || !context.mounted) return false;

  final changed = await ref.read(taskRepositoryProvider).postpone(task, target);
  if (!changed || !context.mounted) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('task_postpone_unavailable'))),
      );
    }
    return false;
  }
  await ref.read(syncServiceProvider).drainOutbox();
  if (!context.mounted) return true;
  final formatted = MaterialLocalizations.of(context).formatFullDate(target);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        context.l10n.format('task_postponed_confirmation', {'date': formatted}),
      ),
    ),
  );
  return true;
}

Future<bool> deleteTaskOrSeries(
  BuildContext context,
  WidgetRef ref,
  LocalTask task,
) async {
  final recurring = task.templateId?.isNotEmpty == true;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        dialogContext.l10n.text(
          recurring ? 'task_delete_series_title' : 'task_delete_title',
        ),
      ),
      content: Text(
        dialogContext.l10n.text(
          recurring
              ? 'task_delete_series_description'
              : 'task_delete_description',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(dialogContext.l10n.text('cancel')),
        ),
        FilledButton.tonalIcon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.delete_outline),
          label: Text(dialogContext.l10n.text('delete')),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  if (recurring) {
    await ref.read(recurrenceServiceProvider).deleteSeries(task);
  } else {
    await ref.read(taskRepositoryProvider).softDelete(task);
  }
  await ref.read(syncServiceProvider).drainOutbox();
  return true;
}

DateTime _oneMonthAfter(DateTime day) {
  final nextMonth = DateTime(day.year, day.month + 1, 1);
  final lastDay = DateTime(day.year, day.month + 2, 0).day;
  return DateTime(nextMonth.year, nextMonth.month, math.min(day.day, lastDay));
}

class _PostponeOption extends StatelessWidget {
  const _PostponeOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

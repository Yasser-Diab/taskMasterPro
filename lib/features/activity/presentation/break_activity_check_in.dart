import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/notifications/notification_sounds.dart';
import '../../../core/providers.dart';
import '../data/activity_repository.dart';

class _BreakActivityOption {
  const _BreakActivityOption({
    required this.classification,
    required this.labelKey,
    required this.icon,
  });

  final String classification;
  final String labelKey;
  final IconData icon;
}

const _breakActivityOptions = <_BreakActivityOption>[
  _BreakActivityOption(
    classification: 'break_activity_reading',
    labelKey: 'break_activity_reading',
    icon: Icons.menu_book_outlined,
  ),
  _BreakActivityOption(
    classification: 'break_activity_sport',
    labelKey: 'break_activity_sport',
    icon: Icons.directions_run_outlined,
  ),
  _BreakActivityOption(
    classification: 'break_activity_relaxing',
    labelKey: 'break_activity_relaxing',
    icon: Icons.self_improvement_outlined,
  ),
  _BreakActivityOption(
    classification: 'break_activity_drink',
    labelKey: 'break_activity_drink',
    icon: Icons.local_cafe_outlined,
  ),
  _BreakActivityOption(
    classification: 'break_activity_other',
    labelKey: 'break_activity_other',
    icon: Icons.more_horiz,
  ),
];

/// Captures the exact break interval before the execution transition changes
/// the runtime, then offers the optional check-in after focus has resumed.
Future<void> finishBreakWithOptionalActivityCheckIn({
  required BuildContext context,
  required WidgetRef ref,
  required LocalTask task,
}) async {
  final tasks = ref.read(taskRepositoryProvider);
  final runtime = await tasks.getRuntime();
  ActivityReviewEntry? entry;
  if (runtime != null &&
      runtime.activeTaskId == task.id &&
      runtime.state == 'break' &&
      runtime.sessionId != null &&
      runtime.segmentStartedAt != null) {
    entry = await ref
        .read(activityRepositoryProvider)
        .prepareBreakActivityReviewIfNeeded(
          taskId: task.id,
          sessionId: runtime.sessionId!,
          startedAt: runtime.segmentStartedAt!,
        );
  }
  await tasks.finishBreak(task);
  if (entry != null && context.mounted) {
    await promptAndResolveBreakActivityCheckIn(
      context: context,
      ref: ref,
      entry: entry,
    );
  }
}

Future<ActivityReviewEntry?> prepareBreakActivityCheckIn({
  required WidgetRef ref,
  required LocalTask task,
  LocalRuntime? runtime,
  DateTime? endedAt,
}) async {
  final snapshot =
      runtime ?? await ref.read(taskRepositoryProvider).getRuntime();
  if (snapshot == null ||
      snapshot.activeTaskId != task.id ||
      snapshot.state != 'break' ||
      snapshot.sessionId == null ||
      snapshot.segmentStartedAt == null) {
    return null;
  }
  return ref
      .read(activityRepositoryProvider)
      .prepareBreakActivityReviewIfNeeded(
        taskId: task.id,
        sessionId: snapshot.sessionId!,
        startedAt: snapshot.segmentStartedAt!,
        endedAt: endedAt,
      );
}

Future<bool> promptAndResolveBreakActivityCheckIn({
  required BuildContext context,
  required WidgetRef ref,
  required ActivityReviewEntry entry,
}) async {
  final repository = ref.read(activityRepositoryProvider);
  final tasks = await repository.listTaskTargets();
  if (!context.mounted) return false;
  final resolution = await showBreakActivityCheckInSheet(
    context: context,
    tasks: tasks,
  );
  if (resolution == null || !context.mounted) return false;
  final localeCode = Localizations.localeOf(context).languageCode;
  try {
    await repository.resolve(entry, resolution);
    if (resolution.classification == 'break_activity_sport') {
      try {
        final settings = await ref.read(appSettingsProvider.future);
        final preferencesJson = settings?.notificationPreferencesJson ?? '{}';
        if (NotificationSounds.categoryEnabled(
          preferencesJson: preferencesJson,
          category: 'coaching',
        )) {
          final l10n = AppLocalizations(Locale(localeCode));
          await localNotificationService.showCategoryNotification(
            id: LocalNotificationService.coachingNotificationId(
              'sport:${entry.segment.id}',
            ),
            category: 'coaching',
            title: l10n.text('coaching_adaptive_sport_title'),
            body: l10n.format('coaching_adaptive_sport_body', {
              'duration': l10n.duration(entry.duration),
            }),
            sound: NotificationSounds.forCategory(
              preferencesJson: preferencesJson,
              category: 'coaching',
              fallbackKey: settings?.notificationSoundKey ?? 'system',
            ),
            payload: 'activity',
            vibration: NotificationSounds.vibrationForCategory(
              preferencesJson: preferencesJson,
              category: 'coaching',
            ),
            localeCode: localeCode,
          );
        }
      } catch (_) {
        // The Activity decision is durable even if this optional immediate
        // encouragement cannot be displayed by the operating system.
      }
    }
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('break_activity_saved'))),
    );
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('break_activity_save_failed')),
        ),
      );
    }
    return false;
  }
}

Future<ActivityResolution?> showBreakActivityCheckInSheet({
  required BuildContext context,
  required List<LocalTask> tasks,
}) {
  return showModalBottomSheet<ActivityResolution>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _BreakActivitySheet(tasks: tasks),
  );
}

class _BreakActivitySheet extends StatefulWidget {
  const _BreakActivitySheet({required this.tasks});

  final List<LocalTask> tasks;

  @override
  State<_BreakActivitySheet> createState() => _BreakActivitySheetState();
}

class _BreakActivitySheetState extends State<_BreakActivitySheet> {
  final _otherController = TextEditingController();
  String? _classification;
  String? _taskId;
  bool _showOtherError = false;

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _save() {
    final classification = _classification;
    if (classification == null) return;
    final otherLabel = _otherController.text.trim();
    if (classification == 'break_activity_other' && otherLabel.isEmpty) {
      setState(() => _showOtherError = true);
      return;
    }
    final taskId = _taskId;
    Navigator.pop(
      context,
      ActivityResolution(
        status: 'confirmed',
        classification: classification,
        targetType: taskId == null ? 'unassigned_activity' : 'task_occurrence',
        targetId: taskId,
        contributionType: taskId == null ? null : 'active_work_seconds',
        taskAllocations: taskId == null
            ? const []
            : [ActivityTaskAllocation(targetTaskId: taskId, percentage: 100)],
        manualLabel: classification == 'break_activity_other'
            ? otherLabel
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottomInset),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.text('break_activity_title'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(l10n.text('break_activity_prompt')),
              const SizedBox(height: 14),
              RadioGroup<String>(
                groupValue: _classification,
                onChanged: (value) => setState(() {
                  _classification = value;
                  _showOtherError = false;
                }),
                child: Column(
                  children: [
                    for (final option in _breakActivityOptions)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: RadioListTile<String>(
                          value: option.classification,
                          secondary: Icon(option.icon),
                          title: Text(l10n.text(option.labelKey)),
                        ),
                      ),
                  ],
                ),
              ),
              if (_classification == 'break_activity_other') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _otherController,
                  autofocus: true,
                  maxLength: 120,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: l10n.text('break_activity_other_label'),
                    errorText: _showOtherError
                        ? l10n.text('break_activity_other_required')
                        : null,
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _taskId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.text('break_activity_assign_task'),
                  helperText: l10n.text('break_activity_assign_task_help'),
                ),
                items: [
                  DropdownMenuItem<String>(
                    value: '',
                    child: Text(l10n.text('break_activity_no_task')),
                  ),
                  for (final task in widget.tasks)
                    DropdownMenuItem<String>(
                      value: task.id,
                      child: Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(
                  () => _taskId = value == null || value.isEmpty ? null : value,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.text('not_now')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _classification == null ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.text('save')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

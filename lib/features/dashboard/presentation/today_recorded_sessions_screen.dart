import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/time/time_zone_service.dart';
import '../../tasks/data/task_execution_providers.dart';
import '../../tasks/presentation/task_workspace_screen.dart';

class TodayRecordedWorkSummary {
  const TodayRecordedWorkSummary({
    required this.totalMs,
    required this.bySessionId,
  });

  static const empty = TodayRecordedWorkSummary(
    totalMs: 0,
    bySessionId: <String, int>{},
  );

  final int totalMs;
  final Map<String, int> bySessionId;
}

final todayRecordedWorkSummaryProvider =
    StreamProvider<TodayRecordedWorkSummary>((ref) {
      final database = ref.watch(databaseProvider);
      final settings = ref.watch(appSettingsProvider).value;
      final zoneName = TimeZoneService.isValidIana(settings?.timeZone ?? '')
          ? settings!.timeZone
          : 'UTC';
      final location = tz.getLocation(zoneName == 'UTC' ? 'Etc/UTC' : zoneName);
      final localNow = tz.TZDateTime.now(location);
      final localStart = tz.TZDateTime(
        location,
        localNow.year,
        localNow.month,
        localNow.day,
      );
      final localEnd = tz.TZDateTime(
        location,
        localNow.year,
        localNow.month,
        localNow.day + 1,
      );
      final query = database.select(database.localEntityRecords)
        ..where(
          (row) =>
              row.entityType.equals('execution_sessions') &
              row.deletedAt.isNull() &
              row.createdAt.isSmallerThanValue(localEnd.toUtc()) &
              (row.createdAt.isBiggerOrEqualValue(localStart.toUtc()) |
                  row.updatedAt.isBiggerOrEqualValue(localStart.toUtc())),
        );
      return query.watch().map((records) {
        final bySession = <String, int>{};
        for (final record in records) {
          final data = _decode(record.dataJson);
          final startedAt = _date(data['started_at']) ?? record.createdAt;
          final finishedAt = _date(data['finished_at']);
          if (!_overlapsDay(
            startedAt,
            finishedAt,
            localStart.toUtc(),
            localEnd.toUtc(),
          )) {
            continue;
          }
          bySession[record.id] =
              ((data['accumulated_active_ms'] as num?)?.toInt() ?? 0)
                  .clamp(0, 1 << 62)
                  .toInt();
        }
        return TodayRecordedWorkSummary(
          totalMs: bySession.values.fold(0, (sum, value) => sum + value),
          bySessionId: Map.unmodifiable(bySession),
        );
      });
    });

/// Displays the exact local execution-session records behind the Dashboard's
/// "Actual work" total for the user's current local day.
class TodayRecordedSessionsScreen extends ConsumerWidget {
  const TodayRecordedSessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final database = ref.watch(databaseProvider);
    final runtime = ref.watch(taskExecutionRuntimeProvider).value;
    if (runtime?.state == 'running') {
      ref.watch(taskExecutionClockProvider);
    }
    final settings = ref.watch(appSettingsProvider).value;
    final zoneName = TimeZoneService.isValidIana(settings?.timeZone ?? '')
        ? settings!.timeZone
        : 'UTC';
    final location = tz.getLocation(zoneName == 'UTC' ? 'Etc/UTC' : zoneName);
    final localNow = tz.TZDateTime.now(location);
    final localStart = tz.TZDateTime(
      location,
      localNow.year,
      localNow.month,
      localNow.day,
    );
    final localEnd = tz.TZDateTime(
      location,
      localNow.year,
      localNow.month,
      localNow.day + 1,
    );
    final sessionQuery = database.select(database.localEntityRecords)
      ..where(
        (row) =>
            row.entityType.equals('execution_sessions') &
            row.deletedAt.isNull() &
            row.createdAt.isSmallerThanValue(localEnd.toUtc()) &
            (row.createdAt.isBiggerOrEqualValue(localStart.toUtc()) |
                row.updatedAt.isBiggerOrEqualValue(localStart.toUtc())),
      )
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]);
    final taskQuery = database.select(database.localTasks)
      ..where((row) => row.deletedAt.isNull());

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: Text(context.l10n.text('dashboard_actual_work'))),
      body: StreamBuilder<List<LocalEntityRecord>>(
        stream: sessionQuery.watch(),
        builder: (context, sessionSnapshot) {
          if (sessionSnapshot.hasError) {
            return Center(
              child: Text(context.l10n.text('activity_load_failed')),
            );
          }
          if (!sessionSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return StreamBuilder<List<LocalTask>>(
            stream: taskQuery.watch(),
            builder: (context, taskSnapshot) {
              if (!taskSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final tasks = {
                for (final task in taskSnapshot.requireData) task.id: task,
              };
              final sessions = sessionSnapshot.requireData
                  .where((session) {
                    final data = _decode(session.dataJson);
                    return _overlapsDay(
                      _date(data['started_at']) ?? session.createdAt,
                      _date(data['finished_at']),
                      localStart.toUtc(),
                      localEnd.toUtc(),
                    );
                  })
                  .toList(growable: false);
              if (sessions.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.l10n.text('activity_none_day'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final data = _decode(session.dataJson);
                  final task = session.parentId == null
                      ? null
                      : tasks[session.parentId];
                  final startedAt =
                      _date(data['started_at']) ?? session.createdAt;
                  final finishedAt = _date(data['finished_at']);
                  var activeMs =
                      (data['accumulated_active_ms'] as num?)?.toInt() ?? 0;
                  if (runtime?.sessionId == session.id) {
                    activeMs = runtime!.accumulatedActiveMs;
                    if (runtime.state == 'running' &&
                        runtime.segmentStartedAt != null) {
                      activeMs += DateTime.now()
                          .toUtc()
                          .difference(runtime.segmentStartedAt!)
                          .inMilliseconds;
                    }
                  }
                  final localStarted = tz.TZDateTime.from(
                    startedAt.toUtc(),
                    location,
                  );
                  final localFinished = finishedAt == null
                      ? null
                      : tz.TZDateTime.from(finishedAt.toUtc(), location);
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: task == null
                          ? null
                          : () => TaskWorkspaceScreen.open(context, task),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              session.status == 'completed'
                                  ? Icons.task_alt_rounded
                                  : session.status == 'cancelled'
                                  ? Icons.cancel_outlined
                                  : Icons.timer_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task?.title ?? session.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _timeRange(
                                      context,
                                      localStarted,
                                      localFinished,
                                    ),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              context.l10n.duration(
                                Duration(milliseconds: activeMs),
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (task != null) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

Map<String, Object?> _decode(String raw) {
  try {
    final value = jsonDecode(raw);
    return value is Map
        ? Map<String, Object?>.from(value)
        : const <String, Object?>{};
  } catch (_) {
    return const <String, Object?>{};
  }
}

DateTime? _date(Object? raw) {
  if (raw is DateTime) return raw;
  return raw is String ? DateTime.tryParse(raw) : null;
}

bool _overlapsDay(
  DateTime startedAt,
  DateTime? finishedAt,
  DateTime dayStart,
  DateTime dayEnd,
) {
  final start = startedAt.toUtc();
  final end = finishedAt?.toUtc();
  return start.isBefore(dayEnd) && (end == null || end.isAfter(dayStart));
}

String _timeRange(
  BuildContext context,
  DateTime startedAt,
  DateTime? finishedAt,
) {
  final formatter = DateFormat.jm(
    Localizations.localeOf(context).toLanguageTag(),
  );
  final start = formatter.format(startedAt);
  return finishedAt == null
      ? start
      : '$start – ${formatter.format(finishedAt)}';
}

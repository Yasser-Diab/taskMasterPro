import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/database/app_database.dart';
import '../../../core/localization/app_localizations.dart';
import '../../activity/domain/activity_reporting_policy.dart';
import '../../tasks/data/installed_application_service.dart';
import '../../../core/time/time_zone_service.dart';
import '../../tasks/domain/daily_planned_time.dart';
import '../../tasks/domain/pomodoro_execution_state.dart';
import '../../tasks/domain/task_domain_catalog.dart';
import '../../tasks/domain/task_occurrence_policy.dart';

enum PerformanceReportType { account, task, household, roadmap }

extension PerformanceReportTypeDetails on PerformanceReportType {
  String get titleLocalizationKey => switch (this) {
    PerformanceReportType.account => 'report_account_title',
    PerformanceReportType.task => 'report_task_title',
    PerformanceReportType.household => 'report_household_title',
    PerformanceReportType.roadmap => 'report_roadmap_title',
  };

  String get fileSlug => switch (this) {
    PerformanceReportType.account => 'performance',
    PerformanceReportType.task => 'task',
    PerformanceReportType.household => 'household',
    PerformanceReportType.roadmap => 'roadmap',
  };
}

class PerformanceReportOptions {
  const PerformanceReportOptions({
    required this.type,
    required this.from,
    required this.to,
    required this.localeCode,
    required this.landscape,
    required this.sections,
    this.roadmapId,
    this.taskId,
    this.includeHealth = false,
    this.timeZone = 'UTC',
  });

  final PerformanceReportType type;
  final DateTime from;
  final DateTime to;
  final String localeCode;
  final bool landscape;
  final Set<String> sections;
  final String? roadmapId;
  final String? taskId;
  final bool includeHealth;
  final String timeZone;

  bool get includesHealth =>
      includeHealth &&
      sections.contains(PerformanceReportService.healthSection);
}

class PerformanceHealthSummaryEntry {
  const PerformanceHealthSummaryEntry({
    required this.metricType,
    required this.value,
    required this.unit,
    required this.summaryDate,
    required this.sources,
    required this.lastUpdatedAt,
    this.recordCount = 0,
    this.estimated = false,
    this.provenance,
  });

  final String metricType;
  final num value;
  final String unit;
  final DateTime summaryDate;
  final List<String> sources;
  final DateTime lastUpdatedAt;
  final int recordCount;
  final bool estimated;
  final String? provenance;
}

class PerformanceReportSnapshot {
  const PerformanceReportSnapshot({
    required this.profile,
    required this.roadmap,
    required this.tasks,
    required this.phases,
    required this.milestones,
    required this.checkpoints,
    required this.activity,
    required this.contributions,
    this.attributions = const [],
    required this.insights,
    required this.health,
    this.roadmaps = const [],
    this.domains = const [],
    this.sessions = const [],
    this.sessionEvents = const [],
    this.pomodoroCycles = const [],
    this.interruptions = const [],
    this.runtime,
  });

  final LocalProfile? profile;
  final LocalRoadmap? roadmap;
  final List<LocalTask> tasks;
  final List<LocalEntityRecord> phases;
  final List<LocalEntityRecord> milestones;
  final List<LocalEntityRecord> checkpoints;
  final List<LocalActivitySegment> activity;
  final List<LocalContribution> contributions;
  final List<LocalAttribution> attributions;
  final List<LocalEntityRecord> insights;
  final List<LocalEntityRecord> health;
  final List<LocalRoadmap> roadmaps;
  final List<LocalDomain> domains;
  final List<LocalEntityRecord> sessions;
  final List<LocalEntityRecord> sessionEvents;
  final List<LocalEntityRecord> pomodoroCycles;
  final List<LocalEntityRecord> interruptions;
  final LocalRuntime? runtime;
}

class PerformanceReportBreakdown {
  const PerformanceReportBreakdown({
    required this.id,
    required this.label,
    required this.durationMs,
    this.count = 0,
  });

  final String id;
  final String label;
  final int durationMs;
  final int count;
}

class PerformanceReportDailyPoint {
  const PerformanceReportDailyPoint({
    required this.day,
    required this.plannedMs,
    required this.productiveMs,
    required this.completedTasks,
  });

  final DateTime day;
  final int plannedMs;
  final int productiveMs;
  final int completedTasks;
}

/// A report row for either one standalone task or all occurrences generated
/// from the same recurring template.
class PerformanceReportTaskGroup {
  const PerformanceReportTaskGroup({
    required this.id,
    required this.title,
    required this.recurring,
    required this.occurrences,
    required this.completed,
    required this.missed,
    required this.upcoming,
    required this.plannedMs,
    required this.recordedMs,
  });

  final String id;
  final String title;
  final bool recurring;
  final int occurrences;
  final int completed;
  final int missed;
  final int upcoming;
  final int plannedMs;
  final int recordedMs;
}

/// Derived report values with no sample, random, or placeholder data.
///
/// Both the interactive report and exported PDF consume this projection, so
/// preview, print, and export cannot silently disagree.
class PerformanceReportFacts {
  const PerformanceReportFacts({
    required this.plannedMs,
    required this.productiveMs,
    required this.focusMs,
    required this.breakMs,
    required this.continuousMs,
    required this.pausedMs,
    required this.interruptionMs,
    required this.interruptionCount,
    required this.activeActivityMs,
    required this.idleActivityMs,
    required this.completedTasks,
    required this.overdueTasks,
    required this.daily,
    required this.applications,
    required this.websites,
    required this.taskDomains,
    required this.roadmaps,
    required this.phases,
    required this.interruptionTypes,
    required this.taskWork,
  });

  final int plannedMs;
  final int productiveMs;
  final int focusMs;
  final int breakMs;
  final int continuousMs;
  final int pausedMs;
  final int interruptionMs;
  final int interruptionCount;
  final int activeActivityMs;
  final int idleActivityMs;
  final int completedTasks;
  final int overdueTasks;
  final List<PerformanceReportDailyPoint> daily;
  final List<PerformanceReportBreakdown> applications;
  final List<PerformanceReportBreakdown> websites;
  final List<PerformanceReportBreakdown> taskDomains;
  final List<PerformanceReportBreakdown> roadmaps;
  final List<PerformanceReportBreakdown> phases;
  final List<PerformanceReportBreakdown> interruptionTypes;
  final List<PerformanceReportBreakdown> taskWork;

  bool get hasRecordedData =>
      productiveMs > 0 ||
      breakMs > 0 ||
      interruptionMs > 0 ||
      activeActivityMs > 0 ||
      idleActivityMs > 0 ||
      completedTasks > 0;
}

/// A bounded slice of recorded time used only while deriving a report.
///
/// The raw stores can contain the same physical period from more than one
/// device or more than one reconciliation pass.  Reports must never add those
/// rows blindly; all elapsed-time values below are derived from unions of
/// these intervals.
class _ReportInterval {
  const _ReportInterval({
    required this.start,
    required this.end,
    this.taskId,
    this.executionMode,
    this.label,
    this.isIdle = false,
    this.isWebsite = false,
  });

  final DateTime start;
  final DateTime end;
  final String? taskId;
  final String? executionMode;
  final String? label;
  final bool isIdle;
  final bool isWebsite;

  int get durationMs => math.max(0, end.difference(start).inMilliseconds);

  _ReportInterval clip(DateTime startAt, DateTime endAt) {
    final clippedStart = start.isBefore(startAt) ? startAt : start;
    final clippedEnd = end.isAfter(endAt) ? endAt : end;
    return _ReportInterval(
      start: clippedStart,
      end: clippedEnd,
      taskId: taskId,
      executionMode: executionMode,
      label: label,
      isIdle: isIdle,
      isWebsite: isWebsite,
    );
  }

  bool get isPositive => end.isAfter(start);
}

class _ProductiveAllocation {
  const _ProductiveAllocation({
    required this.totalMs,
    required this.byTask,
    required this.byMode,
  });

  final int totalMs;
  final Map<String, int> byTask;
  final Map<String, int> byMode;
}

class _ActivityAllocation {
  const _ActivityAllocation({
    required this.activeMs,
    required this.idleMs,
    required this.applications,
    required this.websites,
  });

  final int activeMs;
  final int idleMs;
  final Map<String, int> applications;
  final Map<String, int> websites;
}

class PerformanceReportService {
  PerformanceReportService(this.database);

  static const healthSection = 'health';
  static const _healthMetricOrder = <String, int>{
    'steps': 0,
    'distance': 1,
    'active_calories': 2,
    'average_heart_rate': 3,
    'sleep_duration': 4,
    'exercise_sessions': 5,
  };

  final AppDatabase database;

  static bool isHouseholdTask(LocalTask task) {
    final data = _decodeJsonMap(task.dataJson);
    for (final key in const ['scope', 'type']) {
      final value = data[key];
      if (value is! String) continue;
      final normalized = value
          .trim()
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      if (normalized == 'household' || normalized == 'shared_household') {
        return true;
      }
    }
    return false;
  }

  static List<LocalTask> tasksForReport(
    Iterable<LocalTask> tasks,
    PerformanceReportOptions options,
  ) {
    final endExclusive = _endExclusive(options.to);
    return tasks
        .where((task) {
          if (!TaskOccurrencePolicy.isRealOccurrence(task)) return false;
          final matchesScope = switch (options.type) {
            PerformanceReportType.account => true,
            PerformanceReportType.task =>
              options.taskId != null && task.id == options.taskId,
            PerformanceReportType.household => isHouseholdTask(task),
            PerformanceReportType.roadmap =>
              options.roadmapId != null && task.roadmapId == options.roadmapId,
          };
          if (!matchesScope) return false;
          final activeStart = task.actualStart;
          if (activeStart != null) {
            final activeEnd = task.actualFinish ?? task.updatedAt;
            final startDay = TaskOccurrencePolicy.localDateAt(
              activeStart,
              timeZone: options.timeZone,
            );
            final endDay = TaskOccurrencePolicy.localDateAt(
              activeEnd,
              timeZone: options.timeZone,
            );
            if (!endDay.isBefore(_startOfDay(options.from)) &&
                startDay.isBefore(endExclusive)) {
              return true;
            }
          }
          final time =
              task.actualStart ??
              task.scheduledDate ??
              task.actualFinish ??
              task.updatedAt;
          // A scheduledDate without a plannedStart is a floating calendar
          // date, not an instant.  Treating it as local-machine midnight then
          // converting to UTC shifted an August 1 task into July 31 on
          // non-UTC devices.
          final localDay =
              task.plannedStart == null && task.scheduledDate != null
              ? _startOfDay(task.scheduledDate!)
              : TaskOccurrencePolicy.localDateAt(
                  time,
                  timeZone: options.timeZone,
                );
          return !localDay.isBefore(_startOfDay(options.from)) &&
              localDay.isBefore(endExclusive);
        })
        .toList(growable: false);
  }

  static PerformanceReportFacts factsForSnapshot(
    PerformanceReportSnapshot snapshot,
    PerformanceReportOptions options,
    AppLocalizations l10n, {
    DateTime? now,
  }) {
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final tasksById = {for (final task in snapshot.tasks) task.id: task};
    final sessionsById = <String, LocalEntityRecord>{};
    final sessionTaskById = <String, String>{};

    for (final session in snapshot.sessions) {
      final data = _decodeJsonMap(session.dataJson);
      final taskId =
          session.parentId ??
          data['task_occurrence_id']?.toString() ??
          data['task_id']?.toString();
      if (taskId == null || !tasksById.containsKey(taskId)) continue;
      sessionsById[session.id] = session;
      sessionTaskById[session.id] = taskId;
    }

    // Reported productivity is a user-time union, not a sum of device rows,
    // task caches, and session totals.  This is the boundary that prevents a
    // Windows 10:00–10:30 record and an Android 10:10–10:40 record from
    // becoming an invented 60 minutes.
    final productiveIntervals = _productiveIntervals(
      snapshot: snapshot,
      tasksById: tasksById,
      sessionsById: sessionsById,
      sessionTaskById: sessionTaskById,
      effectiveNow: effectiveNow,
    );
    final productiveByDay = _allocateProductiveByDay(
      productiveIntervals,
      options,
    );
    final activeByTask = <String, int>{};
    final activeByMode = <String, int>{};
    var productiveMs = 0;
    for (final allocation in productiveByDay.values) {
      productiveMs += allocation.totalMs;
      _addAll(activeByTask, allocation.byTask);
      _addAll(activeByMode, allocation.byMode);
    }
    final focusMs = activeByMode['pomodoro'] ?? 0;
    final continuousMs = activeByMode['continuous'] ?? 0;
    final pausedMs = _durationByDay(
      _pausedIntervals(
        snapshot: snapshot,
        sessionsById: sessionsById,
        sessionTaskById: sessionTaskById,
        effectiveNow: effectiveNow,
      ),
      options,
    );
    final breakMs = _durationByDay(
      _breakIntervals(
        snapshot: snapshot,
        tasksById: tasksById,
        sessionTaskById: sessionTaskById,
        effectiveNow: effectiveNow,
      ),
      options,
    );

    final interruptionMs = _durationByDay(
      _interruptionIntervals(snapshot.interruptions, effectiveNow),
      options,
    );
    final interruptionTypeDurations = _allocateLabelsByDay(
      _interruptionIntervals(snapshot.interruptions, effectiveNow),
      options,
    );

    final reportableActivity = reportableActivitySegments(
      segments: snapshot.activity,
      attributions: snapshot.attributions,
    );
    final activityAllocation = _allocateActivityByDay(
      _activityIntervals(reportableActivity, l10n),
      options,
    );
    var activeActivityMs = 0;
    var idleActivityMs = 0;
    final applications = <String, int>{};
    final websites = <String, int>{};
    for (final allocation in activityAllocation.values) {
      activeActivityMs += allocation.activeMs;
      idleActivityMs += allocation.idleMs;
      _addAll(applications, allocation.applications);
      _addAll(websites, allocation.websites);
    }

    final domainsById = {
      for (final domain in snapshot.domains) domain.id: domain,
    };
    final domainDurations = <String, int>{};
    final roadmapDurations = <String, int>{};
    final phaseDurations = <String, int>{};
    for (final task in snapshot.tasks) {
      final active = activeByTask[task.id] ?? 0;
      final domainId = task.domainId ?? '';
      domainDurations.update(
        domainId,
        (value) => value + active,
        ifAbsent: () => active,
      );
      final roadmapId = task.roadmapId;
      if (roadmapId != null && roadmapId.isNotEmpty) {
        roadmapDurations.update(
          roadmapId,
          (value) => value + active,
          ifAbsent: () => active,
        );
      }
      final phaseId = task.roadmapPhaseId;
      if (phaseId != null && phaseId.isNotEmpty) {
        phaseDurations.update(
          phaseId,
          (value) => value + active,
          ifAbsent: () => active,
        );
      }
    }
    final userId =
        snapshot.profile?.userId ?? snapshot.tasks.firstOrNull?.userId ?? '';
    final roadmapNames = {
      for (final roadmap in snapshot.roadmaps) roadmap.id: roadmap.title,
    };
    final phaseNames = {
      for (final phase in snapshot.phases) phase.id: phase.title,
    };

    final startDay = _startOfDay(options.from);
    final endDay = _startOfDay(options.to);
    final daily = <DateTime, ({int planned, int active, int completed})>{};
    for (
      var day = startDay;
      !day.isAfter(endDay);
      day = day.add(const Duration(days: 1))
    ) {
      daily[day] = (
        planned: DailyPlannedTime.calculate(
          snapshot.tasks,
          localDay: day,
          timeZone: options.timeZone,
        ).inMilliseconds,
        active: 0,
        completed: 0,
      );
    }
    for (final task in snapshot.tasks) {
      final completedAt = task.actualFinish;
      if (task.status == 'completed' && completedAt != null) {
        final day = TaskOccurrencePolicy.localDateAt(
          completedAt,
          timeZone: options.timeZone,
        );
        final current = daily[day];
        if (current != null) {
          daily[day] = (
            planned: current.planned,
            active: current.active,
            completed: current.completed + 1,
          );
        }
      }
    }
    for (final entry in productiveByDay.entries) {
      final current = daily[entry.key];
      if (current == null) continue;
      daily[entry.key] = (
        planned: current.planned,
        active: entry.value.totalMs,
        completed: current.completed,
      );
    }

    List<PerformanceReportBreakdown> ordered(
      Map<String, int> values,
      String Function(String id) label, {
      bool discardZero = true,
    }) {
      final result =
          values.entries
              .where((entry) => !discardZero || entry.value > 0)
              .map(
                (entry) => PerformanceReportBreakdown(
                  id: entry.key,
                  label: label(entry.key),
                  durationMs: entry.value,
                ),
              )
              .toList()
            ..sort(
              (left, right) => right.durationMs.compareTo(left.durationMs),
            );
      return List.unmodifiable(result);
    }

    final completed = snapshot.tasks
        .where(TaskOccurrencePolicy.isCompletedOccurrence)
        .length;
    final overdue = TaskOccurrencePolicy.overdueOccurrences(
      snapshot.tasks,
      now: effectiveNow,
      timeZone: options.timeZone,
    ).length;
    return PerformanceReportFacts(
      plannedMs: daily.values.fold<int>(0, (sum, value) => sum + value.planned),
      productiveMs: productiveMs,
      focusMs: focusMs,
      breakMs: breakMs,
      continuousMs: continuousMs,
      pausedMs: pausedMs,
      interruptionMs: interruptionMs,
      interruptionCount: snapshot.interruptions.length,
      activeActivityMs: activeActivityMs,
      idleActivityMs: idleActivityMs,
      completedTasks: completed,
      overdueTasks: overdue,
      daily: daily.entries
          .map(
            (entry) => PerformanceReportDailyPoint(
              day: entry.key,
              plannedMs: entry.value.planned,
              productiveMs: entry.value.active,
              completedTasks: entry.value.completed,
            ),
          )
          .toList(growable: false),
      applications: ordered(applications, (id) => id),
      websites: ordered(websites, (id) => id),
      taskDomains: ordered(domainDurations, (id) {
        if (id.isEmpty) return l10n.text('report_no_task_domain');
        final domain = domainsById[id];
        if (domain == null) return l10n.text('report_domain_unavailable');
        final builtInKey = TaskDomainCatalog.builtInKeyForId(userId, id);
        return builtInKey == null
            ? domain.name
            : l10n.text(TaskDomainCatalog.localizationKey(builtInKey));
      }),
      roadmaps: ordered(
        roadmapDurations,
        (id) => roadmapNames[id]?.trim().isNotEmpty == true
            ? roadmapNames[id]!.trim()
            : l10n.text('report_roadmap_unavailable'),
      ),
      phases: ordered(
        phaseDurations,
        (id) => phaseNames[id]?.trim().isNotEmpty == true
            ? phaseNames[id]!.trim()
            : l10n.text('report_phase_unavailable'),
      ),
      interruptionTypes: ordered(interruptionTypeDurations, (id) {
        final localizationKey = switch (id) {
          'device_internet_problem' => 'interruption_type_device_problem',
          'cross_task' => 'activity_contributions',
          'phone_call' ||
          'family_need' ||
          'work_problem' ||
          'visitor' ||
          'meeting' ||
          'personal_need' ||
          'emergency' ||
          'distraction' ||
          'other' => 'interruption_type_$id',
          _ => 'interruption_type_other',
        };
        return l10n.text(localizationKey);
      }),
      taskWork: ordered(
        activeByTask,
        (id) => tasksById[id]?.title ?? l10n.text('report_task_unavailable'),
      ),
    );
  }

  /// Collapses recurring occurrences to a single report row while retaining
  /// the outcome counts and the union-allocated work credited to every task.
  static List<PerformanceReportTaskGroup> taskGroupsForReport(
    Iterable<LocalTask> tasks,
    PerformanceReportFacts facts, {
    DateTime? now,
    String timeZone = 'UTC',
  }) {
    final occurrenceList = tasks.toList(growable: false);
    final overdueIds = TaskOccurrencePolicy.overdueOccurrences(
      occurrenceList,
      now: (now ?? DateTime.now()).toUtc(),
      timeZone: timeZone,
    ).map((task) => task.id).toSet();
    final recordedByTask = {
      for (final entry in facts.taskWork) entry.id: entry.durationMs,
    };
    final grouped = <String, List<LocalTask>>{};
    for (final task in occurrenceList) {
      final templateId = task.templateId?.trim();
      final key = templateId == null || templateId.isEmpty
          ? 'task:${task.id}'
          : 'template:$templateId';
      grouped.putIfAbsent(key, () => []).add(task);
    }
    final result = <PerformanceReportTaskGroup>[];
    for (final entry in grouped.entries) {
      final occurrences = entry.value
        ..sort((left, right) {
          final leftAt =
              left.plannedStart ?? left.scheduledDate ?? left.createdAt;
          final rightAt =
              right.plannedStart ?? right.scheduledDate ?? right.createdAt;
          return leftAt.compareTo(rightAt);
        });
      final completed = occurrences
          .where(TaskOccurrencePolicy.isCompletedOccurrence)
          .length;
      final missed = occurrences
          .where(
            (task) =>
                task.status.toLowerCase() == 'missed' ||
                overdueIds.contains(task.id),
          )
          .length;
      result.add(
        PerformanceReportTaskGroup(
          id: entry.key,
          title: occurrences.first.title,
          recurring: !entry.key.startsWith('task:'),
          occurrences: occurrences.length,
          completed: completed,
          missed: missed,
          upcoming: math.max(0, occurrences.length - completed - missed),
          plannedMs: occurrences.fold<int>(
            0,
            (sum, task) => sum + task.estimatedDurationMs,
          ),
          recordedMs: occurrences.fold<int>(
            0,
            (sum, task) => sum + (recordedByTask[task.id] ?? 0),
          ),
        ),
      );
    }
    result.sort((left, right) => left.title.compareTo(right.title));
    return List.unmodifiable(result);
  }

  /// Resolves linked roadmap identities before report rendering.
  ///
  /// Database identities intentionally never become display fallbacks. A
  /// removed roadmap receives a localized unavailable label instead.
  static List<String> linkedRoadmapLabels(
    Iterable<LocalTask> tasks,
    Iterable<LocalRoadmap> roadmaps,
    AppLocalizations l10n,
  ) {
    final namesById = {
      for (final roadmap in roadmaps)
        if (roadmap.deletedAt == null) roadmap.id: roadmap.title,
    };
    final labels = <String>[];
    final seen = <String>{};
    for (final task in tasks) {
      final id = task.roadmapId;
      if (id == null || id.isEmpty || !seen.add(id)) continue;
      final name = namesById[id]?.trim();
      labels.add(
        name == null || name.isEmpty
            ? l10n.text('report_roadmap_unavailable')
            : name,
      );
    }
    return List.unmodifiable(labels);
  }

  static List<PerformanceHealthSummaryEntry> healthSummariesForReport(
    Iterable<LocalEntityRecord> records,
    PerformanceReportOptions options,
  ) {
    if (!options.includesHealth) {
      return const <PerformanceHealthSummaryEntry>[];
    }
    final taskRecords = records
        .where((record) {
          if (record.entityType != 'task_health_summaries') return false;
          if (options.type == PerformanceReportType.task &&
              options.taskId != null &&
              record.parentId != options.taskId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (options.type != PerformanceReportType.account &&
        taskRecords.isNotEmpty) {
      return _taskHealthSummariesForReport(taskRecords, options);
    }
    final deduplicated = <String, PerformanceHealthSummaryEntry>{};
    for (final record in records) {
      if (record.entityType != 'health_summaries') continue;
      final data = _decodeJsonMap(record.dataJson);
      final metricType =
          (data['summary_type'] as String?)?.trim().toLowerCase() ??
          record.title.trim().toLowerCase();
      if (!_healthMetricOrder.containsKey(metricType)) continue;
      final value = _numericValue(data['value']);
      if (value == null) continue;
      final recordCount = (data['record_count'] as num?)?.toInt() ?? 0;
      final sources = _healthSources(data);
      if (record.deletedAt != null || recordCount <= 0 || sources.isEmpty) {
        continue;
      }
      final summaryDate = _healthSummaryDate(record, data);
      if (!_dateFallsInRange(summaryDate, options)) continue;
      final lastUpdatedAt =
          _parseDateTime(data['last_updated_at']) ?? record.updatedAt;
      final entry = PerformanceHealthSummaryEntry(
        metricType: metricType,
        value: value,
        unit: data['unit']?.toString().trim() ?? '',
        summaryDate: summaryDate,
        sources: sources,
        lastUpdatedAt: lastUpdatedAt,
        recordCount: recordCount,
        estimated: data['estimated'] == true,
        provenance: data['provenance'] as String?,
      );
      final key =
          '${summaryDate.year.toString().padLeft(4, '0')}-'
          '${summaryDate.month.toString().padLeft(2, '0')}-'
          '${summaryDate.day.toString().padLeft(2, '0')}|$metricType';
      final current = deduplicated[key];
      if (current == null ||
          entry.lastUpdatedAt.isAfter(current.lastUpdatedAt)) {
        deduplicated[key] = entry;
      }
    }
    final result = deduplicated.values.toList(growable: false)
      ..sort((a, b) {
        final dateOrder = b.summaryDate.compareTo(a.summaryDate);
        if (dateOrder != 0) return dateOrder;
        return (_healthMetricOrder[a.metricType] ?? 99).compareTo(
          _healthMetricOrder[b.metricType] ?? 99,
        );
      });
    return result;
  }

  static List<PerformanceHealthSummaryEntry> _taskHealthSummariesForReport(
    Iterable<LocalEntityRecord> records,
    PerformanceReportOptions options,
  ) {
    const taskMetrics = {
      'steps',
      'distance',
      'active_calories',
      'average_heart_rate',
    };
    final deduplicated = <String, PerformanceHealthSummaryEntry>{};
    for (final record in records) {
      final data = _decodeJsonMap(record.dataJson);
      final metricType =
          (data['metric_type'] as String?)?.trim().toLowerCase() ??
          (data['summary_type'] as String?)?.trim().toLowerCase() ??
          record.title.trim().toLowerCase();
      if (!taskMetrics.contains(metricType)) continue;
      final value = _numericValue(data['value']);
      if (value == null) continue;
      final recordCount = (data['record_count'] as num?)?.toInt() ?? 0;
      final sources = _healthSources(data);
      if (recordCount <= 0 || sources.isEmpty) continue;
      final summaryDate = _healthSummaryDate(record, data);
      if (!_dateFallsInRange(summaryDate, options)) continue;
      final lastUpdatedAt =
          _parseDateTime(data['last_updated_at']) ?? record.updatedAt;
      final entry = PerformanceHealthSummaryEntry(
        metricType: metricType,
        value: value,
        unit: data['unit']?.toString().trim() ?? '',
        summaryDate: summaryDate,
        sources: sources,
        lastUpdatedAt: lastUpdatedAt,
        recordCount: recordCount,
        estimated: data['estimated'] == true,
        provenance: data['provenance'] as String?,
      );
      final key =
          '${record.parentId ?? data['task_occurrence_id']}|'
          '${record.secondaryParentId ?? data['execution_session_id']}|'
          '$metricType';
      final current = deduplicated[key];
      if (current == null ||
          entry.lastUpdatedAt.isAfter(current.lastUpdatedAt)) {
        deduplicated[key] = entry;
      }
    }

    final grouped = <String, List<PerformanceHealthSummaryEntry>>{};
    for (final entry in deduplicated.values) {
      grouped.putIfAbsent(entry.metricType, () => []).add(entry);
    }
    final result = <PerformanceHealthSummaryEntry>[];
    for (final group in grouped.entries) {
      final entries = group.value;
      final sources = <String>{
        for (final entry in entries) ...entry.sources,
      }.toList()..sort();
      final latest = entries
          .map((entry) => entry.lastUpdatedAt)
          .reduce((left, right) => left.isAfter(right) ? left : right);
      final summaryDate = entries
          .map((entry) => entry.summaryDate)
          .reduce((left, right) => left.isAfter(right) ? left : right);
      final recordCount = entries.fold<int>(
        0,
        (sum, entry) => sum + entry.recordCount,
      );
      final value = group.key == 'average_heart_rate'
          ? entries.fold<double>(
                  0,
                  (sum, entry) =>
                      sum +
                      entry.value.toDouble() * math.max(1, entry.recordCount),
                ) /
                math.max(1, recordCount)
          : entries.fold<double>(
              0,
              (sum, entry) => sum + entry.value.toDouble(),
            );
      final provenance = entries
          .map((entry) => entry.provenance)
          .whereType<String>()
          .toSet();
      result.add(
        PerformanceHealthSummaryEntry(
          metricType: group.key,
          value: value,
          unit: entries.first.unit,
          summaryDate: summaryDate,
          sources: sources,
          lastUpdatedAt: latest,
          recordCount: recordCount,
          estimated: entries.any((entry) => entry.estimated),
          provenance: provenance.length == 1 ? provenance.single : null,
        ),
      );
    }
    result.sort(
      (left, right) => (_healthMetricOrder[left.metricType] ?? 99).compareTo(
        _healthMetricOrder[right.metricType] ?? 99,
      ),
    );
    return result;
  }

  /// The display identity is deliberately separate from the raw identifier
  /// retained for matching and diagnostics.  A report must not expose package
  /// names, executable filenames, URL paths, or backend identifiers.
  static String? websiteLabel(LocalActivitySegment segment) =>
      _websiteLabel(segment);

  static String applicationLabel(
    LocalActivitySegment segment, {
    required String unavailableLabel,
  }) {
    final raw = segment.processName?.trim().isNotEmpty == true
        ? segment.processName!
        : segment.sourceType;
    final normalized = normalizedApplicationDisplayName(raw);
    return normalized.isEmpty ? unavailableLabel : normalized;
  }

  static String activityDisplayLabel(
    LocalActivitySegment segment, {
    required String unavailableLabel,
  }) =>
      _websiteLabel(segment) ??
      applicationLabel(segment, unavailableLabel: unavailableLabel);

  static int _liveRuntimeSegmentMs({
    required LocalTask task,
    required LocalRuntime runtime,
    required DateTime effectiveNow,
  }) {
    final segmentStartedAt = runtime.segmentStartedAt?.toUtc();
    if (runtime.state != 'running' || segmentStartedAt == null) return 0;

    final rawElapsedMs = math.max(
      0,
      effectiveNow.difference(segmentStartedAt).inMilliseconds,
    );
    if (task.executionMode.trim().toLowerCase() != 'pomodoro') {
      return rawElapsedMs;
    }

    final pomodoro = PomodoroExecutionSnapshot.fromTask(
      task: task,
      runtime: runtime,
      now: effectiveNow,
    );
    final persistedActiveMs = math.max(0, runtime.accumulatedActiveMs);
    final boundedLiveFocusMs = math.max(
      0,
      pomodoro.focusedMs - persistedActiveMs,
    );
    return math.min(rawElapsedMs, boundedLiveFocusMs);
  }

  static int _runtimeRecordedActiveMs({
    required LocalTask task,
    required LocalRuntime runtime,
    required DateTime effectiveNow,
  }) =>
      math.max(0, runtime.accumulatedActiveMs) +
      _liveRuntimeSegmentMs(
        task: task,
        runtime: runtime,
        effectiveNow: effectiveNow,
      );

  static List<_ReportInterval> _productiveIntervals({
    required PerformanceReportSnapshot snapshot,
    required Map<String, LocalTask> tasksById,
    required Map<String, LocalEntityRecord> sessionsById,
    required Map<String, String> sessionTaskById,
    required DateTime effectiveNow,
  }) {
    final eventsBySession = <String, List<LocalEntityRecord>>{};
    for (final event in snapshot.sessionEvents) {
      final data = _decodeJsonMap(event.dataJson);
      final sessionId =
          event.parentId ??
          data['session_id']?.toString() ??
          event.secondaryParentId;
      if (sessionId == null || !sessionsById.containsKey(sessionId)) continue;
      eventsBySession.putIfAbsent(sessionId, () => []).add(event);
    }

    final result = <_ReportInterval>[];
    final tasksWithIntervalEvidence = <String>{};
    for (final entry in sessionsById.entries) {
      final taskId = sessionTaskById[entry.key];
      final task = taskId == null ? null : tasksById[taskId];
      if (task == null) continue;
      final intervals = _sessionActiveIntervals(
        session: entry.value,
        task: task,
        events: eventsBySession[entry.key] ?? const [],
        runtime: snapshot.runtime,
        effectiveNow: effectiveNow,
      );
      if (intervals.isNotEmpty) {
        tasksWithIntervalEvidence.add(task.id);
        result.addAll(intervals);
      }
    }

    // Older records may pre-date the event ledger.  Preserve their recorded
    // effort, but convert it to one bounded interval instead of adding an
    // arbitrary duration to every duplicate task/session row.
    for (final task in tasksById.values) {
      if (tasksWithIntervalEvidence.contains(task.id) ||
          task.activeDurationMs <= 0) {
        continue;
      }
      final interval = _fallbackTaskInterval(task);
      if (interval != null) result.add(interval);
    }

    final runtime = snapshot.runtime;
    final runtimeTask = runtime?.activeTaskId == null
        ? null
        : tasksById[runtime!.activeTaskId!];
    if (runtimeTask != null && runtime != null) {
      final liveSegmentMs = _liveRuntimeSegmentMs(
        task: runtimeTask,
        runtime: runtime,
        effectiveNow: effectiveNow,
      );
      final segmentStartedAt = runtime.segmentStartedAt?.toUtc();
      if (liveSegmentMs > 0 && segmentStartedAt != null) {
        result.add(
          _ReportInterval(
            start: segmentStartedAt,
            end: segmentStartedAt.add(Duration(milliseconds: liveSegmentMs)),
            taskId: runtimeTask.id,
            executionMode: runtimeTask.executionMode,
          ),
        );
      }
    }
    return result.where((interval) => interval.isPositive).toList();
  }

  static List<_ReportInterval> _sessionActiveIntervals({
    required LocalEntityRecord session,
    required LocalTask task,
    required List<LocalEntityRecord> events,
    required LocalRuntime? runtime,
    required DateTime effectiveNow,
  }) {
    final data = _decodeJsonMap(session.dataJson);
    final sessionStart =
        (_parseDateTime(data['started_at']) ?? session.createdAt).toUtc();
    final state = (data['state'] ?? session.status)
        .toString()
        .trim()
        .toLowerCase();
    final finishedAt = _parseDateTime(data['finished_at'])?.toUtc();
    final sessionEnd =
        (finishedAt ??
                (const {'completed', 'cancelled', 'idle'}.contains(state)
                    ? session.updatedAt.toUtc()
                    : effectiveNow))
            .toUtc();
    if (!sessionEnd.isAfter(sessionStart)) return const [];

    final orderedEvents = [...events]
      ..sort(
        (left, right) => _eventInstant(left).compareTo(_eventInstant(right)),
      );
    final intervals = <_ReportInterval>[];
    DateTime? activeStartedAt;
    var sawActiveBoundary = false;

    for (final event in orderedEvents) {
      final at = _clampInstant(_eventInstant(event), sessionStart, sessionEnd);
      final eventType = _eventType(event);
      if (_startsActiveTime(eventType)) {
        activeStartedAt ??= at;
        sawActiveBoundary = true;
      } else if (_stopsActiveTime(eventType)) {
        // A partial history can begin with a stop event.  The session start is
        // the only defensible lower bound, and the accumulated-duration cap
        // below prevents it from inflating the report. A later stop after a
        // break must not reopen the entire session and overlap earlier work.
        if (activeStartedAt == null && !sawActiveBoundary) {
          activeStartedAt = sessionStart;
        }
        if (activeStartedAt != null && at.isAfter(activeStartedAt)) {
          intervals.add(
            _ReportInterval(
              start: activeStartedAt,
              end: at,
              taskId: task.id,
              executionMode: task.executionMode,
            ),
          );
        }
        activeStartedAt = null;
        sawActiveBoundary = true;
      }
    }

    final segmentStartedAt = _parseDateTime(
      data['active_segment_started_at'],
    )?.toUtc();
    if (activeStartedAt == null && segmentStartedAt != null) {
      activeStartedAt = _clampInstant(
        segmentStartedAt,
        sessionStart,
        sessionEnd,
      );
    }
    if (activeStartedAt == null &&
        orderedEvents.isEmpty &&
        state == 'running') {
      activeStartedAt = sessionStart;
    }
    if (activeStartedAt != null && sessionEnd.isAfter(activeStartedAt)) {
      intervals.add(
        _ReportInterval(
          start: activeStartedAt,
          end: sessionEnd,
          taskId: task.id,
          executionMode: task.executionMode,
        ),
      );
    }

    var reportedActiveMs = _integerValue(data['accumulated_active_ms']);
    // Execution transition events carry the canonical cumulative active
    // duration at each boundary. A device can receive those append-only rows
    // before the mutable session projection catches up, so never let a stale
    // zero on the session row erase already-recorded work.
    for (final event in events) {
      final eventData = _decodeJsonMap(event.dataJson);
      reportedActiveMs = math.max(
        reportedActiveMs,
        _integerValue(eventData['duration_ms']),
      );
    }
    if (runtime?.sessionId == session.id && runtime?.activeTaskId == task.id) {
      final runtimeActiveMs = _runtimeRecordedActiveMs(
        task: task,
        runtime: runtime!,
        effectiveNow: effectiveNow,
      );
      reportedActiveMs = math.max(reportedActiveMs, runtimeActiveMs);
    }
    final physicalMs = sessionEnd.difference(sessionStart).inMilliseconds;
    final cappedMs = math.min(physicalMs, reportedActiveMs);
    // A synchronized start can leave a zero-duration session row behind after
    // another device creates and completes the canonical session. Only the
    // account runtime can prove that such an open row is still live; otherwise
    // extending it to report-generation time invents days of productive work.
    final isCanonicalRunningSession =
        state == 'running' &&
        runtime?.state == 'running' &&
        runtime?.sessionId == session.id &&
        runtime?.activeTaskId == task.id;
    final maximumMs = cappedMs > 0
        ? cappedMs
        : isCanonicalRunningSession
        ? null
        : 0;
    final knownBreaks = _sessionBreakIntervals(
      session: session,
      events: events,
      runtime: runtime,
      effectiveNow: effectiveNow,
    );
    final reconciled = _reconcileIntervalsToDuration(
      intervals.where((interval) => interval.isPositive),
      maximumMs,
      sessionStart: sessionStart,
      sessionEnd: sessionEnd,
      taskId: task.id,
      executionMode: task.executionMode,
      excluded: knownBreaks,
    );
    return reconciled;
  }

  static _ReportInterval? _fallbackTaskInterval(LocalTask task) {
    final activeMs = math.max(0, task.activeDurationMs);
    if (activeMs == 0) return null;
    final rawStart = task.actualStart?.toUtc();
    final rawEnd = task.actualFinish?.toUtc();
    final start =
        rawStart ??
        (rawEnd ?? task.updatedAt.toUtc()).subtract(
          Duration(milliseconds: activeMs),
        );
    final end = rawEnd ?? start.add(Duration(milliseconds: activeMs));
    final cappedEnd = end.isAfter(start)
        ? (end.difference(start).inMilliseconds > activeMs
              ? start.add(Duration(milliseconds: activeMs))
              : end)
        : start.add(Duration(milliseconds: activeMs));
    return _ReportInterval(
      start: start,
      end: cappedEnd,
      taskId: task.id,
      executionMode: task.executionMode,
    );
  }

  static List<_ReportInterval> _pausedIntervals({
    required PerformanceReportSnapshot snapshot,
    required Map<String, LocalEntityRecord> sessionsById,
    required Map<String, String> sessionTaskById,
    required DateTime effectiveNow,
  }) {
    final eventsBySession = <String, List<LocalEntityRecord>>{};
    for (final event in snapshot.sessionEvents) {
      final data = _decodeJsonMap(event.dataJson);
      final sessionId = event.parentId ?? data['session_id']?.toString();
      if (sessionId == null || !sessionsById.containsKey(sessionId)) continue;
      eventsBySession.putIfAbsent(sessionId, () => []).add(event);
    }
    final result = <_ReportInterval>[];
    for (final entry in sessionsById.entries) {
      final session = entry.value;
      final data = _decodeJsonMap(session.dataJson);
      final sessionStart =
          (_parseDateTime(data['started_at']) ?? session.createdAt).toUtc();
      final state = (data['state'] ?? session.status).toString().toLowerCase();
      final sessionEnd =
          (_parseDateTime(data['finished_at']) ??
                  (const {'completed', 'cancelled', 'idle'}.contains(state)
                      ? session.updatedAt
                      : effectiveNow))
              .toUtc();
      DateTime? pausedAt;
      final events = [...(eventsBySession[entry.key] ?? const [])]
        ..sort(
          (left, right) => _eventInstant(left).compareTo(_eventInstant(right)),
        );
      for (final event in events) {
        final at = _clampInstant(
          _eventInstant(event),
          sessionStart,
          sessionEnd,
        );
        final type = _eventType(event);
        if (type == 'pause') {
          pausedAt ??= at;
        } else if (type == 'resume' && pausedAt != null) {
          if (at.isAfter(pausedAt)) {
            result.add(_ReportInterval(start: pausedAt, end: at));
          }
          pausedAt = null;
        }
      }
      if (pausedAt != null && sessionEnd.isAfter(pausedAt)) {
        result.add(_ReportInterval(start: pausedAt, end: sessionEnd));
      }
    }
    return result.where((interval) => interval.isPositive).toList();
  }

  static List<_ReportInterval> _breakIntervals({
    required PerformanceReportSnapshot snapshot,
    required Map<String, LocalTask> tasksById,
    required Map<String, String> sessionTaskById,
    required DateTime effectiveNow,
  }) {
    final eventsBySession = <String, List<LocalEntityRecord>>{};
    for (final event in snapshot.sessionEvents) {
      final data = _decodeJsonMap(event.dataJson);
      final sessionId = event.parentId ?? data['session_id']?.toString();
      if (sessionId == null || !sessionTaskById.containsKey(sessionId)) {
        continue;
      }
      eventsBySession.putIfAbsent(sessionId, () => []).add(event);
    }
    final result = <_ReportInterval>[];
    final sessionsById = {
      for (final session in snapshot.sessions) session.id: session,
    };
    for (final entry in eventsBySession.entries) {
      final session = sessionsById[entry.key];
      if (session == null) continue;
      result.addAll(
        _sessionBreakIntervals(
          session: session,
          events: entry.value,
          runtime: snapshot.runtime,
          effectiveNow: effectiveNow,
        ),
      );
    }

    for (final cycle in snapshot.pomodoroCycles) {
      final data = _decodeJsonMap(cycle.dataJson);
      final taskId =
          cycle.secondaryParentId ??
          data['task_occurrence_id']?.toString() ??
          sessionTaskById[cycle.parentId];
      if (taskId == null || tasksById[taskId]?.executionMode != 'pomodoro') {
        continue;
      }
      final breakMs = _integerValue(data['break_duration_ms']);
      if (breakMs <= 0) continue;
      final started = _parseDateTime(
        data['break_started_at'] ??
            data['started_at'] ??
            data['focus_finished_at'],
      )?.toUtc();
      final ended = _parseDateTime(
        data['break_finished_at'] ?? data['ended_at'],
      )?.toUtc();
      final end = ended ?? cycle.updatedAt.toUtc();
      final start = started ?? end.subtract(Duration(milliseconds: breakMs));
      final boundedEnd = end.difference(start).inMilliseconds > breakMs
          ? start.add(Duration(milliseconds: breakMs))
          : end;
      if (boundedEnd.isAfter(start)) {
        result.add(_ReportInterval(start: start, end: boundedEnd));
      }
    }

    final runtime = snapshot.runtime;
    if (runtime?.state == 'break' && runtime?.segmentStartedAt != null) {
      final task = runtime?.activeTaskId == null
          ? null
          : tasksById[runtime!.activeTaskId!];
      if (task?.executionMode == 'pomodoro') {
        result.add(
          _ReportInterval(
            start: runtime!.segmentStartedAt!.toUtc(),
            end: effectiveNow,
          ),
        );
      }
    }
    return result.where((interval) => interval.isPositive).toList();
  }

  static List<_ReportInterval> _sessionBreakIntervals({
    required LocalEntityRecord session,
    required List<LocalEntityRecord> events,
    required LocalRuntime? runtime,
    required DateTime effectiveNow,
  }) {
    final sessionData = _decodeJsonMap(session.dataJson);
    final sessionStart =
        (_parseDateTime(sessionData['started_at']) ?? session.createdAt)
            .toUtc();
    final canonicalLiveBreak =
        runtime?.state == 'break' && runtime?.sessionId == session.id;
    final sessionEnd =
        (_parseDateTime(sessionData['finished_at']) ??
                (canonicalLiveBreak ? effectiveNow : session.updatedAt))
            .toUtc();
    if (!sessionEnd.isAfter(sessionStart)) return const [];

    final orderedEvents = [...events]
      ..sort(
        (left, right) => _eventInstant(left).compareTo(_eventInstant(right)),
      );
    var finalActiveMs = _integerValue(sessionData['accumulated_active_ms']);
    for (final event in orderedEvents) {
      finalActiveMs = math.max(
        finalActiveMs,
        _integerValue(_decodeJsonMap(event.dataJson)['duration_ms']),
      );
    }
    if (runtime?.sessionId == session.id) {
      finalActiveMs = math.max(finalActiveMs, runtime!.accumulatedActiveMs);
    }

    final result = <_ReportInterval>[];
    DateTime? breakStartedAt;
    var activeMsAtBreakStart = 0;
    for (final event in orderedEvents) {
      final at = _clampInstant(_eventInstant(event), sessionStart, sessionEnd);
      final type = _eventType(event);
      final activeMs = _integerValue(
        _decodeJsonMap(event.dataJson)['duration_ms'],
      );
      if (type == 'start_break') {
        breakStartedAt ??= at;
        activeMsAtBreakStart = math.max(activeMsAtBreakStart, activeMs);
        continue;
      }
      if (!const {
            'finish_break',
            'skip_break',
            'complete',
            'finish_task',
            'cancel',
            'cancelled',
          }.contains(type) ||
          breakStartedAt == null) {
        continue;
      }
      final activeAfterBreakStarted = math.max(
        0,
        activeMs - activeMsAtBreakStart,
      );
      final inferredEnd = at.subtract(
        Duration(milliseconds: activeAfterBreakStarted),
      );
      final end = inferredEnd.isBefore(breakStartedAt)
          ? breakStartedAt
          : inferredEnd;
      if (end.isAfter(breakStartedAt)) {
        result.add(_ReportInterval(start: breakStartedAt, end: end));
      }
      breakStartedAt = null;
      activeMsAtBreakStart = 0;
    }
    if (breakStartedAt != null) {
      final activeAfterBreakStarted = math.max(
        0,
        finalActiveMs - activeMsAtBreakStart,
      );
      final inferredEnd = sessionEnd.subtract(
        Duration(milliseconds: activeAfterBreakStarted),
      );
      final end = inferredEnd.isBefore(breakStartedAt)
          ? breakStartedAt
          : inferredEnd;
      if (end.isAfter(breakStartedAt)) {
        result.add(_ReportInterval(start: breakStartedAt, end: end));
      }
    }
    return result.where((interval) => interval.isPositive).toList();
  }

  static List<_ReportInterval> _interruptionIntervals(
    Iterable<LocalEntityRecord> interruptions,
    DateTime effectiveNow,
  ) {
    final result = <_ReportInterval>[];
    for (final interruption in interruptions) {
      final data = _decodeJsonMap(interruption.dataJson);
      final durationMs =
          _integerValue(data['duration_ms']) +
          _integerValue(data['duration_seconds']) * 1000;
      final started = _parseDateTime(data['started_at'])?.toUtc();
      final ended = _parseDateTime(data['ended_at'])?.toUtc();
      final end =
          ended ??
          (started != null && durationMs > 0
              ? started.add(Duration(milliseconds: durationMs))
              : interruption.createdAt.toUtc());
      final start =
          started ??
          (durationMs > 0
              ? end.subtract(Duration(milliseconds: durationMs))
              : end);
      final boundedEnd =
          durationMs > 0 && end.difference(start).inMilliseconds > durationMs
          ? start.add(Duration(milliseconds: durationMs))
          : (ended == null && durationMs == 0 ? effectiveNow : end);
      if (boundedEnd.isAfter(start)) {
        final type = data['interruption_type']?.toString().trim();
        result.add(
          _ReportInterval(
            start: start,
            end: boundedEnd,
            label: type == null || type.isEmpty ? 'other' : type,
          ),
        );
      }
    }
    return result;
  }

  static List<_ReportInterval> _activityIntervals(
    Iterable<LocalActivitySegment> segments,
    AppLocalizations l10n,
  ) {
    final deduplicated = <String, _ReportInterval>{};
    for (final segment in segments) {
      final start = segment.startedAt.toUtc();
      final end = segment.endedAt.toUtc();
      if (!end.isAfter(start)) continue;
      final website = _websiteLabel(segment);
      final interval = _ReportInterval(
        start: start,
        end: end,
        label:
            website ??
            applicationLabel(
              segment,
              unavailableLabel: l10n.text('report_record_unavailable'),
            ),
        isWebsite: website != null,
        isIdle: _isIdleActivity(segment),
      );
      final eventId = segment.deviceEventId.trim();
      final identity = eventId.isEmpty
          ? segment.id
          : '${segment.deviceId.trim().toLowerCase()}|$eventId';
      final existing = deduplicated[identity];
      if (existing == null || interval.durationMs > existing.durationMs) {
        deduplicated[identity] = interval;
      }
    }
    return deduplicated.values.toList(growable: false);
  }

  static Map<DateTime, _ProductiveAllocation> _allocateProductiveByDay(
    Iterable<_ReportInterval> intervals,
    PerformanceReportOptions options,
  ) {
    final result = <DateTime, _ProductiveAllocation>{};
    for (final day in _reportDays(options)) {
      result[day.day] = _allocateProductiveIntervals(
        _clipIntervals(intervals, day.start, day.end),
      );
    }
    return result;
  }

  static Map<DateTime, _ActivityAllocation> _allocateActivityByDay(
    Iterable<_ReportInterval> intervals,
    PerformanceReportOptions options,
  ) {
    final result = <DateTime, _ActivityAllocation>{};
    for (final day in _reportDays(options)) {
      result[day.day] = _allocateActivityIntervals(
        _clipIntervals(intervals, day.start, day.end),
      );
    }
    return result;
  }

  static int _durationByDay(
    Iterable<_ReportInterval> intervals,
    PerformanceReportOptions options,
  ) {
    var total = 0;
    for (final day in _reportDays(options)) {
      total += _unionDuration(_clipIntervals(intervals, day.start, day.end));
    }
    return total;
  }

  static Map<String, int> _allocateLabelsByDay(
    Iterable<_ReportInterval> intervals,
    PerformanceReportOptions options,
  ) {
    final result = <String, int>{};
    for (final day in _reportDays(options)) {
      _addAll(
        result,
        _allocateLabelIntervals(_clipIntervals(intervals, day.start, day.end)),
      );
    }
    return result;
  }

  /// Allocates each physical slice once even when two categorized records
  /// overlap. This keeps the category chart equal to the elapsed-time union.
  static Map<String, int> _allocateLabelIntervals(
    Iterable<_ReportInterval> source,
  ) {
    final intervals = source.where((interval) => interval.isPositive).toList();
    final boundaries = _intervalBoundaries(intervals);
    final result = <String, int>{};
    for (var index = 0; index + 1 < boundaries.length; index++) {
      final start = boundaries[index];
      final end = boundaries[index + 1];
      if (!end.isAfter(start)) continue;
      final labels =
          intervals
              .where(
                (interval) =>
                    !interval.start.isAfter(start) &&
                    !interval.end.isBefore(end),
              )
              .map((interval) => interval.label?.trim() ?? '')
              .where((label) => label.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
      if (labels.isEmpty) continue;
      _splitDuration(end.difference(start).inMilliseconds, labels, (
        label,
        shareMs,
      ) {
        result.update(
          label,
          (value) => value + shareMs,
          ifAbsent: () => shareMs,
        );
      });
    }
    return result;
  }

  static List<_ReportInterval> _clipIntervals(
    Iterable<_ReportInterval> intervals,
    DateTime start,
    DateTime end,
  ) => intervals
      .map((interval) => interval.clip(start, end))
      .where((interval) => interval.isPositive)
      .toList(growable: false);

  static _ProductiveAllocation _allocateProductiveIntervals(
    Iterable<_ReportInterval> source,
  ) {
    final intervals = source.where((interval) => interval.isPositive).toList();
    final boundaries = _intervalBoundaries(intervals);
    final byTask = <String, int>{};
    final byMode = <String, int>{};
    var totalMs = 0;
    for (var index = 0; index + 1 < boundaries.length; index++) {
      final start = boundaries[index];
      final end = boundaries[index + 1];
      if (!end.isAfter(start)) continue;
      final candidates = intervals
          .where(
            (interval) =>
                interval.taskId != null &&
                !interval.start.isAfter(start) &&
                !interval.end.isBefore(end),
          )
          .toList(growable: false);
      final byTaskId = <String, _ReportInterval>{};
      for (final candidate in candidates) {
        byTaskId.putIfAbsent(candidate.taskId!, () => candidate);
      }
      if (byTaskId.isEmpty) continue;
      final taskIds = byTaskId.keys.toList()..sort();
      final durationMs = end.difference(start).inMilliseconds;
      totalMs += durationMs;
      _splitDuration(durationMs, taskIds, (taskId, shareMs) {
        byTask.update(
          taskId,
          (value) => value + shareMs,
          ifAbsent: () => shareMs,
        );
        final mode =
            byTaskId[taskId]?.executionMode?.trim().toLowerCase() ?? 'manual';
        byMode.update(
          mode,
          (value) => value + shareMs,
          ifAbsent: () => shareMs,
        );
      });
    }
    return _ProductiveAllocation(
      totalMs: totalMs,
      byTask: Map.unmodifiable(byTask),
      byMode: Map.unmodifiable(byMode),
    );
  }

  static _ActivityAllocation _allocateActivityIntervals(
    Iterable<_ReportInterval> source,
  ) {
    final intervals = source.where((interval) => interval.isPositive).toList();
    final boundaries = _intervalBoundaries(intervals);
    final applications = <String, int>{};
    final websites = <String, int>{};
    var activeMs = 0;
    var idleMs = 0;
    for (var index = 0; index + 1 < boundaries.length; index++) {
      final start = boundaries[index];
      final end = boundaries[index + 1];
      if (!end.isAfter(start)) continue;
      final candidates = intervals
          .where(
            (interval) =>
                !interval.start.isAfter(start) && !interval.end.isBefore(end),
          )
          .toList(growable: false);
      if (candidates.isEmpty) continue;
      final durationMs = end.difference(start).inMilliseconds;
      final activeCandidates = candidates
          .where((interval) => !interval.isIdle)
          .toList();
      if (activeCandidates.isEmpty) {
        idleMs += durationMs;
        continue;
      }
      activeMs += durationMs;
      final labels = <String, _ReportInterval>{};
      for (final candidate in activeCandidates) {
        final label = candidate.label?.trim();
        if (label == null || label.isEmpty) continue;
        labels.putIfAbsent('${candidate.isWebsite}|$label', () => candidate);
      }
      final keys = labels.keys.toList()..sort();
      if (keys.isEmpty) continue;
      _splitDuration(durationMs, keys, (key, shareMs) {
        final interval = labels[key]!;
        final label = interval.label!;
        final target = interval.isWebsite ? websites : applications;
        target.update(
          label,
          (value) => value + shareMs,
          ifAbsent: () => shareMs,
        );
      });
    }
    return _ActivityAllocation(
      activeMs: activeMs,
      idleMs: idleMs,
      applications: Map.unmodifiable(applications),
      websites: Map.unmodifiable(websites),
    );
  }

  static List<DateTime> _intervalBoundaries(
    Iterable<_ReportInterval> intervals,
  ) {
    final values = <int>{};
    for (final interval in intervals) {
      values
        ..add(interval.start.toUtc().microsecondsSinceEpoch)
        ..add(interval.end.toUtc().microsecondsSinceEpoch);
    }
    final sorted = values.toList()..sort();
    return sorted
        .map((value) => DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true))
        .toList(growable: false);
  }

  static int _unionDuration(Iterable<_ReportInterval> source) {
    final intervals = source.where((interval) => interval.isPositive).toList()
      ..sort((left, right) => left.start.compareTo(right.start));
    if (intervals.isEmpty) return 0;
    var total = 0;
    var start = intervals.first.start;
    var end = intervals.first.end;
    for (final interval in intervals.skip(1)) {
      if (interval.start.isAfter(end)) {
        total += end.difference(start).inMilliseconds;
        start = interval.start;
        end = interval.end;
      } else if (interval.end.isAfter(end)) {
        end = interval.end;
      }
    }
    return total + end.difference(start).inMilliseconds;
  }

  static List<_ReportInterval> _reconcileIntervalsToDuration(
    Iterable<_ReportInterval> source,
    int? maximumMs, {
    required DateTime sessionStart,
    required DateTime sessionEnd,
    required String taskId,
    required String executionMode,
    Iterable<_ReportInterval> excluded = const [],
  }) {
    final exclusions =
        excluded
            .map((interval) => interval.clip(sessionStart, sessionEnd))
            .where((interval) => interval.isPositive)
            .toList()
          ..sort((left, right) => left.start.compareTo(right.start));
    final intervals = <_ReportInterval>[];
    for (final sourceInterval in source) {
      var pieces = <_ReportInterval>[
        sourceInterval.clip(sessionStart, sessionEnd),
      ].where((interval) => interval.isPositive).toList();
      for (final exclusion in exclusions) {
        final next = <_ReportInterval>[];
        for (final piece in pieces) {
          if (!exclusion.end.isAfter(piece.start) ||
              !exclusion.start.isBefore(piece.end)) {
            next.add(piece);
            continue;
          }
          if (exclusion.start.isAfter(piece.start)) {
            next.add(
              _ReportInterval(
                start: piece.start,
                end: exclusion.start,
                taskId: piece.taskId,
                executionMode: piece.executionMode,
              ),
            );
          }
          if (exclusion.end.isBefore(piece.end)) {
            next.add(
              _ReportInterval(
                start: exclusion.end,
                end: piece.end,
                taskId: piece.taskId,
                executionMode: piece.executionMode,
              ),
            );
          }
        }
        pieces = next;
      }
      intervals.addAll(pieces.where((interval) => interval.isPositive));
    }
    intervals.sort((left, right) => left.start.compareTo(right.start));
    if (maximumMs == null) return intervals;
    var remaining = math.min(
      math.max(0, maximumMs),
      sessionEnd.difference(sessionStart).inMilliseconds,
    );
    if (remaining == 0) return const [];

    final coverage = <_ReportInterval>[];
    for (final interval in intervals) {
      final previous = coverage.lastOrNull;
      if (previous == null || interval.start.isAfter(previous.end)) {
        coverage.add(interval);
      } else if (interval.end.isAfter(previous.end)) {
        coverage[coverage.length - 1] = _ReportInterval(
          start: previous.start,
          end: interval.end,
          taskId: taskId,
          executionMode: executionMode,
        );
      }
    }

    final result = <_ReportInterval>[];
    for (final interval in coverage) {
      if (remaining <= 0) break;
      final durationMs = math.min(remaining, interval.durationMs);
      result.add(
        _ReportInterval(
          start: interval.start,
          end: interval.start.add(Duration(milliseconds: durationMs)),
          taskId: interval.taskId,
          executionMode: interval.executionMode,
        ),
      );
      remaining -= durationMs;
    }
    if (remaining <= 0) return result;

    // Missing or delayed event rows must not erase an authoritative cumulative
    // total. Fill uncovered time from the session end backwards: cumulative
    // boundary durations prove that missing work happened after the preceding
    // boundary, while known breaks are never reused as productive time.
    final blocked = [...coverage, ...exclusions]
      ..sort((left, right) => left.start.compareTo(right.start));
    final mergedBlocked = <_ReportInterval>[];
    for (final interval in blocked) {
      final previous = mergedBlocked.lastOrNull;
      if (previous == null || interval.start.isAfter(previous.end)) {
        mergedBlocked.add(interval);
      } else if (interval.end.isAfter(previous.end)) {
        mergedBlocked[mergedBlocked.length - 1] = _ReportInterval(
          start: previous.start,
          end: interval.end,
        );
      }
    }
    final gaps = <_ReportInterval>[];
    var cursor = sessionStart;
    for (final interval in mergedBlocked) {
      if (interval.start.isAfter(cursor)) {
        gaps.add(_ReportInterval(start: cursor, end: interval.start));
      }
      if (interval.end.isAfter(cursor)) cursor = interval.end;
    }
    if (sessionEnd.isAfter(cursor)) {
      gaps.add(_ReportInterval(start: cursor, end: sessionEnd));
    }
    for (final gap in gaps.reversed) {
      if (remaining <= 0) break;
      final durationMs = math.min(remaining, gap.durationMs);
      result.add(
        _ReportInterval(
          start: gap.end.subtract(Duration(milliseconds: durationMs)),
          end: gap.end,
          taskId: taskId,
          executionMode: executionMode,
        ),
      );
      remaining -= durationMs;
    }
    result.sort((left, right) => left.start.compareTo(right.start));
    return result;
  }

  static void _splitDuration(
    int durationMs,
    List<String> keys,
    void Function(String key, int shareMs) onShare,
  ) {
    if (durationMs <= 0 || keys.isEmpty) return;
    final base = durationMs ~/ keys.length;
    final remainder = durationMs % keys.length;
    for (var index = 0; index < keys.length; index++) {
      onShare(keys[index], base + (index < remainder ? 1 : 0));
    }
  }

  static void _addAll(Map<String, int> target, Map<String, int> additions) {
    for (final entry in additions.entries) {
      target.update(
        entry.key,
        (value) => value + entry.value,
        ifAbsent: () => entry.value,
      );
    }
  }

  static List<({DateTime day, DateTime start, DateTime end})> _reportDays(
    PerformanceReportOptions options,
  ) {
    final location = _reportLocation(options.timeZone);
    final result = <({DateTime day, DateTime start, DateTime end})>[];
    for (
      var day = _startOfDay(options.from);
      !day.isAfter(_startOfDay(options.to));
      day = day.add(const Duration(days: 1))
    ) {
      final start = tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day,
      ).toUtc();
      final localNextDay = tz.TZDateTime(
        location,
        day.year,
        day.month,
        day.day + 1,
      ).toUtc();
      // An elapsed-time report never claims more than 24 hours for one
      // calendar date, even if corrupt input or a DST transition presents a
      // longer physical range.
      final end = localNextDay.isAfter(start.add(const Duration(hours: 24)))
          ? start.add(const Duration(hours: 24))
          : localNextDay;
      result.add((day: day, start: start, end: end));
    }
    return result;
  }

  static tz.Location _reportLocation(String timeZone) {
    final normalized = TimeZoneService.isValidIana(timeZone) ? timeZone : 'UTC';
    return tz.getLocation(normalized == 'UTC' ? 'Etc/UTC' : normalized);
  }

  static DateTime _eventInstant(LocalEntityRecord event) {
    final data = _decodeJsonMap(event.dataJson);
    return (_parseDateTime(data['occurred_at']) ??
            _parseDateTime(data['created_at']) ??
            event.createdAt)
        .toUtc();
  }

  static String _eventType(LocalEntityRecord event) {
    final data = _decodeJsonMap(event.dataJson);
    return (data['event_type'] ?? event.title)
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  static bool _startsActiveTime(String eventType) => const {
    'start',
    'resume',
    'finish_break',
    'skip_break',
    'start_focus',
    'start_focus_now',
    'continue',
    'continue_working',
  }.contains(eventType);

  static bool _stopsActiveTime(String eventType) => const {
    'pause',
    'start_break',
    'complete',
    'finish_focus',
    'finish_task',
    'cancel',
    'cancelled',
  }.contains(eventType);

  static DateTime _clampInstant(DateTime value, DateTime start, DateTime end) {
    final utc = value.toUtc();
    if (utc.isBefore(start)) return start;
    if (utc.isAfter(end)) return end;
    return utc;
  }

  static bool _isIdleActivity(LocalActivitySegment segment) => const {
    'idle',
    'inactive',
    'technical_idle',
  }.contains(segment.idleState?.trim().toLowerCase());

  static Map<String, Object?> _decodeJsonMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  static num? _numericValue(Object? value) {
    if (value is num) return value;
    return value is String ? num.tryParse(value) : null;
  }

  static int _integerValue(Object? value) =>
      math.max(0, _numericValue(value)?.round() ?? 0);

  static String? _websiteLabel(LocalActivitySegment segment) {
    final explicitDomain = _registrableDomain(segment.domain);
    return explicitDomain ?? _registrableDomain(segment.url);
  }

  static String? _registrableDomain(String? raw) {
    var value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (!value.contains('://')) value = 'https://$value';
    final host = Uri.tryParse(value)?.host.trim().toLowerCase() ?? '';
    if (host.isEmpty) return null;
    final normalized = host.replaceFirst(RegExp(r'^www\.'), '');
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(normalized) ||
        normalized.contains(':')) {
      return normalized;
    }
    final parts = normalized
        .split('.')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 2) return parts.join('.');
    final suffix = parts.sublist(parts.length - 2).join('.');
    const compoundSuffixes = {
      'co.uk',
      'org.uk',
      'ac.uk',
      'gov.uk',
      'com.au',
      'net.au',
      'org.au',
      'co.nz',
      'co.jp',
      'com.br',
      'com.mx',
      'com.sg',
      'com.tr',
      'co.in',
    };
    return compoundSuffixes.contains(suffix) && parts.length >= 3
        ? parts.sublist(parts.length - 3).join('.')
        : suffix;
  }

  static DateTime _healthSummaryDate(
    LocalEntityRecord record,
    Map<String, Object?> data,
  ) {
    return _parseDateTime(data['summary_date']) ??
        _parseDateTime(data['window_start_at']) ??
        record.updatedAt;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is DateTime) return value;
    if (value is! String || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim());
  }

  static List<String> _healthSources(Map<String, Object?> data) {
    final sources = <String>{};
    final applications = data['source_applications'];
    if (applications is Iterable) {
      for (final source in applications) {
        final value = source?.toString().trim() ?? '';
        if (value.isNotEmpty) sources.add(value);
      }
    }
    final fallback = data['source']?.toString() ?? '';
    for (final source in fallback.split(',')) {
      final value = source.trim();
      if (value.isNotEmpty) sources.add(value);
    }
    return sources.toList(growable: false);
  }

  static DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _endExclusive(DateTime value) =>
      DateTime(value.year, value.month, value.day).add(const Duration(days: 1));

  static bool _dateFallsInRange(
    DateTime value,
    PerformanceReportOptions options,
  ) {
    // Health summaries use YYYY-MM-DD calendar dates.  Preserve that date
    // rather than shifting a local DateTime.parse result through UTC.
    final isFloatingCalendarDate =
        !value.isUtc &&
        value.hour == 0 &&
        value.minute == 0 &&
        value.second == 0 &&
        value.millisecond == 0 &&
        value.microsecond == 0;
    final localDay = isFloatingCalendarDate
        ? _startOfDay(value)
        : TaskOccurrencePolicy.localDateAt(value, timeZone: options.timeZone);
    return !localDay.isBefore(_startOfDay(options.from)) &&
        localDay.isBefore(_endExclusive(options.to));
  }

  Future<PerformanceReportSnapshot> load(
    PerformanceReportOptions options,
  ) async {
    final reportDays = _reportDays(options);
    final reportStart = reportDays.first.start;
    final reportEnd = reportDays.last.end;
    final profiles = await (database.select(
      database.localProfiles,
    )..where((row) => row.deletedAt.isNull())).get();
    final domains = await (database.select(
      database.localDomains,
    )..where((row) => row.deletedAt.isNull() & row.archivedAt.isNull())).get();
    final allRoadmaps = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.deletedAt.isNull())).get();
    final roadmap =
        options.type != PerformanceReportType.roadmap ||
            options.roadmapId == null
        ? null
        : allRoadmaps.where((item) => item.id == options.roadmapId).firstOrNull;
    final allTasks = await (database.select(
      database.localTasks,
    )..where((row) => row.deletedAt.isNull())).get();
    final tasks = tasksForReport(allTasks, options);
    final allActivity =
        await (database.select(database.localActivitySegments)..where(
              (row) =>
                  row.deletedAt.isNull() &
                  row.endedAt.isBiggerThanValue(reportStart) &
                  row.startedAt.isSmallerThanValue(reportEnd),
            ))
            .get();
    final taskIds = tasks.map((task) => task.id).toSet();
    final activityIds = allActivity.map((item) => item.id).toSet();
    final attributions = activityIds.isEmpty
        ? const <LocalAttribution>[]
        : await (database.select(database.localAttributions)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    row.activitySegmentId.isIn(activityIds),
              ))
              .get();
    final reportableActivity = reportableActivitySegments(
      segments: allActivity,
      attributions: attributions,
    );
    final reportableActivityIds = reportableActivity
        .map((item) => item.id)
        .toSet();
    final allContributions = await (database.select(
      database.localContributions,
    )..where((row) => row.deletedAt.isNull())).get();
    final contributions = allContributions
        .where((item) {
          if (!reportableActivityIds.contains(item.activitySegmentId)) {
            return false;
          }
          return switch (options.type) {
            PerformanceReportType.account => true,
            PerformanceReportType.task ||
            PerformanceReportType.household => taskIds.contains(item.targetId),
            PerformanceReportType.roadmap =>
              item.targetId == options.roadmapId ||
                  taskIds.contains(item.targetId),
          };
        })
        .toList(growable: false);
    final scopedActivityIds = contributions
        .map((item) => item.activitySegmentId)
        .toSet();
    final activity = options.type == PerformanceReportType.account
        ? reportableActivity
        : reportableActivity
              .where((item) => scopedActivityIds.contains(item.id))
              .toList(growable: false);
    final entityTypes = <String>{
      'roadmap_phases',
      'roadmap_milestones',
      'roadmap_checkpoints',
      'coaching_insights',
      'execution_sessions',
      'session_events',
      'pomodoro_cycles',
      'interruptions',
      if (options.includesHealth) 'health_summaries',
      if (options.includesHealth) 'task_health_summaries',
    };
    final allEntities =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.deletedAt.isNull() & row.entityType.isIn(entityTypes),
            ))
            .get();
    bool isRoadmapChild(LocalEntityRecord record) =>
        options.type == PerformanceReportType.roadmap &&
        options.roadmapId != null &&
        record.parentId == options.roadmapId;
    final phases =
        allEntities
            .where(
              (record) =>
                  record.entityType == 'roadmap_phases' &&
                  isRoadmapChild(record),
            )
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final milestones = allEntities
        .where(
          (record) =>
              record.entityType == 'roadmap_milestones' &&
              isRoadmapChild(record),
        )
        .toList();
    final checkpoints = allEntities
        .where(
          (record) =>
              record.entityType == 'roadmap_checkpoints' &&
              isRoadmapChild(record),
        )
        .toList();
    final insights = allEntities.where((record) {
      if (record.entityType != 'coaching_insights') return false;
      return switch (options.type) {
        PerformanceReportType.account =>
          record.parentId == null || taskIds.contains(record.parentId),
        PerformanceReportType.task ||
        PerformanceReportType.household => taskIds.contains(record.parentId),
        PerformanceReportType.roadmap =>
          record.parentId == options.roadmapId ||
              taskIds.contains(record.parentId),
      };
    }).toList();
    bool recordMatchesTaskScope(LocalEntityRecord record) {
      final data = _decodeJsonMap(record.dataJson);
      final taskId =
          record.parentId ??
          record.secondaryParentId ??
          data['task_occurrence_id']?.toString() ??
          data['task_id']?.toString();
      return taskId != null && taskIds.contains(taskId);
    }

    bool recordFallsInRange(LocalEntityRecord record) {
      final data = _decodeJsonMap(record.dataJson);
      final start =
          _parseDateTime(data['started_at']) ??
          _parseDateTime(data['focus_started_at']) ??
          _parseDateTime(data['created_at']) ??
          record.createdAt;
      final end =
          _parseDateTime(data['finished_at']) ??
          _parseDateTime(data['ended_at']) ??
          _parseDateTime(data['occurred_at']) ??
          record.updatedAt;
      return end.toUtc().isAfter(reportStart) &&
          start.toUtc().isBefore(reportEnd);
    }

    final sessions = allEntities
        .where(
          (record) =>
              record.entityType == 'execution_sessions' &&
              recordMatchesTaskScope(record) &&
              recordFallsInRange(record),
        )
        .toList(growable: false);
    final sessionIds = sessions.map((record) => record.id).toSet();
    final sessionEvents = allEntities
        .where((record) {
          if (record.entityType != 'session_events') return false;
          final data = _decodeJsonMap(record.dataJson);
          final sessionId = record.parentId ?? data['session_id']?.toString();
          return sessionId != null && sessionIds.contains(sessionId);
        })
        .toList(growable: false);
    final pomodoroCycles = allEntities
        .where((record) {
          if (record.entityType != 'pomodoro_cycles' ||
              !recordFallsInRange(record)) {
            return false;
          }
          return sessionIds.contains(record.parentId) ||
              recordMatchesTaskScope(record);
        })
        .toList(growable: false);
    final interruptions = allEntities
        .where(
          (record) =>
              record.entityType == 'interruptions' &&
              recordMatchesTaskScope(record) &&
              recordFallsInRange(record),
        )
        .toList(growable: false);
    final health = options.includesHealth
        ? allEntities
              .where((record) {
                final matchesScope =
                    options.type == PerformanceReportType.account
                    ? record.entityType == 'health_summaries'
                    : record.entityType == 'task_health_summaries' &&
                          taskIds.contains(record.parentId);
                return matchesScope &&
                    _dateFallsInRange(
                      _healthSummaryDate(
                        record,
                        _decodeJsonMap(record.dataJson),
                      ),
                      options,
                    );
              })
              .toList(growable: false)
        : const <LocalEntityRecord>[];
    final reportUserId =
        tasks.firstOrNull?.userId ??
        roadmap?.userId ??
        profiles.firstOrNull?.userId;
    final runtime = reportUserId == null
        ? null
        : await (database.select(database.localRuntimeStates)
                ..where((row) => row.userId.equals(reportUserId))
                ..limit(1))
              .getSingleOrNull();
    return PerformanceReportSnapshot(
      profile: profiles.firstOrNull,
      roadmap: roadmap,
      tasks: tasks,
      phases: phases,
      milestones: milestones,
      checkpoints: checkpoints,
      activity: activity,
      contributions: contributions,
      attributions: attributions,
      insights: insights,
      health: health,
      roadmaps: allRoadmaps,
      domains: domains,
      sessions: sessions,
      sessionEvents: sessionEvents,
      pomodoroCycles: pomodoroCycles,
      interruptions: interruptions,
      runtime: runtime,
    );
  }

  Future<Uint8List> buildPdf(
    PerformanceReportSnapshot snapshot,
    PerformanceReportOptions options,
  ) async {
    await initializeDateFormatting(options.localeCode);
    final l10n = AppLocalizations(Locale(options.localeCode));
    final rtl = options.localeCode == 'ar';
    final fontData = await rootBundle.load(
      'assets/fonts/NotoSansArabic-Regular.ttf',
    );
    final font = pw.Font.ttf(fontData);
    final logoData = await rootBundle.load(
      'media/app-logo/TaskMaster_Pro_Light_Transparent.png',
    );
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());
    pw.MemoryImage? avatar;
    final avatarPath = snapshot.profile?.imagePath;
    if (avatarPath != null && File(avatarPath).existsSync()) {
      try {
        avatar = pw.MemoryImage(await File(avatarPath).readAsBytes());
      } catch (_) {
        avatar = null;
      }
    }
    final document = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
      title: l10n.text(options.type.titleLocalizationKey),
      author: snapshot.profile?.displayName ?? 'TaskMaster Pro',
    );
    final format = options.landscape
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
    final dateFormat = DateFormat.yMMMd(options.localeCode);
    final dateTimeFormat = DateFormat.yMMMd(options.localeCode).add_jm();
    final healthSummaries = healthSummariesForReport(snapshot.health, options);
    final facts = factsForSnapshot(snapshot, options, l10n);
    final taskGroups = taskGroupsForReport(
      snapshot.tasks,
      facts,
      timeZone: options.timeZone,
    );
    String duration(int milliseconds) =>
        l10n.duration(Duration(milliseconds: milliseconds));
    final delays = snapshot.tasks
        .where((task) => task.plannedStart != null && task.actualStart != null)
        .map(
          (task) => task.actualStart!
              .difference(task.plannedStart!)
              .inMilliseconds
              .clamp(0, 1 << 62),
        )
        .toList();
    final averageDelay = delays.isEmpty
        ? 0
        : delays.reduce((a, b) => a + b) ~/ delays.length;

    pw.Widget localized(pw.Widget child) {
      return pw.Directionality(
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        child: child,
      );
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.fromLTRB(34, 32, 34, 34),
        header: (context) => localized(
          _header(
            l10n: l10n,
            snapshot: snapshot,
            options: options,
            dateFormat: dateFormat,
            logo: logo,
            avatar: avatar,
            rtl: rtl,
          ),
        ),
        footer: (context) => localized(
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                l10n.format('report_generated', {
                  'date': dateFormat.format(DateTime.now()),
                }),
                style: const pw.TextStyle(
                  color: PdfColors.blueGrey600,
                  fontSize: 8,
                ),
              ),
              pw.Text(
                l10n.format('report_page_number', {
                  'page': context.pageNumber,
                  'pages': context.pagesCount,
                }),
                style: const pw.TextStyle(
                  color: PdfColors.blueGrey600,
                  fontSize: 8,
                ),
              ),
            ],
          ),
        ),
        build: (context) {
          final widgets = <pw.Widget>[
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _title(l10n.text(options.type.titleLocalizationKey), rtl),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${dateFormat.format(options.from)} - '
                  '${dateFormat.format(options.to)}',
                  textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.left,
                  style: const pw.TextStyle(color: PdfColors.blueGrey700),
                ),
                if (snapshot.roadmap != null) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    snapshot.roadmap!.title,
                    textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.left,
                    style: const pw.TextStyle(
                      color: PdfColors.blue700,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (options.type == PerformanceReportType.task &&
                    snapshot.tasks.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    snapshot.tasks.first.title,
                    textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.left,
                    style: const pw.TextStyle(
                      color: PdfColors.blue700,
                      fontSize: 13,
                    ),
                  ),
                ],
                pw.SizedBox(height: 18),
              ],
            ),
          ];
          if (options.sections.contains('summary')) {
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(l10n.text('report_summary'), rtl),
                  pw.Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metric(
                        l10n.text('report_planned_effort'),
                        duration(facts.plannedMs),
                      ),
                      _metric(
                        l10n.text('report_productive_work'),
                        duration(facts.productiveMs),
                      ),
                      _metric(
                        l10n.text('report_focus_time'),
                        duration(facts.focusMs),
                      ),
                      _metric(
                        l10n.text('report_break_time'),
                        duration(facts.breakMs),
                      ),
                      _metric(
                        l10n.text('report_continuous_work'),
                        duration(facts.continuousMs),
                      ),
                      _metric(
                        l10n.text('report_interruptions'),
                        facts.interruptionCount == 0
                            ? l10n.text('report_no_interruptions_short')
                            : l10n.format('report_interruption_value', {
                                'count': facts.interruptionCount,
                                'duration': duration(facts.interruptionMs),
                              }),
                      ),
                      _metric(
                        l10n.text('report_active_activity'),
                        duration(facts.activeActivityMs),
                      ),
                      _metric(
                        l10n.text('report_idle_activity'),
                        duration(facts.idleActivityMs),
                      ),
                      _metric(
                        l10n.text('report_paused_time'),
                        duration(facts.pausedMs),
                      ),
                      _metric(
                        l10n.text('report_completion_rate'),
                        snapshot.tasks.isEmpty
                            ? '0%'
                            : '${(facts.completedTasks / snapshot.tasks.length * 100).round()}%',
                      ),
                      _metric(
                        l10n.text('report_average_start_delay'),
                        duration(averageDelay),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  _barChart(
                    l10n: l10n,
                    rtl: rtl,
                    values: {
                      l10n.text('status_completed'): facts.completedTasks
                          .toDouble(),
                      l10n.text('status_overdue'): facts.overdueTasks
                          .toDouble(),
                      l10n.text('report_remaining_tasks'):
                          (snapshot.tasks.length -
                                  facts.completedTasks -
                                  facts.overdueTasks)
                              .clamp(0, snapshot.tasks.length)
                              .toDouble(),
                    },
                  ),
                  if (facts.focusMs > 0 || facts.continuousMs > 0) ...[
                    pw.SizedBox(height: 12),
                    _durationChart(
                      title: l10n.text('report_focus_vs_continuous'),
                      values: {
                        l10n.text('report_focus_time'): facts.focusMs,
                        l10n.text('report_continuous_work'): facts.continuousMs,
                      },
                      duration: duration,
                      rtl: rtl,
                    ),
                  ],
                  if (facts.focusMs > 0 || facts.breakMs > 0) ...[
                    pw.SizedBox(height: 12),
                    _durationChart(
                      title: l10n.text('report_focus_vs_break'),
                      values: {
                        l10n.text('report_focus_time'): facts.focusMs,
                        l10n.text('report_break_time'): facts.breakMs,
                      },
                      duration: duration,
                      rtl: rtl,
                    ),
                  ],
                  if (facts.taskDomains.isNotEmpty) ...[
                    pw.SizedBox(height: 12),
                    _durationChart(
                      title: l10n.text('report_work_by_area'),
                      values: {
                        for (final entry in facts.taskDomains.take(6))
                          entry.label: entry.durationMs,
                      },
                      duration: duration,
                      rtl: rtl,
                    ),
                  ],
                  if (facts.interruptionTypes.isNotEmpty) ...[
                    pw.SizedBox(height: 12),
                    _durationChart(
                      title: l10n.text('report_interruption_distribution'),
                      values: {
                        for (final entry in facts.interruptionTypes.take(6))
                          entry.label: entry.durationMs,
                      },
                      duration: duration,
                      rtl: rtl,
                    ),
                  ],
                  if (facts.daily.any(
                    (point) => point.plannedMs > 0 || point.productiveMs > 0,
                  )) ...[
                    pw.SizedBox(height: 12),
                    _dailyWorkTable(facts.daily, l10n, dateFormat, duration),
                  ] else ...[
                    pw.SizedBox(height: 10),
                    pw.Text(l10n.text('report_no_chart_data')),
                  ],
                  pw.SizedBox(height: 18),
                ],
              ),
            );
          }
          if (options.sections.contains('roadmaps')) {
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(l10n.text('report_roadmap_progress'), rtl),
                  if (snapshot.roadmap != null)
                    _roadmapSummary(snapshot, l10n, dateFormat, duration, rtl)
                  else
                    ...linkedRoadmapLabels(
                          snapshot.tasks,
                          snapshot.roadmaps,
                          l10n,
                        )
                        .take(8)
                        .map(
                          (name) => pw.Bullet(
                            text: l10n.format('report_linked_roadmap_name', {
                              'name': name,
                            }),
                          ),
                        ),
                  if (facts.phases.isNotEmpty) ...[
                    pw.SizedBox(height: 12),
                    _durationChart(
                      title: l10n.text('report_phase_progress'),
                      values: {
                        for (final entry in facts.phases.take(8))
                          entry.label: entry.durationMs,
                      },
                      duration: duration,
                      rtl: rtl,
                    ),
                  ] else if (facts.roadmaps.isNotEmpty) ...[
                    pw.SizedBox(height: 12),
                    _durationChart(
                      title: l10n.text('report_roadmap_progress'),
                      values: {
                        for (final entry in facts.roadmaps.take(8))
                          entry.label: entry.durationMs,
                      },
                      duration: duration,
                      rtl: rtl,
                    ),
                  ],
                  pw.SizedBox(height: 18),
                ],
              ),
            );
          }
          if (options.sections.contains('tasks')) {
            widgets.add(pw.NewPage(freeSpace: 240));
            widgets.add(_sectionTitle(l10n.text('report_tasks'), rtl));
            widgets.add(_taskGroupTable(taskGroups, l10n, duration, rtl));
            widgets.add(pw.SizedBox(height: 18));
          }
          if (options.sections.contains('activity')) {
            widgets.add(pw.NewPage(freeSpace: 100));
            widgets.add(_sectionTitle(l10n.text('report_activity'), rtl));
            widgets.add(_activitySummary(snapshot, facts, l10n, duration, rtl));
            widgets.add(pw.SizedBox(height: 10));
            widgets.add(
              _namedDurationSummary(
                title: l10n.text('report_application_usage'),
                entries: facts.applications,
                emptyLabel: l10n.text('report_no_application_usage'),
                duration: duration,
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
            widgets.add(
              _namedDurationSummary(
                title: l10n.text('report_website_usage'),
                entries: facts.websites,
                emptyLabel: l10n.text('report_no_website_usage'),
                duration: duration,
              ),
            );
            widgets.add(pw.SizedBox(height: 10));
            widgets.add(
              _namedDurationSummary(
                title: l10n.text('report_task_domain_distribution'),
                entries: facts.taskDomains,
                emptyLabel: l10n.text('report_no_domain_data'),
                duration: duration,
              ),
            );
            widgets.add(pw.SizedBox(height: 18));
          }
          if (options.sections.contains('coaching')) {
            widgets.add(pw.NewPage(freeSpace: 100));
            widgets.add(_sectionTitle(l10n.text('report_coaching'), rtl));
            if (snapshot.insights.isEmpty) {
              widgets.add(pw.Text(l10n.text('report_no_coaching')));
            } else {
              widgets.addAll(
                snapshot.insights
                    .take(8)
                    .map((insight) => pw.Bullet(text: insight.title)),
              );
            }
            widgets.add(pw.SizedBox(height: 18));
          }
          if (options.includesHealth) {
            widgets.add(pw.NewPage(freeSpace: 100));
            widgets.add(_sectionTitle(l10n.text('report_health_context'), rtl));
            if (healthSummaries.isEmpty) {
              widgets.add(pw.Text(l10n.text('report_no_health')));
            } else {
              widgets.add(
                _healthSummary(
                  healthSummaries.take(18).toList(growable: false),
                  l10n,
                  dateFormat,
                  dateTimeFormat,
                  rtl,
                ),
              );
            }
          }
          return widgets.map(localized).toList();
        },
      ),
    );
    return document.save();
  }

  pw.Widget _header({
    required AppLocalizations l10n,
    required PerformanceReportSnapshot snapshot,
    required PerformanceReportOptions options,
    required DateFormat dateFormat,
    required pw.MemoryImage logo,
    required pw.MemoryImage? avatar,
    required bool rtl,
  }) {
    final identity = pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        if (avatar != null)
          pw.ClipOval(
            child: pw.Image(
              avatar,
              width: 30,
              height: 30,
              fit: pw.BoxFit.cover,
            ),
          )
        else
          pw.Container(
            width: 30,
            height: 30,
            decoration: const pw.BoxDecoration(
              color: PdfColors.blue100,
              shape: pw.BoxShape.circle,
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              (snapshot.profile?.displayName.isNotEmpty ?? false)
                  ? snapshot.profile!.displayName.characters.first
                  : 'T',
            ),
          ),
        pw.SizedBox(width: 8),
        pw.Text(
          snapshot.profile?.displayName ?? 'TaskMaster Pro',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
    final report = pw.Column(
      crossAxisAlignment: rtl
          ? pw.CrossAxisAlignment.start
          : pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          l10n.text(options.type.titleLocalizationKey),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '${dateFormat.format(options.from)} - '
          '${dateFormat.format(options.to)}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey600),
        ),
      ],
    );
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey200)),
      ),
      child: pw.Row(
        children: rtl
            ? [
                identity,
                pw.Spacer(),
                report,
                pw.SizedBox(width: 10),
                pw.Image(logo, width: 54, height: 30, fit: pw.BoxFit.contain),
              ]
            : [
                pw.Image(logo, width: 54, height: 30, fit: pw.BoxFit.contain),
                pw.SizedBox(width: 10),
                identity,
                pw.Spacer(),
                report,
              ],
      ),
    );
  }

  pw.Widget _title(String value, bool rtl) => pw.Text(
    value,
    textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.left,
    style: pw.TextStyle(
      fontSize: 24,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.blue900,
    ),
  );

  pw.Widget _sectionTitle(String value, bool rtl) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 8),
    padding: const pw.EdgeInsets.only(bottom: 4),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.blue200, width: 1.2),
      ),
    ),
    child: pw.Text(
      value,
      textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 15,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.blue800,
      ),
    ),
  );

  pw.Widget _metric(String label, String value) => pw.Container(
    width: 150,
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: PdfColors.blueGrey50,
      border: pw.Border.all(color: PdfColors.blueGrey200),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey700),
        ),
        pw.SizedBox(height: 3),
        pw.Text(value, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  pw.Widget _barChart({
    required AppLocalizations l10n,
    required bool rtl,
    required Map<String, double> values,
  }) {
    final maximum = values.values.fold<double>(
      1,
      (current, value) => value > current ? value : current,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: values.entries.map((entry) {
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 112,
                child: pw.Text(
                  entry.key,
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(
                width: 220,
                child: pw.Container(
                  height: 9,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blueGrey100,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: rtl
                        ? pw.MainAxisAlignment.end
                        : pw.MainAxisAlignment.start,
                    children: [
                      pw.Container(
                        width: 220 * (entry.value / maximum).clamp(0.0, 1.0),
                        height: 9,
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.blue500,
                          borderRadius: pw.BorderRadius.all(
                            pw.Radius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.SizedBox(
                width: 28,
                child: pw.Text(
                  entry.value.round().toString(),
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _durationChart({
    required String title,
    required Map<String, int> values,
    required String Function(int) duration,
    required bool rtl,
  }) {
    final visible = Map<String, int>.fromEntries(
      values.entries.where((entry) => entry.value > 0),
    );
    if (visible.isEmpty) return pw.SizedBox();
    final maximum = visible.values.reduce(math.max);
    return pw.Container(
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: PdfColors.blueGrey50,
        border: pw.Border.all(color: PdfColors.blueGrey200),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            title,
            textAlign: rtl ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          ),
          pw.SizedBox(height: 5),
          ...visible.entries.map(
            (entry) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 105,
                    child: pw.Text(
                      entry.key,
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ),
                  pw.SizedBox(
                    width: 220,
                    child: pw.Container(
                      height: 8,
                      alignment: rtl
                          ? pw.Alignment.centerRight
                          : pw.Alignment.centerLeft,
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blueGrey100,
                        borderRadius: pw.BorderRadius.all(
                          pw.Radius.circular(4),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: rtl
                            ? pw.MainAxisAlignment.end
                            : pw.MainAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 220 * (entry.value / maximum),
                            height: 8,
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.teal500,
                              borderRadius: pw.BorderRadius.all(
                                pw.Radius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 7),
                  pw.SizedBox(
                    width: 75,
                    child: pw.Text(
                      duration(entry.value),
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _taskGroupTable(
    List<PerformanceReportTaskGroup> groups,
    AppLocalizations l10n,
    String Function(int) duration,
    bool rtl,
  ) {
    if (groups.isEmpty) return pw.Text(l10n.text('report_no_tasks'));
    return pw.TableHelper.fromTextArray(
      headerAlignment: rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      cellAlignment: rtl ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      headerDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      tableDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
      cellStyle: const pw.TextStyle(fontSize: 7),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
      headers: [
        l10n.text('task_title'),
        l10n.text('report_occurrences'),
        l10n.text('status_completed'),
        l10n.text('status_missed'),
        l10n.text('report_upcoming'),
        l10n.text('report_recorded'),
      ],
      data: groups
          .take(40)
          .map((group) {
            final title = group.recurring
                ? '${group.title}\n${l10n.text('report_recurring_task')}'
                : group.title;
            return [
              title,
              group.occurrences.toString(),
              group.completed.toString(),
              group.missed.toString(),
              group.upcoming.toString(),
              duration(group.recordedMs),
            ];
          })
          .toList(growable: false),
    );
  }

  pw.Widget _dailyWorkTable(
    List<PerformanceReportDailyPoint> points,
    AppLocalizations l10n,
    DateFormat dateFormat,
    String Function(int) duration,
  ) {
    final visible = points
        .where(
          (point) =>
              point.plannedMs > 0 ||
              point.productiveMs > 0 ||
              point.completedTasks > 0,
        )
        .toList(growable: false);
    if (visible.isEmpty) return pw.Text(l10n.text('report_no_chart_data'));
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          l10n.text('report_planned_and_productive_by_day'),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        ),
        pw.SizedBox(height: 5),
        ...visible
            .take(16)
            .map(
              (point) => pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Row(
                  children: [
                    pw.SizedBox(
                      width: 78,
                      child: pw.Text(
                        dateFormat.format(point.day),
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        l10n.format('report_daily_work_value', {
                          'planned': duration(point.plannedMs),
                          'actual': duration(point.productiveMs),
                          'completed': point.completedTasks,
                        }),
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  pw.Widget _namedDurationSummary({
    required String title,
    required List<PerformanceReportBreakdown> entries,
    required String emptyLabel,
    required String Function(int) duration,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        ),
        pw.SizedBox(height: 4),
        if (entries.isEmpty)
          pw.Text(emptyLabel, style: const pw.TextStyle(fontSize: 8))
        else
          ...entries
              .take(10)
              .map(
                (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          entry.label,
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Text(
                        duration(entry.durationMs),
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }

  pw.Widget _healthSummary(
    List<PerformanceHealthSummaryEntry> entries,
    AppLocalizations l10n,
    DateFormat dateFormat,
    DateFormat dateTimeFormat,
    bool rtl,
  ) {
    final numberFormat = NumberFormat.decimalPattern(l10n.locale.languageCode);
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entries
          .map((entry) {
            final source = entry.sources.isEmpty
                ? l10n.text('health_no_service_available')
                : entry.sources.join(', ');
            return pw.Container(
              width: 245,
              padding: const pw.EdgeInsets.all(9),
              decoration: pw.BoxDecoration(
                color: PdfColors.blueGrey50,
                border: pw.Border.all(color: PdfColors.blueGrey200),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: rtl
                    ? pw.CrossAxisAlignment.end
                    : pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    entry.estimated && entry.metricType == 'distance'
                        ? l10n.text('health_distance_estimated')
                        : _healthMetricLabel(entry.metricType, l10n),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    _healthMetricValue(entry, l10n, numberFormat),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    dateFormat.format(entry.summaryDate.toLocal()),
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.blueGrey700,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    l10n.format('health_source_latest_record', {
                      'source': source,
                      'time': dateTimeFormat.format(
                        entry.lastUpdatedAt.toLocal(),
                      ),
                    }),
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.blueGrey600,
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }

  String _healthMetricLabel(String metricType, AppLocalizations l10n) =>
      l10n.text(switch (metricType) {
        'steps' => 'health_steps',
        'distance' => 'health_distance',
        'active_calories' => 'health_active_energy',
        'average_heart_rate' => 'health_average_heart_rate',
        'sleep_duration' => 'health_sleep',
        'exercise_sessions' => 'health_workouts',
        _ => 'health_data',
      });

  String _healthMetricValue(
    PerformanceHealthSummaryEntry entry,
    AppLocalizations l10n,
    NumberFormat numberFormat,
  ) {
    final value = entry.value.toDouble();
    String compactNumber(double input) => input == input.roundToDouble()
        ? numberFormat.format(input.round())
        : NumberFormat('0.0', l10n.locale.languageCode).format(input);
    return switch (entry.metricType) {
      'steps' => numberFormat.format(value.round()),
      'distance' =>
        value >= 1000
            ? '${compactNumber(value / 1000)} km'
            : '${compactNumber(value)} m',
      'active_calories' => '${compactNumber(value)} kcal',
      'average_heart_rate' => '${compactNumber(value)} bpm',
      'sleep_duration' => l10n.duration(Duration(minutes: value.round())),
      'exercise_sessions' => numberFormat.format(value.round()),
      _ => compactNumber(value),
    };
  }

  pw.Widget _roadmapSummary(
    PerformanceReportSnapshot snapshot,
    AppLocalizations l10n,
    DateFormat dateFormat,
    String Function(int) duration,
    bool rtl,
  ) {
    final roadmap = snapshot.roadmap!;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _metric(
          l10n.text('report_overall_progress'),
          '${(roadmap.progress * 100).round()}%',
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          l10n.format('report_roadmap_effort', {
            'actual': duration(roadmap.completedEffortMs),
            'planned': duration(roadmap.requiredEffortMs ?? 0),
          }),
        ),
        pw.Text(
          l10n.format('report_forecast_completion', {
            'date': roadmap.forecastTargetDate == null
                ? l10n.text('roadmap_forecast_unavailable')
                : dateFormat.format(roadmap.forecastTargetDate!),
          }),
        ),
        pw.SizedBox(height: 8),
        ...snapshot.phases.map(
          (phase) => pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Row(
              children: [
                pw.Expanded(child: pw.Text(phase.title)),
                pw.Text(
                  l10n.taskStatus(phase.status),
                  style: const pw.TextStyle(
                    color: PdfColors.blueGrey700,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        ),
        pw.Text(
          l10n.format('report_milestones_checkpoints', {
            'milestones': snapshot.milestones
                .where((item) => item.status == 'completed')
                .length,
            'milestoneTotal': snapshot.milestones.length,
            'checkpoints': snapshot.checkpoints
                .where((item) => item.status == 'completed')
                .length,
            'checkpointTotal': snapshot.checkpoints.length,
          }),
        ),
      ],
    );
  }

  pw.Widget _activitySummary(
    PerformanceReportSnapshot snapshot,
    PerformanceReportFacts facts,
    AppLocalizations l10n,
    String Function(int) duration,
    bool rtl,
  ) {
    if (facts.activeActivityMs == 0 && facts.idleActivityMs == 0) {
      return pw.Text(l10n.text('report_no_activity'));
    }
    final excludedSegmentIds = excludedActivitySegmentIds(
      segments: snapshot.activity,
      attributions: snapshot.attributions,
    );
    final crossTask = snapshot.contributions
        .where(
          (item) =>
              item.isCrossTask &&
              !excludedSegmentIds.contains(item.activitySegmentId),
        )
        .fold<int>(0, (sum, item) => sum + item.creditedDurationMs);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          l10n.format('report_cross_task_contributions', {
            'duration': duration(crossTask),
          }),
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            pw.Expanded(child: pw.Text(l10n.text('report_active_activity'))),
            pw.Text(duration(facts.activeActivityMs)),
          ],
        ),
        pw.Row(
          children: [
            pw.Expanded(child: pw.Text(l10n.text('report_idle_activity'))),
            pw.Text(duration(facts.idleActivityMs)),
          ],
        ),
      ],
    );
  }
}

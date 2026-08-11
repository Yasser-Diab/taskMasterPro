import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import '../../tasks/domain/task_occurrence_policy.dart';

/// The visual and conversational posture of a coaching insight.
///
/// This lives with the decision model rather than in the dashboard so every
/// coaching surface can express the same intent without trying to infer it
/// again from localized copy.
enum CoachingMood { celebrating, supportive, firm, recovery, planning }

/// A concrete facial expression used by coaching illustrations.
///
/// Expressions are deliberately separate from [CoachingMood]. A mood controls
/// the card's semantic colour and conversational posture, while an expression
/// gives individual messages a precise, accessible visual reaction.
enum CoachingExpression {
  overwhelmed,
  happy,
  encouraging,
  unconvinced,
  confident,
  quiet,
  tired,
  sad,
  frustrated,
  confused,
  exhausted,
  unwell,
  hurt,
  surprised,
}

extension CoachingExpressionPresentation on CoachingExpression {
  String get labelKey => 'coaching_expression_$name';

  String get semanticLabelKey => 'coaching_expression_${name}_label';

  String get assetPath => 'assets/illustrations/coach/expression_$name.svg';
}

extension CoachingMoodPresentation on CoachingMood {
  String get labelKey => 'coaching_mood_$name';

  String get semanticLabelKey => 'coaching_mood_${name}_label';

  CoachingExpression get defaultExpression => switch (this) {
    CoachingMood.celebrating => CoachingExpression.happy,
    CoachingMood.supportive => CoachingExpression.encouraging,
    CoachingMood.firm => CoachingExpression.confident,
    CoachingMood.recovery => CoachingExpression.quiet,
    CoachingMood.planning => CoachingExpression.confident,
  };

  String get assetPath => defaultExpression.assetPath;
}

enum CoachingFeedbackKind {
  helpful('helpful', 'helpful'),
  notUseful('not_useful', 'not_useful'),
  wrongTiming('wrong_timing', 'wrong_timing'),
  wrongAssumption('wrong_assumption', 'wrong_assumption'),
  tooFrequent('too_frequent', 'too_frequent');

  const CoachingFeedbackKind(this.wireValue, this.labelKey);

  final String wireValue;
  final String labelKey;

  static CoachingFeedbackKind? fromWire(Object? value) {
    final normalized = value?.toString();
    for (final kind in values) {
      if (kind.wireValue == normalized) return kind;
    }
    return null;
  }
}

class CoachingFeedbackSignal {
  const CoachingFeedbackSignal({
    required this.kind,
    required this.category,
    required this.cardKey,
    required this.submittedAt,
    this.assumptionTags = const {},
  });

  final CoachingFeedbackKind kind;
  final String category;
  final String cardKey;
  final DateTime submittedAt;
  final Set<String> assumptionTags;
}

class CoachingEvidenceLabel {
  const CoachingEvidenceLabel(this.key, [this.values = const {}]);

  final String key;
  final Map<String, Object?> values;
}

class AdaptiveCoachingEvidence {
  const AdaptiveCoachingEvidence({
    required this.now,
    required this.accountAgeDays,
    required this.tone,
    required this.sensitivity,
    required this.hasActiveTask,
    required this.activeTaskTitle,
    required this.pausedCount,
    required this.overdueCount,
    required this.readyTodayCount,
    required this.nextTaskId,
    required this.nextTaskTitle,
    required this.openRoadmapTaskCount,
    required this.roadmapTaskId,
    required this.roadmapTaskTitle,
    required this.roadmapAtRisk,
    required this.roadmapProgress,
    required this.lateNightMinutes,
    required this.approvedHealthSummary,
    required this.recentSleepSummary,
    required this.focusCyclesLastWeek,
    required this.completedSessionsLastWeek,
    required this.pausesLastWeek,
    this.overdueTaskIds = const [],
    this.age,
  });

  final DateTime now;
  final int accountAgeDays;
  final int? age;
  final String tone;
  final String sensitivity;
  final bool hasActiveTask;
  final String? activeTaskTitle;
  final int pausedCount;
  final int overdueCount;
  final int readyTodayCount;
  final String? nextTaskId;
  final String? nextTaskTitle;
  final int openRoadmapTaskCount;
  final String? roadmapTaskId;
  final String? roadmapTaskTitle;
  final bool roadmapAtRisk;
  final double? roadmapProgress;
  final int lateNightMinutes;
  final bool approvedHealthSummary;
  final bool recentSleepSummary;
  final int focusCyclesLastWeek;
  final int completedSessionsLastWeek;
  final int pausesLastWeek;
  final List<String> overdueTaskIds;
}

class AdaptiveCoachingDecision {
  const AdaptiveCoachingDecision({
    required this.cardKey,
    required this.category,
    required this.mood,
    required this.titleKey,
    required this.bodyKey,
    required this.score,
    this.bodyValues = const {},
    this.evidence = const [],
    this.assumptionTags = const {},
    this.relatedTaskId,
    this.relatedTaskIds = const [],
    this.expressionOverride,
    this.compact = false,
  });

  final String cardKey;
  final String category;
  final CoachingMood mood;
  final String titleKey;
  final String bodyKey;
  final Map<String, Object?> bodyValues;
  final List<CoachingEvidenceLabel> evidence;
  final Set<String> assumptionTags;
  final String? relatedTaskId;
  final List<String> relatedTaskIds;
  final CoachingExpression? expressionOverride;
  final double score;
  final bool compact;

  CoachingExpression get expression =>
      expressionOverride ??
      switch (cardKey) {
        'first_day_learning' => CoachingExpression.surprised,
        'feedback_space' => CoachingExpression.quiet,
        'late_night_reset' => CoachingExpression.tired,
        'roadmap_recovery' => CoachingExpression.frustrated,
        'overdue_triage' => CoachingExpression.overwhelmed,
        'protect_active_focus' => CoachingExpression.confident,
        'resume_paused' => CoachingExpression.unconvinced,
        'roadmap_next_step' => CoachingExpression.encouraging,
        'focus_momentum' => CoachingExpression.happy,
        'rest_plan' => CoachingExpression.quiet,
        'scheduled_next_step' => CoachingExpression.encouraging,
        'limited_evidence_plan' => CoachingExpression.confused,
        _ => mood.defaultExpression,
      };
}

class AdaptiveCoachingInsight {
  const AdaptiveCoachingInsight({
    required this.insightId,
    required this.decision,
  });

  final String insightId;
  final AdaptiveCoachingDecision decision;
}

class AdaptiveCoachingEngine {
  const AdaptiveCoachingEngine();

  AdaptiveCoachingDecision select(
    AdaptiveCoachingEvidence evidence,
    List<CoachingFeedbackSignal> feedback,
  ) {
    if (evidence.accountAgeDays < 1) {
      return AdaptiveCoachingDecision(
        cardKey: 'first_day_learning',
        category: 'learning',
        mood: CoachingMood.planning,
        titleKey: 'coaching_learning_title',
        bodyKey: _firstDayBodyKey(evidence.age),
        score: 1000,
        assumptionTags: const {'new_account_needs_orientation'},
      );
    }

    final recentTooFrequent = feedback.any(
      (item) =>
          item.kind == CoachingFeedbackKind.tooFrequent &&
          evidence.now.difference(item.submittedAt).inDays < 4,
    );
    if (recentTooFrequent && evidence.overdueCount < 3) {
      return const AdaptiveCoachingDecision(
        cardKey: 'feedback_space',
        category: 'pacing',
        mood: CoachingMood.supportive,
        titleKey: 'coaching_adaptive_space_title',
        bodyKey: 'coaching_adaptive_space_body',
        score: 1000,
        compact: true,
      );
    }

    final candidates = <AdaptiveCoachingDecision>[
      if (evidence.lateNightMinutes >= 15)
        AdaptiveCoachingDecision(
          cardKey: 'late_night_reset',
          category: 'rest_timing',
          mood: CoachingMood.recovery,
          titleKey: 'coaching_adaptive_late_title',
          bodyKey: evidence.recentSleepSummary
              ? 'coaching_adaptive_late_body_with_summary'
              : _lateNightBodyKey(evidence.age),
          bodyValues: {'duration_ms': evidence.lateNightMinutes * 60 * 1000},
          evidence: [
            CoachingEvidenceLabel('coaching_evidence_late_activity', {
              'duration_ms': evidence.lateNightMinutes * 60 * 1000,
            }),
            if (evidence.recentSleepSummary)
              const CoachingEvidenceLabel('coaching_evidence_health_summary'),
          ],
          assumptionTags: const {'late_activity_may_disrupt_planned_rest'},
          score: 130,
        ),
      if (evidence.roadmapAtRisk)
        AdaptiveCoachingDecision(
          cardKey: 'roadmap_recovery',
          category: 'roadmap',
          mood: CoachingMood.firm,
          titleKey: 'coaching_adaptive_roadmap_risk_title',
          bodyKey: 'coaching_adaptive_roadmap_risk_body',
          bodyValues: {'task': evidence.roadmapTaskTitle ?? ''},
          evidence: [
            CoachingEvidenceLabel('coaching_evidence_roadmap_tasks', {
              'count': evidence.openRoadmapTaskCount,
            }),
          ],
          assumptionTags: const {'roadmap_risk_needs_smaller_next_step'},
          relatedTaskId: evidence.roadmapTaskId,
          score: 120,
        ),
      if (evidence.overdueCount > 0)
        AdaptiveCoachingDecision(
          cardKey: 'overdue_triage',
          category: 'overdue',
          mood: CoachingMood.firm,
          titleKey: 'coaching_adaptive_overdue_title',
          bodyKey: 'coaching_adaptive_overdue_body',
          bodyValues: {'count': evidence.overdueCount},
          evidence: [
            CoachingEvidenceLabel('coaching_evidence_overdue', {
              'count': evidence.overdueCount,
            }),
          ],
          assumptionTags: const {'overdue_tasks_need_attention'},
          relatedTaskId: evidence.nextTaskId,
          relatedTaskIds: evidence.overdueTaskIds,
          score: (110 + evidence.overdueCount.clamp(0, 10)).toDouble(),
        ),
      if (evidence.hasActiveTask)
        AdaptiveCoachingDecision(
          cardKey: 'protect_active_focus',
          category: 'active_focus',
          mood: CoachingMood.supportive,
          titleKey: 'coaching_adaptive_active_title',
          bodyKey: 'coaching_adaptive_active_body',
          bodyValues: {'task': evidence.activeTaskTitle ?? ''},
          evidence: const [
            CoachingEvidenceLabel('coaching_evidence_active_task'),
          ],
          assumptionTags: const {'active_task_benefits_from_protected_focus'},
          score: 100,
        ),
      if (evidence.pausedCount > 0)
        AdaptiveCoachingDecision(
          cardKey: 'resume_paused',
          category: 'paused',
          mood: CoachingMood.supportive,
          titleKey: 'coaching_adaptive_paused_title',
          bodyKey: 'coaching_adaptive_paused_body',
          bodyValues: {'count': evidence.pausedCount},
          evidence: [
            CoachingEvidenceLabel('coaching_evidence_paused', {
              'count': evidence.pausedCount,
            }),
          ],
          assumptionTags: const {'paused_task_is_ready_to_resume'},
          score: 90,
        ),
      if (evidence.openRoadmapTaskCount > 0)
        AdaptiveCoachingDecision(
          cardKey: 'roadmap_next_step',
          category: 'roadmap',
          mood: CoachingMood.planning,
          titleKey: 'coaching_adaptive_roadmap_title',
          bodyKey: 'coaching_adaptive_roadmap_body',
          bodyValues: {'task': evidence.roadmapTaskTitle ?? ''},
          evidence: [
            CoachingEvidenceLabel('coaching_evidence_roadmap_tasks', {
              'count': evidence.openRoadmapTaskCount,
            }),
          ],
          assumptionTags: const {'roadmap_next_step_is_useful'},
          relatedTaskId: evidence.roadmapTaskId,
          score: 75,
        ),
      if (evidence.focusCyclesLastWeek > 0 ||
          evidence.completedSessionsLastWeek > 0)
        AdaptiveCoachingDecision(
          cardKey: 'focus_momentum',
          category: 'focus_pattern',
          mood: CoachingMood.celebrating,
          titleKey: 'coaching_adaptive_focus_title',
          bodyKey: 'coaching_adaptive_focus_body',
          bodyValues: {'count': evidence.focusCyclesLastWeek},
          evidence: [
            CoachingEvidenceLabel('coaching_evidence_focus_cycles', {
              'count': evidence.focusCyclesLastWeek,
            }),
          ],
          assumptionTags: const {'recent_focus_pattern_can_be_repeated'},
          score: 65,
        ),
      if (evidence.approvedHealthSummary)
        const AdaptiveCoachingDecision(
          cardKey: 'rest_plan',
          category: 'rest_timing',
          mood: CoachingMood.recovery,
          titleKey: 'coaching_adaptive_rest_title',
          bodyKey: 'coaching_adaptive_rest_body',
          evidence: [CoachingEvidenceLabel('coaching_evidence_health_summary')],
          assumptionTags: {'health_summary_can_inform_daily_pacing'},
          score: 55,
        ),
      if (evidence.readyTodayCount > 0)
        AdaptiveCoachingDecision(
          cardKey: 'scheduled_next_step',
          category: 'schedule',
          mood: CoachingMood.planning,
          titleKey: 'coaching_adaptive_schedule_title',
          bodyKey: 'coaching_adaptive_schedule_body',
          bodyValues: {
            'task': evidence.nextTaskTitle ?? '',
            'count': evidence.readyTodayCount,
          },
          evidence: [
            CoachingEvidenceLabel('coaching_evidence_ready_tasks', {
              'count': evidence.readyTodayCount,
            }),
          ],
          assumptionTags: const {'scheduled_task_is_a_useful_next_step'},
          relatedTaskId: evidence.nextTaskId,
          score: 50,
        ),
      const AdaptiveCoachingDecision(
        cardKey: 'limited_evidence_plan',
        category: 'planning',
        mood: CoachingMood.planning,
        titleKey: 'coaching_adaptive_baseline_title',
        bodyKey: 'coaching_adaptive_baseline_body',
        score: 10,
      ),
    ];

    final adjusted =
        candidates
            .map(
              (candidate) => (
                candidate: candidate,
                score: _adjustedScore(candidate, evidence, feedback),
              ),
            )
            .toList()
          ..sort((left, right) => right.score.compareTo(left.score));
    return adjusted.first.candidate;
  }

  double _adjustedScore(
    AdaptiveCoachingDecision candidate,
    AdaptiveCoachingEvidence evidence,
    List<CoachingFeedbackSignal> feedback,
  ) {
    var score = candidate.score;
    score += switch (evidence.tone) {
      'direct' when const {'overdue', 'paused'}.contains(candidate.category) =>
        15,
      'gentle'
          when const {
            'rest_timing',
            'active_focus',
            'focus_pattern',
          }.contains(candidate.category) =>
        10,
      'detailed'
          when const {
            'roadmap',
            'rest_timing',
            'focus_pattern',
          }.contains(candidate.category) =>
        10,
      _ => 0,
    };
    score += switch (evidence.sensitivity) {
      'persistent'
          when const {'overdue', 'paused'}.contains(candidate.category) =>
        15,
      'active' when candidate.evidence.isNotEmpty => 5,
      'quiet' when candidate.category == 'planning' => 20,
      _ => 0,
    };

    for (final item in feedback) {
      final age = evidence.now.difference(item.submittedAt);
      if (item.kind == CoachingFeedbackKind.helpful &&
          age.inDays < 14 &&
          item.category == candidate.category) {
        score += 18;
      }
      if (item.kind == CoachingFeedbackKind.notUseful &&
          age.inDays < 14 &&
          (item.cardKey == candidate.cardKey ||
              item.category == candidate.category)) {
        score -= 300;
      }
      if (item.kind == CoachingFeedbackKind.wrongTiming &&
          age.inDays < 4 &&
          item.category == candidate.category) {
        score -= 300;
      }
      if (item.kind == CoachingFeedbackKind.wrongAssumption &&
          age.inDays < 30 &&
          candidate.assumptionTags.any(item.assumptionTags.contains)) {
        score -= 500;
      }
    }
    return score;
  }

  String _firstDayBodyKey(int? age) {
    if (age == null) return 'coaching_learning_body';
    if (age < 13) return 'coaching_learning_body_child';
    if (age < 18) return 'coaching_learning_body_teen';
    if (age >= 65) return 'coaching_learning_body_older_adult';
    return 'coaching_learning_body_adult';
  }

  String _lateNightBodyKey(int? age) {
    if (age != null && age < 18) {
      return 'coaching_adaptive_late_body_youth';
    }
    if (age != null && age >= 65) {
      return 'coaching_adaptive_late_body_older_adult';
    }
    return 'coaching_adaptive_late_body';
  }
}

class AdaptiveCoachingService {
  AdaptiveCoachingService({
    required this.database,
    required this.entities,
    required this.userId,
    this.engine = const AdaptiveCoachingEngine(),
  });

  final AppDatabase database;
  final EntityRecordRepository entities;
  final String userId;
  final AdaptiveCoachingEngine engine;
  static const _uuid = Uuid();

  Future<AdaptiveCoachingInsight> buildInsight({
    required List<LocalTask> tasks,
    required LocalRuntime? runtime,
    required LocalAppSetting? settings,
    required DateTime? accountCreatedAt,
    required int? age,
    DateTime? at,
  }) async {
    final now = (at ?? DateTime.now()).toLocal();
    final feedback = await _loadFeedback();
    final roadmaps =
        await (database.select(database.localRoadmaps)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.deletedAt.isNull() &
                  row.status.isNotIn(const ['completed', 'cancelled']),
            ))
            .get();
    final activity = settings?.phoneUsageAnalysisEnabled == true
        ? await (database.select(database.localActivitySegments)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.deletedAt.isNull() &
                    row.endedAt.isBiggerThanValue(
                      now.toUtc().subtract(const Duration(days: 2)),
                    ),
              ))
              .get()
        : const <LocalActivitySegment>[];
    final health = await entities.list(entityType: 'health_summaries');
    final cycles = await entities.list(entityType: 'pomodoro_cycles');
    final sessionEvents = await entities.list(entityType: 'session_events');
    final evidence = _buildEvidence(
      tasks: tasks,
      runtime: runtime,
      settings: settings,
      accountCreatedAt: accountCreatedAt,
      age: age,
      now: now,
      roadmaps: roadmaps,
      activity: activity,
      health: health,
      cycles: cycles,
      sessionEvents: sessionEvents,
    );
    return AdaptiveCoachingInsight(
      insightId: _uuid.v4(),
      decision: engine.select(evidence, feedback),
    );
  }

  Future<void> submitFeedback(
    AdaptiveCoachingInsight insight,
    CoachingFeedbackKind kind, {
    DateTime? at,
  }) async {
    final now = (at ?? DateTime.now()).toUtc();
    final decision = insight.decision;
    final adaptiveData = <String, Object?>{
      'card_key': decision.cardKey,
      'category': decision.category,
      'assumption_tags': decision.assumptionTags.toList(growable: false),
    };
    await entities.create(
      EntityRecordDraft(
        entityType: 'coaching_feedback',
        parentId: insight.insightId,
        title: kind.wireValue,
        status: 'submitted',
        data: {
          'insight_id': insight.insightId,
          'feedback': kind.wireValue,
          'submitted_at': now.toIso8601String(),
          ...adaptiveData,
        },
        syncPayload: {
          'insight_id': insight.insightId,
          'feedback': kind.wireValue,
          'note': null,
          'submitted_at': now.toIso8601String(),
          'data': adaptiveData,
        },
      ),
    );
  }

  AdaptiveCoachingEvidence _buildEvidence({
    required List<LocalTask> tasks,
    required LocalRuntime? runtime,
    required LocalAppSetting? settings,
    required DateTime? accountCreatedAt,
    required int? age,
    required DateTime now,
    required List<LocalRoadmap> roadmaps,
    required List<LocalActivitySegment> activity,
    required List<LocalEntityRecord> health,
    required List<LocalEntityRecord> cycles,
    required List<LocalEntityRecord> sessionEvents,
  }) {
    final timeZone = settings?.timeZone ?? 'UTC';
    final localToday = TaskOccurrencePolicy.localDateAt(
      now,
      timeZone: timeZone,
    );
    final openTasks = tasks
        .where(TaskOccurrencePolicy.isOpenOccurrence)
        .toList(growable: false);
    final activeTask = runtime?.activeTaskId == null
        ? null
        : openTasks
              .where((task) => task.id == runtime!.activeTaskId)
              .firstOrNull;
    final readyToday = openTasks
        .where(
          (task) =>
              TaskOccurrencePolicy.isScheduledOn(
                task,
                localToday,
                timeZone: timeZone,
              ) &&
              task.status != 'in_progress' &&
              task.status != 'paused',
        )
        .toList(growable: false);
    final overdue = TaskOccurrencePolicy.overdueOccurrences(
      tasks,
      now: now,
      timeZone: timeZone,
    );
    final roadmapTasks = openTasks
        .where((task) => task.roadmapId != null)
        .toList(growable: false);
    final roadmapTask = roadmapTasks.firstOrNull;
    final roadmapAtRisk = roadmaps.any(
      (roadmap) => roadmap.riskLevel == 'high' || roadmap.riskLevel == 'medium',
    );
    final roadmapProgress = roadmaps.isEmpty
        ? null
        : roadmaps
                  .map((roadmap) => roadmap.progress)
                  .fold<double>(0, (sum, value) => sum + value) /
              roadmaps.length;
    final healthAllowed =
        settings?.healthConnectEnabled == true ||
        settings?.healthSummarySyncEnabled == true;
    final approvedHealth = healthAllowed
        ? health.where(_isActualHealthSummary).toList(growable: false)
        : const <LocalEntityRecord>[];
    final recentHealthCutoff = now.subtract(const Duration(days: 2));
    final recentSleep = approvedHealth.any((record) {
      final data = _decode(record.dataJson);
      return data['summary_type'] == 'sleep_duration' &&
          record.updatedAt.toLocal().isAfter(recentHealthCutoff);
    });
    final eventCutoff = now.subtract(const Duration(days: 7));
    final recentCycles = cycles.where(
      (record) =>
          record.updatedAt.toLocal().isAfter(eventCutoff) &&
          ((_decode(record.dataJson)['focus_duration_ms'] as num?)?.toInt() ??
                  0) >
              0,
    );
    final recentEvents = sessionEvents
        .where((record) => record.updatedAt.toLocal().isAfter(eventCutoff))
        .map((record) => _decode(record.dataJson))
        .toList(growable: false);
    final accountStart = accountCreatedAt?.toLocal();
    final accountAgeDays = accountStart == null
        ? 0
        : DateTime(now.year, now.month, now.day)
              .difference(
                DateTime(
                  accountStart.year,
                  accountStart.month,
                  accountStart.day,
                ),
              )
              .inDays;
    return AdaptiveCoachingEvidence(
      now: now,
      accountAgeDays: accountAgeDays,
      age: age,
      tone: settings?.coachingTone ?? 'balanced',
      sensitivity: settings?.coachingSensitivity ?? 'standard',
      hasActiveTask:
          activeTask != null &&
          const {'running', 'break'}.contains(runtime?.state),
      activeTaskTitle: activeTask?.title,
      pausedCount: openTasks.where((task) => task.status == 'paused').length,
      overdueCount: overdue.length,
      overdueTaskIds: List.unmodifiable(overdue.map((task) => task.id)),
      readyTodayCount: readyToday.length,
      nextTaskId: readyToday.firstOrNull?.id,
      nextTaskTitle: readyToday.firstOrNull?.title,
      openRoadmapTaskCount: roadmapTasks.length,
      roadmapTaskId: roadmapTask?.id,
      roadmapTaskTitle: roadmapTask?.title,
      roadmapAtRisk: roadmapAtRisk,
      roadmapProgress: roadmapProgress,
      lateNightMinutes: _lateNightMinutes(
        activity,
        now: now,
        sleepTimeMinutes: settings?.sleepTimeMinutes ?? 1320,
        wakeTimeMinutes: settings?.wakeTimeMinutes ?? 420,
      ),
      approvedHealthSummary: approvedHealth.isNotEmpty,
      recentSleepSummary: recentSleep,
      focusCyclesLastWeek: recentCycles.length,
      completedSessionsLastWeek: recentEvents
          .where(
            (event) => const {
              'complete',
              'focus_completed',
            }.contains(event['event_type']),
          )
          .length,
      pausesLastWeek: recentEvents
          .where((event) => event['event_type'] == 'pause')
          .length,
    );
  }

  Future<List<CoachingFeedbackSignal>> _loadFeedback() async {
    final records = await entities.list(entityType: 'coaching_feedback');
    final result = <CoachingFeedbackSignal>[];
    for (final record in records) {
      final data = _decode(record.dataJson);
      final nested = data['data'] is Map
          ? Map<String, Object?>.from(data['data'] as Map)
          : const <String, Object?>{};
      Object? field(String key) => data[key] ?? nested[key];
      final kind = CoachingFeedbackKind.fromWire(
        field('feedback') ?? record.title,
      );
      if (kind == null) continue;
      final submittedAt =
          _date(field('submitted_at')) ?? record.createdAt.toUtc();
      final assumptions = field('assumption_tags');
      result.add(
        CoachingFeedbackSignal(
          kind: kind,
          category: field('category')?.toString() ?? '',
          cardKey: field('card_key')?.toString() ?? '',
          submittedAt: submittedAt,
          assumptionTags: assumptions is Iterable
              ? assumptions.map((value) => value.toString()).toSet()
              : const {},
        ),
      );
    }
    return result;
  }

  bool _isActualHealthSummary(LocalEntityRecord record) {
    final data = _decode(record.dataJson);
    final recordCount = (data['record_count'] as num?)?.toInt() ?? 0;
    final source = data['source']?.toString().trim() ?? '';
    final value = data['value'];
    return recordCount > 0 &&
        source.isNotEmpty &&
        value is num &&
        record.deletedAt == null;
  }

  int _lateNightMinutes(
    List<LocalActivitySegment> segments, {
    required DateTime now,
    required int sleepTimeMinutes,
    required int wakeTimeMinutes,
  }) {
    final intervals = <({DateTime start, DateTime end})>[];
    final today = DateTime(now.year, now.month, now.day);
    for (var offset = -2; offset <= 0; offset++) {
      final day = today.add(Duration(days: offset));
      final nightStart = day.add(Duration(minutes: sleepTimeMinutes));
      final nightEnd = wakeTimeMinutes <= sleepTimeMinutes
          ? day
                .add(const Duration(days: 1))
                .add(Duration(minutes: wakeTimeMinutes))
          : day.add(Duration(minutes: wakeTimeMinutes));
      for (final segment in segments) {
        final segmentStart = segment.startedAt.toLocal();
        final segmentEnd = segment.endedAt.toLocal();
        final start = segmentStart.isAfter(nightStart)
            ? segmentStart
            : nightStart;
        final end = segmentEnd.isBefore(nightEnd) ? segmentEnd : nightEnd;
        if (end.isAfter(start) && !start.isAfter(now)) {
          intervals.add((start: start, end: end.isAfter(now) ? now : end));
        }
      }
    }
    if (intervals.isEmpty) return 0;
    intervals.sort((left, right) => left.start.compareTo(right.start));
    var total = Duration.zero;
    var currentStart = intervals.first.start;
    var currentEnd = intervals.first.end;
    for (final interval in intervals.skip(1)) {
      if (!interval.start.isAfter(currentEnd)) {
        if (interval.end.isAfter(currentEnd)) currentEnd = interval.end;
      } else {
        total += currentEnd.difference(currentStart);
        currentStart = interval.start;
        currentEnd = interval.end;
      }
    }
    total += currentEnd.difference(currentStart);
    return total.inMinutes;
  }

  Map<String, Object?> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  DateTime? _date(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }
}

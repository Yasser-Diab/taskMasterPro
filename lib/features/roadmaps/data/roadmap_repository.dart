import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/account/owner_bootstrap.dart';
import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity.dart';
import '../../activity/domain/activity_reporting_policy.dart';
import '../../tasks/data/task_repository.dart';
import '../../tasks/domain/task_schedule_policy.dart';

class RoadmapDraft {
  const RoadmapDraft({
    required this.title,
    this.description = '',
    this.finalOutcome = '',
    this.plannedStart,
    this.targetDate,
    this.requiredEffort = const Duration(hours: 40),
  });

  final String title;
  final String description;
  final String finalOutcome;
  final DateTime? plannedStart;
  final DateTime? targetDate;
  final Duration requiredEffort;
}

class RoadmapPopulationResult {
  const RoadmapPopulationResult({
    required this.phases,
    required this.milestones,
    required this.checkpoints,
    required this.tasks,
  });

  final int phases;
  final int milestones;
  final int checkpoints;
  final int tasks;
}

/// A deliberately conservative forecast projection. It is based on dated,
/// completed linked work—not on how many empty structural rows a roadmap
/// contains. The public shape makes the evidence policy independently testable
/// and keeps a handful of accidental long sessions from producing a heroic,
/// false "high confidence" date.
class RoadmapForecastProjection {
  const RoadmapForecastProjection({
    required this.forecast,
    required this.rangeStart,
    required this.rangeEnd,
    required this.confidence,
    required this.activeDays,
    required this.observedEffortMs,
    required this.dailyVariation,
  });

  final DateTime? forecast;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final String confidence;
  final int activeDays;
  final int observedEffortMs;
  final double dailyVariation;

  bool get hasEnoughEvidence => confidence != 'insufficient';
}

class RoadmapForecastObservation {
  const RoadmapForecastObservation({required this.day, required this.effortMs});

  final DateTime day;
  final int effortMs;
}

/// The roadmap's effective planned effort.
///
/// Imported legacy roadmaps can have a null/zero roadmap-level effort even
/// after their linked tasks have acquired canonical durations. Prefer an
/// explicit positive roadmap total, otherwise derive the denominator from
/// each linked occurrence's authoritative planning window or estimate.
int? effectiveRoadmapRequiredEffortMs(
  LocalRoadmap roadmap,
  Iterable<LocalTask> linkedTasks,
) {
  final explicit = roadmap.requiredEffortMs;
  if (explicit != null && explicit > 0) return explicit;

  var total = 0;
  for (final task in linkedTasks) {
    if (task.deletedAt != null) continue;
    final window = TaskSchedulePolicy.resolve(
      task.plannedStart,
      task.plannedEnd,
    );
    final taskEffortMs =
        window?.duration.inMilliseconds ??
        (task.estimatedDurationMs > 0 ? task.estimatedDurationMs : 0);
    total += taskEffortMs;
  }
  return total > 0 ? total : null;
}

RoadmapForecastProjection projectRoadmapForecast({
  required int requiredEffortMs,
  required int completedEffortMs,
  required int completedTaskCount,
  required Iterable<RoadmapForecastObservation> observations,
  required DateTime now,
  DateTime? previousForecast,
}) {
  final daily = <DateTime, int>{};
  for (final observation in observations) {
    if (observation.effortMs <= 0) continue;
    final day = DateTime.utc(
      observation.day.toUtc().year,
      observation.day.toUtc().month,
      observation.day.toUtc().day,
    );
    daily.update(
      day,
      (value) => value + observation.effortMs,
      ifAbsent: () => observation.effortMs,
    );
  }
  final dailyEffort = daily.values.where((value) => value > 0).toList()..sort();
  final activeDays = dailyEffort.length;
  if (activeDays == 0) {
    return const RoadmapForecastProjection(
      forecast: null,
      rangeStart: null,
      rangeEnd: null,
      confidence: 'insufficient',
      activeDays: 0,
      observedEffortMs: 0,
      dailyVariation: 0,
    );
  }

  // A single corrupted 12-hour/day can no longer dominate a multi-year
  // roadmap. The cap is intentionally generous and only activates once there
  // are at least three dated observations to establish a median.
  final median = dailyEffort[activeDays ~/ 2];
  final outlierCap = activeDays >= 3 && median > 0
      ? median * 3
      : 24 * 60 * 60 * 1000;
  final trimmed = dailyEffort
      .map((value) => math.min(value, outlierCap))
      .toList(growable: false);
  final observedEffortMs = trimmed.fold<int>(0, (sum, value) => sum + value);
  final mean = observedEffortMs / activeDays;
  final variance =
      trimmed.fold<double>(0, (sum, value) => sum + math.pow(value - mean, 2)) /
      activeDays;
  final dailyVariation = mean <= 0
      ? 0.0
      : (math.sqrt(variance) / mean).toDouble();
  const minimumObservedEffortMs = 3 * 60 * 60 * 1000;
  final enoughEvidence =
      activeDays >= 3 &&
      completedTaskCount >= 2 &&
      observedEffortMs >= minimumObservedEffortMs &&
      requiredEffortMs > 0;
  if (!enoughEvidence) {
    return RoadmapForecastProjection(
      forecast: null,
      rangeStart: null,
      rangeEnd: null,
      confidence: 'insufficient',
      activeDays: activeDays,
      observedEffortMs: observedEffortMs,
      dailyVariation: dailyVariation,
    );
  }

  final remainingMs = math.max(0, requiredEffortMs - completedEffortMs);
  final projectedDays = remainingMs == 0
      ? 0
      : math.max(1, (remainingMs / mean).ceil()).toInt();
  final today = DateTime.utc(
    now.toUtc().year,
    now.toUtc().month,
    now.toUtc().day,
  );
  var forecast = today.add(Duration(days: projectedDays));
  // Forecasts should adjust gradually. A stable projection can move as more
  // evidence arrives, but no one abnormal session gets to move it by years.
  if (previousForecast != null) {
    final delta = forecast.difference(previousForecast.toUtc()).inDays;
    forecast = previousForecast.toUtc().add(
      Duration(days: delta.clamp(-21, 21).toInt()),
    );
  }
  final rangeDays = math
      .max(7, (projectedDays * (0.20 + dailyVariation)).ceil())
      .toInt();
  final confidence =
      activeDays >= 20 &&
          completedTaskCount >= 10 &&
          observedEffortMs >= 25 * 60 * 60 * 1000 &&
          dailyVariation <= .45
      ? 'high'
      : activeDays >= 10 &&
            completedTaskCount >= 5 &&
            observedEffortMs >= 12 * 60 * 60 * 1000 &&
            dailyVariation <= .85
      ? 'medium'
      : 'low';
  return RoadmapForecastProjection(
    forecast: forecast,
    rangeStart: forecast.subtract(Duration(days: rangeDays)),
    rangeEnd: forecast.add(Duration(days: rangeDays)),
    confidence: confidence,
    activeDays: activeDays,
    observedEffortMs: observedEffortMs,
    dailyVariation: dailyVariation,
  );
}

class _ProgrammingPhasePlan {
  const _ProgrammingPhasePlan({
    required this.task,
    required this.taskDescription,
    required this.milestone,
    required this.milestoneDescription,
    required this.checkpoint,
    required this.checkpointObjective,
    required this.checklist,
    required this.resourceLabel,
    required this.resourceUrl,
  });

  final String task;
  final String taskDescription;
  final String milestone;
  final String milestoneDescription;
  final String checkpoint;
  final String checkpointObjective;
  final List<String> checklist;
  final String resourceLabel;
  final String resourceUrl;
}

const _programmingPlan = <_ProgrammingPhasePlan>[
  _ProgrammingPhasePlan(
    task: 'Build a repeatable developer workstation and command-line workflow',
    taskDescription:
        'Set up the editor, Git, terminal, project folders, and a written '
        'workflow that can be reproduced on a clean computer.',
    milestone: 'Digital foundations and developer tools mastered',
    milestoneDescription:
        'The development environment is reliable, version controlled, and '
        'comfortable enough for daily practice.',
    checkpoint: 'Complete the command-line and file-system challenge',
    checkpointObjective:
        'Navigate, create, move, search, and version files without relying on '
        'a graphical file manager.',
    checklist: [
      'Install and verify the editor, Git, and a terminal',
      'Create a repository and make meaningful commits',
      'Write a one-page workstation recovery guide',
    ],
    resourceLabel: 'freeCodeCamp developer tools curriculum',
    resourceUrl: 'https://freecodecamp.org',
  ),
  _ProgrammingPhasePlan(
    task:
        'Create a tested console habit tracker using programming fundamentals',
    taskDescription:
        'Practice variables, control flow, functions, collections, input '
        'validation, errors, and small automated tests in one useful project.',
    milestone: 'Programming fundamentals applied independently',
    milestoneDescription:
        'Core programming constructs are used deliberately rather than copied '
        'from a tutorial.',
    checkpoint: 'Solve and explain thirty programming exercises',
    checkpointObjective:
        'Complete thirty progressively harder exercises and explain the '
        'reasoning and complexity of each solution.',
    checklist: [
      'Design the habit tracker data model',
      'Implement validated commands and persistence',
      'Add tests and explain five important design decisions',
    ],
    resourceLabel: 'Python official tutorial',
    resourceUrl: 'https://docs.python.org/3/tutorial/',
  ),
  _ProgrammingPhasePlan(
    task: 'Build an accessible responsive multi-page portfolio website',
    taskDescription:
        'Create semantic HTML, maintainable CSS, responsive layouts, forms, '
        'accessibility states, and a small amount of progressive JavaScript.',
    milestone: 'Web foundations demonstrated in a polished site',
    milestoneDescription:
        'The portfolio works across phone and desktop sizes and passes basic '
        'accessibility and browser checks.',
    checkpoint: 'Pass the responsive and accessibility review',
    checkpointObjective:
        'Verify keyboard navigation, readable contrast, semantic structure, '
        'form behavior, and layouts from 320 pixels upward.',
    checklist: [
      'Create semantic page structure and navigation',
      'Implement responsive layouts without horizontal overflow',
      'Run keyboard, accessibility, and cross-browser checks',
    ],
    resourceLabel: 'MDN Web Docs learning path',
    resourceUrl:
        'https://developer.mozilla.org/en-US/docs/Learn_web_development',
  ),
  _ProgrammingPhasePlan(
    task:
        'Implement and test a practical algorithms and data-structures library',
    taskDescription:
        'Implement common structures and algorithms, document tradeoffs, and '
        'measure correctness and performance using realistic examples.',
    milestone: 'Data structures and algorithm choices understood',
    milestoneDescription:
        'Solutions select appropriate structures, explain complexity, and are '
        'protected by repeatable tests.',
    checkpoint: 'Complete the algorithms explanation and test review',
    checkpointObjective:
        'Demonstrate searching, sorting, maps, stacks, queues, trees, and graph '
        'traversal with test cases and complexity notes.',
    checklist: [
      'Implement the core data structures',
      'Add correctness and boundary tests',
      'Document time and space complexity tradeoffs',
    ],
    resourceLabel: 'freeCodeCamp algorithms curriculum',
    resourceUrl: 'https://freecodecamp.org/learn/',
  ),
  _ProgrammingPhasePlan(
    task: 'Build a production-style frontend task dashboard',
    taskDescription:
        'Create a typed client application with state management, forms, '
        'routing, API integration, loading states, errors, and component tests.',
    milestone: 'Modern frontend application completed',
    milestoneDescription:
        'The frontend is responsive, accessible, testable, and resilient to '
        'loading, empty, offline, and error states.',
    checkpoint: 'Pass the frontend architecture and usability review',
    checkpointObjective:
        'Review state ownership, component boundaries, keyboard access, error '
        'handling, and automated tests.',
    checklist: [
      'Design routes, state boundaries, and reusable components',
      'Integrate forms and a real API',
      'Add component tests and accessibility checks',
    ],
    resourceLabel: 'MDN client-side tools guide',
    resourceUrl:
        'https://developer.mozilla.org/en-US/docs/Learn_web_development/Extensions/Client-side_tools',
  ),
  _ProgrammingPhasePlan(
    task: 'Build a secure REST API with a relational database',
    taskDescription:
        'Design a normalized schema, migrations, authentication, authorization, '
        'validation, pagination, error handling, and automated API tests.',
    milestone: 'Backend and database foundation completed',
    milestoneDescription:
        'The service stores real data safely, enforces ownership, and exposes '
        'a documented interface that a client can use reliably.',
    checkpoint: 'Pass the schema, authentication, and API test review',
    checkpointObjective:
        'Verify constraints, ownership rules, migrations, validation, failure '
        'responses, and repeatable integration tests.',
    checklist: [
      'Design and migrate the relational schema',
      'Implement authentication and per-user authorization',
      'Document and test every public endpoint',
    ],
    resourceLabel: 'PostgreSQL official tutorial',
    resourceUrl: 'https://www.postgresql.org/docs/current/tutorial.html',
  ),
  _ProgrammingPhasePlan(
    task: 'Build and test a cross-platform Flutter application',
    taskDescription:
        'Create one adaptive Flutter application for Android and Windows with '
        'local persistence, platform integrations, accessibility, and tests.',
    milestone: 'Cross-platform Flutter application completed',
    milestoneDescription:
        'The same product behaves reliably on phone and desktop while using '
        'responsive layouts and the correct platform capabilities.',
    checkpoint: 'Pass the Android and Windows Flutter acceptance review',
    checkpointObjective:
        'Verify navigation, persistence, permissions, responsive layouts, '
        'accessibility, performance, and release builds on both platforms.',
    checklist: [
      'Build adaptive phone, tablet, and desktop layouts',
      'Integrate local persistence and platform services',
      'Run Android and Windows integration and performance tests',
    ],
    resourceLabel: 'Flutter official learning path',
    resourceUrl: 'https://docs.flutter.dev/get-started/codelab',
  ),
  _ProgrammingPhasePlan(
    task: 'Create a secure continuous-integration and delivery pipeline',
    taskDescription:
        'Automate formatting, analysis, tests, builds, dependency review, '
        'container checks, and a documented rollback exercise.',
    milestone: 'Delivery, security, and collaboration workflow established',
    milestoneDescription:
        'Changes are reviewed and validated automatically, secrets remain '
        'protected, and releases can be reproduced safely.',
    checkpoint: 'Pass the CI, security, and rollback readiness review',
    checkpointObjective:
        'Demonstrate protected secrets, dependency checks, build artifacts, '
        'review rules, and a rehearsed rollback without publishing this test.',
    checklist: [
      'Create formatting, analysis, test, and build checks',
      'Run a threat model and dependency review',
      'Document release and rollback procedures',
    ],
    resourceLabel: 'OWASP Top Ten',
    resourceUrl: 'https://owasp.org/www-project-top-ten/',
  ),
  _ProgrammingPhasePlan(
    task: 'Complete and present a production-grade capstone application',
    taskDescription:
        'Plan, build, test, document, and demonstrate an original application '
        'that combines the full roadmap and can be reviewed independently.',
    milestone: 'Capstone and professional portfolio ready',
    milestoneDescription:
        'The final project shows sound product thinking, architecture, '
        'implementation, testing, security, documentation, and communication.',
    checkpoint: 'Complete an independent capstone and portfolio review',
    checkpointObjective:
        'Resolve critical feedback, record a concise demonstration, and publish '
        'clear source documentation and a personal learning retrospective.',
    checklist: [
      'Define scope, success criteria, and architecture',
      'Finish implementation, tests, security review, and documentation',
      'Present the project and resolve critical reviewer feedback',
    ],
    resourceLabel: 'Git documentation',
    resourceUrl: 'https://git-scm.com/doc',
  ),
];

class RoadmapRepository {
  RoadmapRepository(this.database, this.client)
    : entities = EntityRecordRepository(database, client);

  final AppDatabase database;
  final SupabaseClient client;
  final EntityRecordRepository entities;
  static const _uuid = Uuid();

  String get _userId => client.auth.currentUser?.id ?? 'local';

  Stream<List<LocalRoadmap>> watchRoadmaps() {
    final query = database.select(database.localRoadmaps)
      ..where((row) => row.userId.equals(_userId) & row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.status),
        (row) => OrderingTerm.asc(row.forecastTargetDate),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch();
  }

  Stream<LocalRoadmap?> watchRoadmap(String roadmapId) {
    return (database.select(database.localRoadmaps)..where(
          (row) =>
              row.id.equals(roadmapId) &
              row.userId.equals(_userId) &
              row.deletedAt.isNull(),
        ))
        .watchSingleOrNull();
  }

  Stream<List<LocalTask>> watchLinkedTasks(String roadmapId) {
    final query = database.select(database.localTasks)
      ..where(
        (row) =>
            row.userId.equals(_userId) &
            row.roadmapId.equals(roadmapId) &
            row.deletedAt.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.asc(row.roadmapPhaseId),
        (row) => OrderingTerm.asc(row.scheduledDate),
      ]);
    return query.watch();
  }

  Stream<List<LocalEntityRecord>> watchPhases(String roadmapId) {
    return entities.watch(entityType: 'roadmap_phases', parentId: roadmapId);
  }

  Stream<List<LocalEntityRecord>> watchMilestones(String roadmapId) {
    return entities.watch(
      entityType: 'roadmap_milestones',
      parentId: roadmapId,
    );
  }

  Stream<List<LocalEntityRecord>> watchCheckpoints(String roadmapId) {
    return entities.watch(
      entityType: 'roadmap_checkpoints',
      parentId: roadmapId,
    );
  }

  Stream<List<LocalEntityRecord>> watchTaskLinks(String roadmapId) {
    return entities.watch(
      entityType: 'roadmap_task_links',
      parentId: roadmapId,
    );
  }

  Future<String> upsertTaskLink({
    required String roadmapId,
    required String taskId,
    String? phaseId,
    String? milestoneId,
    String? checkpointId,
    String relationshipType = 'primary',
    String contributionRule = 'completion_only',
    double progressWeight = 1,
  }) async {
    final links = await entities.list(
      entityType: 'roadmap_task_links',
      parentId: roadmapId,
    );
    final existing = links.where((link) {
      final data = entities.decode(link);
      return link.secondaryParentId == taskId || data['task_id'] == taskId;
    }).firstOrNull;
    final data = <String, Object?>{
      'roadmap_id': roadmapId,
      'task_id': taskId,
      'phase_id': phaseId,
      'milestone_id': milestoneId,
      'checkpoint_id': checkpointId,
      'relationship_type': relationshipType,
      'contribution_rule': contributionRule,
      'progress_weight': progressWeight,
    };
    final payload = <String, Object?>{
      'roadmap_id': roadmapId,
      'task_id': taskId,
      'phase_id': phaseId,
      'milestone_id': milestoneId,
      'checkpoint_id': checkpointId,
      'relationship_type': relationshipType,
      'contribution_rule': contributionRule,
      'progress_weight': progressWeight,
      'title': 'Task connection',
      'status': 'active',
      'position': 0,
    };
    if (existing == null) {
      return entities.create(
        EntityRecordDraft(
          entityType: 'roadmap_task_links',
          parentId: roadmapId,
          secondaryParentId: taskId,
          title: 'Task connection',
          data: data,
          syncPayload: payload,
        ),
      );
    }
    await entities.update(existing, data: data, syncPayload: payload);
    return existing.id;
  }

  Future<void> unlinkTask({
    required String roadmapId,
    required String taskId,
  }) async {
    final links = await entities.list(
      entityType: 'roadmap_task_links',
      parentId: roadmapId,
    );
    for (final link in links.where((link) {
      final data = entities.decode(link);
      return link.secondaryParentId == taskId || data['task_id'] == taskId;
    })) {
      await entities.softDelete(link);
    }
  }

  Future<String> createRoadmap(RoadmapDraft draft) async {
    final title = draft.title.trim();
    if (title.isEmpty) throw ArgumentError('Roadmap title is required');
    final now = DateTime.now().toUtc();
    final localStart =
        draft.plannedStart ??
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final target = draft.targetDate ?? localStart.add(const Duration(days: 90));
    final id = _uuid.v4();
    final commandId = _uuid.v4();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final sequence = await DeviceIdentity.nextSequence(_userId);
    final payload = <String, Object?>{
      'title': title,
      'description': draft.description.trim(),
      'status': 'active',
      'planned_start': _dateOnly(localStart),
      'original_target_date': _dateOnly(target),
      'forecast_target_date': _dateOnly(target),
      'final_outcome': draft.finalOutcome.trim(),
      'progress': 0,
      'required_effort_ms': draft.requiredEffort.inMilliseconds,
      'completed_effort_ms': 0,
      'risk_level': 'low',
      'forecast_confidence': 'low',
      'data': {'forecast_reasons': <String>[], 'forecast_evidence_count': 0},
    };

    await database.transaction(() async {
      await database
          .into(database.localRoadmaps)
          .insert(
            LocalRoadmapsCompanion.insert(
              id: id,
              userId: _userId,
              title: title,
              description: Value(draft.description.trim()),
              plannedStart: Value(localStart),
              originalTargetDate: Value(target),
              forecastTargetDate: Value(target),
              finalOutcome: Value(draft.finalOutcome.trim()),
              requiredEffortMs: Value(draft.requiredEffort.inMilliseconds),
              createdAt: now,
              updatedAt: now,
              updatedByDeviceId: Value(deviceId),
              lastCommandId: Value(commandId),
            ),
          );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: id,
        commandType: 'create',
        baseRevision: 0,
        payload: payload,
        now: now,
      );
    });
    for (final contributionType in const [
      'active_work_seconds',
      'practice_seconds',
      'reading_time',
      'research_time',
    ]) {
      await entities.create(
        EntityRecordDraft(
          entityType: 'roadmap_progress_rules',
          parentId: id,
          title: 'Approved ${contributionType.replaceAll('_', ' ')}',
          data: {
            'contribution_type': contributionType,
            'weight': 1,
            'automatic_credit_allowed': false,
            'accepted_contribution_types': [contributionType],
            'rule_config': {
              'requires_approved_attribution': true,
              'source': 'roadmap_default',
            },
          },
          syncPayload: {
            'roadmap_id': id,
            'roadmap_phase_id': null,
            'contribution_type': contributionType,
            'weight': 1,
            'automatic_credit_allowed': false,
            'rule_config': {
              'requires_approved_attribution': true,
              'source': 'roadmap_default',
            },
          },
        ),
      );
    }
    return id;
  }

  Future<void> createStarterRoadmap({
    required String userId,
    required String title,
  }) async {
    if (!mayBootstrapOwnerContent(userId)) return;
    final existing =
        await (database.select(database.localRoadmaps)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.title.equals(title) &
                  row.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (existing != null) return;
    final id = await createRoadmap(
      RoadmapDraft(
        title: title,
        description:
            'Starter roadmap created from onboarding. Every field is editable.',
        finalOutcome: 'Complete the goal with measurable evidence',
        requiredEffort: const Duration(hours: 60),
      ),
    );
    final start = DateTime.now();
    final phase1 = await addPhase(
      roadmapId: id,
      title: 'Foundation',
      description: 'Define the baseline, resources, and first repeatable steps',
      position: 0,
      plannedStart: start,
      plannedFinish: start.add(const Duration(days: 30)),
      requiredEffort: const Duration(hours: 15),
    );
    final phase2 = await addPhase(
      roadmapId: id,
      title: 'Core progress',
      description: 'Build consistent execution and complete the main work',
      position: 1,
      plannedStart: start.add(const Duration(days: 31)),
      plannedFinish: start.add(const Duration(days: 65)),
      requiredEffort: const Duration(hours: 30),
    );
    await addMilestone(
      roadmapId: id,
      phaseId: phase1,
      title: 'Foundation review',
      targetDate: start.add(const Duration(days: 30)),
    );
    await addCheckpoint(
      roadmapId: id,
      phaseId: phase2,
      title: 'Demonstrate measurable progress',
      objective: 'Provide a result that can be reviewed',
      targetDate: start.add(const Duration(days: 55)),
      estimatedEffort: const Duration(hours: 5),
    );
  }

  Future<RoadmapPopulationResult> populateProgrammingLearningPlan(
    String roadmapId,
  ) async {
    final phases = await entities.list(
      entityType: 'roadmap_phases',
      parentId: roadmapId,
    );
    if (phases.isEmpty) {
      throw StateError('The roadmap needs phases before it can be completed.');
    }
    final existingMilestones = await entities.list(
      entityType: 'roadmap_milestones',
      parentId: roadmapId,
    );
    final existingCheckpoints = await entities.list(
      entityType: 'roadmap_checkpoints',
      parentId: roadmapId,
    );
    final existingTasks =
        await (database.select(database.localTasks)..where(
              (row) => row.roadmapId.equals(roadmapId) & row.deletedAt.isNull(),
            ))
            .get();
    final taskRepository = TaskRepository(database, client);
    final start = DateTime.now();
    var milestoneCount = 0;
    var checkpointCount = 0;
    var taskCount = 0;

    for (var index = 0; index < phases.length; index++) {
      final phase = phases[index];
      final plan =
          _programmingPlan[index.clamp(0, _programmingPlan.length - 1)];
      final targetDate = start.add(Duration(days: 21 * (index + 1)));
      final phaseMilestones = existingMilestones
          .where((item) => item.secondaryParentId == phase.id)
          .toList();
      if (index == 6 &&
          phaseMilestones.isNotEmpty &&
          phaseMilestones.first.title ==
              'Full-stack application works as one reliable system') {
        final data = entities.decode(phaseMilestones.first)
          ..['description'] = plan.milestoneDescription;
        await entities.update(
          phaseMilestones.first,
          title: plan.milestone,
          data: data,
        );
      }
      final milestoneId = phaseMilestones.isNotEmpty
          ? phaseMilestones.first.id
          : await addMilestone(
              roadmapId: roadmapId,
              phaseId: phase.id,
              title: plan.milestone,
              description: plan.milestoneDescription,
              targetDate: targetDate,
              position: index.toDouble(),
              weight: 1,
              status: index == 0
                  ? 'completed'
                  : index == 1
                  ? 'in_progress'
                  : index == 2
                  ? 'at_risk'
                  : 'not_started',
              completionRule: 'all_required_tasks',
              notes: 'Review the linked evidence before confirming completion.',
            );
      if (phaseMilestones.isEmpty) milestoneCount += 1;

      final phaseCheckpoints = existingCheckpoints
          .where((item) => item.secondaryParentId == phase.id)
          .toList();
      final checkpoint = phaseCheckpoints.isNotEmpty
          ? phaseCheckpoints.first
          : null;
      if (index == 6 &&
          checkpoint?.title ==
              'Complete the full-stack acceptance test suite') {
        final data = entities.decode(checkpoint!)
          ..['objective'] = plan.checkpointObjective;
        await entities.update(checkpoint, title: plan.checkpoint, data: data);
      }
      final checkpointId =
          checkpoint?.id ??
          await addCheckpoint(
            roadmapId: roadmapId,
            phaseId: phase.id,
            milestoneId: milestoneId,
            title: plan.checkpoint,
            objective: plan.checkpointObjective,
            targetDate: targetDate.subtract(const Duration(days: 5)),
            estimatedEffort: const Duration(hours: 4),
            required: true,
            status: index == 0
                ? 'completed'
                : index == 1
                ? 'ready_for_review'
                : index == 2
                ? 'blocked'
                : 'not_started',
            completionRule: 'user_review',
            notes: 'Attach the project, test output, or written explanation.',
          );
      if (checkpoint == null) checkpointCount += 1;

      final phaseTasks = existingTasks
          .where((task) => task.roadmapPhaseId == phase.id)
          .toList();
      late final String taskId;
      if (phaseTasks.isEmpty) {
        taskId = await taskRepository.createTask(
          TaskDraft(
            title: plan.task,
            description: plan.taskDescription,
            priority: index < 3 ? 3 : 2,
            executionMode: index.isEven ? 'pomodoro' : 'continuous',
            scheduledDate: start.add(Duration(days: index * 7)),
            dueAt: targetDate.subtract(const Duration(days: 7)),
            estimatedDuration: Duration(hours: index < 3 ? 6 : 10),
            roadmapId: roadmapId,
            roadmapPhaseId: phase.id,
            configuration: {
              'completion_method': 'checklist',
              'work_demand': index < 3 ? 'medium' : 'high',
              'suggested_resource': plan.resourceUrl,
              'generated_learning_plan_phase': index + 1,
              'time_zone_behavior': 'user_local',
            },
          ),
        );
        taskCount += 1;
        await _addProgrammingTaskChecklist(taskRepository, taskId, plan);
        final created = await taskRepository.getTask(taskId);
        if (created != null) {
          if (index == 0) {
            await taskRepository.changeStatus(created, 'completed');
          } else if (index == 1) {
            await taskRepository.changeStatus(created, 'paused');
          }
        }
      } else {
        taskId = phaseTasks.first.id;
        if (index == 6 &&
            phaseTasks.first.title ==
                'Integrate the frontend and backend with end-to-end quality checks') {
          final task = phaseTasks.first;
          final configuration =
              jsonDecode(task.dataJson) as Map<String, dynamic>;
          await taskRepository.updateTask(
            task,
            TaskDraft(
              title: plan.task,
              description: plan.taskDescription,
              domainId: task.domainId,
              priority: task.priority,
              executionMode: task.executionMode,
              scheduledDate: task.scheduledDate,
              plannedStart: task.plannedStart,
              plannedEnd: task.plannedEnd,
              dueAt: task.dueAt,
              estimatedDuration: Duration(
                milliseconds: task.estimatedDurationMs,
              ),
              roadmapId: roadmapId,
              roadmapPhaseId: phase.id,
              templateId: task.templateId,
              occurrenceKey: task.occurrenceKey,
              configuration: {
                ...configuration,
                'suggested_resource': plan.resourceUrl,
                'generated_learning_plan_phase': index + 1,
              },
            ),
          );
        }
        if (index == 0 && phaseTasks.first.status != 'completed') {
          await taskRepository.changeStatus(phaseTasks.first, 'completed');
        }
      }
      await upsertTaskLink(
        roadmapId: roadmapId,
        taskId: taskId,
        phaseId: phase.id,
        milestoneId: milestoneId,
        checkpointId: checkpointId,
        relationshipType: 'primary',
        contributionRule: 'completion_only',
      );
      if (index == 0 &&
          checkpoint != null &&
          checkpoint.status != 'completed') {
        await setChildStatus(checkpoint, 'completed');
      }
    }

    final roadmapLevelTasks = existingTasks
        .where((task) => task.roadmapPhaseId == null)
        .toList();
    if (roadmapLevelTasks.isEmpty) {
      final taskId = await taskRepository.createTask(
        TaskDraft(
          title: 'Maintain a programming learning journal and weekly review',
          description:
              'Record decisions, errors, fixes, useful resources, and a weekly reflection that connects progress across all nine phases.',
          priority: 2,
          executionMode: 'habit',
          scheduledDate: start,
          dueAt: start.add(const Duration(days: 189)),
          estimatedDuration: const Duration(minutes: 45),
          roadmapId: roadmapId,
          configuration: const {
            'completion_method': 'notes',
            'repeat_hint': 'weekly',
            'time_zone_behavior': 'user_local',
          },
        ),
      );
      await upsertTaskLink(
        roadmapId: roadmapId,
        taskId: taskId,
        contributionRule: 'approved_effort',
      );
      taskCount += 1;
    }

    if (!existingMilestones.any((item) => item.secondaryParentId == null)) {
      final capstoneMilestone = await addMilestone(
        roadmapId: roadmapId,
        title: 'Zero-to-hero portfolio is ready for independent review',
        description:
            'A reviewer can inspect the source, tests, documentation, deployed demonstrations, and the decisions behind the work.',
        targetDate: start.add(const Duration(days: 189)),
        weight: 2,
        completionRule: 'all_linked_checkpoints',
      );
      milestoneCount += 1;
      await addCheckpoint(
        roadmapId: roadmapId,
        milestoneId: capstoneMilestone,
        title:
            'Complete the final architecture, security, and portfolio review',
        objective:
            'Resolve critical findings and produce a concise demonstration of the complete learning journey.',
        targetDate: start.add(const Duration(days: 182)),
        estimatedEffort: const Duration(hours: 8),
        required: true,
        completionRule: 'user_review',
      );
      checkpointCount += 1;
    }
    await recalculateProgress(roadmapId);
    return RoadmapPopulationResult(
      phases: phases.length,
      milestones: milestoneCount,
      checkpoints: checkpointCount,
      tasks: taskCount,
    );
  }

  Future<void> _addProgrammingTaskChecklist(
    TaskRepository taskRepository,
    String taskId,
    _ProgrammingPhasePlan plan,
  ) async {
    for (var index = 0; index < plan.checklist.length; index++) {
      await taskRepository.entities.create(
        EntityRecordDraft(
          entityType: 'checklist_items',
          parentId: taskId,
          title: plan.checklist[index],
          position: index.toDouble(),
          status: 'pending',
          data: {
            'task_occurrence_id': taskId,
            'is_required': true,
            'position': index.toDouble(),
          },
          syncPayload: {
            'task_occurrence_id': taskId,
            'title': plan.checklist[index],
            'description': '',
            'position': index.toDouble(),
            'is_required': true,
            'completed_at': null,
          },
        ),
      );
    }
    await taskRepository.entities.create(
      EntityRecordDraft(
        entityType: 'task_resources',
        parentId: taskId,
        title: plan.resourceLabel,
        data: {
          'task_occurrence_id': taskId,
          'name': plan.resourceLabel,
          'resource_type': 'url',
          'storage_location': 'url',
          'url': plan.resourceUrl,
          'privacy_state': 'private',
        },
        syncPayload: {
          'task_occurrence_id': taskId,
          'name': plan.resourceLabel,
          'resource_type': 'url',
          'description': 'Primary learning resource for this phase',
          'storage_location': 'url',
          'storage_path': plan.resourceUrl,
          'local_path': null,
          'privacy_state': 'private',
          'last_opened_at': null,
          'open_count': 0,
        },
      ),
    );
  }

  Future<void> updateRoadmap(
    LocalRoadmap roadmap, {
    required RoadmapDraft draft,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence(_userId);
    final start = draft.plannedStart ?? roadmap.plannedStart;
    final target = draft.targetDate ?? roadmap.originalTargetDate;
    final payload = <String, Object?>{
      'title': draft.title.trim(),
      'description': draft.description.trim(),
      'planned_start': start == null ? null : _dateOnly(start),
      'original_target_date': target == null ? null : _dateOnly(target),
      'final_outcome': draft.finalOutcome.trim(),
      'required_effort_ms': draft.requiredEffort.inMilliseconds,
    };
    await database.transaction(() async {
      await (database.update(
        database.localRoadmaps,
      )..where((row) => row.id.equals(roadmap.id))).write(
        LocalRoadmapsCompanion(
          title: Value(draft.title.trim()),
          description: Value(draft.description.trim()),
          plannedStart: Value(start),
          originalTargetDate: Value(target),
          finalOutcome: Value(draft.finalOutcome.trim()),
          requiredEffortMs: Value(draft.requiredEffort.inMilliseconds),
          revision: Value(roadmap.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: roadmap.id,
        commandType: 'update',
        baseRevision: roadmap.revision,
        payload: payload,
        now: now,
      );
    });
  }

  Future<void> setStatus(LocalRoadmap roadmap, String status) async {
    await _updateFields(roadmap, {'status': status});
  }

  Future<void> softDelete(LocalRoadmap roadmap) async {
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.accountId(_userId);
    final commandId = _uuid.v4();
    final sequence = await DeviceIdentity.nextSequence(_userId);
    await database.transaction(() async {
      await (database.update(
        database.localRoadmaps,
      )..where((row) => row.id.equals(roadmap.id))).write(
        LocalRoadmapsCompanion(
          deletedAt: Value(now),
          revision: Value(roadmap.revision + 1),
          updatedAt: Value(now),
          updatedByDeviceId: Value(deviceId),
          lastCommandId: Value(commandId),
        ),
      );
      await _enqueue(
        commandId: commandId,
        deviceId: deviceId,
        sequence: sequence,
        entityId: roadmap.id,
        commandType: 'delete',
        baseRevision: roadmap.revision,
        payload: const {},
        now: now,
      );
    });
  }

  Future<String> addPhase({
    required String roadmapId,
    required String title,
    String description = '',
    required double position,
    DateTime? plannedStart,
    DateTime? plannedFinish,
    Duration? requiredEffort,
  }) {
    final data = <String, Object?>{
      'description': description.trim(),
      'planned_start': plannedStart == null ? null : _dateOnly(plannedStart),
      'planned_finish': plannedFinish == null ? null : _dateOnly(plannedFinish),
      'forecast_finish': plannedFinish == null
          ? null
          : _dateOnly(plannedFinish),
      'required_effort_ms': requiredEffort?.inMilliseconds,
      'progress': 0,
      'risk_level': 'low',
      'completion_rules': <Object?>[],
    };
    return entities.create(
      EntityRecordDraft(
        entityType: 'roadmap_phases',
        parentId: roadmapId,
        title: title,
        status: 'planned',
        position: position,
        data: data,
        syncPayload: {
          'roadmap_id': roadmapId,
          'title': title.trim(),
          'description': description.trim(),
          'position': position,
          ...data,
        },
      ),
    );
  }

  Future<String> addMilestone({
    required String roadmapId,
    String? phaseId,
    required String title,
    String description = '',
    DateTime? targetDate,
    double position = 0,
    double weight = 1,
    String status = 'not_started',
    String completionRule = 'manual',
    String notes = '',
  }) {
    final data = <String, Object?>{
      'description': description.trim(),
      'target_date': targetDate == null ? null : _dateOnly(targetDate),
      'weight': weight,
      'completed_at': null,
      'completion_rule': completionRule,
      'notes': notes.trim(),
    };
    return entities.create(
      EntityRecordDraft(
        entityType: 'roadmap_milestones',
        parentId: roadmapId,
        secondaryParentId: phaseId,
        title: title,
        status: status,
        position: position,
        data: data,
        syncPayload: {
          'roadmap_id': roadmapId,
          'phase_id': phaseId,
          'title': title.trim(),
          'description': description.trim(),
          'target_date': data['target_date'],
          'position': position,
          'weight': weight,
          'status': status,
          'data': {'completion_rule': completionRule, 'notes': notes.trim()},
        },
      ),
    );
  }

  Future<String> addCheckpoint({
    required String roadmapId,
    String? phaseId,
    String? milestoneId,
    required String title,
    String objective = '',
    DateTime? targetDate,
    Duration estimatedEffort = Duration.zero,
    double weight = 1,
    bool required = true,
    String status = 'not_started',
    String completionRule = 'manual',
    String notes = '',
  }) {
    final data = <String, Object?>{
      'objective': objective.trim(),
      'target_date': targetDate == null ? null : _dateOnly(targetDate),
      'estimated_effort_ms': estimatedEffort.inMilliseconds,
      'actual_effort_ms': 0,
      'weight': weight,
      'completion_criteria': <Object?>[],
      'evidence': <Object?>[],
      'milestone_id': milestoneId,
      'required': required,
      'completion_rule': completionRule,
      'notes': notes.trim(),
    };
    return entities.create(
      EntityRecordDraft(
        entityType: 'roadmap_checkpoints',
        parentId: roadmapId,
        secondaryParentId: phaseId,
        title: title,
        status: status,
        data: data,
        syncPayload: {
          'roadmap_id': roadmapId,
          'phase_id': phaseId,
          'milestone_id': milestoneId,
          'title': title.trim(),
          'objective': objective.trim(),
          'target_date': data['target_date'],
          'estimated_effort_ms': estimatedEffort.inMilliseconds,
          'actual_effort_ms': 0,
          'completion_criteria': <Object?>[],
          'evidence': <Object?>[],
          'status': status,
          'weight': weight,
          'data': {
            'required': required,
            'completion_rule': completionRule,
            'notes': notes.trim(),
          },
        },
      ),
    );
  }

  Future<void> setChildStatus(LocalEntityRecord record, String status) async {
    final data = entities.decode(record);
    if (status == 'completed') {
      data['completed_at'] = DateTime.now().toUtc().toIso8601String();
      data['progress'] = 1;
    } else {
      data['completed_at'] = null;
      data['progress'] = 0;
    }
    await entities.update(
      record,
      status: status,
      data: data,
      syncPayload: {
        'status': status,
        if (record.entityType == 'roadmap_milestones')
          'completed_at': data['completed_at'],
        if (record.entityType == 'roadmap_phases') 'progress': data['progress'],
      },
    );
    if (record.parentId != null) {
      await recalculateProgress(record.parentId!);
    }
  }

  Future<void> reorderPhases(
    List<LocalEntityRecord> phases,
    int oldIndex,
    int newIndex,
  ) async {
    final reordered = [...phases];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    for (var index = 0; index < reordered.length; index++) {
      final phase = reordered[index];
      if (phase.position == index.toDouble()) continue;
      await entities.update(
        phase,
        position: index.toDouble(),
        syncPayload: {'position': index.toDouble()},
      );
    }
  }

  Future<void> recalculateProgress(
    String roadmapId, {
    bool synchronize = true,
  }) async {
    final roadmap = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.id.equals(roadmapId))).getSingleOrNull();
    if (roadmap == null) return;
    final phases = await entities.list(
      entityType: 'roadmap_phases',
      parentId: roadmapId,
    );
    final milestones = await entities.list(
      entityType: 'roadmap_milestones',
      parentId: roadmapId,
    );
    final checkpoints = await entities.list(
      entityType: 'roadmap_checkpoints',
      parentId: roadmapId,
    );
    final tasks =
        await (database.select(database.localTasks)..where(
              (row) => row.roadmapId.equals(roadmapId) & row.deletedAt.isNull(),
            ))
            .get();
    final taskIds = tasks.map((task) => task.id).toSet();
    final candidateContributions = taskIds.isEmpty
        ? const <LocalContribution>[]
        : await (database.select(database.localContributions)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    row.targetType.equals('task_occurrence') &
                    row.targetId.isIn(taskIds),
              ))
              .get();
    final contributionActivityIds = candidateContributions
        .map((item) => item.activitySegmentId)
        .toSet();
    final contributionSegments = contributionActivityIds.isEmpty
        ? const <LocalActivitySegment>[]
        : await (database.select(database.localActivitySegments)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    row.id.isIn(contributionActivityIds),
              ))
              .get();
    final contributionAttributions = contributionActivityIds.isEmpty
        ? const <LocalAttribution>[]
        : await (database.select(database.localAttributions)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    row.activitySegmentId.isIn(contributionActivityIds),
              ))
              .get();
    final excludedContributionSegments = excludedActivitySegmentIds(
      segments: contributionSegments,
      attributions: contributionAttributions,
    );
    final contributions = candidateContributions
        .where(
          (item) =>
              !excludedContributionSegments.contains(item.activitySegmentId),
        )
        .toList(growable: false);

    final weightedValues = <(double, double)>[];
    for (final phase in phases) {
      final data = entities.decode(phase);
      weightedValues.add((
        (data['progress'] as num?)?.toDouble() ??
            (phase.status == 'completed' ? 1 : 0),
        2,
      ));
    }
    for (final milestone in milestones) {
      final weight =
          (entities.decode(milestone)['weight'] as num?)?.toDouble() ?? 1;
      weightedValues.add((milestone.status == 'completed' ? 1 : 0, weight));
    }
    for (final checkpoint in checkpoints) {
      final weight =
          (entities.decode(checkpoint)['weight'] as num?)?.toDouble() ?? 1;
      weightedValues.add((checkpoint.status == 'completed' ? 1 : 0, weight));
    }
    for (final task in tasks) {
      weightedValues.add((task.progress.clamp(0, 1), 1));
    }
    final directEffort = tasks.fold<int>(
      0,
      (sum, task) => sum + task.activeDurationMs,
    );
    // The task timer already includes direct activity from its own session.
    // Only additional accepted work is added here, preserving one physical
    // timeline while still crediting cross-task and off-schedule progress.
    final attributedEffort = contributions
        .where(
          (item) =>
              item.isUnscheduled || item.isCrossTask || item.isIdleDerived,
        )
        .fold<int>(0, (sum, item) => sum + item.creditedDurationMs);
    final completedEffort = directEffort + attributedEffort;
    final requiredEffortMs = effectiveRoadmapRequiredEffortMs(roadmap, tasks);
    if (requiredEffortMs != null) {
      weightedValues.add(((completedEffort / requiredEffortMs).clamp(0, 1), 2));
    }
    final totalWeight = weightedValues.fold<double>(
      0,
      (sum, item) => sum + item.$2,
    );
    final progress = totalWeight == 0
        ? 0.0
        : weightedValues.fold<double>(
                0,
                (sum, item) => sum + item.$1 * item.$2,
              ) /
              totalWeight;
    final completedTaskCount = tasks
        .where((task) => task.status == 'completed')
        .length;
    final observations = <RoadmapForecastObservation>[
      for (final task in tasks)
        if (task.activeDurationMs > 0)
          RoadmapForecastObservation(
            day:
                task.actualFinish ?? task.actualStart ?? task.updatedAt.toUtc(),
            effortMs: task.activeDurationMs,
          ),
    ];
    final projection = projectRoadmapForecast(
      requiredEffortMs: requiredEffortMs ?? 0,
      completedEffortMs: completedEffort,
      completedTaskCount: completedTaskCount,
      observations: observations,
      now: DateTime.now().toUtc(),
      previousForecast: roadmap.forecastConfidence == 'insufficient'
          ? null
          : roadmap.forecastTargetDate,
    );
    final target = roadmap.originalTargetDate;
    final forecast = projection.forecast;
    final risk =
        !projection.hasEnoughEvidence || target == null || forecast == null
        ? 'low'
        : forecast.difference(target).inDays > 14
        ? 'high'
        : forecast.difference(target).inDays > 3
        ? 'medium'
        : 'low';
    await _updateFields(roadmap, {
      'progress': progress.clamp(0, 1),
      if ((roadmap.requiredEffortMs ?? 0) <= 0 && requiredEffortMs != null)
        'required_effort_ms': requiredEffortMs,
      'completed_effort_ms': completedEffort,
      'forecast_target_date': forecast == null ? null : _dateOnly(forecast),
      'risk_level': risk,
      'forecast_confidence': projection.confidence,
      'data': {
        'forecast_evidence_count': projection.activeDays,
        'forecast_active_days': projection.activeDays,
        'forecast_observed_effort_ms': projection.observedEffortMs,
        'forecast_daily_variation': projection.dailyVariation,
        'forecast_range_start': projection.rangeStart == null
            ? null
            : _dateOnly(projection.rangeStart!),
        'forecast_range_end': projection.rangeEnd == null
            ? null
            : _dateOnly(projection.rangeEnd!),
        'forecast_reasons': [
          '$completedTaskCount linked tasks completed',
          '${projection.activeDays} active days with completed linked work',
          '${projection.observedEffortMs} milliseconds of outlier-trimmed effort observed',
          '${milestones.where((item) => item.status == 'completed').length} milestones completed',
          '${checkpoints.where((item) => item.status == 'completed').length} checkpoints completed',
          '$attributedEffort milliseconds of approved additional activity credited',
        ],
      },
    }, synchronize: synchronize);
  }

  Future<void> _updateFields(
    LocalRoadmap roadmap,
    Map<String, Object?> payload, {
    bool synchronize = true,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = synchronize
        ? await DeviceIdentity.accountId(_userId)
        : null;
    final commandId = synchronize ? _uuid.v4() : null;
    final sequence = synchronize
        ? await DeviceIdentity.nextSequence(_userId)
        : null;
    await database.transaction(() async {
      await (database.update(
        database.localRoadmaps,
      )..where((row) => row.id.equals(roadmap.id))).write(
        LocalRoadmapsCompanion(
          status: payload.containsKey('status')
              ? Value(payload['status']! as String)
              : const Value.absent(),
          progress: payload.containsKey('progress')
              ? Value((payload['progress']! as num).toDouble())
              : const Value.absent(),
          completedEffortMs: payload.containsKey('completed_effort_ms')
              ? Value((payload['completed_effort_ms']! as num).toInt())
              : const Value.absent(),
          requiredEffortMs: payload.containsKey('required_effort_ms')
              ? Value((payload['required_effort_ms']! as num).toInt())
              : const Value.absent(),
          forecastTargetDate: payload.containsKey('forecast_target_date')
              ? Value(_date(payload['forecast_target_date']))
              : const Value.absent(),
          riskLevel: payload.containsKey('risk_level')
              ? Value(payload['risk_level']! as String)
              : const Value.absent(),
          forecastConfidence: payload.containsKey('forecast_confidence')
              ? Value(payload['forecast_confidence']! as String)
              : const Value.absent(),
          // A fallback pull recalculates this local projection frequently.
          // Advancing the canonical revision without an outbox command made
          // the next real roadmap edit conflict with a server revision that
          // had never changed.
          revision: synchronize
              ? Value(roadmap.revision + 1)
              : const Value.absent(),
          updatedAt: Value(now),
          updatedByDeviceId: synchronize
              ? Value(deviceId!)
              : const Value.absent(),
          lastCommandId: synchronize ? Value(commandId!) : const Value.absent(),
        ),
      );
      if (synchronize) {
        await _enqueue(
          commandId: commandId!,
          deviceId: deviceId!,
          sequence: sequence!,
          entityId: roadmap.id,
          commandType: 'update',
          baseRevision: roadmap.revision,
          payload: payload,
          now: now,
        );
      }
    });
  }

  Future<void> _enqueue({
    required String commandId,
    required String deviceId,
    required int sequence,
    required String entityId,
    required String commandType,
    required int baseRevision,
    required Map<String, Object?> payload,
    required DateTime now,
  }) {
    return database
        .into(database.localOutboxCommands)
        .insert(
          LocalOutboxCommandsCompanion.insert(
            commandId: commandId,
            userId: _userId,
            deviceId: deviceId,
            deviceSequence: sequence,
            entityType: 'roadmaps',
            entityId: entityId,
            commandType: commandType,
            baseRevision: baseRevision,
            payloadJson: jsonEncode(payload),
            clientTimestamp: now,
            createdAt: now,
          ),
        );
  }

  String _dateOnly(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  DateTime? _date(Object? value) {
    if (value is DateTime) return value;
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }
}

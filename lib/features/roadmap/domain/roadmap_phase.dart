import 'package:uuid/uuid.dart';

class RoadmapPhase {
  const RoadmapPhase({
    this.id,
    this.roadmapId,
    required this.phase,
    int? phaseOrder,
    required this.period,
    required this.objective,
    required this.exitEvidence,
    this.status = 'not_started',
    this.plannedProgress = 0,
    this.actualHours = 0,
    this.nextAction,
    this.plannedStart,
    this.plannedFinish,
    this.isExplicitlyActive = false,
  }) : phaseOrder = phaseOrder ?? phase;

  final String? id;
  final String? roadmapId;
  final int phase;
  final int phaseOrder;
  final String period;
  final String objective;
  final String exitEvidence;
  final String status;
  final double plannedProgress;
  final double actualHours;
  final String? nextAction;
  final DateTime? plannedStart;
  final DateTime? plannedFinish;
  final bool isExplicitlyActive;

  bool get isCompleted => status == 'completed';

  RoadmapPhase copyWith({
    String? id,
    String? roadmapId,
    int? phase,
    int? phaseOrder,
    String? period,
    String? objective,
    String? exitEvidence,
    String? status,
    double? plannedProgress,
    double? actualHours,
    String? nextAction,
    DateTime? plannedStart,
    DateTime? plannedFinish,
    bool? isExplicitlyActive,
    bool clearId = false,
    bool clearNextAction = false,
    bool clearPlannedStart = false,
    bool clearPlannedFinish = false,
  }) {
    return RoadmapPhase(
      id: clearId ? null : id ?? this.id,
      roadmapId: roadmapId ?? this.roadmapId,
      phase: phase ?? this.phase,
      phaseOrder: phaseOrder ?? this.phaseOrder,
      period: period ?? this.period,
      objective: objective ?? this.objective,
      exitEvidence: exitEvidence ?? this.exitEvidence,
      status: status ?? this.status,
      plannedProgress: plannedProgress ?? this.plannedProgress,
      actualHours: actualHours ?? this.actualHours,
      nextAction: clearNextAction ? null : nextAction ?? this.nextAction,
      plannedStart: clearPlannedStart
          ? null
          : plannedStart ?? this.plannedStart,
      plannedFinish: clearPlannedFinish
          ? null
          : plannedFinish ?? this.plannedFinish,
      isExplicitlyActive: isExplicitlyActive ?? this.isExplicitlyActive,
    );
  }

  factory RoadmapPhase.fromMap(Map<String, dynamic> map) {
    return RoadmapPhase(
      id: map['id']?.toString(),
      roadmapId: map['roadmap_id']?.toString(),
      phase: _intFromMap(map['phase_number'], fallback: 1),
      phaseOrder: _intFromMap(
        map['phase_order'],
        fallback: _intFromMap(map['phase_number'], fallback: 1),
      ),
      period: map['period']?.toString() ?? '',
      objective: map['objective']?.toString() ?? '',
      exitEvidence: map['exit_evidence']?.toString() ?? '',
      status: map['status']?.toString() ?? 'not_started',
      plannedProgress: _doubleFromMap(map['planned_progress']),
      actualHours: _doubleFromMap(map['actual_hours']),
      nextAction: map['next_action']?.toString(),
      plannedStart: _dateFromMap(map['planned_start']),
      plannedFinish: _dateFromMap(map['planned_finish']),
      isExplicitlyActive: _boolFromMap(map['is_explicitly_active']),
    );
  }

  factory RoadmapPhase.create({
    required String roadmapId,
    required int phase,
    required String objective,
    required String period,
    String exitEvidence = '',
  }) {
    return RoadmapPhase(
      id: const Uuid().v4(),
      roadmapId: roadmapId,
      phase: phase,
      phaseOrder: phase,
      period: period,
      objective: objective,
      exitEvidence: exitEvidence,
    );
  }

  Map<String, dynamic> toInsertMap({required String userId}) {
    return {
      'id': id,
      'user_id': userId,
      'roadmap_id': roadmapId,
      'phase_number': phase,
      'phase_order': phaseOrder,
      'period': period,
      'objective': objective,
      'exit_evidence': exitEvidence,
      'status': status,
      'planned_progress': plannedProgress,
      'actual_hours': actualHours,
      'next_action': nextAction,
      'planned_start': plannedStart?.toIso8601String().split('T').first,
      'planned_finish': plannedFinish?.toIso8601String().split('T').first,
      'is_explicitly_active': isExplicitlyActive,
    };
  }
}

DateTime? _dateFromMap(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString());
}

bool _boolFromMap(Object? value) {
  if (value is bool) {
    return value;
  }
  return value?.toString().toLowerCase() == 'true';
}

int _intFromMap(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _doubleFromMap(Object? value) {
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

const baselineRoadmapPhases = <RoadmapPhase>[
  RoadmapPhase(
    phase: 1,
    period: 'Jul-Sep 2026',
    objective: 'Excellent HTML and CSS',
    exitEvidence:
        'Responsive projects, semantic HTML, accessibility, Git history and independent rebuild.',
  ),
  RoadmapPhase(
    phase: 2,
    period: 'Oct-Dec 2026',
    objective: 'JavaScript fundamentals',
    exitEvidence:
        'Multiple independent applications using DOM, APIs, modules and asynchronous JavaScript.',
  ),
  RoadmapPhase(
    phase: 3,
    period: 'Jan-Mar 2027',
    objective: 'Advanced JavaScript and introductory DSA',
    exitEvidence:
        'Concept demonstrations, regular algorithm practice and independent debugging.',
  ),
  RoadmapPhase(
    phase: 4,
    period: 'Apr-Jun 2027',
    objective: 'React and TypeScript basics',
    exitEvidence:
        'Deployed React applications with routing, forms, state management and typed code.',
  ),
  RoadmapPhase(
    phase: 5,
    period: 'Jul-Sep 2027',
    objective: 'Backend engineering',
    exitEvidence:
        'Authenticated APIs, PostgreSQL, authorization and complete backend projects.',
  ),
  RoadmapPhase(
    phase: 6,
    period: 'Oct-Dec 2027',
    objective: 'Deployment and operations',
    exitEvidence:
        'Dockerized and deployed applications with CI/CD and production documentation.',
  ),
  RoadmapPhase(
    phase: 7,
    period: '2028',
    objective: 'Computer science fundamentals',
    exitEvidence:
        'Demonstrated knowledge through projects, notes, tests and algorithm practice.',
  ),
  RoadmapPhase(
    phase: 8,
    period: '2029',
    objective: 'Advanced engineering',
    exitEvidence:
        'Scalable multi-user systems, caching, messaging, cloud and security.',
  ),
  RoadmapPhase(
    phase: 9,
    period: '2030',
    objective: 'Interview and employment preparation',
    exitEvidence:
        'Interview readiness, portfolio, CV, German interviews and targeted applications.',
  ),
];

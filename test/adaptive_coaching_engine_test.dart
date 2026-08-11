import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/coaching/data/adaptive_coaching_service.dart';

void main() {
  const engine = AdaptiveCoachingEngine();
  final now = DateTime.utc(2026, 7, 28, 22, 30);

  AdaptiveCoachingEvidence evidence({
    int accountAgeDays = 2,
    int overdueCount = 0,
    int lateNightMinutes = 0,
    int readyTodayCount = 0,
    bool hasActiveTask = false,
    int focusCyclesLastWeek = 0,
    bool approvedHealthSummary = false,
    List<String> overdueTaskIds = const [],
  }) {
    return AdaptiveCoachingEvidence(
      now: now,
      accountAgeDays: accountAgeDays,
      age: 30,
      tone: 'balanced',
      sensitivity: 'standard',
      hasActiveTask: hasActiveTask,
      activeTaskTitle: hasActiveTask ? 'Current project' : null,
      pausedCount: 0,
      overdueCount: overdueCount,
      readyTodayCount: readyTodayCount,
      nextTaskId: readyTodayCount == 0 ? null : 'task-1',
      nextTaskTitle: readyTodayCount == 0 ? null : 'German lesson',
      openRoadmapTaskCount: 0,
      roadmapTaskId: null,
      roadmapTaskTitle: null,
      roadmapAtRisk: false,
      roadmapProgress: null,
      lateNightMinutes: lateNightMinutes,
      approvedHealthSummary: approvedHealthSummary,
      recentSleepSummary: false,
      focusCyclesLastWeek: focusCyclesLastWeek,
      completedSessionsLastWeek: 0,
      pausesLastWeek: 0,
      overdueTaskIds: overdueTaskIds,
    );
  }

  test('day two always produces a useful limited-evidence card', () {
    final decision = engine.select(evidence(), const []);
    expect(decision.cardKey, 'limited_evidence_plan');
    expect(decision.bodyKey, 'coaching_adaptive_baseline_body');
    expect(decision.mood, CoachingMood.planning);
  });

  test('late local activity creates non-diagnostic rest guidance', () {
    final decision = engine.select(
      evidence(overdueCount: 1, lateNightMinutes: 35),
      const [],
    );
    expect(decision.cardKey, 'late_night_reset');
    expect(decision.category, 'rest_timing');
    expect(
      decision.bodyValues['duration_ms'],
      const Duration(minutes: 35).inMilliseconds,
    );
    expect(decision.mood, CoachingMood.recovery);
  });

  test('wrong-assumption feedback changes the next selected card', () {
    final input = evidence(overdueCount: 2, lateNightMinutes: 35);
    final first = engine.select(input, const []);
    final next = engine.select(input, [
      CoachingFeedbackSignal(
        kind: CoachingFeedbackKind.wrongAssumption,
        category: first.category,
        cardKey: first.cardKey,
        submittedAt: now.subtract(const Duration(minutes: 1)),
        assumptionTags: first.assumptionTags,
      ),
    ]);
    expect(first.cardKey, 'late_night_reset');
    expect(next.cardKey, 'overdue_triage');
    expect(next.mood, CoachingMood.firm);
  });

  test('overdue coaching carries the exact canonical record set', () {
    final decision = engine.select(
      evidence(
        overdueCount: 2,
        overdueTaskIds: const ['occurrence-a', 'occurrence-b'],
      ),
      const [],
    );

    expect(decision.cardKey, 'overdue_triage');
    expect(decision.relatedTaskIds, ['occurrence-a', 'occurrence-b']);
    expect(decision.expression, CoachingExpression.overwhelmed);
  });

  test('too-frequent feedback produces a compact low-pressure card', () {
    final decision = engine.select(evidence(readyTodayCount: 2), [
      CoachingFeedbackSignal(
        kind: CoachingFeedbackKind.tooFrequent,
        category: 'schedule',
        cardKey: 'scheduled_next_step',
        submittedAt: now.subtract(const Duration(hours: 1)),
      ),
    ]);
    expect(decision.cardKey, 'feedback_space');
    expect(decision.compact, isTrue);
    expect(decision.mood, CoachingMood.supportive);
  });

  test('active work receives supportive rather than punitive coaching', () {
    final decision = engine.select(evidence(hasActiveTask: true), const []);
    expect(decision.cardKey, 'protect_active_focus');
    expect(decision.mood, CoachingMood.supportive);
  });

  test('proven focus momentum is celebrated', () {
    final decision = engine.select(evidence(focusCyclesLastWeek: 4), const []);
    expect(decision.cardKey, 'focus_momentum');
    expect(decision.mood, CoachingMood.celebrating);
  });

  test('approved wellbeing context receives recovery guidance', () {
    final decision = engine.select(
      evidence(approvedHealthSummary: true),
      const [],
    );
    expect(decision.cardKey, 'rest_plan');
    expect(decision.mood, CoachingMood.recovery);
  });
}

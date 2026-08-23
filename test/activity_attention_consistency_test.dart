import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';
import 'package:taskmaster_pro/features/activity/data/activity_aggregation_service.dart';
import 'package:taskmaster_pro/features/activity/data/activity_repository.dart';
import 'package:taskmaster_pro/features/activity/presentation/activity_review_screen.dart';

void main() {
  final start = DateTime.utc(2026, 8, 23, 7);

  ActivityReviewEntry entry({
    required String id,
    String reason = 'unknown_application',
    String? idleState = 'active',
    String processName = 'Code.exe',
    String status = 'pending',
    String? suggestedTargetType,
    String? suggestedTargetId,
    String? sourceTaskId,
  }) {
    final segment = LocalActivitySegment(
      id: id,
      userId: 'user-1',
      deviceId: 'device-1',
      deviceEventId: 'event-$id',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 1)),
      sourceType: 'application',
      processName: processName,
      idleState: idleState,
      rawMetadataJson: jsonEncode({'source_task_id': ?sourceTaskId}),
      revision: 1,
      createdAt: start,
      updatedAt: start,
    );
    return ActivityReviewEntry(
      segment: segment,
      review: LocalActivityReview(
        id: 'review-$id',
        userId: 'user-1',
        activitySegmentId: id,
        reviewReason: reason,
        priority: 2,
        suggestedTargetType: suggestedTargetType,
        suggestedTargetId: suggestedTargetId,
        status: status,
        revision: 1,
        createdAt: start,
        updatedAt: start,
      ),
    );
  }

  ActivityPeriodSummary period({
    required String id,
    required ActivityTimeKind kind,
    bool crossTask = false,
    bool isBreak = false,
  }) => ActivityPeriodSummary(
    segmentId: id,
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 1)),
    durationMs: const Duration(minutes: 1).inMilliseconds,
    kind: kind,
    detail: 'Code.exe',
    classification: 'unclassified',
    targetId: null,
    isBreak: isBreak,
    isCrossTask: crossTask,
  );

  test('active capture state is never counted as inactive attention', () {
    final active = entry(id: 'active');
    final idle = entry(id: 'idle', reason: 'idle', idleState: 'technical_idle');

    expect(isInactiveActivityState(active.segment.idleState), isFalse);
    expect(activityAttentionKind(active), ActivityAttentionKind.other);
    expect(activityAttentionKind(idle), ActivityAttentionKind.inactive);
  });

  test('dashboard attention counts the same grouped unit as Activity', () {
    final rows = [
      entry(id: 'code-1'),
      entry(id: 'code-2'),
      entry(id: 'idle-1', reason: 'idle', idleState: 'technical_idle'),
      entry(
        id: 'cross-1',
        sourceTaskId: 'task-a',
        suggestedTargetType: 'task_occurrence',
        suggestedTargetId: 'task-b',
      ),
      entry(id: 'resolved', status: 'confirmed'),
    ];

    final summary = summarizeActivityAttention(rows);
    expect(summary.otherGroups, 1);
    expect(summary.inactiveGroups, 1);
    expect(summary.crossTaskGroups, 1);
    expect(summary.totalGroups, 3);
  });

  test('pending and history filters keep only their matching periods', () {
    final active = period(id: 'active', kind: ActivityTimeKind.active);
    final idle = period(id: 'idle', kind: ActivityTimeKind.idle);
    final cross = period(
      id: 'cross',
      kind: ActivityTimeKind.active,
      crossTask: true,
    );
    final group = ActivityGroupSummary(
      key: 'application:code.exe::unclassified',
      name: 'Visual Studio Code',
      sourceType: 'application',
      totalMs: active.durationMs + idle.durationMs + cross.durationMs,
      activeMs: active.durationMs + cross.durationMs,
      idleMs: idle.durationMs,
      uncertainMs: 0,
      classification: 'unclassified',
      relatedTaskId: null,
      periods: [active, idle, cross],
      containsBreak: false,
      containsCrossTask: true,
      suggestionSource: null,
    );
    final aggregation = ActivityAggregation(
      groups: [group],
      totalMs: group.totalMs,
      activeMs: group.activeMs,
      idleMs: group.idleMs,
      uncertainMs: 0,
      needsReviewMs: group.totalMs,
    );
    final pendingIdle = entry(
      id: 'idle',
      reason: 'idle',
      idleState: 'technical_idle',
    );

    final pendingGroups = activityGroupsForFilter(
      aggregation: aggregation,
      filter: 'needs_review',
      pendingBySegment: {'idle': pendingIdle},
      hideConfirmedSystem: true,
      showPossibleSystem: false,
    );
    expect(pendingGroups.single.periods.map((item) => item.segmentId), [
      'idle',
    ]);
    expect(pendingGroups.single.totalMs, idle.durationMs);

    final idleGroups = activityGroupsForFilter(
      aggregation: aggregation,
      filter: 'idle',
      pendingBySegment: const {},
      hideConfirmedSystem: true,
      showPossibleSystem: true,
    );
    expect(idleGroups.single.periods.map((item) => item.segmentId), ['idle']);

    final crossGroups = activityGroupsForFilter(
      aggregation: aggregation,
      filter: 'cross_task',
      pendingBySegment: const {},
      hideConfirmedSystem: true,
      showPossibleSystem: true,
    );
    expect(crossGroups.single.periods.map((item) => item.segmentId), ['cross']);

    final corrected = activityAggregationWithPendingReviews(aggregation, {
      'idle',
    });
    expect(corrected.needsReviewMs, idle.durationMs);
  });

  test('dashboard pending filters scope the summary to the matching rows', () {
    final rows = [
      entry(id: 'other'),
      entry(id: 'idle', reason: 'idle', idleState: 'technical_idle'),
      entry(
        id: 'cross',
        sourceTaskId: 'task-a',
        suggestedTargetType: 'task_occurrence',
        suggestedTargetId: 'task-b',
      ),
    ];

    expect(pendingReviewSegmentIdsForFilter('pending_other', rows), {'other'});
    expect(pendingReviewSegmentIdsForFilter('pending_idle', rows), {'idle'});
    expect(pendingReviewSegmentIdsForFilter('pending_cross_task', rows), {
      'cross',
    });
  });
}

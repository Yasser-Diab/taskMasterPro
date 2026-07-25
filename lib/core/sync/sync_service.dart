import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../platform/device_identity.dart';

enum SyncHealth { offline, idle, syncing, attention }

class SyncService {
  SyncService({required this.database, required this.client});

  final AppDatabase database;
  final SupabaseClient client;

  final _health = StreamController<SyncHealth>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _drainTimer;
  RealtimeChannel? _channel;

  Stream<SyncHealth> get health => _health.stream;

  Future<void> start() async {
    await _registerDevice();
    _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.every((result) => result == ConnectivityResult.none)) {
        _health.add(SyncHealth.offline);
        return;
      }
      unawaited(drainOutbox());
    });
    _drainTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(drainOutbox()),
    );
    await _subscribeToAccount();
    await pullChanges();
    await drainOutbox();
  }

  Future<void> _registerDevice() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final deviceId = await DeviceIdentity.id();
    final packageInfo = await PackageInfo.fromPlatform();
    await client.from('account_devices').upsert({
      'id': deviceId,
      'user_id': user.id,
      'device_name': DeviceIdentity.displayName,
      'platform': DeviceIdentity.platform,
      'app_version': packageInfo.version,
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      'updated_by_device_id': deviceId,
    });
  }

  Future<void> _subscribeToAccount() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    await _channel?.unsubscribe();
    _channel = client.channel('taskmaster:user:${user.id}:runtime');
    _channel!
        .onBroadcast(
          event: 'entity_changed',
          callback: (_) => unawaited(pullChanges()),
        )
        .subscribe();
  }

  Future<void> drainOutbox() async {
    final user = client.auth.currentUser;
    if (user == null) {
      _health.add(SyncHealth.idle);
      return;
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.every((result) => result == ConnectivityResult.none)) {
      _health.add(SyncHealth.offline);
      return;
    }

    final now = DateTime.now();
    final query = database.select(database.localOutboxCommands)
      ..where(
        (row) =>
            row.status.equals('pending') &
            (row.nextAttemptAt.isNull() |
                row.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)])
      ..limit(50);
    final commands = await query.get();
    if (commands.isEmpty) {
      _health.add(SyncHealth.idle);
      return;
    }

    _health.add(SyncHealth.syncing);
    var needsAttention = false;

    for (final command in commands) {
      try {
        final payload = jsonDecode(command.payloadJson) as Map<String, dynamic>;
        final response = command.entityType == 'task_occurrences'
            ? await client.rpc<Object?>(
                'apply_task_occurrence_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_entity_id': command.entityId,
                  'p_base_revision': command.baseRevision,
                  'p_operation': command.commandType,
                  'p_payload': payload,
                },
              )
            : command.entityType == 'user_settings'
            ? await client.rpc<Object?>(
                'apply_user_settings_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_base_revision': command.baseRevision,
                  'p_payload': payload,
                },
              )
            : await client.rpc<Object?>(
                'apply_entity_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_entity_type': command.entityType,
                  'p_entity_id': command.entityId,
                  'p_base_revision': command.baseRevision,
                  'p_operation': command.commandType,
                  'p_payload': payload,
                },
              );
        final result = response is Map
            ? Map<String, dynamic>.from(response)
            : <String, dynamic>{};
        final remoteStatus = result['status'] as String?;
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          LocalOutboxCommandsCompanion(
            status: Value(remoteStatus == 'accepted' ? 'accepted' : 'conflict'),
            lastError: remoteStatus == 'accepted'
                ? const Value.absent()
                : Value(jsonEncode(result)),
          ),
        );
        needsAttention = needsAttention || remoteStatus != 'accepted';
      } catch (error) {
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          LocalOutboxCommandsCompanion(
            attemptCount: Value(command.attemptCount + 1),
            nextAttemptAt: Value(
              DateTime.now().add(
                Duration(seconds: 5 * (command.attemptCount + 1)),
              ),
            ),
            lastError: Value(error.toString()),
          ),
        );
        needsAttention = true;
        break;
      }
    }

    if (!needsAttention) {
      await pullChanges();
    }
    _health.add(needsAttention ? SyncHealth.attention : SyncHealth.idle);
  }

  Future<void> pullChanges() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    _health.add(SyncHealth.syncing);
    final stateId = 'sync:${user.id}';
    final state = await (database.select(
      database.localSyncStates,
    )..where((row) => row.id.equals(stateId))).getSingleOrNull();
    var sequence = state?.lastChangeSequence ?? 0;

    while (true) {
      final rows = await client
          .from('sync_change_log')
          .select(
            'change_sequence,entity_type,entity_id,operation,entity_revision',
          )
          .gt('change_sequence', sequence)
          .order('change_sequence')
          .limit(250);
      if (rows.isEmpty) break;
      for (final raw in rows) {
        final change = Map<String, dynamic>.from(raw);
        final entityType = change['entity_type'] as String;
        final entityId = change['entity_id'] as String;
        final changeSequence = (change['change_sequence'] as num).toInt();
        if (!await _hasPendingCommand(entityType, entityId)) {
          await _pullEntity(entityType, entityId);
        }
        sequence = changeSequence;
      }
      await database
          .into(database.localSyncStates)
          .insertOnConflictUpdate(
            LocalSyncStatesCompanion.insert(
              id: stateId,
              userId: user.id,
              lastChangeSequence: Value(sequence),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      if (rows.length < 250) break;
    }
    _health.add(SyncHealth.idle);
  }

  Future<bool> _hasPendingCommand(String entityType, String entityId) async {
    final count =
        await (database.selectOnly(database.localOutboxCommands)
              ..addColumns([database.localOutboxCommands.commandId.count()])
              ..where(
                database.localOutboxCommands.entityType.equals(entityType) &
                    database.localOutboxCommands.entityId.equals(entityId) &
                    database.localOutboxCommands.status.equals('pending'),
              ))
            .map(
              (row) =>
                  row.read(database.localOutboxCommands.commandId.count()) ?? 0,
            )
            .getSingle();
    return count > 0;
  }

  Future<void> _pullEntity(String entityType, String entityId) async {
    final remote = await client
        .from(entityType)
        .select()
        .eq('id', entityId)
        .maybeSingle();
    if (remote == null) return;
    final row = Map<String, dynamic>.from(remote);
    switch (entityType) {
      case 'profiles':
        await _applyProfile(row);
      case 'user_settings':
        await _applySettings(row);
      case 'task_domains':
        await _applyDomain(row);
      case 'task_occurrences':
        await _applyTask(row);
      case 'roadmaps':
        await _applyRoadmap(row);
      case 'activity_segments':
        await _applyActivitySegment(row);
      case 'activity_attributions':
        await _applyActivityAttribution(row);
      case 'activity_contributions':
        await _applyActivityContribution(row);
        await _applyGeneric(entityType, row);
      case 'activity_review_queue':
        await _applyActivityReview(row);
      default:
        await _applyGeneric(entityType, row);
        if (entityType == 'execution_sessions') {
          await _applyExecutionRuntime(row);
        }
    }
  }

  Future<void> _applyProfile(Map<String, dynamic> row) async {
    await database
        .into(database.localProfiles)
        .insertOnConflictUpdate(
          LocalProfilesCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            displayName: Value(row['display_name'] as String? ?? ''),
            email: Value(row['email'] as String?),
            imagePath: Value(row['profile_image_path'] as String?),
            genderIdentity: Value(row['gender_identity'] as String?),
            onboardingCompleted: Value(row['onboarding_completed_at'] != null),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            updatedByDeviceId: Value(row['updated_by_device_id'] as String?),
            lastCommandId: Value(row['last_command_id'] as String?),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applySettings(Map<String, dynamic> row) async {
    final data = row['data'] is Map
        ? Map<String, dynamic>.from(row['data'] as Map)
        : const <String, dynamic>{};
    await database
        .into(database.localAppSettings)
        .insertOnConflictUpdate(
          LocalAppSettingsCompanion.insert(
            id: 'app',
            userId: Value(row['user_id'] as String),
            localeCode: Value(row['preferred_language'] as String? ?? 'en'),
            themeKey: Value(row['theme'] as String? ?? 'system'),
            accentColor: Value(
              (row['accent_color'] as num?)?.toInt() ?? 0xFF0B78D1,
            ),
            timeZone: Value(row['time_zone'] as String? ?? 'UTC'),
            clockFormat: Value(row['clock_format'] as String? ?? '24h'),
            notificationSoundKey: Value(
              row['notification_sound'] as String? ?? 'system',
            ),
            healthConnectEnabled: Value(
              data['health_connect_enabled'] as bool? ?? false,
            ),
            cycleTrackingEnabled: Value(
              data['cycle_tracking_enabled'] as bool? ?? false,
            ),
            cycleStorageMode: Value(
              data['cycle_storage_mode'] as String? ?? 'local_only',
            ),
            calendarShowCompleted: Value(
              data['calendar_show_completed'] as bool? ?? true,
            ),
            applicationTrackingEnabled: Value(
              data['application_tracking_enabled'] as bool? ?? false,
            ),
            windowTitleTrackingEnabled: Value(
              data['window_title_tracking_enabled'] as bool? ?? false,
            ),
            idleDetectionEnabled: Value(
              data['idle_detection_enabled'] as bool? ?? true,
            ),
            idleThresholdSeconds: Value(
              (data['idle_threshold_seconds'] as num?)?.toInt() ?? 30,
            ),
            detectBreakActivity: Value(
              data['detect_break_activity'] as bool? ?? true,
            ),
            detectCrossTaskActivity: Value(
              data['detect_cross_task_activity'] as bool? ?? true,
            ),
            retainUnclassifiedActivity: Value(
              data['retain_unclassified_activity'] as bool? ?? true,
            ),
            retainTechnicalIdle: Value(
              data['retain_technical_idle'] as bool? ?? true,
            ),
            automaticTrustedRules: Value(
              data['automatic_trusted_rules'] as bool? ?? false,
            ),
            activitySyncEnabled: Value(
              data['activity_sync_enabled'] as bool? ?? true,
            ),
            automaticConfidenceThreshold: Value(
              (data['automatic_confidence_threshold'] as num?)?.toDouble() ??
                  0.9,
            ),
            minimumSuggestionDurationMs: Value(
              (data['minimum_suggestion_duration_ms'] as num?)?.toInt() ??
                  30000,
            ),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            lastCommandId: Value(row['last_command_id'] as String?),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyDomain(Map<String, dynamic> row) async {
    await database
        .into(database.localDomains)
        .insertOnConflictUpdate(
          LocalDomainsCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            name: row['name'] as String? ?? 'Domain',
            iconName: Value(row['icon_name'] as String? ?? 'folder'),
            colorValue: (row['color_value'] as num?)?.toInt() ?? 0xFF4169E1,
            position: Value((row['position'] as num?)?.toDouble() ?? 0),
            archivedAt: Value(_instant(row['archived_at'])),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            createdByDeviceId: Value(row['created_by_device_id'] as String?),
            updatedByDeviceId: Value(row['updated_by_device_id'] as String?),
            lastCommandId: Value(row['last_command_id'] as String?),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyTask(Map<String, dynamic> row) async {
    await database
        .into(database.localTasks)
        .insertOnConflictUpdate(
          LocalTasksCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            templateId: Value(row['template_id'] as String?),
            title: row['title'] as String? ?? 'Untitled task',
            description: Value(row['description'] as String? ?? ''),
            domainId: Value(row['domain_id'] as String?),
            status: Value(row['status'] as String? ?? 'ready'),
            priority: Value((row['priority'] as num?)?.toInt() ?? 2),
            executionMode: Value(row['execution_mode'] as String? ?? 'manual'),
            scheduledDate: Value(_date(row['scheduled_date'])),
            plannedStart: Value(_instant(row['planned_start'])?.toLocal()),
            plannedEnd: Value(_instant(row['planned_end'])?.toLocal()),
            dueAt: Value(_instant(row['due_at'])?.toLocal()),
            estimatedDurationMs: Value(
              (row['estimated_duration_ms'] as num?)?.toInt() ?? 0,
            ),
            actualStart: Value(_instant(row['actual_start'])?.toLocal()),
            actualFinish: Value(_instant(row['actual_finish'])?.toLocal()),
            activeDurationMs: Value(
              (row['actual_duration_ms'] as num?)?.toInt() ?? 0,
            ),
            progress: Value((row['progress'] as num?)?.toDouble() ?? 0),
            roadmapId: Value(row['roadmap_id'] as String?),
            roadmapPhaseId: Value(row['roadmap_phase_id'] as String?),
            occurrenceKey: Value(row['occurrence_key'] as String?),
            dataJson: Value(
              jsonEncode(
                row['data'] is Map
                    ? Map<String, dynamic>.from(row['data'] as Map)
                    : const <String, dynamic>{},
              ),
            ),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            createdByDeviceId: Value(row['created_by_device_id'] as String?),
            updatedByDeviceId: Value(row['updated_by_device_id'] as String?),
            lastCommandId: Value(row['last_command_id'] as String?),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyRoadmap(Map<String, dynamic> row) async {
    await database
        .into(database.localRoadmaps)
        .insertOnConflictUpdate(
          LocalRoadmapsCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            title: row['title'] as String? ?? 'Untitled roadmap',
            description: Value(row['description'] as String? ?? ''),
            status: Value(row['status'] as String? ?? 'active'),
            plannedStart: Value(_date(row['planned_start'])),
            originalTargetDate: Value(_date(row['original_target_date'])),
            forecastTargetDate: Value(_date(row['forecast_target_date'])),
            finalOutcome: Value(row['final_outcome'] as String? ?? ''),
            progress: Value((row['progress'] as num?)?.toDouble() ?? 0),
            requiredEffortMs: Value(
              (row['required_effort_ms'] as num?)?.toInt(),
            ),
            completedEffortMs: Value(
              (row['completed_effort_ms'] as num?)?.toInt() ?? 0,
            ),
            riskLevel: Value(row['risk_level'] as String? ?? 'low'),
            forecastConfidence: Value(
              row['forecast_confidence'] as String? ?? 'low',
            ),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            updatedByDeviceId: Value(row['updated_by_device_id'] as String?),
            lastCommandId: Value(row['last_command_id'] as String?),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyActivitySegment(Map<String, dynamic> row) async {
    final startedAt = _instant(row['started_at']);
    final endedAt = _instant(row['ended_at']);
    if (startedAt == null || endedAt == null) return;
    await database
        .into(database.localActivitySegments)
        .insertOnConflictUpdate(
          LocalActivitySegmentsCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            deviceId: row['device_id'] as String,
            deviceEventId:
                row['device_event_id'] as String? ?? row['id'] as String,
            startedAt: startedAt,
            endedAt: endedAt,
            sourceType: row['source_type'] as String? ?? 'unknown',
            processName: Value(row['process_name'] as String?),
            windowTitle: Value(row['window_title'] as String?),
            domain: Value(row['domain'] as String?),
            url: Value(row['url'] as String?),
            pageTitle: Value(row['page_title'] as String?),
            idleState: Value(row['idle_state'] as String?),
            captureConfidence: Value(
              (row['capture_confidence'] as num?)?.toDouble(),
            ),
            rawMetadataJson: Value(
              jsonEncode(
                row['raw_metadata'] is Map
                    ? Map<String, dynamic>.from(row['raw_metadata'] as Map)
                    : const <String, dynamic>{},
              ),
            ),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyActivityAttribution(Map<String, dynamic> row) async {
    await database
        .into(database.localAttributions)
        .insertOnConflictUpdate(
          LocalAttributionsCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            activitySegmentId: row['activity_segment_id'] as String,
            targetType: row['target_type'] as String? ?? 'unassigned_activity',
            targetId: Value(row['target_id'] as String?),
            classification: row['classification'] as String? ?? 'unknown',
            confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
            attributionStatus: Value(
              row['attribution_status'] as String? ?? 'proposed',
            ),
            confirmedByUser: Value(row['confirmed_by_user'] as bool? ?? false),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyActivityContribution(Map<String, dynamic> row) async {
    await database
        .into(database.localContributions)
        .insertOnConflictUpdate(
          LocalContributionsCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            activitySegmentId: row['activity_segment_id'] as String,
            attributionId: row['activity_attribution_id'] as String,
            targetType: row['target_type'] as String? ?? 'unassigned_activity',
            targetId: Value(row['target_id'] as String?),
            contributionType:
                row['contribution_type'] as String? ?? 'informational_only',
            physicalDurationMs:
                (row['physical_duration_ms'] as num?)?.toInt() ?? 0,
            creditedDurationMs:
                (row['credited_duration_ms'] as num?)?.toInt() ?? 0,
            progressValue: Value((row['progress_value'] as num?)?.toDouble()),
            isUnscheduled: Value(row['is_unscheduled'] as bool? ?? false),
            isCrossTask: Value(row['is_cross_task'] as bool? ?? false),
            isIdleDerived: Value(row['is_idle_derived'] as bool? ?? false),
            isAutomatic: Value(row['is_automatic'] as bool? ?? false),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyActivityReview(Map<String, dynamic> row) async {
    final suggestions = row['suggested_targets'];
    String? targetType;
    String? targetId;
    String? targetTitle;
    if (suggestions is List && suggestions.isNotEmpty) {
      final first = suggestions.first;
      if (first is Map) {
        targetType = first['target_type'] as String?;
        targetId = first['target_id'] as String?;
        targetTitle = first['title'] as String?;
      }
    }
    await database
        .into(database.localActivityReviews)
        .insertOnConflictUpdate(
          LocalActivityReviewsCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            activitySegmentId: row['activity_segment_id'] as String,
            reviewReason: row['review_reason'] as String? ?? 'unknown',
            priority: Value((row['priority'] as num?)?.toInt() ?? 2),
            suggestedTargetType: Value(targetType),
            suggestedTargetId: Value(targetId),
            suggestedTargetTitle: Value(targetTitle),
            suggestedClassification: Value(
              row['suggested_classification'] as String?,
            ),
            confidence: Value((row['confidence'] as num?)?.toDouble()),
            status: Value(row['status'] as String? ?? 'pending'),
            reviewedAt: Value(_instant(row['reviewed_at'])),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyGeneric(
    String entityType,
    Map<String, dynamic> row,
  ) async {
    final title =
        row['title'] as String? ??
        row['name'] as String? ??
        row['topic'] as String? ??
        row['url'] as String? ??
        row['summary_type'] as String? ??
        entityType.replaceAll('_', ' ');
    final parentId =
        row['roadmap_id'] as String? ??
        row['task_occurrence_id'] as String? ??
        row['task_template_id'] as String? ??
        row['workspace_id'] as String? ??
        row['session_id'] as String? ??
        row['resource_id'] as String? ??
        row['scope_id'] as String? ??
        row['reading_target_id'] as String?;
    final secondaryParentId =
        row['phase_id'] as String? ??
        row['roadmap_phase_id'] as String? ??
        row['checkpoint_id'] as String? ??
        row['application_id'] as String? ??
        row['depends_on_task_id'] as String?;
    await database
        .into(database.localEntityRecords)
        .insertOnConflictUpdate(
          LocalEntityRecordsCompanion.insert(
            id: row['id'] as String,
            userId: row['user_id'] as String,
            entityType: entityType,
            parentId: Value(parentId),
            secondaryParentId: Value(secondaryParentId),
            title: Value(title),
            status: Value(
              row['status'] as String? ?? row['state'] as String? ?? 'active',
            ),
            position: Value((row['position'] as num?)?.toDouble() ?? 0),
            dataJson: Value(jsonEncode(row)),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            createdAt: _instant(row['created_at']) ?? DateTime.now().toUtc(),
            updatedAt: _instant(row['updated_at']) ?? DateTime.now().toUtc(),
            createdByDeviceId: Value(row['created_by_device_id'] as String?),
            updatedByDeviceId: Value(row['updated_by_device_id'] as String?),
            lastCommandId: Value(row['last_command_id'] as String?),
            deletedAt: Value(_instant(row['deleted_at'])),
          ),
        );
  }

  Future<void> _applyExecutionRuntime(Map<String, dynamic> row) async {
    final state = row['state'] as String? ?? 'idle';
    final sessionId = row['id'] as String;
    final taskId = row['task_occurrence_id'] as String?;
    final current = await (database.select(
      database.localRuntimeStates,
    )..where((runtime) => runtime.id.equals('runtime'))).getSingleOrNull();
    final updatedAt = _instant(row['updated_at']) ?? DateTime.now().toUtc();
    if (current != null && current.updatedAt.isAfter(updatedAt)) return;
    if (state == 'completed' || state == 'cancelled' || state == 'stopped') {
      if (current?.sessionId != sessionId) return;
      await database
          .into(database.localRuntimeStates)
          .insertOnConflictUpdate(
            LocalRuntimeStatesCompanion.insert(
              id: 'runtime',
              userId: row['user_id'] as String,
              state: const Value('idle'),
              accumulatedActiveMs: Value(
                (row['accumulated_active_ms'] as num?)?.toInt() ?? 0,
              ),
              accumulatedPausedMs: Value(
                (row['accumulated_paused_ms'] as num?)?.toInt() ?? 0,
              ),
              revision: Value((row['revision'] as num?)?.toInt() ?? 1),
              updatedAt: updatedAt,
            ),
          );
      return;
    }
    if (state != 'running' && state != 'paused') return;
    await database
        .into(database.localRuntimeStates)
        .insertOnConflictUpdate(
          LocalRuntimeStatesCompanion.insert(
            id: 'runtime',
            userId: row['user_id'] as String,
            activeTaskId: Value(taskId),
            sessionId: Value(sessionId),
            state: Value(state),
            segmentStartedAt: Value(_instant(row['active_segment_started_at'])),
            accumulatedActiveMs: Value(
              (row['accumulated_active_ms'] as num?)?.toInt() ?? 0,
            ),
            accumulatedPausedMs: Value(
              (row['accumulated_paused_ms'] as num?)?.toInt() ?? 0,
            ),
            revision: Value((row['revision'] as num?)?.toInt() ?? 1),
            updatedAt: updatedAt,
          ),
        );
  }

  DateTime? _instant(Object? value) {
    return value is String ? DateTime.tryParse(value)?.toUtc() : null;
  }

  DateTime? _date(Object? value) {
    if (value is! String) return null;
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  Future<void> dispose() async {
    _drainTimer?.cancel();
    await _connectivitySubscription?.cancel();
    await _channel?.unsubscribe();
    await _health.close();
  }
}

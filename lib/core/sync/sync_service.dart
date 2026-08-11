import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../platform/device_identity.dart';
import '../../features/activity/data/activity_privacy_policy.dart';
import '../../features/roadmaps/data/roadmap_repository.dart';

enum SyncHealth { offline, idle, syncing, attention }

enum SyncDeliveryFailureKind { retryable, permanent, applicationCatalogAlias }

enum SyncConflictCategory {
  alreadyApplied,
  duplicate,
  superseded,
  permanentFailure,
  revisionConflict,
  discardedByUser,
  needsReview,
}

class SyncConflictNotice {
  const SyncConflictNotice({
    required this.commandId,
    required this.conflictId,
    required this.category,
    required this.subject,
    required this.localSummary,
    required this.serverSummary,
    required this.canKeepDeviceVersion,
    required this.isResolved,
  });

  final String commandId;
  final String? conflictId;
  final SyncConflictCategory category;
  final String subject;
  final String localSummary;
  final String? serverSummary;
  final bool canKeepDeviceVersion;
  final bool isResolved;
}

@visibleForTesting
SyncConflictCategory syncConflictCategoryForReason(
  String? reason, {
  String errorText = '',
}) {
  final normalized = reason?.trim().toLowerCase();
  final message = errorText.toLowerCase();
  if (const {'already_applied', 'same_intended_result'}.contains(normalized)) {
    return SyncConflictCategory.alreadyApplied;
  }
  if (const {
        'duplicate',
        'unique_constraint',
        'duplicate_review_resolved',
      }.contains(normalized) ||
      message.contains('unique_constraint')) {
    return SyncConflictCategory.duplicate;
  }
  if (const {
    'superseded',
    'newer_command',
    'entity_deleted',
  }.contains(normalized)) {
    return SyncConflictCategory.superseded;
  }
  if (normalized == 'discarded_by_user') {
    return SyncConflictCategory.discardedByUser;
  }
  if (normalized == 'revision_mismatch') {
    return SyncConflictCategory.revisionConflict;
  }
  if (const {
        'invalid_command_contract',
        'invalid_command_payload',
        'permanent_failure',
      }.contains(normalized) ||
      message.contains('invalid input syntax for type uuid')) {
    return SyncConflictCategory.permanentFailure;
  }
  return SyncConflictCategory.needsReview;
}

/// Separates ordinary connectivity/server interruption from a command the
/// server has definitively rejected.
///
/// Pending retryable work remains durable and is shown as synchronizing. It
/// must not become a scary user-facing "needs attention" item after one
/// temporary failure. Permission, malformed-payload and other deterministic
/// rejections remain visible in technical diagnostics.
@visibleForTesting
SyncDeliveryFailureKind classifySyncDeliveryFailure({
  required String entityType,
  required String commandType,
  required String? errorCode,
  required String errorMessage,
}) {
  final code = errorCode?.trim().toUpperCase();
  final message = errorMessage.toLowerCase();
  if (entityType == 'application_catalog' &&
      commandType == 'create' &&
      code == '23505' &&
      (message.contains('application_catalog_identifier_idx') ||
          (message.contains('platform') &&
              message.contains('application_identifier')))) {
    return SyncDeliveryFailureKind.applicationCatalogAlias;
  }

  if (code == '42501' ||
      code == '23502' ||
      code == '23505' ||
      code == '23514' ||
      code == '22P02' ||
      code == '42703' ||
      code == '42883' ||
      message.contains('permission denied') ||
      message.contains('device_not_registered') ||
      message.contains('unsupported_entity_type') ||
      message.contains('unsupported_operation') ||
      message.contains('invalid_payload_columns')) {
    return SyncDeliveryFailureKind.permanent;
  }

  // A child can be observed before its parent command is accepted. Dependency
  // ordering and the missing-parent repair pass make 23503 recoverable.
  return SyncDeliveryFailureKind.retryable;
}

@visibleForTesting
bool isLegacyPendingApplicationCatalogAlias({
  required String entityType,
  required String commandType,
  required String? lastError,
}) {
  final message = lastError?.toLowerCase() ?? '';
  return entityType == 'application_catalog' &&
      commandType == 'create' &&
      message.contains('23505') &&
      (message.contains('application_catalog_identifier_idx') ||
          (message.contains('platform') &&
              message.contains('application_identifier')));
}

@visibleForTesting
bool isPermanentSyncInfrastructureFailure({
  required String? errorCode,
  required String errorMessage,
}) {
  final code = errorCode?.trim().toUpperCase();
  final message = errorMessage.toLowerCase();
  return code == '42501' ||
      code == '42703' ||
      code == '42883' ||
      code == 'PGRST202' ||
      message.contains('permission denied') ||
      message.contains('device_not_registered') ||
      message.contains('authentication_required');
}

@visibleForTesting
Duration syncRetryDelay(int completedAttempts) {
  final exponent = completedAttempts.clamp(1, 6).toInt();
  final seconds = 5 * (1 << (exponent - 1));
  return Duration(seconds: seconds.clamp(5, 300));
}

@visibleForTesting
class ReplayableSyncOperation {
  Future<void>? _inFlight;
  bool _replayRequested = false;

  Future<void>? get inFlight => _inFlight;

  Future<void> run(Future<void> Function() action) {
    final existing = _inFlight;
    if (existing != null) {
      // A command can be inserted after the active pass has already read an
      // empty outbox. Remember that wake-up so it is not delayed until the
      // periodic fallback timer.
      _replayRequested = true;
      return existing;
    }

    late final Future<void> operation;
    operation =
        (() async {
          do {
            _replayRequested = false;
            await action();
          } while (_replayRequested);
        })().whenComplete(() {
          if (identical(_inFlight, operation)) {
            _inFlight = null;
          }
        });
    _inFlight = operation;
    return operation;
  }

  void cancelReplay() {
    _replayRequested = false;
  }
}

@visibleForTesting
bool authoritativeSnapshotCanAdvanceCursor(Iterable<String> failedEntities) =>
    failedEntities.isEmpty;

@visibleForTesting
bool shouldRunAuthoritativeSnapshot({
  required bool hasDurableCursor,
  required bool snapshotRetryRequired,
}) => snapshotRetryRequired || !hasDurableCursor;

@visibleForTesting
bool hasUsableDurableSyncCursor(int? lastChangeSequence) =>
    lastChangeSequence != null && lastChangeSequence > 0;

/// Entity tables needed to make a first device bootstrap usable before the
/// incremental cursor advances. Keep task resources and their task-scoped
/// website relationships here: a fresh device cannot recover either record
/// created before its initial high-water mark from incremental changes later.
@visibleForTesting
const authoritativeSnapshotEntityTypes = <String>[
  'profiles',
  'user_settings',
  'task_domains',
  'task_occurrences',
  'task_resources',
  'website_rules',
  'execution_sessions',
  'user_runtime_state',
  'session_events',
  'pomodoro_cycles',
  'task_completion_evidence',
  'checklist_items',
  'task_templates',
  'roadmaps',
  'roadmap_phases',
  'roadmap_milestones',
  'roadmap_checkpoints',
  'roadmap_task_links',
  'roadmap_progress_rules',
  'application_catalog',
  'user_application_overrides',
  'task_application_links',
  'application_rules',
  'activity_contributions',
  'contribution_roadmap_effects',
  'coaching_settings',
  'privacy_settings',
  'account_deletion_requests',
  'user_vaults',
  'vault_items',
  'vault_device_keys',
  'health_summaries',
];

/// A snapshot cursor is only valid for the entity set it has fully covered.
///
/// v1 could advance a fresh device's cursor without applying
/// `task_resources`, which made imported URL resources permanently invisible
/// until a later change touched each row. v2 still omitted the corresponding
/// `website_rules`, so the task's Website Connections could remain absent even
/// when its Resources were present. Bumping this epoch performs one bounded,
/// authoritative repair snapshot for the incomplete local cache; it does not
/// alter server state or replay local commands.
const _authoritativeSnapshotCursorEpoch = 3;

@visibleForTesting
String authoritativeSnapshotStateId(String userId) =>
    'sync:v$_authoritativeSnapshotCursorEpoch:$userId';

@visibleForTesting
bool shouldMigrateLegacyActivityConflict({
  required String status,
  required String entityType,
  required String commandType,
  required String? reason,
}) {
  if (status != 'conflict' || commandType != 'create') return false;
  if (!const {
    'activity_segments',
    'activity_attributions',
    'activity_contributions',
    'activity_review_queue',
    'classification_feedback',
  }.contains(entityType)) {
    return false;
  }
  return const {
    'invalid_command_payload',
    'invalid_command_contract',
    'missing_entity',
    'server_rejected_command',
  }.contains(reason);
}

@visibleForTesting
int canonicalTaskActiveDurationMs(
  Map<String, dynamic> row, {
  required int existingValue,
}) {
  final value = row['active_duration_ms'] ?? row['actual_duration_ms'];
  return value is num ? value.toInt() : existingValue;
}

@visibleForTesting
bool shouldSupersedeOnlineCanonicalMismatch(String entityType, String? reason) {
  return const {
        'revision_mismatch',
        'active_session_changed',
        'stale_runtime',
      }.contains(reason) &&
      const {
        'execution_runtime',
        'execution_runtime_switch',
      }.contains(entityType);
}

@visibleForTesting
bool isIdempotentDuplicateCreateConflict({
  required String commandType,
  required String? reason,
  required Object? serverRevision,
}) {
  final revision = switch (serverRevision) {
    num value => value.toInt(),
    String value => int.tryParse(value.trim()),
    _ => null,
  };
  return commandType == 'create' &&
      ((reason == 'revision_mismatch' && (revision ?? 0) >= 1) ||
          reason == 'unique_constraint');
}

/// A create can be retired only when the server has proved that the exact
/// durable UUID already belongs to this account and is still an active row.
///
/// This deliberately does not treat a matching display name, a deleted row,
/// or another account's row as equivalent. Those cases may carry real user
/// intent and remain ordinary conflicts.
@visibleForTesting
bool isProvenCanonicalDuplicateCreate({
  required String commandType,
  required String? reason,
  required Object? serverRevision,
  required String commandEntityId,
  required String userId,
  required Map<String, dynamic>? canonicalRow,
}) {
  if (!isIdempotentDuplicateCreateConflict(
    commandType: commandType,
    reason: reason,
    serverRevision: serverRevision,
  )) {
    return false;
  }
  if (canonicalRow == null || canonicalRow['deleted_at'] != null) {
    return false;
  }
  return canonicalRow['id'] == commandEntityId &&
      canonicalRow['user_id'] == userId;
}

@visibleForTesting
bool shouldRecreateMissingActivitySegment({
  required String commandType,
  required bool hasAcceptedCreate,
  required bool hasLocalSegment,
}) {
  return commandType == 'update' && !hasAcceptedCreate && hasLocalSegment;
}

/// Gives pre-v0.0.27 Activity observations a permanent server-safe identity.
///
/// Early Android capture code used readable event keys such as
/// `android-history-com.example-...` as the local primary key. Supabase UUID
/// columns cannot accept those values. The same authenticated owner and local
/// event key always produce the same UUID, so recovery is idempotent across
/// retries without using a display name, translated label, or array position.
@visibleForTesting
String canonicalActivitySegmentSyncId({
  required String userId,
  required String localSegmentId,
}) {
  final normalized = localSegmentId.trim().toLowerCase();
  if (RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-'
    r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(normalized)) {
    return normalized;
  }
  return const Uuid().v5(
    Namespace.url.value,
    'https://taskmasterpro.app/account/$userId/'
    'legacy-activity-segment/${Uri.encodeComponent(localSegmentId)}',
  );
}

@visibleForTesting
bool shouldDeferCanonicalRuntimeApply(Iterable<String> pendingEntityTypes) {
  return pendingEntityTypes.any(
    const {'execution_runtime', 'execution_runtime_switch'}.contains,
  );
}

/// The canonical runtime is revisioned just like every other synchronized
/// entity.  A Realtime message is delivery-not-ordered, so it must never be
/// treated as the authority merely because it arrived last.
///
/// Equal revisions are only harmless duplicates when they carry the same
/// command identity.  A different command at the same revision is an
/// invariant violation; retaining the local snapshot is safer than rolling a
/// visible timer backwards while the regular recovery path obtains a newer
/// canonical revision.
enum CanonicalRuntimeApplyDecision { apply, duplicate, staleOrInconsistent }

@visibleForTesting
CanonicalRuntimeApplyDecision canonicalRuntimeApplyDecision({
  required int? localRevision,
  required String? localCommandId,
  required int incomingRevision,
  required String? incomingCommandId,
}) {
  if (localRevision == null || incomingRevision > localRevision) {
    return CanonicalRuntimeApplyDecision.apply;
  }
  if (incomingRevision < localRevision) {
    return CanonicalRuntimeApplyDecision.staleOrInconsistent;
  }
  if (incomingCommandId != null && incomingCommandId == localCommandId) {
    return CanonicalRuntimeApplyDecision.duplicate;
  }
  return CanonicalRuntimeApplyDecision.staleOrInconsistent;
}

/// A revision-guarded runtime command can be accepted as a durable duplicate
/// while its requested transition is superseded.  That is not a user-facing
/// conflict: the response already includes the state which won the race.
///
/// Keep this narrow to execution commands.  Ordinary entities can carry a
/// similarly named field for different merge semantics and must keep their
/// normal conflict handling.
@visibleForTesting
bool isCanonicalOnlyRuntimeResponse({
  required String entityType,
  required Map<String, dynamic> result,
}) {
  if (!const {
    'execution_runtime',
    'execution_runtime_switch',
  }.contains(entityType)) {
    return false;
  }
  return result['status'] == 'accepted' &&
      (result['canonical_only'] == true || result['superseded'] == true) &&
      result['canonical_runtime'] is Map;
}

@visibleForTesting
SyncHealth deriveSyncHealth({
  required bool online,
  required bool operationInFlight,
  required int pendingChanges,
  required int failedChanges,
  required int conflicts,
  required bool recoveryConnectionAvailable,
}) {
  if (!online) return SyncHealth.offline;
  if (operationInFlight) return SyncHealth.syncing;
  if (failedChanges > 0 || conflicts > 0) {
    return SyncHealth.attention;
  }
  if (pendingChanges > 0) return SyncHealth.syncing;
  if (!recoveryConnectionAvailable) return SyncHealth.attention;
  return SyncHealth.idle;
}

@visibleForTesting
String remoteEntityTypeForCommand(String localEntityType) =>
    localEntityType == 'task_health_summaries'
    ? 'health_summaries'
    : localEntityType;

@visibleForTesting
String localEntityTypeForRemoteRow(
  String remoteEntityType,
  Map<String, dynamic> row,
) {
  return remoteEntityType == 'health_summaries' &&
          row['task_occurrence_id'] != null
      ? 'task_health_summaries'
      : remoteEntityType;
}

@visibleForTesting
String? localParentIdForRemoteRow(String entityType, Map<String, dynamic> row) {
  // A task resource can also carry roadmap/template ownership metadata.
  // Its local parent is nevertheless the concrete task occurrence so the
  // Resources workspace can retrieve it. Choosing roadmap_id first made
  // correctly synchronized website resources disappear from their tasks.
  if (entityType == 'task_resources') {
    return row['task_occurrence_id'] as String? ??
        row['task_template_id'] as String? ??
        row['roadmap_id'] as String?;
  }
  return row['roadmap_id'] as String? ??
      row['task_occurrence_id'] as String? ??
      row['task_template_id'] as String? ??
      row['workspace_id'] as String? ??
      row['session_id'] as String? ??
      row['resource_id'] as String? ??
      row['scope_id'] as String? ??
      row['reading_target_id'] as String?;
}

@visibleForTesting
bool isSemanticLifecyclePayload(
  String entityType,
  Map<String, dynamic> payload,
) {
  if (payload.isEmpty) return false;
  final allowedKeys = switch (entityType) {
    'task_occurrences' => const {
      'status',
      'progress',
      'actual_start',
      'actual_finish',
      'active_duration_ms',
      // Accepted only for commands queued by older v0.0.26 builds.
      'actual_duration_ms',
    },
    'execution_sessions' => const {
      'state',
      'active_segment_started_at',
      'finished_at',
      'accumulated_active_ms',
      'current_pomodoro_segment',
    },
    _ => const <String>{},
  };
  return allowedKeys.isNotEmpty &&
      payload.keys.every(allowedKeys.contains) &&
      payload.keys.any(allowedKeys.contains);
}

@visibleForTesting
bool isCurrentSyncOperation({
  required int capturedGeneration,
  required int currentGeneration,
  required String expectedUserId,
  required String? currentUserId,
  required String? startedForUserId,
}) {
  return capturedGeneration == currentGeneration &&
      currentUserId == expectedUserId &&
      startedForUserId == expectedUserId;
}

@visibleForTesting
Future<void> waitForInFlightSyncOperations(
  Iterable<Future<void>?> operations,
) async {
  await Future.wait([
    for (final operation in operations)
      if (operation != null)
        operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
  ]);
}

class _StaleSyncOperation implements Exception {
  const _StaleSyncOperation();
}

class _IncompleteCanonicalSnapshot implements Exception {
  const _IncompleteCanonicalSnapshot(this.failedEntities);

  final Set<String> failedEntities;

  @override
  String toString() =>
      'Incomplete canonical snapshot: ${failedEntities.join(', ')}';
}

class SyncSnapshot {
  const SyncSnapshot({
    required this.health,
    required this.pendingChanges,
    required this.failedChanges,
    required this.conflicts,
    required this.lastSuccessfulSync,
    required this.connectionAvailable,
    required this.liveConnectionAvailable,
    required this.currentDeviceId,
    required this.deviceName,
    required this.accountEmail,
    required this.otherDevices,
    required this.diagnosticProblems,
  });

  final SyncHealth health;
  final int pendingChanges;
  final int failedChanges;
  final int conflicts;
  final DateTime? lastSuccessfulSync;
  final bool connectionAvailable;
  final bool liveConnectionAvailable;
  final String? currentDeviceId;
  final String deviceName;
  final String? accountEmail;
  final List<Map<String, dynamic>> otherDevices;

  /// Technical-only summaries for Help and diagnostics. Never surface these
  /// raw server details in normal sync messaging.
  final List<String> diagnosticProblems;

  bool get isTruthfullySynced =>
      health == SyncHealth.idle &&
      pendingChanges == 0 &&
      failedChanges == 0 &&
      conflicts == 0 &&
      connectionAvailable &&
      liveConnectionAvailable;
}

class SyncTrafficDiagnostic {
  const SyncTrafficDiagnostic({
    required this.source,
    required this.requestCount,
    required this.downloadedBytes,
    required this.uploadedBytes,
    required this.realtimeMessageCount,
    required this.repeatedQueryCount,
    required this.largestPayloadBytes,
    required this.lastSynchronization,
  });

  final String source;
  final int requestCount;
  final int downloadedBytes;
  final int uploadedBytes;
  final int realtimeMessageCount;
  final int repeatedQueryCount;
  final int largestPayloadBytes;
  final DateTime? lastSynchronization;
}

class SyncConnectionDiagnostic {
  const SyncConnectionDiagnostic({
    required this.activeRealtimeConnections,
    required this.activeAccountChannels,
    required this.registeredEventHandlers,
    required this.duplicateHandlersDetected,
  });

  final int activeRealtimeConnections;
  final int activeAccountChannels;
  final int registeredEventHandlers;
  final int duplicateHandlersDetected;
}

class _MutableSyncTrafficDiagnostic {
  int requestCount = 0;
  int downloadedBytes = 0;
  int uploadedBytes = 0;
  int realtimeMessageCount = 0;
  int repeatedQueryCount = 0;
  int largestPayloadBytes = 0;
  DateTime? lastSynchronization;
  String? lastFingerprint;

  SyncTrafficDiagnostic freeze(String source) => SyncTrafficDiagnostic(
    source: source,
    requestCount: requestCount,
    downloadedBytes: downloadedBytes,
    uploadedBytes: uploadedBytes,
    realtimeMessageCount: realtimeMessageCount,
    repeatedQueryCount: repeatedQueryCount,
    largestPayloadBytes: largestPayloadBytes,
    lastSynchronization: lastSynchronization,
  );
}

class SyncService {
  SyncService({required this.database, required this.client}) {
    _liveServices.add(this);
  }

  final AppDatabase database;
  final SupabaseClient client;
  static const _uuid = Uuid();
  static final Set<SyncService> _liveServices = <SyncService>{};

  /// A backend switch happens before Supabase is initialized in production,
  /// but this barrier also covers an in-process test/hot-restart transition.
  /// It shuts down realtime, periodic recovery and outbox workers before a
  /// new project namespace can become active.
  static Future<void> stopAllForBackendCutover() async {
    final services = List<SyncService>.of(_liveServices);
    await Future.wait(services.map((service) => service.stop()));
  }

  final _health = StreamController<SyncHealth>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _drainTimer;
  RealtimeChannel? _channel;
  SyncHealth _currentHealth = SyncHealth.syncing;
  bool _liveConnectionAvailable = false;
  bool _fallbackCheckAvailable = false;
  Future<void>? _pullFuture;
  Future<void>? _snapshotFuture;
  final ReplayableSyncOperation _drainOperation = ReplayableSyncOperation();
  final ReplayableSyncOperation _synchronizeOperation =
      ReplayableSyncOperation();
  int _accountGeneration = 0;
  bool _snapshotRetryRequired = false;
  String? _startedForUserId;
  DateTime? _lastDeviceAuthorizationCheck;
  DateTime? _lastFallbackPullAt;
  Timer? _realtimePullTimer;
  final Map<String, _MutableSyncTrafficDiagnostic> _traffic = {};
  String? _subscribedForUserId;
  int _registeredRealtimeHandlers = 0;

  Stream<SyncHealth> get health => _health.stream;
  SyncHealth get currentHealth => _currentHealth;

  List<SyncTrafficDiagnostic> getTrafficDiagnostics() {
    final rows =
        [for (final entry in _traffic.entries) entry.value.freeze(entry.key)]
          ..sort((left, right) {
            final count = right.requestCount.compareTo(left.requestCount);
            return count != 0 ? count : left.source.compareTo(right.source);
          });
    return List.unmodifiable(rows);
  }

  SyncConnectionDiagnostic getConnectionDiagnostics() =>
      SyncConnectionDiagnostic(
        activeRealtimeConnections: _liveConnectionAvailable ? 1 : 0,
        activeAccountChannels: _channel == null ? 0 : 1,
        registeredEventHandlers: _registeredRealtimeHandlers,
        // Duplicate creation is prevented before registering a handler, so a
        // duplicate can never become live state.
        duplicateHandlersDetected: 0,
      );

  void _recordTraffic(
    String source, {
    Object? uploaded,
    Object? downloaded,
    int requests = 1,
    int realtimeMessages = 0,
    String? fingerprint,
  }) {
    final row = _traffic.putIfAbsent(source, _MutableSyncTrafficDiagnostic.new);
    final uploadedBytes = _encodedSize(uploaded);
    final downloadedBytes = _encodedSize(downloaded);
    row.requestCount += requests;
    row.uploadedBytes += uploadedBytes;
    row.downloadedBytes += downloadedBytes;
    row.realtimeMessageCount += realtimeMessages;
    row.largestPayloadBytes = [
      row.largestPayloadBytes,
      uploadedBytes,
      downloadedBytes,
    ].reduce((left, right) => left > right ? left : right);
    if (fingerprint != null && row.lastFingerprint == fingerprint) {
      row.repeatedQueryCount += 1;
    }
    row.lastFingerprint = fingerprint;
    row.lastSynchronization = DateTime.now().toUtc();
  }

  int _encodedSize(Object? value) {
    if (value == null) return 0;
    try {
      return utf8.encode(jsonEncode(value)).length;
    } catch (_) {
      return utf8.encode(value.toString()).length;
    }
  }

  /// Stops every account-bound worker before the local database namespace is
  /// changed.  This prevents an old realtime subscription, periodic pull, or
  /// outbox drain from writing into the next account's workspace.
  Future<void> stop() async {
    // Invalidate first. Any remote response that arrives while workers are
    // being cancelled is prevented from writing to the local account cache.
    _accountGeneration += 1;
    _drainOperation.cancelReplay();
    _synchronizeOperation.cancelReplay();
    final operations = <Future<void>?>[
      _synchronizeOperation.inFlight,
      _pullFuture,
      _drainOperation.inFlight,
      _snapshotFuture,
    ];
    _drainTimer?.cancel();
    _drainTimer = null;
    _realtimePullTimer?.cancel();
    _realtimePullTimer = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _channel?.unsubscribe();
    _channel = null;
    _subscribedForUserId = null;
    _registeredRealtimeHandlers = 0;
    await waitForInFlightSyncOperations(operations);
    _startedForUserId = null;
    _snapshotRetryRequired = false;
    _liveConnectionAvailable = false;
    _fallbackCheckAvailable = false;
    _lastDeviceAuthorizationCheck = null;
    _lastFallbackPullAt = null;
    _traffic.clear();
    _setHealth(SyncHealth.offline);
  }

  void _setHealth(SyncHealth value) {
    _currentHealth = value;
    _health.add(value);
  }

  Future<void> start() async {
    var user = client.auth.currentUser;
    if (user == null) return;
    // Auth restoration and an Android network hand-off can call start more
    // than once.  Reuse the durable workers for the same account, but make
    // every such call an immediate recovery attempt rather than a no-op.
    if (_startedForUserId == user.id) {
      await _synchronizeNow();
      return;
    }
    if (_startedForUserId != null) {
      await stop();
      user = client.auth.currentUser;
      if (user == null) return;
    }
    _accountGeneration += 1;
    final generation = _accountGeneration;
    _startedForUserId = user.id;
    _snapshotRetryRequired = false;

    // A device-registration or identifier repair failure is not allowed to
    // suppress the reconnect listener and fallback pull for the whole app.
    await _runBestEffort(_repairAccountScopedDeviceIdentity);
    if (!_isCurrentOperation(generation, user.id)) return;
    await _runBestEffort(_registerDevice);
    if (!_isCurrentOperation(generation, user.id)) return;
    if (!await _ensureCurrentDeviceAuthorized(
      force: true,
      generation: generation,
      expectedUserId: user.id,
    )) {
      return;
    }
    if (!_isCurrentOperation(generation, user.id)) return;
    _connectivitySubscription ??= Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (results.every((result) => result == ConnectivityResult.none)) {
        _setHealth(SyncHealth.offline);
        return;
      }
      unawaited(_synchronizeNow());
    });
    _drainTimer ??= Timer.periodic(
      // Realtime remains the within-seconds path. This timer is only the
      // incremental recovery net; running the full repair/pull pipeline every
      // three seconds kept large local accounts busy even with an empty
      // outbox and made execution controls feel unresponsive.
      const Duration(seconds: 30),
      (_) => unawaited(_synchronizeNow()),
    );
    await _runBestEffort(_subscribeToAccount);
    if (!_isCurrentOperation(generation, user.id)) return;
    await _runBestEffort(_reconcileCanonicalState);
    if (!_isCurrentOperation(generation, user.id)) return;
    if (!_snapshotRetryRequired) {
      await _runBestEffort(pullChanges);
    }
    // Fetch the one canonical active-session row directly as well as through
    // the change cursor.  This is a recovery path for old clients whose
    // cursor had already advanced past the bootstrap runtime row.
    await _runBestEffort(_restoreCanonicalRuntime);
    await _runBestEffort(_supersedeCanonicalConflicts);
    await _runBestEffort(_recalculateRoadmaps);
    // A pull or local cache repair may fail independently. Never let that
    // prevent the durable outbox from delivering otherwise valid user work.
    await drainOutbox();
  }

  Future<void> _runBestEffort(Future<void> Function() action) async {
    try {
      await action();
    } on _StaleSyncOperation {
      // Account invalidation is expected during sign-out or namespace switch.
    } catch (error) {
      final errorCode = error is PostgrestException ? error.code : null;
      if (isPermanentSyncInfrastructureFailure(
        errorCode: errorCode,
        errorMessage: error.toString(),
      )) {
        _setHealth(SyncHealth.attention);
        return;
      }
      final connectivity = await Connectivity().checkConnectivity();
      _setHealth(
        connectivity.every((result) => result == ConnectivityResult.none)
            ? SyncHealth.offline
            : SyncHealth.syncing,
      );
    }
  }

  bool _isCurrentOperation(int generation, String expectedUserId) {
    return isCurrentSyncOperation(
      capturedGeneration: generation,
      currentGeneration: _accountGeneration,
      expectedUserId: expectedUserId,
      currentUserId: client.auth.currentUser?.id,
      startedForUserId: _startedForUserId,
    );
  }

  void _ensureCurrentOperation(int generation, String expectedUserId) {
    if (!_isCurrentOperation(generation, expectedUserId)) {
      throw const _StaleSyncOperation();
    }
  }

  /// Reconciles a stale local cache before the normal incremental pull.
  ///
  /// Realtime is only an optimization. A device that missed an event, was
  /// upgraded from an older schema, or retained a stale account cache must
  /// converge without restarting or downloading rows one change at a time.
  Future<void> _reconcileCanonicalState() {
    final existing = _snapshotFuture;
    if (existing != null) return existing;
    final userId = _startedForUserId;
    if (userId == null) return Future<void>.value();
    final generation = _accountGeneration;
    late final Future<void> operation;
    operation = _reconcileCanonicalStateInternal(generation, userId)
        .whenComplete(() {
          if (identical(_snapshotFuture, operation)) {
            _snapshotFuture = null;
          }
        });
    _snapshotFuture = operation;
    return operation;
  }

  Future<void> _reconcileCanonicalStateInternal(
    int generation,
    String userId,
  ) async {
    _ensureCurrentOperation(generation, userId);
    final user = client.auth.currentUser;
    if (user == null || user.id != userId) {
      throw const _StaleSyncOperation();
    }
    final stateId = authoritativeSnapshotStateId(user.id);
    final state = await (database.select(
      database.localSyncStates,
    )..where((row) => row.id.equals(stateId))).getSingleOrNull();
    _ensureCurrentOperation(generation, userId);
    final highWater = await _latestRemoteChangeSequence();
    _ensureCurrentOperation(generation, userId);
    if (highWater == null) {
      _snapshotRetryRequired = true;
      throw const _IncompleteCanonicalSnapshot({'sync_change_log'});
    }
    // A durable cursor means the incremental log is authoritative regardless
    // of how many changes accumulated while this device slept. The previous
    // gap-based condition downloaded every account table whenever Activity
    // produced more than five changes, which caused the reported egress spike.
    // Full snapshots are now reserved for first bootstrap or an explicitly
    // detected incomplete snapshot.
    if (!shouldRunAuthoritativeSnapshot(
      hasDurableCursor: hasUsableDurableSyncCursor(state?.lastChangeSequence),
      snapshotRetryRequired: _snapshotRetryRequired,
    )) {
      return;
    }

    final canonicalExecutionSessionIds = <String>{};
    final failedEntities = <String>{};

    for (final entityType in authoritativeSnapshotEntityTypes) {
      try {
        _ensureCurrentOperation(generation, userId);
        var offset = 0;
        while (true) {
          final rows = await client
              .from(entityType)
              .select()
              .order('id')
              .range(offset, offset + 249);
          _recordTraffic(
            'snapshot:$entityType',
            downloaded: rows,
            fingerprint: '$entityType:$offset',
          );
          _ensureCurrentOperation(generation, userId);
          for (final raw in rows) {
            final row = Map<String, dynamic>.from(raw);
            final entityId = row['id'] as String?;
            if (entityType == 'execution_sessions' && entityId != null) {
              canonicalExecutionSessionIds.add(entityId);
            }
            if (entityId == null ||
                !await _shouldApplyRemoteEntity(entityType, userId: userId) ||
                await _hasPendingCommand(
                  entityType,
                  entityId,
                  userId: userId,
                )) {
              continue;
            }
            _ensureCurrentOperation(generation, userId);
            await _applyEntity(entityType, row);
          }
          if (rows.length < 250) break;
          offset += rows.length;
        }
      } on _StaleSyncOperation {
        rethrow;
      } catch (_) {
        failedEntities.add(entityType);
      }
    }
    if (!authoritativeSnapshotCanAdvanceCursor(failedEntities)) {
      _snapshotRetryRequired = true;
      throw _IncompleteCanonicalSnapshot(failedEntities);
    }
    _ensureCurrentOperation(generation, userId);
    await _clearOrphanedRuntime(
      userId: user.id,
      canonicalSessionIds: canonicalExecutionSessionIds,
    );
    _ensureCurrentOperation(generation, userId);
    // The snapshot represents canonical rows visible at `highWater`. Moving
    // the cursor past older changes prevents an Activity-heavy history from
    // delaying task, roadmap, and profile recovery. `pullChanges` follows
    // immediately and receives any rows written after this point.
    await database
        .into(database.localSyncStates)
        .insertOnConflictUpdate(
          LocalSyncStatesCompanion.insert(
            id: stateId,
            userId: user.id,
            lastChangeSequence: Value(highWater),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
    _ensureCurrentOperation(generation, userId);
    _snapshotRetryRequired = false;
  }

  Future<int?> _latestRemoteChangeSequence() async {
    try {
      final rows = await client
          .from('sync_change_log')
          .select('change_sequence')
          .order('change_sequence', ascending: false)
          .limit(1);
      _recordTraffic(
        'table:sync_change_log_high_water',
        downloaded: rows,
        fingerprint: 'latest',
      );
      if (rows.isEmpty) return 0;
      return ((rows.first as Map)['change_sequence'] as num?)?.toInt();
    } catch (_) {
      return null;
    }
  }

  /// An old runtime row can survive sign-out, an upgrade, or a partially
  /// completed earlier sync. After a successful authoritative session
  /// snapshot it must not keep presenting a non-existent task as active.
  /// A genuine offline start retains a pending session command and is kept.
  Future<void> _clearOrphanedRuntime({
    required String userId,
    required Set<String> canonicalSessionIds,
  }) async {
    final runtimeId = localRuntimeStateId(userId);
    final runtime =
        await (database.select(database.localRuntimeStates)..where(
              (row) => row.id.equals(runtimeId) & row.userId.equals(userId),
            ))
            .getSingleOrNull();
    final sessionId = runtime?.sessionId;
    if (runtime == null) return;
    if (sessionId != null &&
        (canonicalSessionIds.contains(sessionId) ||
            await _hasPendingCommand(
              'execution_sessions',
              sessionId,
              userId: userId,
            ))) {
      return;
    }
    await (database.update(
          database.localRuntimeStates,
        )..where((row) => row.id.equals(runtimeId) & row.userId.equals(userId)))
        .write(
          LocalRuntimeStatesCompanion(
            activeTaskId: const Value(null),
            sessionId: const Value(null),
            state: const Value('idle'),
            segmentStartedAt: const Value(null),
            revision: Value(runtime.revision + 1),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  Future<void> _repairAccountScopedDeviceIdentity() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final accountDeviceId = await DeviceIdentity.accountId(user.id);
    await (database.update(database.localOutboxCommands)..where(
          (row) =>
              row.userId.equals(user.id) &
              row.status.equals('pending') &
              row.deviceId.equals(accountDeviceId).not(),
        ))
        .write(LocalOutboxCommandsCompanion(deviceId: Value(accountDeviceId)));
  }

  Future<void> _registerDevice() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final deviceId = await DeviceIdentity.accountId(user.id);
    final packageInfo = await PackageInfo.fromPlatform();
    try {
      final response = await client.rpc<Object?>(
        'register_account_device',
        params: {
          'p_device_id': deviceId,
          'p_device_name': DeviceIdentity.displayName,
          'p_platform': DeviceIdentity.platform,
          'p_app_version': packageInfo.version,
          'p_device_public_key': null,
        },
      );
      final result = response is Map
          ? Map<String, dynamic>.from(response)
          : const <String, dynamic>{};
      if (result['status'] != 'accepted') {
        throw StateError('device_registration_rejected');
      }
    } on PostgrestException catch (error) {
      final reason = _deviceRegistrationSecurityReason(error);
      if (reason == null) rethrow;

      _setHealth(SyncHealth.attention);
      _lastDeviceAuthorizationCheck = null;
      if (reason == 'device_revoked') {
        await DeviceIdentity.rotateAfterRemoteRevocation();
      }
      // A missing/inactive Auth session or a revoked installation must not
      // proceed to Realtime subscription or command delivery with its
      // already-issued access token.
      await client.auth.signOut(scope: SignOutScope.local);
    }
  }

  String? _deviceRegistrationSecurityReason(PostgrestException error) {
    final message = [
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();
    const handledReasons = <String>[
      'device_revoked',
      'auth_session_missing',
      'auth_session_inactive',
      'device_session_already_bound',
      'auth_session_already_registered',
    ];
    for (final reason in handledReasons) {
      if (message.contains(reason)) return reason;
    }
    return null;
  }

  /// A remote revocation is authoritative. The installation can keep local
  /// unsynchronized work while offline, but stops using this account as soon
  /// as it confirms that the owner revoked the device.
  Future<bool> _ensureCurrentDeviceAuthorized({
    bool force = false,
    int? generation,
    String? expectedUserId,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return false;
    void ensureCurrent() {
      if (generation != null && expectedUserId != null) {
        _ensureCurrentOperation(generation, expectedUserId);
      }
    }

    ensureCurrent();
    final now = DateTime.now().toUtc();
    if (!force &&
        _lastDeviceAuthorizationCheck != null &&
        now.difference(_lastDeviceAuthorizationCheck!) <
            const Duration(minutes: 2)) {
      return true;
    }
    _lastDeviceAuthorizationCheck = now;
    final deviceId = await DeviceIdentity.accountId(user.id);
    ensureCurrent();
    final record = await client
        .from('account_devices')
        .select('revoked_at')
        .eq('id', deviceId)
        .eq('user_id', user.id)
        .maybeSingle();
    ensureCurrent();
    if (record != null && record['revoked_at'] == null) return true;

    _setHealth(SyncHealth.attention);
    await _channel?.unsubscribe();
    _channel = null;
    _subscribedForUserId = null;
    _registeredRealtimeHandlers = 0;
    _liveConnectionAvailable = false;
    ensureCurrent();
    // Keep the old account-device row revoked. A future explicit sign-in must
    // register a new device identity instead of accidentally reviving the
    // session that the account owner removed.
    await DeviceIdentity.rotateAfterRemoteRevocation();
    ensureCurrent();
    await client.auth.signOut(scope: SignOutScope.local);
    return false;
  }

  /// Uses a permanent command ID to revoke another signed-in device. The
  /// current installation must use the normal local sign-out flow instead.
  Future<void> revokeOtherDevice(String targetDeviceId) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('authentication_required');
    final currentDeviceId = await DeviceIdentity.accountId(user.id);
    if (targetDeviceId == currentDeviceId) {
      throw ArgumentError('use_local_sign_out');
    }
    await client.rpc<Object?>(
      'revoke_account_device',
      params: {
        'p_command_id': _uuid.v4(),
        'p_requesting_device_id': currentDeviceId,
        'p_device_sequence': await DeviceIdentity.nextSequence(user.id),
        'p_target_device_id': targetDeviceId,
      },
    );
    await pullChanges();
  }

  Future<void> _subscribeToAccount() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    if (_channel != null && _subscribedForUserId == user.id) {
      return;
    }
    await _channel?.unsubscribe();
    _registeredRealtimeHandlers = 0;
    _channel = client.channel(
      'taskmaster:user:${user.id}:runtime',
      opts: const RealtimeChannelConfig(private: true),
    );
    _subscribedForUserId = user.id;
    _registeredRealtimeHandlers = 1;
    _channel!
        .onBroadcast(
          event: 'entity_changed',
          callback: (payload) {
            _recordTraffic(
              'realtime:entity_changed',
              downloaded: payload,
              requests: 0,
              realtimeMessages: 1,
            );
            // A command transaction can emit several entity broadcasts.
            // Coalesce that burst into one incremental cursor pull instead
            // of downloading the same entity set once per notification.
            _realtimePullTimer?.cancel();
            _realtimePullTimer = Timer(const Duration(milliseconds: 750), () {
              _realtimePullTimer = null;
              unawaited(pullChanges());
            });
          },
        )
        .subscribe((status, _) {
          _liveConnectionAvailable =
              status == RealtimeSubscribeStatus.subscribed;
          if (!_liveConnectionAvailable &&
              status == RealtimeSubscribeStatus.channelError) {
            _setHealth(SyncHealth.attention);
          }
        });
  }

  /// Runs both directions even when there is no local work.  The previous
  /// implementation returned early for an empty outbox, which left a passive
  /// device stale until restart despite a remote change being available.
  Future<void> _synchronizeNow() {
    final userId = _startedForUserId;
    if (userId == null) return Future<void>.value();
    final generation = _accountGeneration;
    return _synchronizeOperation.run(
      () => _synchronizeNowInternal(generation, userId),
    );
  }

  Future<void> _synchronizeNowInternal(int generation, String userId) async {
    try {
      _ensureCurrentOperation(generation, userId);
      if (!await _ensureCurrentDeviceAuthorized(
        generation: generation,
        expectedUserId: userId,
      )) {
        return;
      }
      _ensureCurrentOperation(generation, userId);
      if (_snapshotRetryRequired) {
        await _runBestEffort(_reconcileCanonicalState);
        _ensureCurrentOperation(generation, userId);
      }
      final now = DateTime.now().toUtc();
      final fallbackPullDue =
          !_liveConnectionAvailable ||
          _lastFallbackPullAt == null ||
          now.difference(_lastFallbackPullAt!) >= const Duration(minutes: 2);
      // Realtime is the normal within-seconds path. The incremental cursor is
      // a bounded recovery check, not a fixed high-frequency account poll.
      if (!_snapshotRetryRequired && fallbackPullDue) {
        unawaited(pullChanges());
      }
      await drainOutbox();
      _ensureCurrentOperation(generation, userId);
      if (fallbackPullDue) {
        await _runBestEffort(_restoreCanonicalRuntime);
      }
    } on _StaleSyncOperation {
      // The next account owns the database namespace now.
    }
  }

  /// A user-requested retry is explicit recovery, so it must not remain held
  /// behind an exponential backoff that was calculated for an earlier
  /// temporary server or network failure. The command IDs stay unchanged;
  /// this only makes the durable retry eligible now.
  Future<void> synchronizeNow() async {
    final user = client.auth.currentUser;
    if (user != null) {
      await (database.update(database.localOutboxCommands)..where(
            (row) => row.userId.equals(user.id) & row.status.equals('pending'),
          ))
          .write(
            LocalOutboxCommandsCompanion(
              nextAttemptAt: Value(DateTime.now().toUtc()),
            ),
          );
    }
    await _synchronizeNow();
  }

  Future<List<SyncConflictNotice>> getConflictNotices() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];
    final commands =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(user.id) &
                    row.status.equals('conflict') &
                    row.entityType.equals('sync_conflict_decisions').not(),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    final notices = <SyncConflictNotice>[];
    for (final command in commands) {
      final payload = _payloadMap(command.payloadJson);
      final error = _payloadMap(command.lastError ?? '');
      final reason = error['reason'] as String?;
      final serverPayloadValue =
          error['server_payload'] ?? error['canonical_payload'];
      final serverPayload = serverPayloadValue is Map
          ? Map<String, dynamic>.from(serverPayloadValue)
          : const <String, dynamic>{};
      final subject = await _friendlyConflictSubject(command, payload);
      notices.add(
        SyncConflictNotice(
          commandId: command.commandId,
          conflictId: null,
          category: syncConflictCategoryForReason(
            reason,
            errorText: command.lastError ?? '',
          ),
          subject: subject,
          localSummary:
              _friendlyPayloadSummary(payload) ?? 'Local change on this device',
          serverSummary:
              _friendlyPayloadSummary(serverPayload) ??
              (error['server_title'] as String?),
          canKeepDeviceVersion:
              command.commandType != 'delete' &&
              _supportsAtomicDeviceConflictChoice(command.entityType),
          isResolved: false,
        ),
      );
    }
    return List.unmodifiable(notices);
  }

  Future<List<SyncConflictNotice>> getResolvedConflictNotices() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];
    try {
      final rows = await client
          .from('sync_conflicts')
          .select(
            'id,command_id,entity_type,entity_id,conflict_type,local_payload,'
            'server_payload,resolution_status,resolution,resolved_at',
          )
          .neq('resolution_status', 'unresolved')
          .isFilter('deleted_at', null)
          .order('resolved_at', ascending: false)
          .limit(50);
      final notices = <SyncConflictNotice>[];
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final commandId = row['command_id'] as String?;
        final conflictId = row['id'] as String?;
        if (commandId == null || conflictId == null) continue;
        final localPayload = row['local_payload'] is Map
            ? Map<String, dynamic>.from(row['local_payload'] as Map)
            : const <String, dynamic>{};
        final serverPayload = row['server_payload'] is Map
            ? Map<String, dynamic>.from(row['server_payload'] as Map)
            : const <String, dynamic>{};
        final resolution = row['resolution'] is Map
            ? Map<String, dynamic>.from(row['resolution'] as Map)
            : const <String, dynamic>{};
        final strategy = resolution['strategy'] as String?;
        notices.add(
          SyncConflictNotice(
            commandId: commandId,
            conflictId: conflictId,
            category: syncConflictCategoryForReason(switch (strategy) {
              'discarded_local_change' => 'discarded_by_user',
              'idempotent_duplicate_create' => 'duplicate',
              'already_applied' ||
              'legacy_transport_retired' => 'already_applied',
              _ => 'superseded',
            }),
            subject:
                (localPayload['title'] as String?)?.trim().isNotEmpty == true
                ? (localPayload['title'] as String).trim()
                : _friendlyEntitySubject(row['entity_type'] as String?),
            localSummary:
                _friendlyPayloadSummary(localPayload) ??
                _friendlyEntitySubject(row['entity_type'] as String?),
            serverSummary: _friendlyPayloadSummary(serverPayload),
            canKeepDeviceVersion: false,
            isResolved: true,
          ),
        );
      }
      return List.unmodifiable(notices);
    } catch (_) {
      return const [];
    }
  }

  bool _supportsAtomicDeviceConflictChoice(String entityType) => const {
    'profiles',
    'user_settings',
    'task_occurrences',
    'roadmap_task_links',
    'task_application_links',
    'task_domains',
    'task_categories',
    'tags',
    'task_templates',
    'recurrence_rules',
    'recurrence_exceptions',
    'task_dependencies',
    'task_reminders',
    'execution_sessions',
    'session_events',
    'checklist_items',
    'pomodoro_cycles',
    'interruptions',
    'task_completion_evidence',
    'work_demands',
    'learning_checkpoints',
    'reading_targets',
    'reading_positions',
    'habit_records',
    'event_attendance',
    'task_notes',
    'roadmaps',
    'roadmap_phases',
    'roadmap_milestones',
    'roadmap_checkpoints',
    'task_resources',
    'browser_workspaces',
    'browser_tabs',
    'coaching_feedback',
    'health_summaries',
  }.contains(entityType);

  String _friendlyEntitySubject(String? entityType) => switch (entityType) {
    'task_occurrences' => 'Task change',
    'roadmaps' || 'roadmap_phases' => 'Roadmap change',
    'profiles' => 'Profile change',
    'user_settings' => 'Settings change',
    'task_application_links' => 'Connected application change',
    _ => 'Unsynchronized change',
  };

  Future<void> resolveConflictsAutomatically() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    await _prepareNormalizedActivityCommands();
    await _supersedeCanonicalConflicts();
    await _supersedeResolvedConflicts(user.id);
    await _retireSafeLegacyTransportConflicts(user.id);
    await pullChanges();
    await _settleHealth();
  }

  Future<void> dismissResolvedConflict(SyncConflictNotice notice) async {
    if (!notice.isResolved || notice.conflictId == null) return;
    await _enqueueConflictDecision(
      strategy: 'dismiss_notice',
      conflictId: notice.conflictId,
      originalCommandId: notice.commandId,
    );
  }

  Future<void> clearResolvedConflicts() =>
      _enqueueConflictDecision(strategy: 'clear_resolved');

  Future<void> discardLocalChange(String commandId) =>
      _enqueueConflictDecisionForCommand(
        commandId,
        strategy: 'discarded_local_change',
      );

  Future<void> keepServerVersion(String commandId) =>
      _enqueueConflictDecisionForCommand(
        commandId,
        strategy: 'kept_server_version',
      );

  Future<void> keepDeviceVersion(String commandId) =>
      _enqueueConflictDecisionForCommand(
        commandId,
        strategy: 'kept_device_version',
      );

  Future<void> _enqueueConflictDecisionForCommand(
    String commandId, {
    required String strategy,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final command =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(user.id) &
                  row.commandId.equals(commandId) &
                  row.status.equals('conflict'),
            ))
            .getSingleOrNull();
    if (command == null) return;
    if (strategy == 'kept_device_version' &&
        (command.commandType == 'delete' ||
            !_supportsAtomicDeviceConflictChoice(command.entityType))) {
      return;
    }
    await _enqueueConflictDecision(strategy: strategy, original: command);
  }

  Future<void> _enqueueConflictDecision({
    required String strategy,
    LocalOutboxCommand? original,
    String? conflictId,
    String? originalCommandId,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final decisionId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final payload = <String, dynamic>{
      'strategy': strategy,
      'conflict_id': conflictId,
      'original_command_id': original?.commandId ?? originalCommandId,
      'original_entity_type': original?.entityType,
      'original_entity_id': original?.entityId,
      'original_command_type': original?.commandType,
      'original_payload': original == null
          ? null
          : _payloadMap(original.payloadJson),
    };
    await database.transaction(() async {
      if (original != null) {
        await (database.update(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(user.id) &
                  row.commandId.equals(original.commandId) &
                  row.status.equals('conflict'),
            ))
            .write(
              LocalOutboxCommandsCompanion(
                status: const Value('resolution_pending'),
                nextAttemptAt: const Value(null),
                lastError: Value(
                  jsonEncode({
                    'reason': 'resolution_pending',
                    'strategy': strategy,
                    'decision_id': decisionId,
                    'previous_conflict': _payloadMap(original.lastError ?? ''),
                    'decided_at': now.toIso8601String(),
                  }),
                ),
              ),
            );
      }
      await database
          .into(database.localOutboxCommands)
          .insert(
            LocalOutboxCommandsCompanion.insert(
              commandId: decisionId,
              userId: user.id,
              deviceId:
                  original?.deviceId ?? await DeviceIdentity.accountId(user.id),
              deviceSequence: await DeviceIdentity.nextSequence(user.id),
              entityType: 'sync_conflict_decisions',
              entityId: decisionId,
              commandType: 'resolve',
              baseRevision: 0,
              payloadJson: jsonEncode(payload),
              clientTimestamp: now,
              createdAt: now,
              nextAttemptAt: Value(now),
            ),
          );
    });
    await drainOutbox();
    await _settleHealth();
  }

  Future<void> _retireSafeLegacyTransportConflicts(String userId) async {
    final commands =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) & row.status.equals('conflict'),
            ))
            .get();
    for (final command in commands) {
      final errorText = command.lastError ?? '';
      final error = _payloadMap(errorText);
      final reason = error['reason'] as String?;
      final legacyTransportId =
          const {
            'activity_segments',
            'activity_review_queue',
            'activity_contributions',
            'activity_attributions',
          }.contains(command.entityType) &&
          (errorText.toLowerCase().contains(
                'invalid input syntax for type uuid',
              ) ||
              reason == 'unrecoverable_legacy_transport_id');
      final alreadySettled = const {
        'already_applied',
        'same_intended_result',
        'duplicate_review_resolved',
        'entity_deleted',
        'superseded',
      }.contains(reason);
      if (!legacyTransportId && !alreadySettled) continue;
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        LocalOutboxCommandsCompanion(
          status: const Value('superseded'),
          nextAttemptAt: const Value(null),
          lastError: Value(
            jsonEncode({
              'reason': legacyTransportId
                  ? 'unrecoverable_legacy_transport_id'
                  : 'already_applied',
              'auto_resolved_at': DateTime.now().toUtc().toIso8601String(),
            }),
          ),
        ),
      );
      await _markRemoteConflictResolved(
        command,
        strategy: legacyTransportId
            ? 'legacy_transport_retired'
            : 'already_applied',
      );
    }
  }

  Future<String> _friendlyConflictSubject(
    LocalOutboxCommand command,
    Map<String, dynamic> payload,
  ) async {
    if (command.entityType == 'task_occurrences') {
      final task =
          await (database.select(database.localTasks)..where(
                (row) =>
                    row.userId.equals(command.userId) &
                    row.id.equals(command.entityId),
              ))
              .getSingleOrNull();
      return task?.title.trim().isNotEmpty == true
          ? task!.title
          : (payload['title'] as String?)?.trim().isNotEmpty == true
          ? (payload['title'] as String).trim()
          : 'Task change';
    }
    if (command.entityType == 'roadmaps') {
      final roadmap =
          await (database.select(database.localRoadmaps)..where(
                (row) =>
                    row.userId.equals(command.userId) &
                    row.id.equals(command.entityId),
              ))
              .getSingleOrNull();
      if (roadmap?.title.trim().isNotEmpty == true) return roadmap!.title;
    }
    final record =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(command.userId) &
                  row.id.equals(command.entityId),
            ))
            .getSingleOrNull();
    if (record?.title.trim().isNotEmpty == true) return record!.title;
    return _friendlyPayloadSummary(payload) ?? 'Unsynchronized change';
  }

  String? _friendlyPayloadSummary(Map<String, dynamic> payload) {
    for (final key in const [
      'title',
      'display_name',
      'name',
      'custom_display_name',
      'status',
      'classification',
    ]) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  @visibleForTesting
  Future<void> repairResolvedConflictsForTesting(String userId) =>
      _supersedeResolvedConflicts(userId);

  Future<void> drainOutbox() {
    final userId = _startedForUserId;
    if (userId == null) return Future<void>.value();
    final generation = _accountGeneration;
    return _drainOperation.run(() => _drainOutboxTracked(generation, userId));
  }

  Future<void> _drainOutboxTracked(int generation, String userId) async {
    try {
      await _drainOutboxInternal(generation, userId);
    } on _StaleSyncOperation {
      // Account switches invalidate delivery without mutating retry state.
    }
  }

  Future<void> _drainOutboxInternal(int generation, String userId) async {
    _ensureCurrentOperation(generation, userId);
    final user = client.auth.currentUser;
    if (user == null) {
      _setHealth(SyncHealth.attention);
      return;
    }
    if (user.id != userId) throw const _StaleSyncOperation();

    await _runBestEffort(_prepareNormalizedActivityCommands);
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(() => _retryClassifierPrivilegeConflicts(user.id));
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(_supersedeCanonicalConflicts);
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(() => _restoreMissingParentCommands(user.id));
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(() => _compactLegacyOutbox(user.id));
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(() => _retireInvalidHealthSummaryCommands(user.id));
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(() => _supersedeResolvedConflicts(user.id));
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(() => _repairDependencyBlockedCommands(user.id));
    _ensureCurrentOperation(generation, userId);
    await _runBestEffort(
      () => _makeLegacyApplicationCatalogAliasesDue(user.id),
    );
    final connectivity = await Connectivity().checkConnectivity();
    _ensureCurrentOperation(generation, userId);
    if (connectivity.every((result) => result == ConnectivityResult.none)) {
      _setHealth(SyncHealth.offline);
      return;
    }

    final now = DateTime.now();
    final query = database.select(database.localOutboxCommands)
      ..where(
        (row) =>
            row.userId.equals(user.id) &
            row.status.equals('pending') &
            (row.nextAttemptAt.isNull() |
                row.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)])
      ..limit(250);
    final commands = await query.get();
    _ensureCurrentOperation(generation, userId);
    commands.sort((left, right) {
      final priority = _outboxPriority(left).compareTo(_outboxPriority(right));
      return priority != 0
          ? priority
          : left.deviceSequence.compareTo(right.deviceSequence);
    });
    if (commands.isEmpty) {
      // An idle device is synchronized by its private Realtime channel and
      // the bounded fallback in _synchronizeNowInternal.  Pulling here turns
      // the 30-second maintenance tick into an account-wide polling loop,
      // even when nothing has changed.
      return;
    }

    _setHealth(SyncHealth.syncing);
    var needsAttention = false;
    var deliveryInterrupted = false;

    var commandIndex = 0;
    while (commandIndex < commands.length) {
      _ensureCurrentOperation(generation, userId);
      // Commands may be rebased while an earlier mutation for the same
      // entity is accepted.  Reload the durable command before sending so a
      // coalesced Activity extension never uses the stale base revision that
      // was present when this batch was first read.
      final command =
          await (database.select(database.localOutboxCommands)..where(
                (row) => row.commandId.equals(commands[commandIndex].commandId),
              ))
              .getSingleOrNull();
      if (command == null || command.status != 'pending') {
        commandIndex += 1;
        continue;
      }
      if (command.entityType == 'activity_contributions') {
        var batchEnd = commandIndex + 1;
        while (batchEnd < commands.length &&
            commands[batchEnd].entityType == 'activity_contributions' &&
            batchEnd - commandIndex < 20) {
          batchEnd += 1;
        }
        if (batchEnd - commandIndex > 1) {
          try {
            final batchNeedsAttention = await _sendActivityContributionBatch(
              commands.sublist(commandIndex, batchEnd),
              generation: generation,
              userId: userId,
            );
            needsAttention = needsAttention || batchNeedsAttention;
            commandIndex = batchEnd;
            if (batchNeedsAttention) break;
            continue;
          } on _StaleSyncOperation {
            rethrow;
          } catch (_) {
            // A server that has not received the batch migration yet safely
            // falls back to the stable per-command path below.
          }
        }
      }
      try {
        final payload = _canonicalPayload(
          command,
          jsonDecode(command.payloadJson) as Map<String, dynamic>,
        );
        final response = command.entityType == 'sync_conflict_decisions'
            ? await client.rpc<Object?>(
                'apply_sync_conflict_decision_v0027',
                params: {
                  'p_decision_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_conflict_id': payload['conflict_id'],
                  'p_original_command_id': payload['original_command_id'],
                  'p_original_entity_id': payload['original_entity_id'],
                  'p_strategy': payload['strategy'],
                  'p_decision_payload': payload,
                },
              )
            : command.entityType == 'task_occurrences'
            ? await client.rpc<Object?>(
                'apply_task_occurrence_v0026_command',
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
            : command.entityType == 'execution_runtime'
            ? await client.rpc<Object?>(
                'apply_execution_transition_v0028_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_session_id': command.entityId,
                  'p_task_occurrence_id': payload['task_occurrence_id'],
                  'p_action': payload['action'],
                  'p_mode': payload['mode'],
                  // The runtime mutation is compare-and-set, not last writer
                  // wins.  A delayed device must receive the canonical state
                  // rather than silently rewrite a newer focus/break interval.
                  'p_expected_runtime_revision': command.baseRevision,
                },
              )
            : command.entityType == 'execution_runtime_switch'
            ? await client.rpc<Object?>(
                'apply_execution_switch_v0028_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_new_session_id': command.entityId,
                  'p_new_task_occurrence_id': payload['task_occurrence_id'],
                  'p_expected_active_session_id':
                      payload['expected_active_session_id'],
                  'p_expected_active_task_id':
                      payload['expected_active_task_id'],
                  'p_current_task_action': payload['current_task_action'],
                  'p_mode': payload['mode'],
                  'p_expected_runtime_revision': command.baseRevision,
                },
              )
            : command.entityType == 'activity_review_classifications'
            ? await client.rpc<Object?>(
                'classify_activity_review',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_review_item_id': command.entityId,
                  'p_expected_revision': command.baseRevision,
                  'p_classification': payload['classification'],
                  'p_target_task_id': payload['target_task_id'],
                  'p_rule_scope': payload['rule_scope'],
                  'p_details': payload,
                },
              )
            : command.entityType == 'user_settings'
            ? await client.rpc<Object?>(
                'apply_user_settings_merge_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_base_revision': command.baseRevision,
                  'p_payload': payload,
                },
              )
            : command.entityType == 'profiles'
            ? await client.rpc<Object?>(
                'apply_profile_merge_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_base_revision': command.baseRevision,
                  'p_payload': payload,
                },
              )
            : const {
                'user_vaults',
                'vault_items',
                'vault_device_keys',
              }.contains(command.entityType)
            ? await client.rpc<Object?>(
                'apply_vault_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_entity_type': remoteEntityTypeForCommand(
                    command.entityType,
                  ),
                  'p_entity_id': command.entityId,
                  'p_base_revision': command.baseRevision,
                  'p_operation': command.commandType,
                  'p_payload': payload,
                },
              )
            : command.entityType == 'website_rules' &&
                  command.commandType != 'delete' &&
                  payload['scope_type'] == 'task' &&
                  payload['scope_id'] != null
            ? await client.rpc<Object?>(
                'connect_website_to_task',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_rule_id': command.entityId,
                  'p_task_occurrence_id':
                      payload['scope_id'] ?? payload['target_id'],
                  'p_base_revision': command.baseRevision,
                  'p_domain': payload['domain'],
                  'p_url_pattern': payload['url_pattern'],
                  'p_match_scope': payload['data'] is Map
                      ? (payload['data'] as Map)['match_scope'] ?? 'host'
                      : 'host',
                  'p_data': payload['data'] is Map
                      ? Map<String, Object?>.from(payload['data'] as Map)
                      : const <String, Object?>{},
                },
              )
            : command.entityType == 'task_application_links'
            ? command.commandType == 'delete'
                  ? await client.rpc<Object?>(
                      'remove_application_from_task',
                      params: {
                        'p_command_id': command.commandId,
                        'p_device_id': command.deviceId,
                        'p_device_sequence': command.deviceSequence,
                        'p_link_id': command.entityId,
                        'p_base_revision': command.baseRevision,
                      },
                    )
                  : await client.rpc<Object?>(
                      'connect_application_to_task',
                      params: {
                        'p_command_id': command.commandId,
                        'p_device_id': command.deviceId,
                        'p_device_sequence': command.deviceSequence,
                        'p_application_id': payload['application_id'],
                        'p_link_id': command.entityId,
                        'p_task_occurrence_id': payload['task_occurrence_id'],
                        'p_platform': payload['platform'] ?? 'unknown',
                        'p_raw_identifier':
                            payload['raw_identifier'] ??
                            payload['raw_identifier_snapshot'],
                        'p_detected_display_name':
                            payload['detected_display_name'] ??
                            payload['display_name_snapshot'],
                        'p_relationship_type':
                            payload['relationship_type'] ?? 'supporting',
                      },
                    )
            : command.entityType == 'roadmap_task_links'
            ? await client.rpc<Object?>(
                'apply_roadmap_task_link_command',
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
            : await client.rpc<Object?>(
                'apply_entity_command',
                params: {
                  'p_command_id': command.commandId,
                  'p_device_id': command.deviceId,
                  'p_device_sequence': command.deviceSequence,
                  'p_entity_type': remoteEntityTypeForCommand(
                    command.entityType,
                  ),
                  'p_entity_id': command.entityId,
                  'p_base_revision': command.baseRevision,
                  'p_operation': command.commandType,
                  'p_payload': payload,
                },
              );
        _ensureCurrentOperation(generation, userId);
        _recordTraffic(
          'rpc:${command.entityType}',
          uploaded: payload,
          downloaded: response,
          fingerprint:
              '${command.entityType}:${command.commandType}:'
              '${command.entityId}:${command.baseRevision}',
        );
        final result = response is Map
            ? Map<String, dynamic>.from(response)
            : <String, dynamic>{};
        final remoteStatus = result['status'] as String?;
        final canonicalOnlyRuntime = isCanonicalOnlyRuntimeResponse(
          entityType: command.entityType,
          result: result,
        );
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          LocalOutboxCommandsCompanion(
            // A compare-and-set command can be durably accepted as an
            // idempotent no-op. Retire it silently, but do not call it an
            // ordinary acknowledgement: its optimistic local transition did
            // not become canonical.
            status: Value(
              remoteStatus == 'accepted'
                  ? (canonicalOnlyRuntime ? 'superseded' : 'accepted')
                  : 'conflict',
            ),
            lastError: remoteStatus == 'accepted'
                ? const Value.absent()
                : Value(jsonEncode(result)),
          ),
        );
        if (canonicalOnlyRuntime) {
          final canonicalRuntime = Map<String, dynamic>.from(
            result['canonical_runtime'] as Map,
          );
          // The optimistic command has just been retired, so the returned
          // canonical runtime is the only permitted backwards correction.
          // Applying the RPC response directly avoids an extra sync pull and
          // avoids waiting for an out-of-order Realtime event.
          await _applyRemoteRuntime(canonicalRuntime, force: true);
        } else if (remoteStatus == 'accepted') {
          await _applyAcceptedCommandRevision(command, result);
        } else if (command.entityType == 'sync_conflict_decisions') {
          await _restoreRejectedConflictDecision(command, result);
        } else if (command.entityType == 'activity_segments' &&
            result['reason'] == 'revision_mismatch') {
          await _recoverActivitySegmentConflict(command, payload);
        } else if (await _retireProvenDuplicateCreate(
          command,
          reason: result['reason'] as String?,
          serverRevision: result['server_revision'],
          generation: generation,
          userId: userId,
        )) {
          // A same-ID create is not a competing edit when the canonical owner
          // row is positively readable. Resolve it in this delivery pass so
          // an ordinary duplicate starter Area never spends even one refresh
          // in the user-facing synchronization queue.
        } else if (await _recoverOnlineCanonicalMismatch(
          command,
          result,
          generation: generation,
          userId: userId,
        )) {
          // A server response proves that this device is online.  A stale
          // revision in that situation is a cache-recovery event, not an
          // ordinary user conflict. Pull the accepted canonical state and
          // retire the superseded intent so it cannot keep resubmitting an
          // obsolete base revision.
        } else {
          needsAttention = true;
        }
      } on _StaleSyncOperation {
        rethrow;
      } catch (error) {
        _ensureCurrentOperation(generation, userId);
        final errorCode = error is PostgrestException ? error.code : null;
        final failureKind = classifySyncDeliveryFailure(
          entityType: command.entityType,
          commandType: command.commandType,
          errorCode: errorCode,
          errorMessage: error.toString(),
        );
        if (failureKind == SyncDeliveryFailureKind.applicationCatalogAlias) {
          final recovered = await _recoverApplicationCatalogAlias(
            command,
            generation: generation,
            userId: userId,
          );
          if (recovered) {
            // Reference repair can enqueue one canonical application-rule
            // update after this pass captured its batch. Request an immediate
            // replay instead of waiting for the ten-second fallback timer.
            unawaited(drainOutbox());
            commandIndex += 1;
            continue;
          }
        }
        if (failureKind == SyncDeliveryFailureKind.permanent) {
          if (command.entityType == 'sync_conflict_decisions') {
            await _restoreRejectedConflictDecision(command, {
              'status': 'conflict',
              'reason': _permanentFailureReason(errorCode, error),
            });
            needsAttention = true;
            commandIndex += 1;
            continue;
          }
          await (database.update(
            database.localOutboxCommands,
          )..where((row) => row.commandId.equals(command.commandId))).write(
            LocalOutboxCommandsCompanion(
              status: const Value('conflict'),
              attemptCount: Value(command.attemptCount + 1),
              nextAttemptAt: const Value(null),
              lastError: Value(
                jsonEncode({
                  'reason': _permanentFailureReason(errorCode, error),
                  'code': errorCode,
                  'message': error.toString(),
                }),
              ),
            ),
          );
          needsAttention = true;
          commandIndex += 1;
          continue;
        }
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          LocalOutboxCommandsCompanion(
            attemptCount: Value(command.attemptCount + 1),
            nextAttemptAt: Value(
              DateTime.now().add(syncRetryDelay(command.attemptCount + 1)),
            ),
            lastError: Value(error.toString()),
          ),
        );
        deliveryInterrupted = true;
        break;
      }
      commandIndex += 1;
    }

    if (!needsAttention && !deliveryInterrupted) {
      _ensureCurrentOperation(generation, userId);
      if (!_snapshotRetryRequired) {
        await pullChanges();
      }
    }
    _ensureCurrentOperation(generation, userId);
    if (needsAttention) {
      _setHealth(SyncHealth.attention);
    } else {
      await _settleHealth();
    }
  }

  int _outboxPriority(LocalOutboxCommand command) {
    // Foreign-key parents must reach the canonical account before children.
    // This order is intentionally small and explicit: it prevents a blocked
    // task/session from holding the entire queue hostage while preserving a
    // device's sequence within each dependency level.
    return switch (command.entityType) {
      'profiles' ||
      'user_settings' ||
      'coaching_settings' ||
      'privacy_settings' ||
      'account_devices' => 10,
      'task_domains' || 'task_categories' || 'tags' => 20,
      'task_templates' || 'recurrence_rules' || 'recurrence_exceptions' => 30,
      'roadmaps' => 40,
      'roadmap_phases' ||
      'roadmap_milestones' ||
      'roadmap_checkpoints' ||
      'roadmap_progress_rules' => 45,
      'task_occurrences' => 50,
      'roadmap_task_links' || 'task_dependencies' => 55,
      'application_catalog' ||
      'user_application_overrides' ||
      'task_application_links' => 58,
      'execution_sessions' || 'pomodoro_cycles' => 60,
      'execution_runtime' || 'execution_runtime_switch' => 62,
      'session_events' || 'interruptions' => 65,
      'checklist_items' ||
      'task_notes' ||
      'task_reminders' ||
      'task_resources' ||
      'browser_workspaces' ||
      'browser_tabs' ||
      'browser_bookmarks' => 70,
      'activity_segments' ||
      'activity_attributions' ||
      'activity_contributions' ||
      'activity_review_queue' ||
      'activity_review_classifications' ||
      'classification_feedback' ||
      'application_rules' ||
      'website_rules' => 80,
      'health_permissions' ||
      'health_summaries' ||
      'task_health_summaries' => 90,
      _ => 75,
    };
  }

  Future<void> _repairDependencyBlockedCommands(String userId) async {
    // A command may have backed off before the dependency-ordering fix was
    // installed.  Bring only database foreign-key failures forward so the
    // newly ordered pass can retry after its parents have been accepted.
    final blocked =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('pending') &
                  (row.lastError.like('%foreign key%') |
                      row.lastError.like('%out of range%') |
                      row.lastError.like('%malformed array literal%')),
            ))
            .get();
    if (blocked.isEmpty) return;
    final now = DateTime.now().toUtc();
    for (final command in blocked) {
      await (database.update(database.localOutboxCommands)
            ..where((row) => row.commandId.equals(command.commandId)))
          .write(LocalOutboxCommandsCompanion(nextAttemptAt: Value(now)));
    }
  }

  Future<void> _makeLegacyApplicationCatalogAliasesDue(String userId) async {
    final candidates =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('pending') &
                  row.entityType.equals('application_catalog') &
                  row.commandType.equals('create') &
                  row.lastError.isNotNull(),
            ))
            .get();
    final now = DateTime.now().toUtc();
    for (final command in candidates) {
      if (!isLegacyPendingApplicationCatalogAlias(
        entityType: command.entityType,
        commandType: command.commandType,
        lastError: command.lastError,
      )) {
        continue;
      }
      await (database.update(database.localOutboxCommands)
            ..where((row) => row.commandId.equals(command.commandId)))
          .write(LocalOutboxCommandsCompanion(nextAttemptAt: Value(now)));
    }
  }

  Future<void> _restoreMissingParentCommands(String userId) async {
    // Starter domains used to be inserted directly into SQLite before an
    // account was connected. They therefore had no outbox command, leaving
    // every dependent task permanently blocked by a remote foreign key.
    final tasks =
        await (database.select(database.localTasks)..where(
              (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
            ))
            .get();
    final referencedIds = tasks
        .map((task) => task.domainId)
        .whereType<String>()
        .toSet();
    if (referencedIds.isEmpty) return;
    // Do not make recovery depend on a REST read. Older installations can
    // retain a valid authenticated RPC session while their cached REST
    // permissions are stale; in that case a read failure must not prevent the
    // parent command from being reconstructed. A normal current client always
    // has a create command from `seedStarterDomains`, so this path only serves
    // legacy records that have no delivery history at all.
    const remoteIds = <String>{};
    final deviceId = await DeviceIdentity.accountId(userId);
    final now = DateTime.now().toUtc();
    final domains =
        await (database.select(database.localDomains)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.deletedAt.isNull() &
                  row.id.isIn(referencedIds),
            ))
            .get();
    for (final domain in domains) {
      // A row pulled from the server already carries a command identity.  It
      // is not a legacy local starter domain and must never be re-created.
      if (domain.lastCommandId != null) continue;
      if (remoteIds.contains(domain.id)) continue;
      final exists =
          await (database.select(database.localOutboxCommands)
                ..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.entityType.equals('task_domains') &
                      row.entityId.equals(domain.id) &
                      row.status.isIn(const ['pending', 'accepted']),
                )
                ..limit(1))
              .getSingleOrNull();
      if (exists != null) continue;
      final commandId = _uuid.v4();
      await database.transaction(() async {
        await database
            .into(database.localOutboxCommands)
            .insert(
              LocalOutboxCommandsCompanion.insert(
                commandId: commandId,
                userId: userId,
                deviceId: deviceId,
                deviceSequence: await DeviceIdentity.nextSequence(userId),
                entityType: 'task_domains',
                entityId: domain.id,
                commandType: 'create',
                baseRevision: 0,
                payloadJson: jsonEncode({
                  'name': domain.name,
                  'icon_name': domain.iconName,
                  'color_value': _databaseColorValue(domain.colorValue),
                  'position': domain.position,
                  'data': <String, Object?>{},
                }),
                clientTimestamp: now,
                createdAt: now,
              ),
            );
        await (database.update(database.localDomains)..where(
              (row) => row.id.equals(domain.id) & row.userId.equals(userId),
            ))
            .write(LocalDomainsCompanion(lastCommandId: Value(commandId)));
      });
    }
  }

  Future<void> _compactLegacyOutbox(String userId) async {
    // Older clients kept every state update even while their create command
    // was pending. Compact each entity's unsent mutation chain into one
    // command with a valid base revision before we resume delivery.
    final commands =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.status.equals('pending') &
                    row.entityType.isNotIn(const ['session_events']),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)]))
            .get();
    final groups = <String, List<LocalOutboxCommand>>{};
    for (final command in commands) {
      groups
          .putIfAbsent(
            '${command.entityType}:${command.entityId}',
            () => <LocalOutboxCommand>[],
          )
          .add(command);
    }
    for (final group in groups.values) {
      if (group.length < 2) {
        if (group.single.entityType == 'recurrence_rules' ||
            group.single.entityType == 'task_domains') {
          await _normalizeLegacyPayload(group.single);
        }
        continue;
      }
      final create = group
          .where((command) => command.commandType == 'create')
          .firstOrNull;
      final delete = group
          .where((command) => command.commandType == 'delete')
          .lastOrNull;
      if (create != null && delete != null) {
        await _supersedeCommands(group);
        continue;
      }
      final retained = create ?? group.first;
      var payload = _payloadMap(retained.payloadJson);
      for (final command in group) {
        if (command.commandId == retained.commandId ||
            command.commandType == 'delete') {
          continue;
        }
        payload = _mergePayloadMaps(payload, _payloadMap(command.payloadJson));
      }
      payload = _normalizePayloadForWire(retained.entityType, payload);
      if (delete != null && create == null) {
        payload = <String, Object?>{};
      }
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(retained.commandId))).write(
        LocalOutboxCommandsCompanion(
          commandType: Value(delete == null ? retained.commandType : 'delete'),
          payloadJson: Value(jsonEncode(payload)),
          clientTimestamp: Value(group.last.clientTimestamp),
        ),
      );
      await _supersedeCommands(
        group.where((command) => command.commandId != retained.commandId),
      );
    }
  }

  Future<void> _normalizeLegacyPayload(LocalOutboxCommand command) async {
    final payload = _normalizePayloadForWire(
      command.entityType,
      _payloadMap(command.payloadJson),
    );
    await (database.update(
      database.localOutboxCommands,
    )..where((row) => row.commandId.equals(command.commandId))).write(
      LocalOutboxCommandsCompanion(payloadJson: Value(jsonEncode(payload))),
    );
  }

  Map<String, Object?> _payloadMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Map<String, Object?> _mergePayloadMaps(
    Map<String, Object?> left,
    Map<String, Object?> right,
  ) {
    final merged = <String, Object?>{...left, ...right};
    final leftData = left['data'];
    final rightData = right['data'];
    if (leftData is Map || rightData is Map) {
      merged['data'] = <String, Object?>{
        if (leftData is Map) ...Map<String, Object?>.from(leftData),
        if (rightData is Map) ...Map<String, Object?>.from(rightData),
      };
    }
    return merged;
  }

  Map<String, Object?> _normalizePayloadForWire(
    String entityType,
    Map<String, Object?> payload,
  ) {
    final normalized = <String, Object?>{...payload};
    if (entityType == 'recurrence_rules') {
      final weekdays = normalized['weekdays'];
      if (weekdays is List) {
        normalized['weekdays'] =
            '{${weekdays.whereType<num>().map((day) => day.toInt()).join(',')}}';
      }
    }
    if (entityType == 'task_domains' && normalized['color_value'] is num) {
      normalized['color_value'] = _databaseColorValue(
        (normalized['color_value'] as num).toInt(),
      );
    }
    return normalized;
  }

  Future<void> _supersedeCommands(Iterable<LocalOutboxCommand> commands) async {
    for (final command in commands) {
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        const LocalOutboxCommandsCompanion(
          status: Value('superseded'),
          lastError: Value(null),
        ),
      );
    }
  }

  Future<void> _retireInvalidHealthSummaryCommands(String userId) async {
    // Zero-record placeholder summaries do not prove a connected health
    // source. Retire their legacy retries rather than repeatedly reporting a
    // sync error or fabricating a health import on other devices.
    final records =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.entityType.equals('health_summaries') &
                  row.deletedAt.isNull(),
            ))
            .get();
    final invalidIds = <String>{};
    for (final record in records) {
      final data = _payloadMap(record.dataJson);
      final value = data['value'];
      final noData =
          (data['record_count'] == null ||
              (data['record_count'] as num?)?.toInt() == 0) &&
          (value == null || value == 0 || value == 0.0);
      if (!noData) continue;
      invalidIds.add(record.id);
      await (database.update(database.localEntityRecords)..where(
            (row) => row.id.equals(record.id) & row.userId.equals(userId),
          ))
          .write(
            LocalEntityRecordsCompanion(
              deletedAt: Value(DateTime.now().toUtc()),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
    }
    if (invalidIds.isEmpty) return;
    await (database.update(database.localOutboxCommands)..where(
          (row) =>
              row.userId.equals(userId) &
              row.entityType.equals('health_summaries') &
              row.entityId.isIn(invalidIds) &
              row.status.isIn(const ['pending', 'conflict']),
        ))
        .write(
          const LocalOutboxCommandsCompanion(
            status: Value('superseded'),
            lastError: Value(null),
          ),
        );
  }

  Future<void> _supersedeResolvedConflicts(String userId) async {
    // A legacy update can be sent before its create reaches Supabase. Once
    // that create is accepted, the earlier missing-entity result is no longer
    // actionable. Retire it instead of keeping the account permanently in an
    // attention state. Delete conflicts are retired only after the canonical
    // row confirms that it is already deleted.
    final conflicts =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) & row.status.equals('conflict'),
            ))
            .get();
    final handledMissingActivitySegments = <String>{};
    for (final command in conflicts) {
      final error = _payloadMap(command.lastError ?? '');
      final reason = error['reason'] as String?;
      if (reason == 'missing_entity') {
        final acceptedCreate =
            await (database.select(database.localOutboxCommands)
                  ..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.entityType.equals(command.entityType) &
                        row.entityId.equals(command.entityId) &
                        row.commandType.equals('create') &
                        row.status.equals('accepted'),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (acceptedCreate != null) {
          await _supersedeCommands([command]);
          await _markRemoteConflictResolved(
            command,
            strategy: 'accepted_create_superseded_stale_update',
          );
          continue;
        }
        if (command.entityType == 'activity_segments') {
          if (!handledMissingActivitySegments.add(command.entityId)) {
            continue;
          }
          final sameSegment =
              conflicts
                  .where(
                    (candidate) =>
                        candidate.entityType == 'activity_segments' &&
                        candidate.entityId == command.entityId &&
                        candidate.commandType == 'update' &&
                        _payloadMap(candidate.lastError ?? '')['reason'] ==
                            'missing_entity',
                  )
                  .toList()
                ..sort(
                  (left, right) =>
                      left.deviceSequence.compareTo(right.deviceSequence),
                );
          final localSegment =
              await (database.select(database.localActivitySegments)..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.id.equals(command.entityId) &
                        row.deletedAt.isNull(),
                  ))
                  .getSingleOrNull();
          if (shouldRecreateMissingActivitySegment(
            commandType: command.commandType,
            hasAcceptedCreate: false,
            hasLocalSegment: localSegment != null,
          )) {
            final retained = sameSegment.isEmpty ? command : sameSegment.last;
            await _supersedeCommands(
              sameSegment.where(
                (candidate) => candidate.commandId != retained.commandId,
              ),
            );
            await (database.update(
              database.localOutboxCommands,
            )..where((row) => row.commandId.equals(retained.commandId))).write(
              LocalOutboxCommandsCompanion(
                commandType: const Value('create'),
                baseRevision: const Value(0),
                status: const Value('pending'),
                attemptCount: const Value(0),
                nextAttemptAt: Value(DateTime.now().toUtc()),
                lastError: const Value(null),
              ),
            );
          } else if (localSegment == null) {
            // The canonical row never existed and this device no longer has
            // source evidence to recreate it. Replaying stale extensions
            // cannot recover user data.
            final staleCommands = sameSegment.isEmpty ? [command] : sameSegment;
            await _supersedeCommands(staleCommands);
            for (final stale in staleCommands) {
              await _markRemoteConflictResolved(
                stale,
                strategy: 'missing_local_activity_source',
              );
            }
          }
        }
        continue;
      }
      if (reason != 'revision_mismatch' ||
          command.commandType != 'delete' ||
          command.entityType != 'task_occurrences') {
        continue;
      }
      try {
        final remote = await client
            .from('task_occurrences')
            .select('deleted_at')
            .eq('id', command.entityId)
            .maybeSingle();
        if (remote != null && remote['deleted_at'] != null) {
          await _supersedeCommands([command]);
          await _markRemoteConflictResolved(
            command,
            strategy: 'delete_already_canonical',
          );
        }
      } catch (_) {
        // Keep the conflict visible until the next successful pull can prove
        // that the delete already happened.
      }
    }
  }

  Future<void> _markRemoteConflictResolved(
    LocalOutboxCommand command, {
    required String strategy,
  }) async {
    try {
      final rows = await client
          .from('sync_conflicts')
          .select('id')
          .eq('command_id', command.commandId)
          .eq('entity_id', command.entityId)
          .eq('resolution_status', 'unresolved');
      for (final row in rows) {
        await client.rpc<Object?>(
          'resolve_sync_conflict_v0026',
          params: {'p_conflict_id': row['id'], 'p_strategy': strategy},
        );
      }
    } catch (_) {
      // Remote conflict history is diagnostics only. Local convergence must
      // never depend on an older schema allowing this annotation.
    }
  }

  int _databaseColorValue(int value) =>
      value > 0x7fffffff ? value - 0x100000000 : value;

  int _appColorValue(int value) => value < 0 ? value + 0x100000000 : value;

  Future<void> _prepareNormalizedActivityCommands() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final settings =
        await (database.select(database.localAppSettings)
              ..where((row) => row.id.equals(localAppSettingsId(user.id))))
            .getSingleOrNull();
    final privacyPolicy = await ActivityPrivacyPolicy.load(database, user.id);
    final synchronizeActivity = privacyPolicy.allowsApprovedContributionUpload(
      settings,
    );
    final detailedActivitySyncEnabled = privacyPolicy
        .allowsDetailedActivityUpload(settings);
    const activityTypes = <String>[
      'activity_segments',
      'activity_attributions',
      'activity_contributions',
      'activity_review_queue',
      'activity_review_classifications',
      'classification_feedback',
    ];
    if (!synchronizeActivity) {
      await (database.update(database.localOutboxCommands)..where(
            (row) =>
                row.userId.equals(user.id) &
                row.status.isIn(const ['pending', 'conflict']) &
                row.entityType.isIn(activityTypes),
          ))
          .write(
            const LocalOutboxCommandsCompanion(
              status: Value('superseded'),
              lastError: Value(null),
            ),
          );
      return;
    }
    await _canonicalizeLegacyActivitySegmentIds(user.id);
    await _migrateRejectedLegacyActivityCommands(
      user.id,
      detailedActivitySyncEnabled: detailedActivitySyncEnabled,
    );

    // The normal Activity privacy mode keeps unapproved device-usage records
    // on their source device.  Earlier development builds may have queued
    // those records already, so retire only their outgoing commands (never
    // the local Activity itself).  Confirmed task contributions retain their
    // normalized segment, attribution and review context for cross-device
    // totals and reports.
    final approvedSegmentIds = <String>{};
    if (!detailedActivitySyncEnabled) {
      approvedSegmentIds.addAll(
        (await (database.select(
          database.localContributions,
        )..where((row) => row.userId.equals(user.id))).get()).map(
          (row) => row.activitySegmentId,
        ),
      );
      final reviewSegmentById = {
        for (final row in await (database.select(
          database.localActivityReviews,
        )..where((row) => row.userId.equals(user.id))).get())
          row.id: row.activitySegmentId,
      };
      final attributionSegmentById = {
        for (final row in await (database.select(
          database.localAttributions,
        )..where((row) => row.userId.equals(user.id))).get())
          row.id: row.activitySegmentId,
      };
      final feedbackSegmentById = {
        for (final row
            in await (database.select(database.localEntityRecords)..where(
                  (row) =>
                      row.userId.equals(user.id) &
                      row.entityType.equals('classification_feedback'),
                ))
                .get())
          row.id: row.parentId,
      };
      final candidates =
          await (database.select(database.localOutboxCommands)..where(
                (row) =>
                    row.userId.equals(user.id) &
                    row.status.isIn(const ['pending', 'conflict']) &
                    row.entityType.isIn(const [
                      'activity_segments',
                      'activity_attributions',
                      'activity_review_queue',
                      'classification_feedback',
                    ]),
              ))
              .get();
      for (final command in candidates) {
        final segmentId = switch (command.entityType) {
          'activity_segments' => command.entityId,
          'activity_attributions' => attributionSegmentById[command.entityId],
          'activity_review_queue' => reviewSegmentById[command.entityId],
          'classification_feedback' => feedbackSegmentById[command.entityId],
          _ => null,
        };
        final isApprovedSegment =
            command.entityType == 'activity_segments' &&
            segmentId != null &&
            approvedSegmentIds.contains(segmentId);
        if (isApprovedSegment) {
          continue;
        }
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          const LocalOutboxCommandsCompanion(
            status: Value('superseded'),
            lastError: Value(null),
          ),
        );
        if (command.status == 'conflict') {
          await _markRemoteConflictResolved(
            command,
            strategy: 'device_local_activity_not_shared',
          );
        }
      }
    }

    // Commands created by older builds can contain optional private capture
    // fields. Normalized Activity itself must synchronize, but these fields
    // must never escape the device unless the user enabled detailed history.
    if (detailedActivitySyncEnabled) return;
    final commands =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(user.id) &
                  row.status.equals('pending') &
                  row.entityType.equals('activity_segments'),
            ))
            .get();
    for (final command in commands) {
      if (!approvedSegmentIds.contains(command.entityId)) {
        // The earlier pass normally retires this already. Keep this extra
        // guard so a malformed legacy command cannot become a raw upload.
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          const LocalOutboxCommandsCompanion(
            status: Value('superseded'),
            lastError: Value(null),
          ),
        );
        continue;
      }
      final raw = jsonDecode(command.payloadJson);
      if (raw is! Map) continue;
      final payload = Map<String, dynamic>.from(raw);
      final existingData = payload['data'] is Map
          ? Map<String, dynamic>.from(payload['data'] as Map)
          : <String, dynamic>{};
      final safePayload = <String, dynamic>{
        ...payload,
        'process_name': null,
        'window_title': null,
        'domain': null,
        'url': null,
        'page_title': null,
        'raw_metadata': const <String, Object?>{
          'normalized': true,
          'raw_samples_included': false,
        },
        'data': {
          ...existingData,
          'approved_contribution': true,
          'capture_state': 'finalized',
          'detail_level': 'privacy_safe',
          'raw_samples_included': false,
        },
      };
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        LocalOutboxCommandsCompanion(
          payloadJson: Value(jsonEncode(safePayload)),
        ),
      );
    }
  }

  /// Migrates the readable Activity keys used by early Android builds to UUID
  /// identities before any command reaches a UUID-typed Supabase function.
  ///
  /// This is a local identity migration, not a second Activity observation:
  /// the segment row and every dependent reference are repointed together.
  /// Rejected commands are made eligible once under the same idempotent
  /// command ID because PostgreSQL could not record a command whose UUID
  /// argument failed to parse.
  Future<void> _canonicalizeLegacyActivitySegmentIds(String userId) async {
    final segments =
        await (database.select(database.localActivitySegments)..where(
              (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
            ))
            .get();
    final aliases = <String, String>{
      for (final segment in segments)
        if (_uuidOrNull(segment.id) == null)
          segment.id: canonicalActivitySegmentSyncId(
            userId: userId,
            localSegmentId: segment.id,
          ),
    };

    for (final entry in aliases.entries) {
      final localId = entry.key;
      final canonicalId = entry.value;
      final existingCanonical =
          await (database.select(database.localActivitySegments)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.id.equals(canonicalId) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();
      final now = DateTime.now().toUtc();
      await database.transaction(() async {
        if (existingCanonical == null) {
          await (database.update(database.localActivitySegments)..where(
                (row) => row.userId.equals(userId) & row.id.equals(localId),
              ))
              .write(LocalActivitySegmentsCompanion(id: Value(canonicalId)));
        } else {
          // A prior interrupted repair already created the canonical row.
          // Keep one observation and retire only its stale local alias.
          await (database.update(database.localActivitySegments)..where(
                (row) => row.userId.equals(userId) & row.id.equals(localId),
              ))
              .write(LocalActivitySegmentsCompanion(deletedAt: Value(now)));
        }
        await (database.update(database.localActivityReviews)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.activitySegmentId.equals(localId),
            ))
            .write(
              LocalActivityReviewsCompanion(
                activitySegmentId: Value(canonicalId),
              ),
            );
        await (database.update(database.localAttributions)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.activitySegmentId.equals(localId),
            ))
            .write(
              LocalAttributionsCompanion(activitySegmentId: Value(canonicalId)),
            );
        await (database.update(database.localContributions)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.activitySegmentId.equals(localId),
            ))
            .write(
              LocalContributionsCompanion(
                activitySegmentId: Value(canonicalId),
              ),
            );
        await (database.update(database.localEntityRecords)..where(
              (row) => row.userId.equals(userId) & row.parentId.equals(localId),
            ))
            .write(LocalEntityRecordsCompanion(parentId: Value(canonicalId)));
        await (database.update(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.secondaryParentId.equals(localId),
            ))
            .write(
              LocalEntityRecordsCompanion(
                secondaryParentId: Value(canonicalId),
              ),
            );

        final commands =
            await (database.select(database.localOutboxCommands)..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.status.isIn(const ['pending', 'conflict']),
                ))
                .get();
        for (final command in commands) {
          final payload = _payloadMap(command.payloadJson);
          final repairedPayload = _replacePayloadIdentity(
            payload,
            localId,
            canonicalId,
          );
          final segmentCommand =
              command.entityType == 'activity_segments' &&
              command.entityId == localId;
          if (!segmentCommand &&
              jsonEncode(repairedPayload) == jsonEncode(payload)) {
            continue;
          }
          await (database.update(
            database.localOutboxCommands,
          )..where((row) => row.commandId.equals(command.commandId))).write(
            LocalOutboxCommandsCompanion(
              entityId: segmentCommand
                  ? Value(canonicalId)
                  : const Value.absent(),
              payloadJson: Value(jsonEncode(repairedPayload)),
              status: segmentCommand
                  ? const Value('pending')
                  : const Value.absent(),
              attemptCount: segmentCommand
                  ? const Value(0)
                  : const Value.absent(),
              nextAttemptAt: segmentCommand ? Value(now) : const Value.absent(),
              lastError: segmentCommand
                  ? const Value(null)
                  : const Value.absent(),
            ),
          );
        }
      });
    }

    // An interrupted earlier repair may already have replaced a malformed
    // segment command while leaving an atomic classifier with a null segment
    // ID. Recover it from the typed review row before delivery.
    final reviewSegmentById = {
      for (final review
          in await (database.select(database.localActivityReviews)..where(
                (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
              ))
              .get())
        review.id: review.activitySegmentId,
    };
    final atomicCommands =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.isIn(const ['pending', 'conflict']) &
                  row.entityType.equals('activity_review_classifications') &
                  row.commandType.equals('classify'),
            ))
            .get();
    for (final command in atomicCommands) {
      final payload = _payloadMap(command.payloadJson);
      final currentSegmentId = payload['activity_segment_id'] as String?;
      if (_uuidOrNull(currentSegmentId) != null) continue;
      final localSegmentId = reviewSegmentById[command.entityId];
      if (localSegmentId == null) continue;
      final canonicalSegmentId = canonicalActivitySegmentSyncId(
        userId: userId,
        localSegmentId: localSegmentId,
      );
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        LocalOutboxCommandsCompanion(
          payloadJson: Value(
            jsonEncode({
              ..._sanitizeAtomicActivityPayload(payload),
              'activity_segment_id': canonicalSegmentId,
            }),
          ),
          status: const Value('pending'),
          attemptCount: const Value(0),
          nextAttemptAt: Value(DateTime.now().toUtc()),
          lastError: const Value(null),
        ),
      );
    }
  }

  Map<String, Object?> _replacePayloadIdentity(
    Map<String, Object?> payload,
    String oldId,
    String canonicalId,
  ) {
    Object? replace(Object? value) {
      if (value == oldId) return canonicalId;
      if (value is List) return value.map(replace).toList(growable: false);
      if (value is Map) {
        return <String, Object?>{
          for (final entry in value.entries)
            entry.key.toString(): replace(entry.value),
        };
      }
      return value;
    }

    return Map<String, Object?>.from(replace(payload)! as Map);
  }

  /// Rebuilds malformed v0.0.26 Activity creates from the typed local rows.
  ///
  /// Older clients queued split writes with stale enum, UUID, or revision
  /// shapes. Replaying those payloads can never succeed because processed
  /// command IDs are immutable. This pass keeps the local evidence, replaces
  /// the segment with one sanitized create, and converts a resolved review
  /// into the v0.0.27 atomic classification command.
  Future<void> _migrateRejectedLegacyActivityCommands(
    String userId, {
    required bool detailedActivitySyncEnabled,
  }) async {
    final conflicts =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.status.equals('conflict') &
                    row.commandType.equals('create') &
                    row.entityType.isIn(const [
                      'activity_segments',
                      'activity_attributions',
                      'activity_contributions',
                      'activity_review_queue',
                      'classification_feedback',
                    ]),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)]))
            .get();
    final candidates = conflicts
        .where((command) {
          final reason =
              _payloadMap(command.lastError ?? '')['reason'] as String?;
          return shouldMigrateLegacyActivityConflict(
            status: command.status,
            entityType: command.entityType,
            commandType: command.commandType,
            reason: reason,
          );
        })
        .toList(growable: false);
    if (candidates.isEmpty) return;

    final segments =
        await (database.select(database.localActivitySegments)..where(
              (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
            ))
            .get();
    final segmentById = {for (final row in segments) row.id: row};
    final reviews =
        await (database.select(database.localActivityReviews)..where(
              (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
            ))
            .get();
    final reviewById = {for (final row in reviews) row.id: row};
    final attributions =
        await (database.select(database.localAttributions)..where(
              (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
            ))
            .get();
    final attributionById = {for (final row in attributions) row.id: row};
    final contributions =
        await (database.select(database.localContributions)..where(
              (row) => row.userId.equals(userId) & row.deletedAt.isNull(),
            ))
            .get();
    final contributionById = {for (final row in contributions) row.id: row};
    final feedbackRecords =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.entityType.equals('classification_feedback') &
                  row.deletedAt.isNull(),
            ))
            .get();
    final feedbackById = {for (final row in feedbackRecords) row.id: row};

    String? segmentIdFor(LocalOutboxCommand command) {
      return switch (command.entityType) {
        'activity_segments' => command.entityId,
        'activity_review_queue' =>
          reviewById[command.entityId]?.activitySegmentId,
        'activity_attributions' =>
          attributionById[command.entityId]?.activitySegmentId,
        'activity_contributions' =>
          contributionById[command.entityId]?.activitySegmentId,
        'classification_feedback' =>
          feedbackById[command.entityId]?.parentId ??
              _payloadMap(
                    feedbackById[command.entityId]?.dataJson ?? '',
                  )['activity_segment_id']
                  as String?,
        _ => null,
      };
    }

    final grouped = <String, List<LocalOutboxCommand>>{};
    for (final command in candidates) {
      final segmentId = segmentIdFor(command);
      if (segmentId == null || segmentId.isEmpty) {
        // There is no typed local evidence to reconstruct. Retain the local
        // record but retire the permanently malformed transport command.
        await _supersedeCommands([command]);
        continue;
      }
      grouped.putIfAbsent(segmentId, () => []).add(command);
    }

    final deviceId = await DeviceIdentity.accountId(userId);
    for (final entry in grouped.entries) {
      final segmentId = entry.key;
      final commands = entry.value;
      final segment = segmentById[segmentId];
      if (segment == null) {
        await _supersedeCommands(commands);
        continue;
      }

      final acceptedSegmentCreate =
          await (database.select(database.localOutboxCommands)
                ..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.entityType.equals('activity_segments') &
                      row.entityId.equals(segmentId) &
                      row.commandType.equals('create') &
                      row.status.equals('accepted'),
                )
                ..limit(1))
              .getSingleOrNull();
      final pendingSegmentCreate =
          await (database.select(database.localOutboxCommands)
                ..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.entityType.equals('activity_segments') &
                      row.entityId.equals(segmentId) &
                      row.commandType.equals('create') &
                      row.status.equals('pending'),
                )
                ..limit(1))
              .getSingleOrNull();
      if (acceptedSegmentCreate == null && pendingSegmentCreate == null) {
        final now = DateTime.now().toUtc();
        final end = segment.endedAt.isBefore(segment.startedAt)
            ? segment.startedAt
            : segment.endedAt;
        final rawMetadata = _payloadMap(segment.rawMetadataJson);
        final confidence = segment.captureConfidence?.clamp(0.0, 1.0);
        await database
            .into(database.localOutboxCommands)
            .insert(
              LocalOutboxCommandsCompanion.insert(
                commandId: _uuid.v4(),
                userId: userId,
                deviceId: deviceId,
                deviceSequence: await DeviceIdentity.nextSequence(userId),
                entityType: 'activity_segments',
                entityId: segmentId,
                commandType: 'create',
                baseRevision: 0,
                payloadJson: jsonEncode({
                  'device_id': _uuidOrNull(segment.deviceId) ?? deviceId,
                  'device_event_id': segment.deviceEventId.isEmpty
                      ? segment.id
                      : segment.deviceEventId,
                  'started_at': segment.startedAt.toUtc().toIso8601String(),
                  'ended_at': end.toUtc().toIso8601String(),
                  'source_type': segment.sourceType.isEmpty
                      ? 'unknown'
                      : segment.sourceType,
                  'application_id': null,
                  'website_rule_id': null,
                  'resource_id': null,
                  'process_name': segment.processName,
                  'window_title': detailedActivitySyncEnabled
                      ? segment.windowTitle
                      : null,
                  'domain': detailedActivitySyncEnabled ? segment.domain : null,
                  'url': detailedActivitySyncEnabled ? segment.url : null,
                  'page_title': detailedActivitySyncEnabled
                      ? segment.pageTitle
                      : null,
                  'input_state': segment.idleState == 'technical_idle'
                      ? 'idle'
                      : 'active',
                  'idle_state': segment.idleState,
                  'screen_state': 'unlocked',
                  'capture_confidence': confidence,
                  'raw_metadata': detailedActivitySyncEnabled
                      ? rawMetadata
                      : const <String, Object?>{
                          'normalized': true,
                          'raw_samples_included': false,
                        },
                  'data': <String, Object?>{
                    'normalization_version': 1,
                    'detail_level': detailedActivitySyncEnabled
                        ? 'sensitive_details_enabled'
                        : 'privacy_safe',
                    'legacy_transport_repaired': true,
                  },
                }),
                clientTimestamp: now,
                createdAt: now,
              ),
            );
      }

      final segmentReviews =
          reviews.where((row) => row.activitySegmentId == segmentId).toList()
            ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final segmentAttributions =
          attributions
              .where((row) => row.activitySegmentId == segmentId)
              .toList()
            ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      final review = segmentReviews.firstOrNull;
      final attribution = segmentAttributions
          .where((row) => row.attributionStatus != 'proposed')
          .firstOrNull;

      if (review != null && attribution != null) {
        final existingAtomic =
            await (database.select(database.localOutboxCommands)
                  ..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.entityType.equals(
                          'activity_review_classifications',
                        ) &
                        row.entityId.equals(review.id) &
                        row.status.isIn(const ['pending', 'accepted']),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (existingAtomic == null) {
          final contribution = contributions
              .where(
                (row) =>
                    row.activitySegmentId == segmentId &&
                    row.attributionId == attribution.id &&
                    row.targetType == attribution.targetType &&
                    row.targetId == attribution.targetId,
              )
              .firstOrNull;
          final feedback = feedbackRecords
              .where((row) => row.parentId == segmentId)
              .firstOrNull;
          final targetType = _normalizedActivityTargetType(
            attribution.targetType,
          );
          final targetTaskId = targetType == 'task_occurrence'
              ? _uuidOrNull(attribution.targetId)
              : null;
          final now = DateTime.now().toUtc();
          await database
              .into(database.localOutboxCommands)
              .insert(
                LocalOutboxCommandsCompanion.insert(
                  commandId: _uuid.v4(),
                  userId: userId,
                  deviceId: deviceId,
                  deviceSequence: await DeviceIdentity.nextSequence(userId),
                  entityType: 'activity_review_classifications',
                  entityId: review.id,
                  commandType: 'classify',
                  baseRevision: review.revision,
                  payloadJson: jsonEncode({
                    'activity_segment_id': segmentId,
                    'review_reason': review.reviewReason,
                    'priority': review.priority.clamp(0, 4),
                    'status': _normalizedActivityReviewStatus(
                      attribution.attributionStatus,
                    ),
                    'classification': attribution.classification,
                    'target_type': targetType,
                    'target_task_id': targetTaskId,
                    'contribution_type': contribution?.contributionType,
                    'physical_duration_ms': contribution?.physicalDurationMs,
                    'credited_duration_ms': contribution?.creditedDurationMs,
                    'is_idle_derived': contribution?.isIdleDerived ?? false,
                    'is_automatic':
                        attribution.attributionStatus == 'automatic',
                    'confidence': attribution.confidence.clamp(0.0, 1.0),
                    'attribution_id': _uuidOrNull(attribution.id),
                    'contribution_id': _uuidOrNull(contribution?.id),
                    'classification_feedback_id': _uuidOrNull(feedback?.id),
                    'suggested_classification': review.suggestedClassification,
                    'suggested_target_type': review.suggestedTargetType,
                    'suggested_target_id': _uuidOrNull(
                      review.suggestedTargetId,
                    ),
                    'feedback_type':
                        feedback?.status ??
                        _normalizedActivityReviewStatus(
                          attribution.attributionStatus,
                        ),
                    'rule_scope': null,
                    'contribution_data': <String, Object?>{
                      'source_device_id': segment.deviceId,
                      'utc_started_at': segment.startedAt
                          .toUtc()
                          .toIso8601String(),
                      'utc_ended_at': segment.endedAt.toUtc().toIso8601String(),
                      'classification_source': 'legacy_repair',
                      'raw_details_included': false,
                    },
                  }),
                  clientTimestamp: now,
                  createdAt: now,
                ),
              );
        }
      } else if (review != null && detailedActivitySyncEnabled) {
        final pendingReviewCreate =
            await (database.select(database.localOutboxCommands)
                  ..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.entityType.equals('activity_review_queue') &
                        row.entityId.equals(review.id) &
                        row.commandType.equals('create') &
                        row.status.equals('pending'),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (pendingReviewCreate == null) {
          final now = DateTime.now().toUtc();
          await database
              .into(database.localOutboxCommands)
              .insert(
                LocalOutboxCommandsCompanion.insert(
                  commandId: _uuid.v4(),
                  userId: userId,
                  deviceId: deviceId,
                  deviceSequence: await DeviceIdentity.nextSequence(userId),
                  entityType: 'activity_review_queue',
                  entityId: review.id,
                  commandType: 'create',
                  baseRevision: 0,
                  payloadJson: jsonEncode({
                    'activity_segment_id': segmentId,
                    'review_reason': review.reviewReason.isEmpty
                        ? 'manual_review'
                        : review.reviewReason,
                    'priority': review.priority.clamp(0, 4),
                    'suggested_targets': <Object?>[],
                    'suggested_classification': review.suggestedClassification,
                    'confidence': review.confidence?.clamp(0.0, 1.0),
                    'status': 'pending',
                    'data': const <String, Object?>{
                      'legacy_transport_repaired': true,
                    },
                  }),
                  clientTimestamp: now,
                  createdAt: now,
                ),
              );
        }
      } else if (!detailedActivitySyncEnabled) {
        // Unresolved device observations remain local in normal privacy mode.
        // They must not hold the account-wide queue in a permanent error.
      }

      await _supersedeCommands(commands);
    }
  }

  /// Retries only classifier calls rejected before the v0.0.27 database
  /// function received its owner-scoped execution context.
  ///
  /// The marker prevents a bad deployment from becoming another infinite
  /// retry loop. A fresh command ID is used because processed command results
  /// are immutable.
  Future<void> _retryClassifierPrivilegeConflicts(String userId) async {
    final conflicts =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('conflict') &
                  row.entityType.equals('activity_review_classifications') &
                  row.commandType.equals('classify'),
            ))
            .get();
    if (conflicts.isEmpty) return;
    final deviceId = await DeviceIdentity.accountId(userId);
    final grouped = <String, List<LocalOutboxCommand>>{};
    for (final command in conflicts) {
      grouped.putIfAbsent(command.entityId, () => []).add(command);
    }
    for (final group in grouped.values) {
      group.sort(
        (left, right) => left.deviceSequence.compareTo(right.deviceSequence),
      );
      final command = group.last;
      final error = _payloadMap(command.lastError ?? '');
      final payload = _payloadMap(command.payloadJson);
      final repairVersion =
          (payload['transport_repair_version'] as num?)?.toInt() ?? 0;
      final reason = error['reason'];
      final nextPayload = switch (reason) {
        'permission_denied' when repairVersion < 1 => <String, Object?>{
          ...payload,
          'transport_repair_version': 1,
        },
        'invalid_command_payload' when repairVersion < 2 =>
          _sanitizeAtomicActivityPayload(payload),
        _ => null,
      };
      if (nextPayload == null) {
        if (group.length > 1) {
          await _supersedeCommands(group.take(group.length - 1));
        }
        continue;
      }
      final now = DateTime.now().toUtc();
      await database.transaction(() async {
        await _supersedeCommands(group);
        await database
            .into(database.localOutboxCommands)
            .insert(
              LocalOutboxCommandsCompanion.insert(
                commandId: _uuid.v4(),
                userId: userId,
                deviceId: deviceId,
                deviceSequence: await DeviceIdentity.nextSequence(userId),
                entityType: command.entityType,
                entityId: command.entityId,
                commandType: command.commandType,
                baseRevision: command.baseRevision,
                payloadJson: jsonEncode(nextPayload),
                clientTimestamp: now,
                createdAt: now,
              ),
            );
      });
      await _markRemoteConflictResolved(
        command,
        strategy: 'local_command_already_superseded',
      );
    }
  }

  Map<String, Object?> _sanitizeAtomicActivityPayload(
    Map<String, Object?> payload,
  ) {
    final physical = ((payload['physical_duration_ms'] as num?)?.toInt() ?? 0)
        .clamp(0, 1 << 53);
    final credited =
        ((payload['credited_duration_ms'] as num?)?.toInt() ?? physical).clamp(
          0,
          physical,
        );
    final targetType = _normalizedActivityTargetType(
      payload['target_type'] as String? ?? 'task_occurrence',
    );
    String? validUuid(Object? value) =>
        value is String ? _uuidOrNull(value) : null;
    return <String, Object?>{
      ...payload,
      'activity_segment_id': validUuid(payload['activity_segment_id']),
      'priority': ((payload['priority'] as num?)?.toInt() ?? 2).clamp(0, 4),
      'status': _normalizedActivityReviewStatus(
        payload['status'] as String? ?? 'confirmed',
      ),
      'target_type': targetType,
      'target_task_id': targetType == 'task_occurrence'
          ? validUuid(payload['target_task_id'])
          : null,
      'physical_duration_ms': physical,
      'credited_duration_ms': credited,
      'confidence': ((payload['confidence'] as num?)?.toDouble() ?? 1).clamp(
        0.0,
        1.0,
      ),
      'attribution_id': validUuid(payload['attribution_id']),
      'contribution_id': validUuid(payload['contribution_id']),
      'classification_feedback_id': validUuid(
        payload['classification_feedback_id'],
      ),
      'suggested_target_id': validUuid(payload['suggested_target_id']),
      'source_task_id': validUuid(payload['source_task_id']),
      'source_session_id': validUuid(payload['source_session_id']),
      'rule_id': validUuid(payload['rule_id']),
      'rule_scope_id': validUuid(payload['rule_scope_id']),
      'application_id': validUuid(payload['application_id']),
      'transport_repair_version': 2,
    };
  }

  String? _uuidOrNull(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    return RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(normalized)
        ? normalized
        : null;
  }

  String _normalizedActivityReviewStatus(String status) {
    return switch (status) {
      'rejected' => 'rejected',
      'ignored' => 'ignored',
      _ => 'confirmed',
    };
  }

  String _normalizedActivityTargetType(String targetType) {
    return switch (targetType) {
      'task' => 'task_occurrence',
      'task_occurrence' => 'task_occurrence',
      _ => targetType,
    };
  }

  /// Applies compact canonical acknowledgement data immediately.
  ///
  /// Realtime delivery is intentionally not used as the acknowledgement path:
  /// the UI must not wait for another request merely to display a newly linked
  /// application, and the next Activity extension can be captured before a
  /// broadcast arrives.
  Future<void> _applyAcceptedCommandRevision(
    LocalOutboxCommand command,
    Map<String, dynamic> result,
  ) async {
    if (command.entityType == 'sync_conflict_decisions') {
      await _applyAcceptedConflictDecision(command, result);
      return;
    }
    if (command.entityType == 'task_application_links') {
      await _applyAcceptedTaskApplicationLink(command, result);
      return;
    }
    if (command.entityType == 'website_rules' && result['rule_id'] != null) {
      await _applyAcceptedTaskWebsiteRule(command, result);
      return;
    }
    if (command.entityType != 'activity_segments') return;
    final revision = (result['revision'] as num?)?.toInt();
    if (revision == null) return;
    await database.transaction(() async {
      await (database.update(
        database.localActivitySegments,
      )..where((row) => row.id.equals(command.entityId))).write(
        LocalActivitySegmentsCompanion(
          revision: Value(revision),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      // An active segment has at most one coalesced pending update.  Rebase
      // it on this acknowledgement before it is read by the next drain step.
      await (database.update(database.localOutboxCommands)..where(
            (row) =>
                row.entityType.equals('activity_segments') &
                row.entityId.equals(command.entityId) &
                row.status.equals('pending') &
                row.commandType.equals('update'),
          ))
          .write(LocalOutboxCommandsCompanion(baseRevision: Value(revision)));
    });
  }

  Future<void> _applyAcceptedConflictDecision(
    LocalOutboxCommand decision,
    Map<String, dynamic> result,
  ) async {
    final payload = _payloadMap(decision.payloadJson);
    final originalCommandId = payload['original_command_id'] as String?;
    final strategy = payload['strategy'] as String? ?? 'already_applied';
    final canonicalEntityType =
        result['canonical_entity_type'] as String? ??
        payload['original_entity_type'] as String?;
    final canonicalPayload = result['canonical_payload'] is Map
        ? Map<String, dynamic>.from(result['canonical_payload'] as Map)
        : const <String, dynamic>{};
    if (canonicalEntityType != null && canonicalPayload.isNotEmpty) {
      await _applyEntity(canonicalEntityType, canonicalPayload);
    }
    if (originalCommandId == null) return;
    final finalStatus = strategy == 'discarded_local_change'
        ? 'discarded_by_user'
        : 'superseded';
    await (database.update(database.localOutboxCommands)..where(
          (row) =>
              row.userId.equals(decision.userId) &
              row.commandId.equals(originalCommandId) &
              row.status.equals('resolution_pending'),
        ))
        .write(
          LocalOutboxCommandsCompanion(
            status: Value(finalStatus),
            nextAttemptAt: const Value(null),
            lastError: Value(
              jsonEncode({
                'reason': strategy == 'discarded_local_change'
                    ? 'discarded_by_user'
                    : strategy,
                'decision_id': decision.commandId,
                'accepted_at': DateTime.now().toUtc().toIso8601String(),
                'canonical_revision': result['canonical_revision'],
              }),
            ),
          ),
        );
  }

  Future<void> _restoreRejectedConflictDecision(
    LocalOutboxCommand decision,
    Map<String, dynamic> result,
  ) async {
    final payload = _payloadMap(decision.payloadJson);
    final originalCommandId = payload['original_command_id'] as String?;
    await (database.update(
      database.localOutboxCommands,
    )..where((row) => row.commandId.equals(decision.commandId))).write(
      LocalOutboxCommandsCompanion(
        status: const Value('superseded'),
        nextAttemptAt: const Value(null),
        lastError: Value(
          jsonEncode({
            'reason': 'decision_not_applied',
            'result': result,
            'settled_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      ),
    );
    if (originalCommandId == null) return;
    await (database.update(database.localOutboxCommands)..where(
          (row) =>
              row.userId.equals(decision.userId) &
              row.commandId.equals(originalCommandId) &
              row.status.equals('resolution_pending'),
        ))
        .write(
          LocalOutboxCommandsCompanion(
            status: const Value('conflict'),
            nextAttemptAt: const Value(null),
            lastError: Value(jsonEncode(result)),
          ),
        );
  }

  /// Old builds could enqueue several extensions of one Activity segment with
  /// locally incremented revisions.  Preserve the latest interval safely when
  /// such a command reaches a newer server revision rather than leaving the
  /// account permanently in a conflict state.
  Future<void> _recoverActivitySegmentConflict(
    LocalOutboxCommand command,
    Map<String, dynamic> payload,
  ) async {
    final localBefore = await (database.select(
      database.localActivitySegments,
    )..where((row) => row.id.equals(command.entityId))).getSingleOrNull();
    await _pullEntity('activity_segments', command.entityId);
    final canonical = await (database.select(
      database.localActivitySegments,
    )..where((row) => row.id.equals(command.entityId))).getSingleOrNull();
    if (canonical == null) return;

    final payloadStart = _instant(payload['started_at']);
    final payloadEnd = _instant(payload['ended_at']);
    final intendedStart = [
      canonical.startedAt,
      ?localBefore?.startedAt,
      ?payloadStart,
    ].reduce((a, b) => a.isBefore(b) ? a : b);
    final intendedEnd = [
      canonical.endedAt,
      ?localBefore?.endedAt,
      ?payloadEnd,
    ].reduce((a, b) => a.isAfter(b) ? a : b);

    if (!intendedEnd.isAfter(canonical.endedAt)) {
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        const LocalOutboxCommandsCompanion(
          status: Value('superseded'),
          lastError: Value(null),
        ),
      );
      return;
    }

    final replacementPayload = <String, dynamic>{
      ...payload,
      'started_at': intendedStart.toUtc().toIso8601String(),
      'ended_at': intendedEnd.toUtc().toIso8601String(),
    };
    final sequence = await DeviceIdentity.nextSequence(command.userId);
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      await (database.update(
        database.localActivitySegments,
      )..where((row) => row.id.equals(command.entityId))).write(
        LocalActivitySegmentsCompanion(
          startedAt: Value(intendedStart),
          endedAt: Value(intendedEnd),
          revision: Value(canonical.revision),
          updatedAt: Value(now),
        ),
      );
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        const LocalOutboxCommandsCompanion(
          status: Value('superseded'),
          lastError: Value(null),
        ),
      );
      await database
          .into(database.localOutboxCommands)
          .insert(
            LocalOutboxCommandsCompanion.insert(
              commandId: _uuid.v4(),
              userId: command.userId,
              deviceId: command.deviceId,
              deviceSequence: sequence,
              entityType: 'activity_segments',
              entityId: command.entityId,
              commandType: 'update',
              baseRevision: canonical.revision,
              payloadJson: jsonEncode(replacementPayload),
              clientTimestamp: now,
              createdAt: now,
            ),
          );
    });
  }

  Future<void> _applyAcceptedTaskApplicationLink(
    LocalOutboxCommand command,
    Map<String, dynamic> result,
  ) async {
    final revision = (result['revision'] as num?)?.toInt();
    if (result['deleted'] == true) {
      await (database.update(database.localEntityRecords)..where(
            (row) =>
                row.userId.equals(command.userId) &
                row.entityType.equals('task_application_links') &
                row.id.equals(command.entityId),
          ))
          .write(
            LocalEntityRecordsCompanion(
              revision: revision == null
                  ? const Value.absent()
                  : Value(revision),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
      return;
    }

    final canonicalId =
        result['link_id'] as String? ??
        result['entity_id'] as String? ??
        command.entityId;
    final displayName =
        (result['display_name'] as String?)?.trim().isNotEmpty == true
        ? (result['display_name'] as String).trim()
        : (result['display_name_snapshot'] as String?)?.trim().isNotEmpty ==
              true
        ? (result['display_name_snapshot'] as String).trim()
        : 'Unknown application';
    final canonical = <String, dynamic>{
      'id': canonicalId,
      'user_id': result['user_id'] ?? command.userId,
      'task_occurrence_id': result['task_occurrence_id'],
      'application_id': result['application_id'],
      'relationship_type': result['relationship_type'] ?? 'supporting',
      'display_name': displayName,
      'display_name_snapshot': displayName,
      'raw_identifier_snapshot':
          result['raw_identifier'] ?? result['raw_identifier_snapshot'],
      'normalized_application_key_snapshot':
          result['normalized_key'] ??
          result['normalized_application_key_snapshot'],
      'icon_reference_snapshot':
          result['icon_reference'] ?? result['icon_reference_snapshot'],
      'status': 'active',
      'revision': revision ?? 1,
      'created_at': result['created_at'],
      'updated_at': result['updated_at'],
      'deleted_at': result['deleted_at'],
      'data': const {
        'classification': 'direct_task_work',
        'automatic_credit': true,
      },
    };
    await _applyGeneric('task_application_links', canonical);

    if (canonicalId != command.entityId) {
      final now = DateTime.now().toUtc();
      await (database.update(database.localEntityRecords)..where(
            (row) =>
                row.userId.equals(command.userId) &
                row.entityType.equals('task_application_links') &
                row.id.equals(command.entityId),
          ))
          .write(
            LocalEntityRecordsCompanion(
              status: const Value('canonical_alias'),
              updatedAt: Value(now),
              deletedAt: Value(now),
            ),
          );
    }
  }

  /// Applies the canonical acknowledgement for a task website connection.
  ///
  /// A semantic duplicate may have arrived from an older device with another
  /// UUID. The server returns the one canonical rule; the local alias is
  /// retired rather than left as a blank/removable ghost connection.
  Future<void> _applyAcceptedTaskWebsiteRule(
    LocalOutboxCommand command,
    Map<String, dynamic> result,
  ) async {
    final canonicalId =
        result['rule_id'] as String? ??
        result['entity_id'] as String? ??
        command.entityId;
    final revision = (result['revision'] as num?)?.toInt() ?? 1;
    final data = result['data'] is Map
        ? Map<String, dynamic>.from(result['data'] as Map)
        : const <String, dynamic>{};
    final canonical = <String, dynamic>{
      'id': canonicalId,
      'user_id': result['user_id'] ?? command.userId,
      'domain': result['domain'],
      'url_pattern': result['url_pattern'],
      'scope_type': result['scope_type'] ?? 'task',
      'scope_id': result['scope_id'],
      'classification': result['classification'] ?? 'direct_task_work',
      'target_type': result['target_type'] ?? 'task_occurrence',
      'target_id': result['target_id'],
      'contribution_type': result['contribution_type'] ?? 'active_work_seconds',
      'automatic_credit': result['automatic_credit'] ?? true,
      'priority': result['priority'] ?? 200,
      'revision': revision,
      'created_at': result['created_at'],
      'updated_at': result['updated_at'],
      'deleted_at': result['deleted_at'],
      'data': data,
    };
    await _applyGeneric('website_rules', canonical);

    if (canonicalId != command.entityId) {
      final now = DateTime.now().toUtc();
      await (database.update(database.localEntityRecords)..where(
            (row) =>
                row.userId.equals(command.userId) &
                row.entityType.equals('website_rules') &
                row.id.equals(command.entityId),
          ))
          .write(
            LocalEntityRecordsCompanion(
              status: const Value('canonical_alias'),
              updatedAt: Value(now),
              deletedAt: Value(now),
            ),
          );
    }
  }

  /// Runtime transitions represent one canonical machine state, so an online
  /// mismatch can safely converge to the accepted runtime. Ordinary writes
  /// may contain independent user intent and must remain real conflicts until
  /// a type-specific merge/rebase policy proves that intent was preserved.
  Future<bool> _recoverOnlineCanonicalMismatch(
    LocalOutboxCommand command,
    Map<String, dynamic> result, {
    required int generation,
    required String userId,
  }) async {
    final reason = result['reason'] as String?;
    if (!shouldSupersedeOnlineCanonicalMismatch(command.entityType, reason)) {
      return false;
    }
    try {
      _ensureCurrentOperation(generation, userId);
      await (database.update(
        database.localOutboxCommands,
      )..where((row) => row.commandId.equals(command.commandId))).write(
        const LocalOutboxCommandsCompanion(
          status: Value('superseded'),
          lastError: Value(null),
        ),
      );
      _ensureCurrentOperation(generation, userId);
      // Remove the rejected optimistic command before applying the server's
      // canonical row.  It is one of the very few legitimate cases where a
      // local revision can move backwards: the attempted state never existed
      // remotely.  A normal Realtime/pull row never gets this privilege.
      await pullChanges();
      _ensureCurrentOperation(generation, userId);
      await _restoreCanonicalRuntime(force: true);
      _ensureCurrentOperation(generation, userId);
      return true;
    } on _StaleSyncOperation {
      rethrow;
    } catch (_) {
      // Retain the command as a visible conflict only if a canonical pull
      // itself failed; this is then genuinely actionable diagnostics.
      return false;
    }
  }

  String _permanentFailureReason(String? code, Object error) {
    final message = error.toString().toLowerCase();
    if (code == '42501' ||
        message.contains('permission denied') ||
        message.contains('device_not_registered')) {
      return 'permission_denied';
    }
    if (message.contains('invalid_payload_columns') ||
        message.contains('unsupported_entity_type') ||
        message.contains('unsupported_operation')) {
      return 'invalid_command_contract';
    }
    if (code == '23505') return 'unique_constraint';
    if (code == '23502' || code == '23514' || code == '22P02') {
      return 'invalid_command_payload';
    }
    return 'server_rejected_command';
  }

  /// Converges two offline discoveries of the same application catalog row.
  ///
  /// The server's natural-key constraint proves that the existing row is the
  /// same user/platform/application. RLS proves ownership. The local alias is
  /// retired, dependent rule references are repointed, and accepted dependent
  /// rows receive a regular revision-checked update command.
  Future<bool> _recoverApplicationCatalogAlias(
    LocalOutboxCommand command, {
    required int generation,
    required String userId,
  }) async {
    final payload = _payloadMap(command.payloadJson);
    final platform = (payload['platform'] as String?)?.trim().toLowerCase();
    final identifier = (payload['application_identifier'] as String?)
        ?.trim()
        .toLowerCase();
    if (platform == null ||
        platform.isEmpty ||
        identifier == null ||
        identifier.isEmpty) {
      return false;
    }

    try {
      _ensureCurrentOperation(generation, userId);
      final rows = await client
          .from('application_catalog')
          .select()
          .eq('platform', platform)
          .eq('application_identifier', identifier)
          .isFilter('deleted_at', null)
          .limit(1);
      _ensureCurrentOperation(generation, userId);
      if (rows.isEmpty) return false;
      final canonical = Map<String, dynamic>.from(rows.first);
      final canonicalId = canonical['id'] as String?;
      if (canonicalId == null ||
          canonicalId == command.entityId ||
          canonical['user_id'] != userId) {
        return false;
      }

      await _applyGeneric('application_catalog', canonical);
      _ensureCurrentOperation(generation, userId);
      await _repointLocalApplicationReferences(
        userId: userId,
        aliasId: command.entityId,
        canonicalId: canonicalId,
      );
      _ensureCurrentOperation(generation, userId);
      final now = DateTime.now().toUtc();
      await database.transaction(() async {
        await (database.update(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.id.equals(command.entityId) &
                  row.entityType.equals('application_catalog'),
            ))
            .write(
              LocalEntityRecordsCompanion(
                status: const Value('canonical_alias'),
                updatedAt: Value(now),
                deletedAt: Value(now),
              ),
            );
        await (database.update(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.commandId.equals(command.commandId),
            ))
            .write(
              const LocalOutboxCommandsCompanion(
                status: Value('superseded'),
                lastError: Value(null),
                nextAttemptAt: Value(null),
              ),
            );
      });
      return true;
    } on _StaleSyncOperation {
      rethrow;
    } catch (_) {
      // A natural-key error is only retired after the canonical owner row was
      // positively read and every local dependent reference was made durable.
      return false;
    }
  }

  Future<void> _repointLocalApplicationReferences({
    required String userId,
    required String aliasId,
    required String canonicalId,
  }) async {
    final candidates =
        await (database.select(database.localEntityRecords)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.deletedAt.isNull() &
                  row.entityType.isIn(const [
                    'application_rules',
                    'classification_feedback',
                  ]),
            ))
            .get();
    if (candidates.isEmpty) return;
    final currentDeviceId = await DeviceIdentity.accountId(userId);
    final now = DateTime.now().toUtc();

    for (final record in candidates) {
      final decoded = _payloadMap(record.dataJson);
      final nextData = _replaceApplicationReference(
        decoded,
        aliasId: aliasId,
        canonicalId: canonicalId,
      );
      final referencesAlias =
          record.secondaryParentId == aliasId || !mapEquals(decoded, nextData);
      if (!referencesAlias) continue;

      final unresolved =
          await (database.select(database.localOutboxCommands)
                ..where(
                  (row) =>
                      row.userId.equals(userId) &
                      row.entityType.equals(record.entityType) &
                      row.entityId.equals(record.id) &
                      row.status.isIn(const ['pending', 'conflict']),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.deviceSequence)]))
              .get();
      final remoteEvidence =
          unresolved.isNotEmpty ||
          decoded['user_id'] == userId ||
          await (database.select(database.localOutboxCommands)
                    ..where(
                      (row) =>
                          row.userId.equals(userId) &
                          row.entityType.equals(record.entityType) &
                          row.entityId.equals(record.id) &
                          row.status.equals('accepted'),
                    )
                    ..limit(1))
                  .getSingleOrNull() !=
              null;
      if (!remoteEvidence) {
        await (database.update(database.localEntityRecords)..where(
              (row) => row.userId.equals(userId) & row.id.equals(record.id),
            ))
            .write(
              LocalEntityRecordsCompanion(
                secondaryParentId: record.secondaryParentId == aliasId
                    ? Value(canonicalId)
                    : const Value.absent(),
                dataJson: Value(jsonEncode(nextData)),
                updatedAt: Value(now),
              ),
            );
        continue;
      }

      if (unresolved.isNotEmpty) {
        await database.transaction(() async {
          await (database.update(database.localEntityRecords)..where(
                (row) => row.userId.equals(userId) & row.id.equals(record.id),
              ))
              .write(
                LocalEntityRecordsCompanion(
                  secondaryParentId: record.secondaryParentId == aliasId
                      ? Value(canonicalId)
                      : const Value.absent(),
                  dataJson: Value(jsonEncode(nextData)),
                  updatedAt: Value(now),
                ),
              );
          for (final pending in unresolved) {
            final nextPayload = _replaceApplicationReference(
              _payloadMap(pending.payloadJson),
              aliasId: aliasId,
              canonicalId: canonicalId,
            );
            await (database.update(
              database.localOutboxCommands,
            )..where((row) => row.commandId.equals(pending.commandId))).write(
              LocalOutboxCommandsCompanion(
                status: const Value('pending'),
                payloadJson: Value(jsonEncode(nextPayload)),
                attemptCount: const Value(0),
                nextAttemptAt: Value(now),
                lastError: const Value(null),
              ),
            );
          }
        });
        continue;
      }

      final commandId = _uuid.v4();
      final sequence = await DeviceIdentity.nextSequence(userId);
      await database.transaction(() async {
        await (database.update(database.localEntityRecords)..where(
              (row) => row.userId.equals(userId) & row.id.equals(record.id),
            ))
            .write(
              LocalEntityRecordsCompanion(
                secondaryParentId: record.secondaryParentId == aliasId
                    ? Value(canonicalId)
                    : const Value.absent(),
                dataJson: Value(jsonEncode(nextData)),
                revision: Value(record.revision + 1),
                updatedAt: Value(now),
                updatedByDeviceId: Value(currentDeviceId),
                lastCommandId: Value(commandId),
              ),
            );
        await database
            .into(database.localOutboxCommands)
            .insert(
              LocalOutboxCommandsCompanion.insert(
                commandId: commandId,
                userId: userId,
                deviceId: currentDeviceId,
                deviceSequence: sequence,
                entityType: record.entityType,
                entityId: record.id,
                commandType: 'update',
                baseRevision: record.revision,
                payloadJson: jsonEncode({'application_id': canonicalId}),
                clientTimestamp: now,
                createdAt: now,
              ),
            );
      });
    }
  }

  Map<String, Object?> _replaceApplicationReference(
    Map<String, Object?> source, {
    required String aliasId,
    required String canonicalId,
  }) {
    final result = <String, Object?>{...source};
    if (result['application_id'] == aliasId) {
      result['application_id'] = canonicalId;
    }
    final nested = result['data'];
    if (nested is Map) {
      final nestedMap = Map<String, Object?>.from(nested);
      if (nestedMap['application_id'] == aliasId) {
        nestedMap['application_id'] = canonicalId;
        result['data'] = nestedMap;
      }
    }
    return result;
  }

  Future<bool> _sendActivityContributionBatch(
    List<LocalOutboxCommand> commands, {
    required int generation,
    required String userId,
  }) async {
    _ensureCurrentOperation(generation, userId);
    final requestPayload = [
      for (final command in commands)
        {
          'command_id': command.commandId,
          'device_id': command.deviceId,
          'device_sequence': command.deviceSequence,
          'entity_id': command.entityId,
          'base_revision': command.baseRevision,
          'operation': command.commandType,
          'payload': jsonDecode(command.payloadJson),
        },
    ];
    final response = await client.rpc<Object?>(
      'apply_activity_contribution_batch',
      params: {'p_commands': requestPayload},
    );
    _recordTraffic(
      'rpc:activity_contributions_batch',
      uploaded: requestPayload,
      downloaded: response,
      fingerprint: 'activity_contributions:${commands.length}',
    );
    _ensureCurrentOperation(generation, userId);
    if (response is! List || response.length != commands.length) {
      throw const FormatException('Invalid contribution batch response');
    }
    var needsAttention = false;
    await database.transaction(() async {
      for (var index = 0; index < commands.length; index++) {
        _ensureCurrentOperation(generation, userId);
        final item = response[index];
        final result = item is Map && item['result'] is Map
            ? Map<String, dynamic>.from(item['result'] as Map)
            : <String, dynamic>{};
        final remoteStatus = result['status'] as String?;
        await (database.update(database.localOutboxCommands)
              ..where((row) => row.commandId.equals(commands[index].commandId)))
            .write(
              LocalOutboxCommandsCompanion(
                status: Value(
                  remoteStatus == 'accepted' ? 'accepted' : 'conflict',
                ),
                lastError: remoteStatus == 'accepted'
                    ? const Value.absent()
                    : Value(jsonEncode(result)),
              ),
            );
        needsAttention = needsAttention || remoteStatus != 'accepted';
      }
    });
    return needsAttention;
  }

  Future<void> pullChanges() {
    final existing = _pullFuture;
    if (existing != null) return existing;
    final userId = _startedForUserId;
    if (userId == null) return Future<void>.value();
    final generation = _accountGeneration;
    late final Future<void> operation;
    operation = _pullChangesTracked(generation, userId).whenComplete(() {
      if (identical(_pullFuture, operation)) {
        _pullFuture = null;
      }
    });
    _pullFuture = operation;
    return operation;
  }

  Future<void> _pullChangesTracked(int generation, String userId) async {
    try {
      _ensureCurrentOperation(generation, userId);
      if (_snapshotRetryRequired) {
        await _reconcileCanonicalState();
        _ensureCurrentOperation(generation, userId);
        if (_snapshotRetryRequired) return;
      }
      // Android can retain an HTTP request during a Wi-Fi/mobile hand-off.
      // Without a bounded request the in-flight flag stayed true forever,
      // leaving a reconnected device on an old canonical task state.  The
      // pull is idempotent, so a later retry is safe after this timeout.
      await _pullChangesInternal(
        generation,
        userId,
      ).timeout(const Duration(seconds: 15));
    } on _StaleSyncOperation {
      // Account switches invalidate the response without changing its cursor.
    } on _IncompleteCanonicalSnapshot {
      _setHealth(SyncHealth.attention);
    } on TimeoutException {
      if (_isCurrentOperation(generation, userId)) {
        _setHealth(SyncHealth.attention);
      }
    }
  }

  Future<void> _pullChangesInternal(int generation, String userId) async {
    _ensureCurrentOperation(generation, userId);
    final user = client.auth.currentUser;
    if (user == null) return;
    if (user.id != userId) throw const _StaleSyncOperation();
    _fallbackCheckAvailable = false;
    _setHealth(SyncHealth.syncing);
    final stateId = authoritativeSnapshotStateId(user.id);
    final state = await (database.select(
      database.localSyncStates,
    )..where((row) => row.id.equals(stateId))).getSingleOrNull();
    _ensureCurrentOperation(generation, userId);
    var sequence = state?.lastChangeSequence ?? 0;
    final affectedRoadmapIds = <String>{};

    while (true) {
      final rows = await client
          .from('sync_change_log')
          .select(
            'change_sequence,entity_type,entity_id,operation,entity_revision',
          )
          .gt('change_sequence', sequence)
          .order('change_sequence')
          .limit(250);
      _recordTraffic(
        'table:sync_change_log',
        downloaded: rows,
        fingerprint: 'after:$sequence',
      );
      _ensureCurrentOperation(generation, userId);
      if (rows.isEmpty) break;
      // A single entity (especially an active normalized Activity segment)
      // may appear many times in one change page.  Fetch its current
      // canonical row once instead of issuing one HTTP request per change.
      final latestByEntity = <String, Map<String, dynamic>>{};
      for (final raw in rows) {
        final change = Map<String, dynamic>.from(raw);
        final entityType = change['entity_type'] as String;
        final entityId = change['entity_id'] as String;
        final changeSequence = (change['change_sequence'] as num).toInt();
        latestByEntity['$entityType:$entityId'] = change;
        sequence = changeSequence;
      }
      await _pullChangedEntityBatch(
        latestByEntity.values,
        affectedRoadmapIds,
        generation: generation,
        userId: userId,
      );
      _ensureCurrentOperation(generation, userId);
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
    _ensureCurrentOperation(generation, userId);
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
    _ensureCurrentOperation(generation, userId);
    await _recalculateRoadmaps(affectedRoadmapIds);
    _ensureCurrentOperation(generation, userId);
    _fallbackCheckAvailable = true;
    await _supersedeCanonicalConflicts();
    _ensureCurrentOperation(generation, userId);
    await _settleHealth();
    _lastFallbackPullAt = DateTime.now().toUtc();
  }

  /// Applies one change-log page with a bounded number of network reads.
  ///
  /// This is deliberately independent of Realtime: a client that was asleep
  /// or missed broadcasts can catch up through the same efficient path.
  Future<void> _pullChangedEntityBatch(
    Iterable<Map<String, dynamic>> changes,
    Set<String> affectedRoadmapIds, {
    required int generation,
    required String userId,
  }) async {
    _ensureCurrentOperation(generation, userId);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final change in changes) {
      final entityType = change['entity_type'] as String;
      final entityId = change['entity_id'] as String;
      if (!await _shouldApplyRemoteEntity(entityType, userId: userId)) continue;
      if (await _hasPendingCommand(entityType, entityId, userId: userId)) {
        continue;
      }
      _ensureCurrentOperation(generation, userId);
      grouped.putIfAbsent(entityType, () => []).add(change);
    }
    for (final entry in grouped.entries) {
      final entityType = entry.key;
      final changesForType = entry.value;
      for (var offset = 0; offset < changesForType.length; offset += 100) {
        final page = changesForType.sublist(
          offset,
          (offset + 100).clamp(0, changesForType.length).toInt(),
        );
        final ids = page
            .map((change) => change['entity_id'] as String)
            .toList(growable: false);
        final remoteRows = await client
            .from(entityType)
            .select()
            .inFilter('id', ids);
        _recordTraffic(
          'table:$entityType',
          uploaded: {'ids': ids},
          downloaded: remoteRows,
          fingerprint: '$entityType:${ids.join(',')}',
        );
        _ensureCurrentOperation(generation, userId);
        final rowsById = {
          for (final raw in remoteRows)
            (raw as Map)['id'] as String: Map<String, dynamic>.from(raw),
        };
        for (final change in page) {
          final entityId = change['entity_id'] as String;
          final row = rowsById[entityId];
          if (row == null) continue;
          await _applyEntity(entityType, row);
          _ensureCurrentOperation(generation, userId);
          affectedRoadmapIds.addAll(
            await _roadmapIdsForEntity(entityType, entityId),
          );
        }
      }
    }
  }

  /// Detailed Activity records are intentionally device-local unless the user
  /// opted in.  Approved contributions carry the cross-device task effect;
  /// they are the only Activity timeline records needed by another device in
  /// the default privacy mode.
  Future<bool> _shouldApplyRemoteEntity(
    String entityType, {
    String? userId,
  }) async {
    const localOnlyByDefault = <String>{
      'activity_segments',
      'activity_attributions',
      'activity_review_queue',
      'classification_feedback',
    };
    if (!localOnlyByDefault.contains(entityType)) return true;
    final scopedUserId = userId ?? client.auth.currentUser?.id;
    if (scopedUserId == null) return false;
    final settings =
        await (database.select(database.localAppSettings)
              ..where((row) => row.id.equals(localAppSettingsId(scopedUserId))))
            .getSingleOrNull();
    final privacyPolicy = await ActivityPrivacyPolicy.load(
      database,
      scopedUserId,
    );
    return privacyPolicy.allowsDetailedActivityUpload(settings);
  }

  Map<String, dynamic> _canonicalPayload(
    LocalOutboxCommand command,
    Map<String, dynamic> payload,
  ) {
    if (command.entityType == 'task_health_summaries') {
      final sourceApplications = payload['source_applications'];
      final source =
          payload['source'] ??
          (sourceApplications is List
              ? sourceApplications.whereType<String>().join(', ')
              : '');
      final start = _instant(
        payload['interval_start_at'] ?? payload['window_start_at'],
      );
      return <String, dynamic>{
        'summary_date':
            payload['summary_date'] ??
            (start ?? DateTime.now().toUtc())
                .toIso8601String()
                .split('T')
                .first,
        'source': source,
        'summary_type': payload['summary_type'] ?? payload['metric_type'],
        'value': payload['value'],
        'unit': payload['unit'],
        'record_count': payload['record_count'] ?? 0,
        'source_applications': sourceApplications ?? const <String>[],
        'source_record_counts':
            payload['source_record_counts'] ?? const <String, int>{},
        'last_updated_at': payload['last_updated_at'],
        'window_start_at':
            payload['window_start_at'] ?? payload['interval_start_at'],
        'window_end_at': payload['window_end_at'] ?? payload['interval_end_at'],
        'raw_record_count':
            payload['raw_record_count'] ?? payload['record_count'] ?? 0,
        'discarded_overlap_count': payload['discarded_overlap_count'] ?? 0,
        'task_occurrence_id': payload['task_occurrence_id'],
        'execution_session_id': payload['execution_session_id'],
        'interval_start_at': payload['interval_start_at'],
        'interval_end_at': payload['interval_end_at'],
        'allocation_method': payload['allocation_method'],
        'estimated': payload['estimated'] == true,
        'provenance': payload['provenance'],
        'overlap_fraction': payload['overlap_fraction'],
        'height_cm': payload['height_cm'],
        'stride_factor': payload['stride_factor'],
      };
    }
    if (command.entityType == 'checklist_items' &&
        payload.containsKey('required') &&
        !payload.containsKey('is_required')) {
      return {
        for (final entry in payload.entries)
          if (entry.key != 'required') entry.key: entry.value,
        'is_required': payload['required'],
      };
    }
    if (!const {
      'roadmap_milestones',
      'roadmap_checkpoints',
    }.contains(command.entityType)) {
      return payload;
    }

    // Older v0.0.26 builds placed planning-only fields at the top level.
    // They have always belonged in `data`, so repair the already-queued
    // idempotent command instead of creating a duplicate roadmap record.
    final legacyDataKeys = command.entityType == 'roadmap_milestones'
        ? const {'completion_rule', 'notes'}
        : const {'required', 'completion_rule', 'notes'};
    final legacyValues = <String, dynamic>{
      for (final key in legacyDataKeys)
        if (payload.containsKey(key)) key: payload[key],
    };
    if (legacyValues.isEmpty) return payload;
    final existingData = payload['data'] is Map
        ? Map<String, dynamic>.from(payload['data'] as Map)
        : <String, dynamic>{};
    return {
      for (final entry in payload.entries)
        if (!legacyDataKeys.contains(entry.key)) entry.key: entry.value,
      'data': {...existingData, ...legacyValues},
    };
  }

  Future<void> _supersedeCanonicalConflicts() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    await _reconcileRemoteConflictDecisions(user.id);
    await _reconcileTaskOccurrenceAliases(user.id);
    await _reconcileRoadmapTaskLinkAliases(user.id);
    await _reconcileLegacyActivityCommandConflicts(user.id);
    await _reconcileDuplicateCreates(user.id);
    await _reconcileStaleLifecycleConflicts(user.id);
    await _retireSafeLegacyTransportConflicts(user.id);
    await _resolveRemoteCanonicalConflictHistory(user.id);
  }

  Future<void> _reconcileRemoteConflictDecisions(String userId) async {
    final originals =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.isIn(const ['conflict', 'resolution_pending']) &
                  row.entityType.equals('sync_conflict_decisions').not(),
            ))
            .get();
    if (originals.isEmpty) return;
    final originalById = {
      for (final command in originals) command.commandId: command,
    };
    try {
      final rows = await client
          .from('sync_conflict_decisions')
          .select(
            'id,original_command_id,strategy,decision_status,result,created_at',
          )
          .inFilter('original_command_id', originalById.keys.toList())
          .eq('decision_status', 'accepted')
          .order('created_at', ascending: false)
          .limit(250);
      final acceptedByOriginal = <String, Map<String, dynamic>>{};
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final originalId = row['original_command_id'] as String?;
        if (originalId != null) {
          acceptedByOriginal.putIfAbsent(originalId, () => row);
        }
      }
      for (final entry in acceptedByOriginal.entries) {
        final command = originalById[entry.key];
        if (command == null) continue;
        final row = entry.value;
        final strategy = row['strategy'] as String? ?? 'already_applied';
        final result = row['result'] is Map
            ? Map<String, dynamic>.from(row['result'] as Map)
            : const <String, dynamic>{};
        final canonicalType =
            result['canonical_entity_type'] as String? ?? command.entityType;
        final canonical = result['canonical_payload'] is Map
            ? Map<String, dynamic>.from(result['canonical_payload'] as Map)
            : const <String, dynamic>{};
        if (canonical.isNotEmpty) {
          await _applyEntity(canonicalType, canonical);
        }
        await database.transaction(() async {
          await (database.update(database.localOutboxCommands)..where(
                (outbox) =>
                    outbox.userId.equals(userId) &
                    outbox.commandId.equals(command.commandId) &
                    outbox.status.isIn(const [
                      'conflict',
                      'resolution_pending',
                    ]),
              ))
              .write(
                LocalOutboxCommandsCompanion(
                  status: Value(
                    strategy == 'discarded_local_change'
                        ? 'discarded_by_user'
                        : 'superseded',
                  ),
                  nextAttemptAt: const Value(null),
                  lastError: Value(
                    jsonEncode({
                      'reason': strategy,
                      'decision_id': row['id'],
                      'accepted_on_another_device': true,
                    }),
                  ),
                ),
              );
          final pendingDecisions =
              await (database.select(database.localOutboxCommands)..where(
                    (outbox) =>
                        outbox.userId.equals(userId) &
                        outbox.entityType.equals('sync_conflict_decisions') &
                        outbox.status.equals('pending'),
                  ))
                  .get();
          for (final decision in pendingDecisions) {
            final payload = _payloadMap(decision.payloadJson);
            if (payload['original_command_id'] != command.commandId) continue;
            await (database.update(database.localOutboxCommands)..where(
                  (outbox) => outbox.commandId.equals(decision.commandId),
                ))
                .write(
                  LocalOutboxCommandsCompanion(
                    status: const Value('superseded'),
                    nextAttemptAt: const Value(null),
                    lastError: Value(
                      jsonEncode({
                        'reason': 'decision_already_applied',
                        'accepted_decision_id': row['id'],
                      }),
                    ),
                  ),
                );
          }
        });
      }
    } catch (_) {
      // A compact decision pull is a recovery path. The original conflicting
      // command remains stopped while its durable decision command retries.
    }
  }

  /// Converts v0.0.26's split Activity writes into canonical success.
  ///
  /// Those builds sent review, attribution, contribution, and rule mutations
  /// independently. A semantic contribution or review could already exist
  /// while another command was reported as `unique_constraint` or
  /// `revision_mismatch`. Canonical proof is required before retiring a
  /// command; no duration is added during this repair.
  Future<void> _reconcileLegacyActivityCommandConflicts(String userId) async {
    final candidates =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('conflict') &
                  row.entityType.isIn(const [
                    'activity_contributions',
                    'activity_review_queue',
                    'application_rules',
                  ]),
            ))
            .get();
    for (final command in candidates) {
      final errorText = command.lastError?.toLowerCase() ?? '';
      final reason =
          _payloadMap(command.lastError ?? '')['reason'] as String? ?? '';
      final isExpectedConvergence =
          reason == 'revision_mismatch' ||
          reason == 'unique_constraint' ||
          reason == 'invalid_command_contract' ||
          errorText.contains('unique_constraint') ||
          errorText.contains('invalid_command_contract') ||
          errorText.contains('23505');
      if (!isExpectedConvergence) continue;
      final payload = _payloadMap(command.payloadJson);
      try {
        Map<String, dynamic>? canonical;
        if (command.entityType == 'activity_contributions') {
          final segmentId = payload['activity_segment_id'] as String?;
          final targetType = payload['target_type'] as String?;
          final targetId = payload['target_id'] as String?;
          final contributionType = payload['contribution_type'] as String?;
          if (segmentId == null ||
              targetType == null ||
              contributionType == null) {
            continue;
          }
          var query = client
              .from('activity_contributions')
              .select()
              .eq('activity_segment_id', segmentId)
              .eq('target_type', targetType)
              .eq('contribution_type', contributionType)
              .isFilter('deleted_at', null);
          query = targetId == null
              ? query.isFilter('target_id', null)
              : query.eq('target_id', targetId);
          final rows = await query.limit(1);
          if (rows.isNotEmpty) {
            canonical = Map<String, dynamic>.from(rows.first);
          }
        } else if (command.entityType == 'activity_review_queue') {
          final exact = await client
              .from('activity_review_queue')
              .select()
              .eq('id', command.entityId)
              .maybeSingle();
          if (exact != null) {
            canonical = Map<String, dynamic>.from(exact);
          } else {
            final segmentId = payload['activity_segment_id'] as String?;
            final reviewReason = payload['review_reason'] as String?;
            if (segmentId != null && reviewReason != null) {
              final rows = await client
                  .from('activity_review_queue')
                  .select()
                  .eq('activity_segment_id', segmentId)
                  .eq('review_reason', reviewReason)
                  .isFilter('deleted_at', null)
                  .limit(1);
              if (rows.isNotEmpty) {
                canonical = Map<String, dynamic>.from(rows.first);
              }
            }
          }
        } else if (command.entityType == 'application_rules') {
          final applicationId = payload['application_id'] as String?;
          final scopeType = payload['scope_type'] as String?;
          final scopeId = payload['scope_id'] as String?;
          if (applicationId != null && scopeType != null) {
            var query = client
                .from('application_rules')
                .select()
                .eq('application_id', applicationId)
                .eq('scope_type', scopeType)
                .isFilter('deleted_at', null);
            query = scopeId == null
                ? query.isFilter('scope_id', null)
                : query.eq('scope_id', scopeId);
            final rows = await query.limit(1);
            if (rows.isNotEmpty) {
              canonical = Map<String, dynamic>.from(rows.first);
            }
          }
        }
        if (canonical != null) {
          if (command.entityType != 'activity_review_queue' ||
              canonical['id'] == command.entityId) {
            await _applyEntity(command.entityType, canonical);
          }
          await _supersedeCommands([command]);
          await _markRemoteConflictResolved(
            command,
            strategy: 'idempotent_duplicate_create',
          );
          continue;
        }
        if (command.entityType == 'application_rules' &&
            (reason == 'invalid_command_contract' ||
                errorText.contains('invalid_command_contract'))) {
          // The legacy command was rejected before a canonical rule existed.
          // Replay its same UUID and payload once under a fresh idempotency
          // command; never retry the rejected command ID in a loop.
          final replacementId = _uuid.v4();
          final now = DateTime.now().toUtc();
          await database.transaction(() async {
            await _supersedeCommands([command]);
            await database
                .into(database.localOutboxCommands)
                .insert(
                  LocalOutboxCommandsCompanion.insert(
                    commandId: replacementId,
                    userId: command.userId,
                    deviceId: command.deviceId,
                    deviceSequence: await DeviceIdentity.nextSequence(userId),
                    entityType: command.entityType,
                    entityId: command.entityId,
                    commandType: command.commandType,
                    baseRevision: command.baseRevision,
                    payloadJson: command.payloadJson,
                    clientTimestamp: now,
                    createdAt: now,
                  ),
                );
          });
          await _markRemoteConflictResolved(
            command,
            strategy: 'local_command_already_superseded',
          );
        }
      } catch (_) {
        // Only canonical proof can retire Activity history. A transient read
        // failure is retried on the next incremental synchronization pass.
      }
    }
  }

  /// Keeps server diagnostics aligned with local automatic convergence.
  ///
  /// Older Android builds recorded companion lifecycle conflicts remotely,
  /// then a newer client safely retired the local commands. Without this pass
  /// Supabase continued to report those already-resolved rows as unresolved.
  Future<void> _resolveRemoteCanonicalConflictHistory(String userId) async {
    try {
      final settings =
          await (database.select(database.localAppSettings)
                ..where((row) => row.id.equals(localAppSettingsId(userId))))
              .getSingleOrNull();
      final detailedActivitySyncEnabled = (await ActivityPrivacyPolicy.load(
        database,
        userId,
      )).allowsDetailedActivityUpload(settings);
      final rows = await client
          .from('sync_conflicts')
          .select(
            'id,command_id,entity_type,entity_id,conflict_type,'
            'local_payload,resolution_status',
          )
          .eq('resolution_status', 'unresolved')
          .limit(250);
      for (final raw in rows) {
        final conflict = Map<String, dynamic>.from(raw);
        final conflictId = conflict['id'] as String?;
        final commandId = conflict['command_id'] as String?;
        final entityType = conflict['entity_type'] as String?;
        final conflictType = conflict['conflict_type'] as String?;
        final payloadValue = conflict['local_payload'];
        final payload = payloadValue is Map
            ? Map<String, dynamic>.from(payloadValue)
            : const <String, dynamic>{};
        String? strategy;
        final localCommand = commandId == null
            ? null
            : await (database.select(database.localOutboxCommands)..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.commandId.equals(commandId),
                  ))
                  .getSingleOrNull();
        if (localCommand?.status == 'superseded') {
          strategy = 'local_command_already_superseded';
        } else if (conflictType == 'revision_mismatch' &&
            entityType != null &&
            isSemanticLifecyclePayload(entityType, payload)) {
          strategy = 'canonical_lifecycle_superseded';
        } else if (entityType == 'activity_review_queue' &&
            !detailedActivitySyncEnabled) {
          strategy = 'device_local_activity_not_shared';
        }
        if (conflictId == null || strategy == null) continue;
        await client.rpc<Object?>(
          'resolve_sync_conflict_v0026',
          params: {'p_conflict_id': conflictId, 'p_strategy': strategy},
        );
      }
    } catch (_) {
      // Conflict history is diagnostic metadata. A connectivity or policy
      // failure here cannot block canonical task delivery.
    }
  }

  /// Runtime transitions update both the active occurrence and its execution
  /// session.  An older online client can have one of those companion updates
  /// rejected after another device has already accepted the canonical
  /// transition. These narrowly-scoped payloads are companion cache writes,
  /// not independent task edits. Pull the canonical row and retire the stale
  /// lifecycle retry for both current and historical sessions.
  Future<void> _reconcileStaleLifecycleConflicts(String userId) async {
    final candidates =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('conflict') &
                  row.commandType.equals('update') &
                  row.entityType.isIn(const [
                    'task_occurrences',
                    'execution_sessions',
                  ]),
            ))
            .get();
    for (final command in candidates) {
      if (_payloadMap(command.lastError ?? '')['reason'] !=
          'revision_mismatch') {
        continue;
      }
      final payload = _payloadMap(command.payloadJson);
      if (!isSemanticLifecyclePayload(command.entityType, payload)) {
        continue;
      }
      try {
        if (command.entityType == 'task_occurrences') {
          final remote = await client
              .from('task_occurrences')
              .select()
              .eq('id', command.entityId)
              .maybeSingle();
          if (remote == null) continue;
          await _applyTask(Map<String, dynamic>.from(remote));
        } else {
          final remote = await client
              .from('execution_sessions')
              .select()
              .eq('id', command.entityId)
              .maybeSingle();
          if (remote == null) continue;
          await _applyEntity(
            'execution_sessions',
            Map<String, dynamic>.from(remote),
          );
        }
        await (database.update(
          database.localOutboxCommands,
        )..where((row) => row.commandId.equals(command.commandId))).write(
          const LocalOutboxCommandsCompanion(
            status: Value('superseded'),
            lastError: Value(null),
          ),
        );
        await _markRemoteConflictResolved(
          command,
          strategy: 'canonical_lifecycle_superseded',
        );
      } catch (_) {
        // Keep the entry visible only when the canonical row cannot be read.
        // A later healthy pull will retry this narrow reconciliation.
      }
    }
  }

  /// Permanent entity UUIDs make a same-ID create idempotent across devices.
  /// If Supabase proves that the exact active owner row already exists, the
  /// rejected create is not competing user work and can be retired locally.
  ///
  /// This is intentionally the same recovery used immediately after a server
  /// response and during startup repair, so no retry timing difference can
  /// turn a stale `task_domains` create into user-visible sync attention.
  Future<bool> _retireProvenDuplicateCreate(
    LocalOutboxCommand command, {
    required String? reason,
    required Object? serverRevision,
    required String userId,
    int? generation,
  }) async {
    if (!isIdempotentDuplicateCreateConflict(
      commandType: command.commandType,
      reason: reason,
      serverRevision: serverRevision,
    )) {
      return false;
    }
    try {
      if (generation != null) _ensureCurrentOperation(generation, userId);
      final remoteEntityType = remoteEntityTypeForCommand(command.entityType);
      final remote = await client
          .from(remoteEntityType)
          .select()
          .eq('id', command.entityId)
          .maybeSingle();
      if (generation != null) _ensureCurrentOperation(generation, userId);
      final canonical = remote == null
          ? null
          : Map<String, dynamic>.from(remote);
      if (canonical == null) return false;
      if (!isProvenCanonicalDuplicateCreate(
        commandType: command.commandType,
        reason: reason,
        serverRevision: serverRevision,
        commandEntityId: command.entityId,
        userId: userId,
        canonicalRow: canonical,
      )) {
        return false;
      }
      await _applyEntity(remoteEntityType, canonical);
      if (generation != null) _ensureCurrentOperation(generation, userId);
      await (database.update(database.localOutboxCommands)..where(
            (row) =>
                row.userId.equals(userId) &
                row.commandId.equals(command.commandId) &
                row.status.equals('conflict'),
          ))
          .write(
            const LocalOutboxCommandsCompanion(
              status: Value('superseded'),
              lastError: Value(null),
              nextAttemptAt: Value(null),
            ),
          );
      // Diagnostics reconciliation is explicitly best-effort inside this
      // helper. Local convergence must not depend on historical conflict rows
      // being writable on the current server schema.
      await _markRemoteConflictResolved(
        command,
        strategy: 'idempotent_duplicate_create',
      );
      return true;
    } on _StaleSyncOperation {
      rethrow;
    } catch (_) {
      // No canonical proof means leave the actual user conflict untouched.
      return false;
    }
  }

  Future<void> _reconcileDuplicateCreates(String userId) async {
    final candidates =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('conflict') &
                  row.commandType.equals('create'),
            ))
            .get();
    for (final command in candidates) {
      final error = _payloadMap(command.lastError ?? '');
      await _retireProvenDuplicateCreate(
        command,
        reason: error['reason'] as String?,
        serverRevision: error['server_revision'],
        userId: userId,
      );
    }
  }

  /// Adopts the canonical UUID for a recurring occurrence that an older
  /// device created with a second random UUID.
  ///
  /// Supabase's `(user_id, template_id, occurrence_key)` uniqueness proves
  /// that both rows describe the same occurrence. References and queued
  /// child commands are repointed before the duplicate local card is hidden,
  /// so roadmap links do not retry `invalid_task_relationship` forever.
  Future<void> _reconcileTaskOccurrenceAliases(String userId) async {
    final candidates =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('conflict') &
                  row.entityType.equals('task_occurrences') &
                  row.commandType.equals('create'),
            ))
            .get();
    for (final command in candidates) {
      final error = _payloadMap(command.lastError ?? '');
      if (error['reason'] != 'unique_constraint') continue;
      final localTask =
          await (database.select(database.localTasks)..where(
                (row) =>
                    row.userId.equals(userId) & row.id.equals(command.entityId),
              ))
              .getSingleOrNull();
      final payload = _payloadMap(command.payloadJson);
      final templateId =
          localTask?.templateId ?? payload['template_id'] as String?;
      final occurrenceKey =
          localTask?.occurrenceKey ?? payload['occurrence_key'] as String?;
      if (localTask == null ||
          templateId == null ||
          templateId.isEmpty ||
          occurrenceKey == null ||
          occurrenceKey.isEmpty) {
        continue;
      }
      try {
        final rows = await client
            .from('task_occurrences')
            .select()
            .eq('template_id', templateId)
            .eq('occurrence_key', occurrenceKey)
            .isFilter('deleted_at', null)
            .limit(1);
        if (rows.isEmpty) continue;
        final remote = Map<String, dynamic>.from(rows.first);
        if (remote['user_id'] != userId) continue;
        final canonicalId = remote['id'] as String?;
        if (canonicalId == null || canonicalId == command.entityId) continue;
        await _applyEntity('task_occurrences', remote);

        final canonicalTask =
            await (database.select(database.localTasks)..where(
                  (row) =>
                      row.userId.equals(userId) & row.id.equals(canonicalId),
                ))
                .getSingleOrNull();
        if (canonicalTask == null) continue;
        final now = DateTime.now().toUtc();
        final mergedActive =
            localTask.activeDurationMs > canonicalTask.activeDurationMs
            ? localTask.activeDurationMs
            : canonicalTask.activeDurationMs;
        final mergedPaused =
            localTask.pausedDurationMs > canonicalTask.pausedDurationMs
            ? localTask.pausedDurationMs
            : canonicalTask.pausedDurationMs;
        final mergedIdle =
            localTask.idleDurationMs > canonicalTask.idleDurationMs
            ? localTask.idleDurationMs
            : canonicalTask.idleDurationMs;
        final mergedProgress = localTask.progress > canonicalTask.progress
            ? localTask.progress
            : canonicalTask.progress;
        final localIsNewer = localTask.updatedAt.isAfter(
          _instant(remote['updated_at']) ?? canonicalTask.updatedAt,
        );
        final mergedStatus = localIsNewer
            ? localTask.status
            : canonicalTask.status;
        final needsCanonicalUpdate =
            mergedActive != canonicalTask.activeDurationMs ||
            mergedPaused != canonicalTask.pausedDurationMs ||
            mergedIdle != canonicalTask.idleDurationMs ||
            mergedProgress != canonicalTask.progress ||
            mergedStatus != canonicalTask.status;

        await database.transaction(() async {
          await (database.update(database.localTasks)..where(
                (row) => row.userId.equals(userId) & row.id.equals(canonicalId),
              ))
              .write(
                LocalTasksCompanion(
                  title: Value(
                    localIsNewer ? localTask.title : canonicalTask.title,
                  ),
                  description: Value(
                    localIsNewer
                        ? localTask.description
                        : canonicalTask.description,
                  ),
                  status: Value(mergedStatus),
                  activeDurationMs: Value(mergedActive),
                  pausedDurationMs: Value(mergedPaused),
                  idleDurationMs: Value(mergedIdle),
                  progress: Value(mergedProgress),
                  updatedAt: Value(
                    localIsNewer
                        ? localTask.updatedAt
                        : canonicalTask.updatedAt,
                  ),
                ),
              );
          await (database.update(database.localTasks)..where(
                (row) =>
                    row.userId.equals(userId) & row.id.equals(command.entityId),
              ))
              .write(
                LocalTasksCompanion(
                  deletedAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
          await (database.update(database.localRuntimeStates)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.activeTaskId.equals(command.entityId),
              ))
              .write(
                LocalRuntimeStatesCompanion(
                  activeTaskId: Value(canonicalId),
                  updatedAt: Value(now),
                ),
              );
          await (database.update(database.localAttributions)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.targetId.equals(command.entityId),
              ))
              .write(LocalAttributionsCompanion(targetId: Value(canonicalId)));
          await (database.update(database.localContributions)..where(
                (row) =>
                    row.userId.equals(userId) &
                    row.targetId.equals(command.entityId),
              ))
              .write(LocalContributionsCompanion(targetId: Value(canonicalId)));

          final records = await (database.select(
            database.localEntityRecords,
          )..where((row) => row.userId.equals(userId))).get();
          for (final record in records) {
            final replaced = _replaceUuidInValue(
              _payloadMap(record.dataJson),
              command.entityId,
              canonicalId,
            );
            final parentChanged = record.parentId == command.entityId;
            final secondaryChanged =
                record.secondaryParentId == command.entityId;
            if (!parentChanged &&
                !secondaryChanged &&
                jsonEncode(replaced) == record.dataJson) {
              continue;
            }
            await (database.update(database.localEntityRecords)..where(
                  (row) => row.userId.equals(userId) & row.id.equals(record.id),
                ))
                .write(
                  LocalEntityRecordsCompanion(
                    parentId: parentChanged
                        ? Value(canonicalId)
                        : const Value.absent(),
                    secondaryParentId: secondaryChanged
                        ? Value(canonicalId)
                        : const Value.absent(),
                    dataJson: Value(jsonEncode(replaced)),
                    updatedAt: Value(now),
                  ),
                );
          }

          final queued =
              await (database.select(database.localOutboxCommands)..where(
                    (row) =>
                        row.userId.equals(userId) &
                        row.status.isIn(const ['pending', 'conflict']),
                  ))
                  .get();
          for (final queuedCommand in queued) {
            if (queuedCommand.entityType == 'task_occurrences' &&
                queuedCommand.entityId == command.entityId) {
              await _supersedeCommands([queuedCommand]);
              continue;
            }
            final currentPayload = _payloadMap(queuedCommand.payloadJson);
            final repairedPayload = _replaceUuidInValue(
              currentPayload,
              command.entityId,
              canonicalId,
            );
            if (jsonEncode(repairedPayload) == jsonEncode(currentPayload)) {
              continue;
            }
            await (database.update(database.localOutboxCommands)..where(
                  (row) => row.commandId.equals(queuedCommand.commandId),
                ))
                .write(
                  LocalOutboxCommandsCompanion(
                    payloadJson: Value(jsonEncode(repairedPayload)),
                    status: const Value('pending'),
                    attemptCount: const Value(0),
                    nextAttemptAt: Value(now),
                    lastError: const Value(null),
                  ),
                );
          }

          if (needsCanonicalUpdate) {
            await database
                .into(database.localOutboxCommands)
                .insert(
                  LocalOutboxCommandsCompanion.insert(
                    commandId: _uuid.v4(),
                    userId: userId,
                    deviceId: await DeviceIdentity.accountId(userId),
                    deviceSequence: await DeviceIdentity.nextSequence(userId),
                    entityType: 'task_occurrences',
                    entityId: canonicalId,
                    commandType: 'update',
                    baseRevision: (remote['revision'] as num?)?.toInt() ?? 1,
                    payloadJson: jsonEncode({
                      'title': localIsNewer
                          ? localTask.title
                          : canonicalTask.title,
                      'description': localIsNewer
                          ? localTask.description
                          : canonicalTask.description,
                      'status': mergedStatus,
                      'active_duration_ms': mergedActive,
                      'paused_duration_ms': mergedPaused,
                      'idle_duration_ms': mergedIdle,
                      'progress': mergedProgress,
                    }),
                    clientTimestamp: now,
                    createdAt: now,
                  ),
                );
          }
        });
        await _markRemoteConflictResolved(
          command,
          strategy: 'idempotent_duplicate_create',
        );
      } catch (_) {
        // Keep the alias visible in diagnostics until canonical ownership and
        // the semantic occurrence identity can be proven online.
      }
    }
  }

  Future<void> _reconcileRoadmapTaskLinkAliases(String userId) async {
    final candidates =
        await (database.select(database.localOutboxCommands)..where(
              (row) =>
                  row.userId.equals(userId) &
                  row.status.equals('conflict') &
                  row.entityType.equals('roadmap_task_links') &
                  row.commandType.equals('create'),
            ))
            .get();
    for (final command in candidates) {
      final error = _payloadMap(command.lastError ?? '');
      if (error['reason'] != 'unique_constraint') continue;
      final payload = _payloadMap(command.payloadJson);
      final roadmapId = _uuidOrNull(payload['roadmap_id'] as String?);
      final taskId = _uuidOrNull(payload['task_id'] as String?);
      if (roadmapId == null || taskId == null) continue;
      try {
        var query = client
            .from('roadmap_task_links')
            .select()
            .eq('roadmap_id', roadmapId)
            .eq('task_id', taskId)
            .eq(
              'relationship_type',
              payload['relationship_type'] as String? ?? 'primary',
            )
            .isFilter('deleted_at', null);
        for (final field in const [
          'phase_id',
          'milestone_id',
          'checkpoint_id',
        ]) {
          final value = _uuidOrNull(payload[field] as String?);
          query = value == null
              ? query.isFilter(field, null)
              : query.eq(field, value);
        }
        final rows = await query.limit(1);
        if (rows.isEmpty) continue;
        final remote = Map<String, dynamic>.from(rows.first);
        if (remote['user_id'] != userId) continue;
        await _applyEntity('roadmap_task_links', remote);
        final now = DateTime.now().toUtc();
        await database.transaction(() async {
          await _supersedeCommands([command]);
          await (database.update(database.localEntityRecords)..where(
                (row) =>
                    row.userId.equals(userId) & row.id.equals(command.entityId),
              ))
              .write(
                LocalEntityRecordsCompanion(
                  deletedAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
        });
        await _markRemoteConflictResolved(
          command,
          strategy: 'idempotent_duplicate_create',
        );
      } catch (_) {
        // Retry only after the canonical semantic relationship can be read.
      }
    }
  }

  Object? _replaceUuidInValue(Object? value, String oldId, String newId) {
    if (value is String) return value == oldId ? newId : value;
    if (value is List) {
      return [
        for (final item in value) _replaceUuidInValue(item, oldId, newId),
      ];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): _replaceUuidInValue(entry.value, oldId, newId),
      };
    }
    return value;
  }

  Future<Set<String>> _roadmapIdsForEntity(
    String entityType,
    String entityId,
  ) async {
    if (entityType == 'roadmaps') return {entityId};
    if (entityType == 'task_occurrences') {
      final task = await (database.select(
        database.localTasks,
      )..where((row) => row.id.equals(entityId))).getSingleOrNull();
      return task?.roadmapId == null ? const {} : {task!.roadmapId!};
    }
    if (entityType.startsWith('roadmap_')) {
      final record = await (database.select(
        database.localEntityRecords,
      )..where((row) => row.id.equals(entityId))).getSingleOrNull();
      return record?.parentId == null ? const {} : {record!.parentId!};
    }
    if (entityType == 'activity_contributions') {
      final contribution = await (database.select(
        database.localContributions,
      )..where((row) => row.id.equals(entityId))).getSingleOrNull();
      if (contribution?.targetType != 'task_occurrence' ||
          contribution?.targetId == null) {
        return const {};
      }
      final task =
          await (database.select(database.localTasks)
                ..where((row) => row.id.equals(contribution!.targetId!)))
              .getSingleOrNull();
      return task?.roadmapId == null ? const {} : {task!.roadmapId!};
    }
    return const {};
  }

  Future<void> _recalculateRoadmaps([Set<String>? roadmapIds]) async {
    final ids =
        roadmapIds ??
        (await (database.select(
              database.localRoadmaps,
            )..where((row) => row.deletedAt.isNull())).get())
            .map((roadmap) => roadmap.id)
            .toSet();
    if (ids.isEmpty) return;
    final repository = RoadmapRepository(database, client);
    for (final id in ids) {
      await repository.recalculateProgress(id, synchronize: false);
    }
  }

  Future<void> _settleHealth() async {
    final snapshot = await getSnapshot(checkRemoteDevices: false);
    _setHealth(
      snapshot.connectionAvailable == false
          ? SyncHealth.offline
          : snapshot.failedChanges > 0 || snapshot.conflicts > 0
          ? SyncHealth.attention
          : snapshot.pendingChanges > 0
          ? SyncHealth.syncing
          : !snapshot.liveConnectionAvailable
          ? SyncHealth.attention
          : SyncHealth.idle,
    );
  }

  Future<SyncSnapshot> getSnapshot({bool checkRemoteDevices = true}) async {
    final user = client.auth.currentUser;
    final connectivity = await Connectivity().checkConnectivity();
    final online = connectivity.any(
      (result) => result != ConnectivityResult.none,
    );
    final pendingExpression = database.localOutboxCommands.status.equals(
      'pending',
    );
    // A retryable pending command is durable work, not failed user data.
    // Temporary network/server interruptions stay in the normal synchronizing
    // state. Only a deterministic server conflict requires attention.
    final failedExpression = database.localOutboxCommands.status.equals(
      'conflict',
    );
    Future<int> count(Expression<bool> expression) {
      return (database.selectOnly(database.localOutboxCommands)
            ..addColumns([database.localOutboxCommands.commandId.count()])
            ..where(
              expression &
                  database.localOutboxCommands.userId.equals(
                    user?.id ?? '__signed_out__',
                  ),
            ))
          .map(
            (row) =>
                row.read(database.localOutboxCommands.commandId.count()) ?? 0,
          )
          .getSingle();
    }

    final pending = await count(pendingExpression);
    final failed = await count(failedExpression);
    final conflicts = await count(
      database.localOutboxCommands.status.equals('conflict'),
    );
    final diagnosticRows =
        await (database.select(database.localOutboxCommands)
              ..where(
                (row) =>
                    row.userId.equals(user?.id ?? '__signed_out__') &
                    row.status.isIn(const ['pending', 'conflict']),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
              ..limit(12))
            .get();
    final diagnosticProblems = [
      for (final command in diagnosticRows)
        '${command.status} ${command.entityType}/${command.commandType}: '
            '${_diagnosticReason(command.lastError)}',
    ];
    final state = user == null
        ? null
        : await (database.select(database.localSyncStates)..where(
                (row) => row.id.equals(authoritativeSnapshotStateId(user.id)),
              ))
              .getSingleOrNull();
    final currentDeviceId = user == null
        ? null
        : await DeviceIdentity.accountId(user.id);
    List<Map<String, dynamic>> devices = const [];
    if (checkRemoteDevices && online && user != null) {
      try {
        devices =
            (await client
                    .from('account_devices')
                    .select(
                      'id,device_name,platform,app_version,last_seen_at,revoked_at',
                    )
                    .isFilter('deleted_at', null)
                    .isFilter('revoked_at', null)
                    .order('last_seen_at', ascending: false))
                .map(Map<String, dynamic>.from)
                .toList();
      } catch (_) {
        devices = const [];
      }
    }
    final derived = deriveSyncHealth(
      online: online,
      operationInFlight:
          _synchronizeOperation.inFlight != null ||
          _pullFuture != null ||
          _drainOperation.inFlight != null ||
          _snapshotFuture != null,
      pendingChanges: pending,
      failedChanges: failed,
      conflicts: conflicts,
      recoveryConnectionAvailable:
          _liveConnectionAvailable || _fallbackCheckAvailable,
    );
    return SyncSnapshot(
      health: derived,
      pendingChanges: pending,
      failedChanges: failed,
      conflicts: conflicts,
      lastSuccessfulSync: state?.updatedAt.toLocal(),
      connectionAvailable: online,
      liveConnectionAvailable:
          _liveConnectionAvailable || _fallbackCheckAvailable,
      currentDeviceId: currentDeviceId,
      deviceName: DeviceIdentity.displayName,
      accountEmail: user?.email,
      otherDevices: devices,
      diagnosticProblems: diagnosticProblems,
    );
  }

  String _diagnosticReason(String? raw) {
    final payload = _payloadMap(raw ?? '');
    return (payload['reason'] as String?) ??
        (raw?.trim().isNotEmpty == true ? raw!.trim() : 'waiting');
  }

  Future<bool> _hasPendingCommand(
    String entityType,
    String entityId, {
    String? userId,
  }) async {
    final scopedUserId = userId ?? client.auth.currentUser?.id;
    if (scopedUserId == null) return false;
    final localTypes = entityType == 'health_summaries'
        ? const ['health_summaries', 'task_health_summaries']
        : <String>[entityType];
    final count =
        await (database.selectOnly(database.localOutboxCommands)
              ..addColumns([database.localOutboxCommands.commandId.count()])
              ..where(
                database.localOutboxCommands.userId.equals(scopedUserId) &
                    database.localOutboxCommands.entityType.isIn(localTypes) &
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
    await _applyEntity(entityType, Map<String, dynamic>.from(remote));
  }

  Future<void> _applyEntity(String entityType, Map<String, dynamic> row) async {
    // A client may receive a delayed message while an account transition is
    // happening.  RLS protects the remote read, but this local guard makes
    // stale subscriptions harmless even if they race with sign-out.
    final rowUserId = row['user_id'] as String?;
    if (rowUserId == null || rowUserId != client.auth.currentUser?.id) {
      return;
    }
    switch (entityType) {
      case 'profiles':
        await _applyProfile(row);
      case 'user_settings':
        await _applySettings(row);
      case 'privacy_settings':
        await _applyGeneric(entityType, row);
        await _applyCanonicalActivityPrivacy(row);
      case 'task_domains':
        await _applyDomain(row);
      case 'task_occurrences':
        await _applyTask(row);
      case 'user_runtime_state':
        await _applyRemoteRuntime(row);
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
      case 'health_summaries':
        await _applyGeneric(localEntityTypeForRemoteRow(entityType, row), row);
      case 'application_catalog':
      case 'application_rules':
      case 'website_rules':
        if (await _activityRuleSyncEnabled()) {
          await _applyGeneric(entityType, row);
        }
      default:
        await _applyGeneric(entityType, row);
    }
  }

  Future<bool> _activityRuleSyncEnabled() async {
    final settings =
        await (database.select(database.localAppSettings)..where(
              (row) => row.id.equals(
                localAppSettingsId(client.auth.currentUser?.id ?? 'local'),
              ),
            ))
            .getSingleOrNull();
    return settings?.activityRuleSyncEnabled ?? true;
  }

  /// `privacy_settings` is the authority for Activity transport.  This direct
  /// local projection deliberately does not enqueue a user-settings command:
  /// it prevents a delayed or legacy preference row from turning detailed
  /// uploads back on after the privacy row has withdrawn consent.
  Future<void> _applyCanonicalActivityPrivacy(Map<String, dynamic> row) async {
    final userId = row['user_id'] as String?;
    if (userId == null) return;
    final settings =
        await (database.select(database.localAppSettings)
              ..where((item) => item.id.equals(localAppSettingsId(userId))))
            .getSingleOrNull();
    if (settings == null) return;
    final policy = ActivityPrivacyPolicy.fromRemoteRow(
      Map<String, Object?>.from(row),
    );
    final detailedAllowed = policy.hasCanonicalDetailedActivityConsent;
    final contributionAllowed = policy.allowsApprovedContributionUpload(
      settings,
    );
    if (settings.detailedActivitySyncEnabled == detailedAllowed &&
        settings.activitySyncEnabled == contributionAllowed) {
      return;
    }
    await (database.update(
      database.localAppSettings,
    )..where((item) => item.id.equals(settings.id))).write(
      LocalAppSettingsCompanion(
        detailedActivitySyncEnabled: Value(detailedAllowed),
        activitySyncEnabled: Value(contributionAllowed),
      ),
    );
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
            dateOfBirth: Value(_instant(row['date_of_birth'])),
            heightCm: Value((row['height_cm'] as num?)?.toDouble()),
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
            id: localAppSettingsId(row['user_id'] as String),
            userId: Value(row['user_id'] as String),
            localeCode: Value(row['preferred_language'] as String? ?? 'en'),
            themeKey: Value(row['theme'] as String? ?? 'system'),
            accentColor: Value(
              (row['accent_color'] as num?)?.toInt() ?? 0xFF0B78D1,
            ),
            timeZone: Value(row['time_zone'] as String? ?? 'UTC'),
            useDeviceTimeZone: Value(
              data['use_device_time_zone'] as bool? ?? true,
            ),
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
              data['application_tracking_enabled'] as bool? ?? true,
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
            activityRuleSyncEnabled: Value(
              data['activity_rule_sync_enabled'] as bool? ?? true,
            ),
            detailedActivitySyncEnabled: Value(
              data['detailed_activity_sync_enabled'] as bool? ?? false,
            ),
            localActivityRetentionDays: Value(
              (data['local_activity_retention_days'] as num?)?.toInt() ?? 30,
            ),
            hideConfirmedSystemActivity: Value(
              data['hide_confirmed_system_activity'] as bool? ?? true,
            ),
            showPossibleSystemActivity: Value(
              data['show_possible_system_activity'] as bool? ?? true,
            ),
            automaticConfidenceThreshold: Value(
              (data['automatic_confidence_threshold'] as num?)?.toDouble() ??
                  0.9,
            ),
            minimumSuggestionDurationMs: Value(
              (data['minimum_suggestion_duration_ms'] as num?)?.toInt() ??
                  30000,
            ),
            wakeTimeMinutes: Value(
              (data['wake_time_minutes'] as num?)?.toInt() ?? 420,
            ),
            sleepTimeMinutes: Value(
              (data['sleep_time_minutes'] as num?)?.toInt() ?? 1320,
            ),
            workingDaysJson: Value(
              jsonEncode(data['working_days'] ?? const [1, 2, 3, 4, 5]),
            ),
            workStartMinutes: Value(
              (data['work_start_minutes'] as num?)?.toInt() ?? 540,
            ),
            workEndMinutes: Value(
              (data['work_end_minutes'] as num?)?.toInt() ?? 1020,
            ),
            quietStartMinutes: Value(
              (data['quiet_start_minutes'] as num?)?.toInt() ?? 1320,
            ),
            quietEndMinutes: Value(
              (data['quiet_end_minutes'] as num?)?.toInt() ?? 420,
            ),
            sleepReminderEnabled: Value(
              data['sleep_reminder_enabled'] as bool? ?? true,
            ),
            sleepReminderOffsetMinutes: Value(
              (data['sleep_reminder_offset_minutes'] as num?)?.toInt() ?? 30,
            ),
            phoneUsageAnalysisEnabled: Value(
              data['phone_usage_analysis_enabled'] as bool? ?? false,
            ),
            coachingSensitivity: Value(
              data['coaching_sensitivity'] as String? ?? 'standard',
            ),
            coachingTone: Value(data['coaching_tone'] as String? ?? 'balanced'),
            healthSummarySyncEnabled: Value(
              data['health_summary_sync_enabled'] as bool? ?? false,
            ),
            healthReportPrivacy: Value(
              data['health_report_privacy'] as String? ?? 'ask',
            ),
            notificationPreferencesJson: Value(
              jsonEncode(
                data['notification_preferences'] ??
                    const {
                      'task_reminders': true,
                      'scheduled_starts': true,
                      'overdue_tasks': true,
                      'focus_completed': true,
                      'short_break_completed': true,
                      'long_break_completed': true,
                      'roadmaps': true,
                      'activity_review': true,
                      'coaching': true,
                      'sleep_health': true,
                      'synchronization': true,
                      'security': true,
                      'vibration': true,
                    },
              ),
            ),
            countryCode: Value(data['country_code'] as String? ?? ''),
            dateFormat: Value(data['date_format'] as String? ?? 'locale'),
            firstDayOfWeek: Value(
              (data['first_day_of_week'] as num?)?.toInt() ?? 1,
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
            colorValue: _appColorValue(
              (row['color_value'] as num?)?.toInt() ?? 0xFF4169E1,
            ),
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
    final taskId = row['id'] as String;
    final existing = await (database.select(
      database.localTasks,
    )..where((task) => task.id.equals(taskId))).getSingleOrNull();
    await database
        .into(database.localTasks)
        .insertOnConflictUpdate(
          LocalTasksCompanion.insert(
            id: taskId,
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
              canonicalTaskActiveDurationMs(
                row,
                existingValue: existing?.activeDurationMs ?? 0,
              ),
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
        <String?>[
              row['title'] as String?,
              row['name'] as String?,
              row['topic'] as String?,
              row['url'] as String?,
              // A website rule's durable user-facing label is its normalized
              // domain. Without this, the canonical RPC acknowledgement
              // replaced a useful local label such as `freecodecamp.org`
              // with the backend entity name `website rules`.
              row['domain'] as String?,
              row['summary_type'] as String?,
              row['custom_display_name'] as String?,
              row['default_display_name'] as String?,
              row['display_name'] as String?,
              row['display_name_snapshot'] as String?,
              row['raw_identifier_snapshot'] as String?,
            ]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => entityType == 'task_application_links'
                  ? 'Unknown application'
                  : entityType.replaceAll('_', ' '),
            );
    final parentId = localParentIdForRemoteRow(entityType, row);
    final secondaryParentId =
        (entityType == 'roadmap_task_links'
            ? row['task_id'] as String?
            : null) ??
        row['phase_id'] as String? ??
        row['roadmap_phase_id'] as String? ??
        row['checkpoint_id'] as String? ??
        row['application_id'] as String? ??
        row['execution_session_id'] as String? ??
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

  /// `user_runtime_state` is the sole cross-device authority for the current
  /// timer.  Session rows remain auditable history; they must never compete
  /// with each other to decide which task is live on a dashboard.
  Future<void> _applyRemoteRuntime(
    Map<String, dynamic> row, {
    bool force = false,
  }) async {
    final userId = row['user_id'] as String?;
    if (userId == null || userId != client.auth.currentUser?.id) return;
    final pending =
        await (database.select(database.localOutboxCommands)
              ..where(
                (command) =>
                    command.userId.equals(userId) &
                    command.entityType.isIn(const [
                      'execution_runtime',
                      'execution_runtime_switch',
                    ]) &
                    command.status.equals('pending'),
              )
              ..limit(1))
            .get();
    // Keep instant local start/pause/resume feedback until the corresponding
    // durable command is acknowledged. A stale remote broadcast must not
    // make the initiating device jump backwards.
    if (!force &&
        shouldDeferCanonicalRuntimeApply(
          pending.map((command) => command.entityType),
        )) {
      return;
    }
    final runtimeId = localRuntimeStateId(userId);
    final local =
        await (database.select(database.localRuntimeStates)..where(
              (runtime) =>
                  runtime.id.equals(runtimeId) & runtime.userId.equals(userId),
            ))
            .getSingleOrNull();
    final incomingRevision = (row['revision'] as num?)?.toInt() ?? 1;
    final decision = canonicalRuntimeApplyDecision(
      localRevision: local?.revision,
      localCommandId: local?.lastCommandId,
      incomingRevision: incomingRevision,
      incomingCommandId: row['last_command_id'] as String?,
    );
    if (!force && decision != CanonicalRuntimeApplyDecision.apply) {
      // A duplicate needs no write.  For stale/inconsistent rows, retain the
      // newer local runtime and let the already-bounded canonical recovery
      // path observe a future server revision instead of reintroducing an old
      // focus/break state from an out-of-order broadcast.
      return;
    }
    final state = row['state'] as String? ?? 'idle';
    final updatedAt = _instant(row['updated_at']) ?? DateTime.now().toUtc();
    await database
        .into(database.localRuntimeStates)
        .insertOnConflictUpdate(
          LocalRuntimeStatesCompanion.insert(
            id: runtimeId,
            userId: userId,
            activeTaskId: Value(
              state == 'idle'
                  ? null
                  : row['active_task_occurrence_id'] as String?,
            ),
            sessionId: Value(
              state == 'idle' ? null : row['active_session_id'] as String?,
            ),
            state: Value(state),
            segmentStartedAt: Value(_instant(row['active_segment_started_at'])),
            accumulatedActiveMs: Value(
              (row['accumulated_active_ms'] as num?)?.toInt() ?? 0,
            ),
            accumulatedPausedMs: Value(
              (row['accumulated_paused_ms'] as num?)?.toInt() ?? 0,
            ),
            revision: Value(incomingRevision),
            updatedAt: updatedAt,
            lastCommandId: Value(row['last_command_id'] as String?),
          ),
        );
  }

  Future<void> _restoreCanonicalRuntime({bool force = false}) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    final remote = await client
        .from('user_runtime_state')
        .select()
        .eq('user_id', user.id)
        .maybeSingle();
    if (remote == null) return;
    await _applyRemoteRuntime(Map<String, dynamic>.from(remote), force: force);
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
    _liveServices.remove(this);
    await stop();
    await _health.close();
  }
}

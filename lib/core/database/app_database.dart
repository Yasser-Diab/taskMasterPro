import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../config/supabase_config.dart';

part 'app_database.g.dart';

/// Local settings are account-scoped. A device can retain an offline cache
/// for more than one account, so a global `app` row must not be reused after
/// sign-out and sign-in.
String localAppSettingsId(String userId) =>
    userId == 'local' ? 'app' : 'app:$userId';

/// Runtime state is a per-account cache, not a machine-wide singleton.  A
/// device can retain a previous account's database rows after sign-out, so a
/// stable account-scoped key prevents those rows from controlling the next
/// signed-in account's timer.
String localRuntimeStateId(String userId) =>
    userId == 'local' ? 'runtime' : 'runtime:$userId';

/// Returns a safe physical namespace for one Supabase project.
///
/// The project identity is part of every durable database and therefore every
/// durable outbox as well. Changing a backend opens a fresh namespace instead
/// of replaying commands, sync cursors or timer state created for the prior
/// project. Old databases are intentionally left in place for recovery.
String localBackendNamespaceForProject(String projectRef) {
  final normalized = projectRef.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
  return normalized.isEmpty ? 'unknown_project' : normalized;
}

/// Returns the local database namespace for exactly one authenticated account
/// and backend project.
///
/// A device can be used by more than one person.  Keeping all rows in a
/// shared database and relying only on query filters made a stale cache far
/// too easy to expose during an account switch.  The authenticated Supabase
/// UUID and backend project are now part of the database name as physical
/// isolation boundaries. The signed-out workspace deliberately uses its own
/// empty namespace and is never used as an offline fallback for an account.
String localDatabaseNameForAccount(
  String? userId, {
  String projectRef = SupabaseConfig.projectRef,
}) {
  final normalized = (userId == null || userId.isEmpty)
      ? 'signed_out'
      : userId.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');
  return 'taskmaster_${localBackendNamespaceForProject(projectRef)}_$normalized';
}

@DataClassName('LocalProfile')
class LocalProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get email => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get genderIdentity => text().nullable()();
  DateTimeColumn get dateOfBirth => dateTime().nullable()();
  RealColumn get heightCm => real().nullable()();
  BoolColumn get onboardingCompleted =>
      boolean().withDefault(const Constant(false))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get updatedByDeviceId => text().nullable()();
  TextColumn get lastCommandId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalAppSetting')
class LocalAppSettings extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text().withDefault(const Constant('local'))();
  TextColumn get localeCode => text().withDefault(const Constant('en'))();
  TextColumn get themeKey => text().withDefault(const Constant('system'))();
  IntColumn get accentColor =>
      integer().withDefault(const Constant(0xFF0B78D1))();
  TextColumn get timeZone => text().withDefault(const Constant('UTC'))();
  BoolColumn get useDeviceTimeZone =>
      boolean().withDefault(const Constant(true))();
  TextColumn get clockFormat => text().withDefault(const Constant('24h'))();
  TextColumn get notificationSoundKey =>
      text().withDefault(const Constant('system'))();
  BoolColumn get healthConnectEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get cycleTrackingEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get cycleStorageMode =>
      text().withDefault(const Constant('local_only'))();
  BoolColumn get calendarShowCompleted =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get applicationTrackingEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get windowTitleTrackingEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get idleDetectionEnabled =>
      boolean().withDefault(const Constant(true))();
  IntColumn get idleThresholdSeconds =>
      integer().withDefault(const Constant(30))();
  BoolColumn get detectBreakActivity =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get detectCrossTaskActivity =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get retainUnclassifiedActivity =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get retainTechnicalIdle =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get automaticTrustedRules =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get activitySyncEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get activityRuleSyncEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get detailedActivitySyncEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get localActivityRetentionDays =>
      integer().withDefault(const Constant(30))();
  BoolColumn get hideConfirmedSystemActivity =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showPossibleSystemActivity =>
      boolean().withDefault(const Constant(true))();
  RealColumn get automaticConfidenceThreshold =>
      real().withDefault(const Constant(0.9))();
  IntColumn get minimumSuggestionDurationMs =>
      integer().withDefault(const Constant(30000))();
  IntColumn get wakeTimeMinutes => integer().withDefault(const Constant(420))();
  IntColumn get sleepTimeMinutes =>
      integer().withDefault(const Constant(1320))();
  TextColumn get workingDaysJson =>
      text().withDefault(const Constant('[1,2,3,4,5]'))();
  IntColumn get workStartMinutes =>
      integer().withDefault(const Constant(540))();
  IntColumn get workEndMinutes => integer().withDefault(const Constant(1020))();
  IntColumn get quietStartMinutes =>
      integer().withDefault(const Constant(1320))();
  IntColumn get quietEndMinutes => integer().withDefault(const Constant(420))();
  BoolColumn get sleepReminderEnabled =>
      boolean().withDefault(const Constant(true))();
  IntColumn get sleepReminderOffsetMinutes =>
      integer().withDefault(const Constant(30))();
  BoolColumn get phoneUsageAnalysisEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get coachingSensitivity =>
      text().withDefault(const Constant('standard'))();
  TextColumn get coachingTone =>
      text().withDefault(const Constant('balanced'))();
  BoolColumn get healthSummarySyncEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get healthReportPrivacy =>
      text().withDefault(const Constant('ask'))();
  TextColumn get notificationPreferencesJson => text().withDefault(
    const Constant(
      '{"task_reminders":true,"scheduled_starts":true,'
      '"overdue_tasks":true,"focus_completed":true,'
      '"short_break_completed":true,"long_break_completed":true,'
      '"roadmaps":true,"activity_review":true,"coaching":true,'
      '"sleep_health":true,"synchronization":true,"security":true,'
      '"vibration":true}',
    ),
  )();
  TextColumn get countryCode => text().withDefault(const Constant(''))();
  TextColumn get dateFormat => text().withDefault(const Constant('locale'))();
  IntColumn get firstDayOfWeek => integer().withDefault(const Constant(1))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get lastCommandId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalDomain')
class LocalDomains extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get name => text()();
  TextColumn get iconName => text().withDefault(const Constant('folder'))();
  IntColumn get colorValue => integer()();
  RealColumn get position => real().withDefault(const Constant(0))();
  DateTimeColumn get archivedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get createdByDeviceId => text().nullable()();
  TextColumn get updatedByDeviceId => text().nullable()();
  TextColumn get lastCommandId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalTask')
class LocalTasks extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get templateId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get domainId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('ready'))();
  IntColumn get priority => integer().withDefault(const Constant(2))();
  TextColumn get executionMode =>
      text().withDefault(const Constant('manual'))();
  DateTimeColumn get scheduledDate => dateTime().nullable()();
  DateTimeColumn get plannedStart => dateTime().nullable()();
  DateTimeColumn get plannedEnd => dateTime().nullable()();
  DateTimeColumn get dueAt => dateTime().nullable()();
  IntColumn get estimatedDurationMs =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get actualStart => dateTime().nullable()();
  DateTimeColumn get actualFinish => dateTime().nullable()();
  IntColumn get activeDurationMs => integer().withDefault(const Constant(0))();
  IntColumn get pausedDurationMs => integer().withDefault(const Constant(0))();
  IntColumn get idleDurationMs => integer().withDefault(const Constant(0))();
  RealColumn get progress => real().withDefault(const Constant(0))();
  TextColumn get roadmapId => text().nullable()();
  TextColumn get roadmapPhaseId => text().nullable()();
  TextColumn get occurrenceKey => text().nullable()();
  TextColumn get dataJson => text().withDefault(const Constant('{}'))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get createdByDeviceId => text().nullable()();
  TextColumn get updatedByDeviceId => text().nullable()();
  TextColumn get lastCommandId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalRuntime')
class LocalRuntimeStates extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get activeTaskId => text().nullable()();
  TextColumn get sessionId => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('idle'))();
  DateTimeColumn get segmentStartedAt => dateTime().nullable()();
  IntColumn get accumulatedActiveMs =>
      integer().withDefault(const Constant(0))();
  IntColumn get accumulatedPausedMs =>
      integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get lastCommandId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalRoadmap')
class LocalRoadmaps extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get plannedStart => dateTime().nullable()();
  DateTimeColumn get originalTargetDate => dateTime().nullable()();
  DateTimeColumn get forecastTargetDate => dateTime().nullable()();
  TextColumn get finalOutcome => text().withDefault(const Constant(''))();
  RealColumn get progress => real().withDefault(const Constant(0))();
  IntColumn get requiredEffortMs => integer().nullable()();
  IntColumn get completedEffortMs => integer().withDefault(const Constant(0))();
  TextColumn get riskLevel => text().withDefault(const Constant('low'))();
  TextColumn get forecastConfidence =>
      text().withDefault(const Constant('low'))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get updatedByDeviceId => text().nullable()();
  TextColumn get lastCommandId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalActivitySegment')
class LocalActivitySegments extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();
  TextColumn get deviceEventId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  TextColumn get sourceType => text()();
  TextColumn get processName => text().nullable()();
  TextColumn get windowTitle => text().nullable()();
  TextColumn get domain => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get pageTitle => text().nullable()();
  TextColumn get idleState => text().nullable()();
  RealColumn get captureConfidence => real().nullable()();
  TextColumn get rawMetadataJson => text().withDefault(const Constant('{}'))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalAttribution')
class LocalAttributions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get activitySegmentId => text()();
  TextColumn get targetType => text()();
  TextColumn get targetId => text().nullable()();
  TextColumn get classification => text()();
  RealColumn get confidence => real()();
  TextColumn get attributionStatus =>
      text().withDefault(const Constant('proposed'))();
  BoolColumn get confirmedByUser =>
      boolean().withDefault(const Constant(false))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalContribution')
class LocalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get activitySegmentId => text()();
  TextColumn get attributionId => text()();
  TextColumn get targetType => text()();
  TextColumn get targetId => text().nullable()();
  TextColumn get contributionType => text()();
  IntColumn get physicalDurationMs => integer()();
  IntColumn get creditedDurationMs => integer()();
  RealColumn get progressValue => real().nullable()();
  BoolColumn get isUnscheduled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isCrossTask => boolean().withDefault(const Constant(false))();
  BoolColumn get isIdleDerived =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isAutomatic => boolean().withDefault(const Constant(false))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalActivityReview')
class LocalActivityReviews extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get activitySegmentId => text()();
  TextColumn get reviewReason => text()();
  IntColumn get priority => integer().withDefault(const Constant(2))();
  TextColumn get suggestedTargetType => text().nullable()();
  TextColumn get suggestedTargetId => text().nullable()();
  TextColumn get suggestedTargetTitle => text().nullable()();
  TextColumn get suggestedClassification => text().nullable()();
  RealColumn get confidence => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get reviewedAt => dateTime().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalEntityRecord')
class LocalEntityRecords extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get secondaryParentId => text().nullable()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  RealColumn get position => real().withDefault(const Constant(0))();
  TextColumn get dataJson => text().withDefault(const Constant('{}'))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get createdByDeviceId => text().nullable()();
  TextColumn get updatedByDeviceId => text().nullable()();
  TextColumn get lastCommandId => text().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LocalOutboxCommand')
class LocalOutboxCommands extends Table {
  TextColumn get commandId => text()();
  TextColumn get userId => text()();
  TextColumn get deviceId => text()();
  IntColumn get deviceSequence => integer()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get commandType => text()();
  IntColumn get baseRevision => integer()();
  TextColumn get payloadJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get clientTimestamp => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {commandId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {userId, deviceId, deviceSequence},
  ];
}

@DataClassName('LocalSyncState')
class LocalSyncStates extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  IntColumn get lastChangeSequence =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    LocalProfiles,
    LocalAppSettings,
    LocalDomains,
    LocalTasks,
    LocalRuntimeStates,
    LocalRoadmaps,
    LocalActivitySegments,
    LocalAttributions,
    LocalContributions,
    LocalActivityReviews,
    LocalEntityRecords,
    LocalOutboxCommands,
    LocalSyncStates,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: localDatabaseNameForAccount(null)));

  /// Opens a database that is private to [userId].  Production code must use
  /// this constructor; the positional constructor is retained for in-memory
  /// tests and the signed-out shell only.
  AppDatabase.forAccount(String? userId)
    : super(driftDatabase(name: localDatabaseNameForAccount(userId)));

  @override
  int get schemaVersion => 17;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      // Early desktop builds were distributed with a partially-applied schema:
      // SQLite's `user_version` could still be 9 while one or more columns from
      // later versions had already been added. A regular `ADD COLUMN` then
      // aborts startup with a duplicate-column error before the sync service
      // can even restore the signed-in account. Treat migrations as
      // idempotent so that those durable local databases can recover in place.
      Future<bool> tableExists(String tableName) async {
        final result = await customSelect(
          "SELECT 1 AS present FROM sqlite_master "
          "WHERE type = 'table' AND name = ? LIMIT 1",
          variables: [Variable.withString(tableName)],
        ).getSingleOrNull();
        return result != null;
      }

      Future<void> createTableIfMissing(TableInfo table) async {
        if (!await tableExists(table.actualTableName)) {
          await migrator.createTable(table);
        }
      }

      Future<void> addColumnIfMissing(
        TableInfo table,
        GeneratedColumn column,
      ) async {
        if (!await tableExists(table.actualTableName)) {
          // A table introduced by the same recovered migration will contain
          // every current column when it is created below.
          return;
        }
        final columns = await customSelect(
          'PRAGMA table_info(${table.actualTableName})',
        ).get();
        final exists = columns.any(
          (row) => row.read<String>('name') == column.$name,
        );
        if (!exists) {
          await migrator.addColumn(table, column);
        }
      }

      if (from < 2) {
        await createTableIfMissing(localEntityRecords);
      }
      if (from < 3) {
        await addColumnIfMissing(localProfiles, localProfiles.genderIdentity);
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.healthConnectEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.cycleTrackingEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.cycleStorageMode,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.calendarShowCompleted,
        );
      }
      if (from < 4) {
        await createTableIfMissing(localSyncStates);
      }
      if (from < 5) {
        await addColumnIfMissing(localRoadmaps, localRoadmaps.plannedStart);
        await addColumnIfMissing(localRoadmaps, localRoadmaps.finalOutcome);
        await addColumnIfMissing(
          localRoadmaps,
          localRoadmaps.forecastConfidence,
        );
      }
      if (from < 6) {
        await addColumnIfMissing(localTasks, localTasks.dataJson);
      }
      if (from < 7) {
        await addColumnIfMissing(localTasks, localTasks.occurrenceKey);
      }
      if (from < 8) {
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.applicationTrackingEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.windowTitleTrackingEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.idleDetectionEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.idleThresholdSeconds,
        );
      }
      if (from < 9) {
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.activitySyncEnabled,
        );
      }
      if (from < 10) {
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.wakeTimeMinutes,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.sleepTimeMinutes,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.workingDaysJson,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.workStartMinutes,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.workEndMinutes,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.quietStartMinutes,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.quietEndMinutes,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.sleepReminderEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.sleepReminderOffsetMinutes,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.phoneUsageAnalysisEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.coachingSensitivity,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.healthSummarySyncEnabled,
        );
      }
      if (from < 11) {
        await addColumnIfMissing(localProfiles, localProfiles.dateOfBirth);
      }
      if (from < 12) {
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.activityRuleSyncEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.detailedActivitySyncEnabled,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.localActivityRetentionDays,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.hideConfirmedSystemActivity,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.showPossibleSystemActivity,
        );
      }
      if (from < 13) {
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.coachingTone,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.healthReportPrivacy,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.notificationPreferencesJson,
        );
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.countryCode,
        );
        await addColumnIfMissing(localAppSettings, localAppSettings.dateFormat);
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.firstDayOfWeek,
        );
      }
      if (from < 14) {
        // Preserve the settings record while moving the old single-account
        // cache key to the authenticated account it belongs to.
        await customStatement(
          "UPDATE local_app_settings "
          "SET id = 'app:' || user_id "
          "WHERE id = 'app' AND user_id <> 'local'",
        );
      }
      if (from < 15) {
        // The original runtime cache used one global `runtime` row. Preserve
        // it, but scope it to the account it belongs to so a signed-out
        // account can never resume or pause the current account's task.
        await customStatement(
          "UPDATE local_runtime_states "
          "SET id = 'runtime:' || user_id "
          "WHERE id = 'runtime' AND user_id <> 'local'",
        );
      }
      if (from < 16) {
        await addColumnIfMissing(
          localAppSettings,
          localAppSettings.useDeviceTimeZone,
        );
      }
      if (from < 17) {
        await addColumnIfMissing(localProfiles, localProfiles.heightCm);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}

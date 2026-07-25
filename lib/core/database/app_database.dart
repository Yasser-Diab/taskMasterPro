import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('LocalProfile')
class LocalProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  TextColumn get displayName => text().withDefault(const Constant(''))();
  TextColumn get email => text().nullable()();
  TextColumn get imagePath => text().nullable()();
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
  TextColumn get clockFormat => text().withDefault(const Constant('24h'))();
  TextColumn get notificationSoundKey =>
      text().withDefault(const Constant('system'))();
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
  RealColumn get automaticConfidenceThreshold =>
      real().withDefault(const Constant(0.9))();
  IntColumn get minimumSuggestionDurationMs =>
      integer().withDefault(const Constant(30000))();
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
  DateTimeColumn get originalTargetDate => dateTime().nullable()();
  DateTimeColumn get forecastTargetDate => dateTime().nullable()();
  RealColumn get progress => real().withDefault(const Constant(0))();
  IntColumn get requiredEffortMs => integer().nullable()();
  IntColumn get completedEffortMs => integer().withDefault(const Constant(0))();
  TextColumn get riskLevel => text().withDefault(const Constant('low'))();
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
    LocalOutboxCommands,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'taskmaster_pro'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/platform/device_identity.dart';

class RoadmapRepository {
  RoadmapRepository(this.database);

  final AppDatabase database;
  static const _uuid = Uuid();

  Stream<List<LocalRoadmap>> watchRoadmaps() {
    final query = database.select(database.localRoadmaps)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy([
        (row) => OrderingTerm.asc(row.status),
        (row) => OrderingTerm.asc(row.forecastTargetDate),
      ]);
    return query.watch();
  }

  Future<void> createStarterRoadmap({
    required String userId,
    required String title,
  }) async {
    final existing = await (database.select(
      database.localRoadmaps,
    )..where((row) => row.title.equals(title))).getSingleOrNull();
    if (existing != null) return;
    final now = DateTime.now().toUtc();
    final deviceId = await DeviceIdentity.id();
    await database
        .into(database.localRoadmaps)
        .insert(
          LocalRoadmapsCompanion.insert(
            id: _uuid.v4(),
            userId: userId,
            title: title,
            description: const Value(
              'Starter roadmap created from onboarding. Every field is editable.',
            ),
            originalTargetDate: Value(now.add(const Duration(days: 90))),
            forecastTargetDate: Value(now.add(const Duration(days: 90))),
            createdAt: now,
            updatedAt: now,
            updatedByDeviceId: Value(deviceId),
          ),
        );
  }
}

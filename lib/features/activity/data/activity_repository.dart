import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class ActivityReviewEntry {
  const ActivityReviewEntry({required this.review, required this.segment});

  final LocalActivityReview review;
  final LocalActivitySegment segment;

  Duration get duration => segment.endedAt.difference(segment.startedAt);
}

class ActivityRepository {
  ActivityRepository(this.database);

  final AppDatabase database;

  Stream<List<ActivityReviewEntry>> watchReviewQueue() {
    final query =
        database.select(database.localActivityReviews).join([
            innerJoin(
              database.localActivitySegments,
              database.localActivitySegments.id.equalsExp(
                database.localActivityReviews.activitySegmentId,
              ),
            ),
          ])
          ..where(
            database.localActivityReviews.deletedAt.isNull() &
                database.localActivityReviews.status.equals('pending'),
          )
          ..orderBy([
            OrderingTerm.desc(database.localActivityReviews.priority),
            OrderingTerm.desc(database.localActivityReviews.createdAt),
          ]);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          ActivityReviewEntry(
            review: row.readTable(database.localActivityReviews),
            segment: row.readTable(database.localActivitySegments),
          ),
      ],
    );
  }

  Future<void> resolve(
    ActivityReviewEntry entry, {
    required String status,
  }) async {
    await (database.update(
      database.localActivityReviews,
    )..where((row) => row.id.equals(entry.review.id))).write(
      LocalActivityReviewsCompanion(
        status: Value(status),
        reviewedAt: Value(DateTime.now().toUtc()),
        revision: Value(entry.review.revision + 1),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}

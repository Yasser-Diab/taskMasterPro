import 'package:uuid/uuid.dart';

/// Stable identity for one account/template/calendar occurrence.
///
/// Recurrence is generated independently on offline devices. Basing the UUID
/// on the semantic key makes both devices create the same logical row instead
/// of relying on a later unique-constraint conflict to repair duplicates.
String recurringOccurrenceId({
  required String userId,
  required String templateId,
  required String occurrenceKey,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/task-template/'
  '$templateId/occurrence/$occurrenceKey',
);

String recurringRelationshipId({
  required String userId,
  required String taskId,
  required String relationshipKind,
  int position = 0,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/task/$taskId/'
  '$relationshipKind/$position',
);

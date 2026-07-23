import 'package:uuid/uuid.dart';

enum BreakContributionType {
  rest,
  learning,
  reading,
  exercise,
  housework,
  anotherTask,
  other,
}

extension BreakContributionTypeX on BreakContributionType {
  String get storageValue => switch (this) {
    BreakContributionType.anotherTask => 'another_task',
    _ => name,
  };

  static BreakContributionType fromStorage(String? value) => switch (value) {
    'german' || 'learning' => BreakContributionType.learning,
    'reading' => BreakContributionType.reading,
    'exercise' => BreakContributionType.exercise,
    'housework' => BreakContributionType.housework,
    'another_task' => BreakContributionType.anotherTask,
    'other' => BreakContributionType.other,
    _ => BreakContributionType.rest,
  };
}

class BreakContribution {
  BreakContribution({
    String? id,
    required this.sourceTaskId,
    required this.sourceSessionId,
    this.relatedTaskId,
    this.relatedBookId,
    required this.type,
    required this.durationSeconds,
    this.progressValue,
    this.evidenceType,
    this.evidenceReference,
    this.userConfirmed = false,
    required this.startedAt,
    required this.endedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : assert(durationSeconds >= 0),
       assert(!endedAt.isBefore(startedAt)),
       id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String sourceTaskId;
  final String sourceSessionId;
  final String? relatedTaskId;
  final String? relatedBookId;
  final BreakContributionType type;
  final int durationSeconds;
  final double? progressValue;
  final String? evidenceType;
  final String? evidenceReference;
  final bool userConfirmed;
  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toMap({String? userId}) => {
    'id': id,
    'user_id': userId,
    'source_task_id': sourceTaskId,
    'source_session_id': sourceSessionId,
    'related_task_id': relatedTaskId,
    'related_book_id': relatedBookId,
    'contribution_type': type.storageValue,
    'duration_seconds': durationSeconds,
    'progress_value': progressValue,
    'evidence_type': evidenceType,
    'evidence_reference': evidenceReference,
    'user_confirmed': userConfirmed,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory BreakContribution.fromMap(Map<String, dynamic> map) {
    return BreakContribution(
      id: map['id']?.toString(),
      sourceTaskId: map['source_task_id']?.toString() ?? '',
      sourceSessionId: map['source_session_id']?.toString() ?? '',
      relatedTaskId: map['related_task_id']?.toString(),
      relatedBookId: map['related_book_id']?.toString(),
      type: BreakContributionTypeX.fromStorage(
        map['contribution_type']?.toString(),
      ),
      durationSeconds: _int(map['duration_seconds']),
      progressValue: _doubleOrNull(map['progress_value']),
      evidenceType: map['evidence_type']?.toString(),
      evidenceReference: map['evidence_reference']?.toString(),
      userConfirmed: map['user_confirmed'] == true,
      startedAt: _date(map['started_at']),
      endedAt: _date(map['ended_at']),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }
}

enum BookFormat { physical, pdf, epub, web, audiobook, other }

enum BookStatus { planned, reading, paused, completed, abandoned }

class ReadingBook {
  ReadingBook({
    String? id,
    required this.readingTaskId,
    required this.title,
    this.author = '',
    this.edition,
    this.isbn,
    this.format = BookFormat.physical,
    required this.totalPages,
    this.currentPage = 0,
    this.status = BookStatus.planned,
    this.coverReference,
    this.localFileReference,
    this.localDeviceId,
    this.remoteFileReference,
    this.webUrl,
    this.targetFinishDate,
    this.notes = '',
    this.priority = 0,
    this.roadmapId,
    this.roadmapPhaseId,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deletedAt,
  }) : assert(totalPages > 0),
       assert(currentPage >= 0 && currentPage <= totalPages),
       id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String readingTaskId;
  final String title;
  final String author;
  final String? edition;
  final String? isbn;
  final BookFormat format;
  final int totalPages;
  final int currentPage;
  final BookStatus status;
  final String? coverReference;
  final String? localFileReference;
  final String? localDeviceId;
  final String? remoteFileReference;
  final String? webUrl;
  final DateTime? targetFinishDate;
  final String notes;
  final int priority;
  final String? roadmapId;
  final String? roadmapPhaseId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  double get progress => totalPages == 0 ? 0 : currentPage / totalPages;
  int get remainingPages => totalPages - currentPage;

  ReadingBook copyWith({int? currentPage, BookStatus? status}) => ReadingBook(
    id: id,
    readingTaskId: readingTaskId,
    title: title,
    author: author,
    edition: edition,
    isbn: isbn,
    format: format,
    totalPages: totalPages,
    currentPage: currentPage ?? this.currentPage,
    status: status ?? this.status,
    coverReference: coverReference,
    localFileReference: localFileReference,
    localDeviceId: localDeviceId,
    remoteFileReference: remoteFileReference,
    webUrl: webUrl,
    targetFinishDate: targetFinishDate,
    notes: notes,
    priority: priority,
    roadmapId: roadmapId,
    roadmapPhaseId: roadmapPhaseId,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    deletedAt: deletedAt,
  );

  Map<String, dynamic> toMap({String? userId, bool includeLocal = true}) => {
    'id': id,
    'user_id': userId,
    'reading_task_id': readingTaskId,
    'title': title,
    'author': author,
    'edition': edition,
    'isbn': isbn,
    'format': format.name,
    'total_pages': totalPages,
    'current_page': currentPage,
    'status': status.name,
    'cover_reference': coverReference,
    if (includeLocal) 'local_file_reference': localFileReference,
    if (includeLocal) 'local_device_id': localDeviceId,
    'remote_file_reference': remoteFileReference,
    'web_url': webUrl,
    'target_finish_date': targetFinishDate?.toIso8601String().split('T').first,
    'notes': notes,
    'priority': priority,
    'roadmap_id': roadmapId,
    'roadmap_phase_id': roadmapPhaseId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'deleted_at': deletedAt?.toUtc().toIso8601String(),
  };

  factory ReadingBook.fromMap(Map<String, dynamic> map) => ReadingBook(
    id: map['id']?.toString(),
    readingTaskId: map['reading_task_id']?.toString() ?? '',
    title: map['title']?.toString() ?? '',
    author: map['author']?.toString() ?? '',
    edition: map['edition']?.toString(),
    isbn: map['isbn']?.toString(),
    format: BookFormat.values.firstWhere(
      (value) => value.name == map['format']?.toString(),
      orElse: () => BookFormat.other,
    ),
    totalPages: _int(map['total_pages']).clamp(1, 1000000),
    currentPage: _int(
      map['current_page'],
    ).clamp(0, _int(map['total_pages']).clamp(1, 1000000)),
    status: BookStatus.values.firstWhere(
      (value) => value.name == map['status']?.toString(),
      orElse: () => BookStatus.planned,
    ),
    coverReference: map['cover_reference']?.toString(),
    localFileReference: map['local_file_reference']?.toString(),
    localDeviceId: map['local_device_id']?.toString(),
    remoteFileReference: map['remote_file_reference']?.toString(),
    webUrl: map['web_url']?.toString(),
    targetFinishDate: _dateOrNull(map['target_finish_date']),
    notes: map['notes']?.toString() ?? '',
    priority: _int(map['priority']),
    roadmapId: map['roadmap_id']?.toString(),
    roadmapPhaseId: map['roadmap_phase_id']?.toString(),
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    deletedAt: _dateOrNull(map['deleted_at']),
  );
}

class ReadingSession {
  ReadingSession({
    String? id,
    required this.taskId,
    required this.bookId,
    this.taskSessionId,
    required this.startPage,
    required this.endPage,
    required this.previousBookPage,
    required this.durationSeconds,
    this.readingMode = 'external',
    required this.startedAt,
    required this.endedAt,
    this.notes = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : assert(startPage >= 0),
       assert(endPage >= startPage),
       assert(durationSeconds >= 0),
       id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String taskId;
  final String bookId;
  final String? taskSessionId;
  final int startPage;
  final int endPage;
  final int previousBookPage;
  final int durationSeconds;
  final String readingMode;
  final DateTime startedAt;
  final DateTime endedAt;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get pagesTraversed => endPage - startPage;
  int get uniquePagesAdvanced =>
      (endPage - previousBookPage).clamp(0, pagesTraversed);
  int get rereadPages => pagesTraversed - uniquePagesAdvanced;

  void validateFor(ReadingBook book) {
    if (endPage > book.totalPages || startPage > book.totalPages) {
      throw ArgumentError('The page number is outside this book.');
    }
  }

  Map<String, dynamic> toMap({String? userId}) => {
    'id': id,
    'user_id': userId,
    'task_id': taskId,
    'book_id': bookId,
    'task_session_id': taskSessionId,
    'start_page': startPage,
    'end_page': endPage,
    'unique_pages_advanced': uniquePagesAdvanced,
    'reread_pages': rereadPages,
    'duration_seconds': durationSeconds,
    'reading_mode': readingMode,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt.toUtc().toIso8601String(),
    'notes': notes,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory ReadingSession.fromMap(Map<String, dynamic> map) => ReadingSession(
    id: map['id']?.toString(),
    taskId: map['task_id']?.toString() ?? '',
    bookId: map['book_id']?.toString() ?? '',
    taskSessionId: map['task_session_id']?.toString(),
    startPage: _int(map['start_page']),
    endPage: _int(map['end_page']),
    previousBookPage:
        _int(map['end_page']) - _int(map['unique_pages_advanced']),
    durationSeconds: _int(map['duration_seconds']),
    readingMode: map['reading_mode']?.toString() ?? 'external',
    startedAt: _date(map['started_at']),
    endedAt: _date(map['ended_at']),
    notes: map['notes']?.toString() ?? '',
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
  );
}

DateTime _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
DateTime? _dateOrNull(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());
int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;
double? _doubleOrNull(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');

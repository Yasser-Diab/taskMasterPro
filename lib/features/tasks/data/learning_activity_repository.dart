import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../../core/config/supabase_service.dart';
import '../domain/learning_activity_models.dart';

class LearningActivityRepository {
  LearningActivityRepository(this._supabase, {Directory? baseDirectory})
    : _baseDirectory = baseDirectory;

  final SupabaseService _supabase;
  final Directory? _baseDirectory;
  Future<void> _writeTail = Future<void>.value();

  Future<List<ReadingBook>> loadBooks(String taskId) async {
    final user = _supabase.currentUser;
    if (user == null) return const [];
    final local = await _readCollection(user.id, 'books', ReadingBook.fromMap);
    final visible = local
        .where((book) => book.readingTaskId == taskId && book.deletedAt == null)
        .toList();
    _refreshBooks(user.id, taskId);
    return visible;
  }

  Future<List<ReadingSession>> loadReadingSessions(String taskId) async {
    final user = _supabase.currentUser;
    if (user == null) return const [];
    return (await _readCollection(
      user.id,
      'reading_sessions',
      ReadingSession.fromMap,
    )).where((session) => session.taskId == taskId).toList();
  }

  Future<List<BreakContribution>> loadBreakContributions({
    String? sourceTaskId,
    String? relatedTaskId,
  }) async {
    final user = _supabase.currentUser;
    if (user == null) return const [];
    final rows = await _readCollection(
      user.id,
      'break_contributions',
      BreakContribution.fromMap,
    );
    return rows.where((row) {
      if (sourceTaskId != null && row.sourceTaskId != sourceTaskId) {
        return false;
      }
      if (relatedTaskId != null && row.relatedTaskId != relatedTaskId) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<ReadingBook> saveBook(ReadingBook book) async {
    final user = _requireUser();
    await _upsertLocal(user.id, 'books', book.id, book.toMap());
    final mutation = _LearningMutation(
      entityType: 'book',
      entityId: book.id,
      operation: 'upsert',
      payload: book.toMap(userId: user.id, includeLocal: false),
    );
    await _enqueue(user.id, mutation);
    await synchronizePending();
    return book;
  }

  Future<ReadingSession> recordReadingSession({
    required ReadingBook book,
    required ReadingSession session,
  }) async {
    session.validateFor(book);
    final user = _requireUser();
    final updatedBook = book.copyWith(
      currentPage: session.endPage > book.currentPage
          ? session.endPage
          : book.currentPage,
      status: session.endPage >= book.totalPages
          ? BookStatus.completed
          : BookStatus.reading,
    );
    await _mutate(user.id, (raw) {
      _upsertRow(raw, 'reading_sessions', session.id, session.toMap());
      _upsertRow(raw, 'books', updatedBook.id, updatedBook.toMap());
      _appendMutation(
        raw,
        _LearningMutation(
          entityType: 'reading_session',
          entityId: session.id,
          operation: 'insert',
          payload: session.toMap(userId: user.id),
        ),
      );
      _appendMutation(
        raw,
        _LearningMutation(
          entityType: 'book',
          entityId: updatedBook.id,
          operation: 'upsert',
          payload: updatedBook.toMap(userId: user.id, includeLocal: false),
        ),
      );
    });
    await synchronizePending();
    return session;
  }

  Future<BreakContribution> recordBreakContribution(
    BreakContribution contribution,
  ) async {
    final user = _requireUser();
    await _upsertLocal(
      user.id,
      'break_contributions',
      contribution.id,
      contribution.toMap(),
    );
    await _enqueue(
      user.id,
      _LearningMutation(
        entityType: 'break_contribution',
        entityId: contribution.id,
        operation: 'insert',
        payload: contribution.toMap(userId: user.id),
      ),
    );
    await synchronizePending();
    return contribution;
  }

  Future<void> synchronizePending() async {
    final client = _supabase.clientOrNull;
    final user = _supabase.currentUser;
    if (client == null || user == null) return;
    final raw = await _read(user.id);
    final mutations = raw['outbox'] is List
        ? (raw['outbox'] as List)
              .whereType<Map>()
              .map((row) => _LearningMutation.fromMap(Map.from(row)))
              .toList()
        : <_LearningMutation>[];
    mutations.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final mutation in mutations) {
      try {
        await client
            .from('sync_outbox')
            .upsert(
              mutation.toRemoteOutbox(user.id),
              onConflict: 'mutation_id',
            );
        switch (mutation.entityType) {
          case 'book':
            await client.from('books').upsert(mutation.payload);
          case 'reading_session':
            await client
                .from('reading_sessions')
                .upsert(mutation.payload, onConflict: 'id');
          case 'break_contribution':
            await client
                .from('break_contributions')
                .upsert(mutation.payload, onConflict: 'id');
        }
        await client
            .from('sync_outbox')
            .update({'sync_state': 'synchronized', 'last_error': null})
            .eq('mutation_id', mutation.id);
        await _removeMutation(user.id, mutation.id);
      } on Object {
        return;
      }
    }
  }

  Future<void> _refreshBooks(String userId, String taskId) async {
    final client = _supabase.clientOrNull;
    if (client == null) return;
    try {
      final rows = await client
          .from('books')
          .select()
          .eq('reading_task_id', taskId)
          .eq('user_id', userId)
          .isFilter('deleted_at', null)
          .order('priority', ascending: false)
          .order('created_at');
      final remote = rows.map<ReadingBook>(ReadingBook.fromMap).toList();
      await _mutate(userId, (raw) {
        final pendingBookIds = raw['outbox'] is List
            ? (raw['outbox'] as List)
                  .whereType<Map>()
                  .where((row) => row['entity_type'] == 'book')
                  .map((row) => row['entity_id']?.toString())
                  .toSet()
            : <String?>{};
        final current = raw['books'] is List
            ? List<Object?>.from(raw['books'] as List)
            : <Object?>[];
        current.removeWhere(
          (row) =>
              row is Map &&
              row['reading_task_id']?.toString() == taskId &&
              !pendingBookIds.contains(row['id']?.toString()),
        );
        current.addAll(remote.map((book) => book.toMap()));
        raw['books'] = current;
      });
    } on Object {
      // The retained local snapshot remains the source of truth offline.
    }
  }

  dynamic _requireUser() {
    final user = _supabase.currentUser;
    if (user == null) throw StateError('You need to sign in first.');
    return user;
  }

  Future<List<T>> _readCollection<T>(
    String userId,
    String key,
    T Function(Map<String, dynamic>) fromMap,
  ) async {
    final raw = await _read(userId);
    final rows = raw[key];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map) fromMap(Map<String, dynamic>.from(row)),
    ];
  }

  Future<void> _upsertLocal(
    String userId,
    String collection,
    String id,
    Map<String, dynamic> row,
  ) => _mutate(userId, (raw) => _upsertRow(raw, collection, id, row));

  void _upsertRow(
    Map<String, dynamic> raw,
    String collection,
    String id,
    Map<String, dynamic> row,
  ) {
    final rows = raw[collection] is List
        ? List<Object?>.from(raw[collection] as List)
        : <Object?>[];
    rows.removeWhere((value) => value is Map && value['id']?.toString() == id);
    rows.add(row);
    raw[collection] = rows;
  }

  Future<void> _enqueue(String userId, _LearningMutation mutation) =>
      _mutate(userId, (raw) => _appendMutation(raw, mutation));

  void _appendMutation(Map<String, dynamic> raw, _LearningMutation mutation) {
    final rows = raw['outbox'] is List
        ? List<Object?>.from(raw['outbox'] as List)
        : <Object?>[];
    rows.removeWhere(
      (row) => row is Map && row['mutation_id']?.toString() == mutation.id,
    );
    rows.add(mutation.toMap());
    raw['outbox'] = rows;
  }

  Future<void> _removeMutation(String userId, String mutationId) =>
      _mutate(userId, (raw) {
        final rows = raw['outbox'] is List
            ? List<Object?>.from(raw['outbox'] as List)
            : <Object?>[];
        rows.removeWhere(
          (row) => row is Map && row['mutation_id']?.toString() == mutationId,
        );
        raw['outbox'] = rows;
      });

  Future<void> _mutate(
    String userId,
    void Function(Map<String, dynamic>) change,
  ) {
    final operation = _writeTail.then((_) async {
      final raw = await _read(userId);
      change(raw);
      await _write(userId, raw);
    });
    _writeTail = operation.catchError((_) {});
    return operation;
  }

  Future<Map<String, dynamic>> _read(String userId) async {
    final file = _file(userId);
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } on Object {
      return {};
    }
  }

  Future<void> _write(String userId, Map<String, dynamic> raw) async {
    final file = _file(userId);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(raw), flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  File _file(String userId) {
    final base =
        _baseDirectory ??
        Directory(
          Platform.isWindows
              ? (Platform.environment['LOCALAPPDATA'] ??
                    Directory.systemTemp.path)
              : (Platform.environment['HOME'] ?? Directory.systemTemp.path),
        );
    return File(
      '${base.path}${Platform.pathSeparator}TaskMasterPro'
      '${Platform.pathSeparator}users${Platform.pathSeparator}$userId'
      '${Platform.pathSeparator}learning-local.json',
    );
  }
}

class _LearningMutation {
  _LearningMutation({
    String? id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    'mutation_id': id,
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'payload': payload,
    'created_at': createdAt.toUtc().toIso8601String(),
    'retry_count': 0,
    'sync_state': 'pending',
  };

  Map<String, dynamic> toRemoteOutbox(String userId) => {
    ...toMap(),
    'user_id': userId,
    'device_id': payload['local_device_id'] ?? 'unknown',
    'base_revision': 0,
  };

  factory _LearningMutation.fromMap(Map<dynamic, dynamic> map) =>
      _LearningMutation(
        id: map['mutation_id']?.toString(),
        entityType: map['entity_type']?.toString() ?? '',
        entityId: map['entity_id']?.toString() ?? '',
        operation: map['operation']?.toString() ?? '',
        payload: map['payload'] is Map
            ? Map<String, dynamic>.from(map['payload'] as Map)
            : {},
        createdAt:
            DateTime.tryParse(map['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';

class TaskResourceService {
  TaskResourceService({required this.entities, required this.client});

  final EntityRecordRepository entities;
  final SupabaseClient client;
  static const _uuid = Uuid();

  Future<List<String>> pickAndAddFiles({
    required String taskId,
    required bool synchronizeFiles,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Add files to task',
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return const [];
    final ids = <String>[];
    for (final picked in result.files) {
      final sourcePath = picked.path;
      if (sourcePath == null) continue;
      final source = File(sourcePath);
      final size = await source.length();
      if (size > 50 * 1024 * 1024) {
        throw FileSystemException(
          '${picked.name} is larger than the 50 MB attachment limit',
        );
      }
      final stored = await _copyToAppStorage(taskId, source, picked.name);
      var remotePath = <String, Object?>{};
      var synchronized = false;
      if (synchronizeFiles && client.auth.currentUser != null) {
        try {
          final storagePath =
              '${client.auth.currentUser!.id}/$taskId/'
              '${_uuid.v4()}_${_safeFileName(picked.name)}';
          await client.storage
              .from('task-resources')
              .upload(
                storagePath,
                stored,
                fileOptions: FileOptions(
                  upsert: false,
                  contentType: _contentType(picked.name),
                ),
              );
          remotePath = {
            'storage_location': 'supabase',
            'storage_path': storagePath,
          };
          synchronized = true;
        } catch (_) {
          remotePath = {'storage_location': 'local', 'storage_path': null};
        }
      }
      final resourceType = _resourceType(picked.name);
      final data = <String, Object?>{
        'task_occurrence_id': taskId,
        'name': picked.name,
        'resource_type': resourceType,
        'description': '',
        'storage_location': remotePath['storage_location'] ?? 'local',
        'storage_path': remotePath['storage_path'],
        'local_path': stored.path,
        'privacy_state': 'private',
        'size_bytes': size,
        'pending_upload': synchronizeFiles && !synchronized,
        'extension': path.extension(picked.name).toLowerCase(),
      };
      ids.add(
        await entities.create(
          EntityRecordDraft(
            entityType: 'task_resources',
            parentId: taskId,
            title: picked.name,
            status: 'available',
            data: data,
            synchronize: synchronized,
            syncPayload: synchronized
                ? {
                    'task_occurrence_id': taskId,
                    'task_template_id': null,
                    'roadmap_id': null,
                    'name': picked.name,
                    'resource_type': resourceType,
                    'description': '',
                    'storage_location': 'supabase',
                    'storage_path': remotePath['storage_path'],
                    'local_path': null,
                    'privacy_state': 'private',
                    'open_count': 0,
                    'data': {
                      'size_bytes': size,
                      'extension': path.extension(picked.name).toLowerCase(),
                    },
                  }
                : null,
          ),
        ),
      );
    }
    return ids;
  }

  Future<String> addUrl({
    required String taskId,
    required String url,
    String? title,
  }) {
    final uri = Uri.parse(url);
    final normalized = uri.hasScheme ? uri.toString() : 'https://$url';
    final displayTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : Uri.parse(normalized).host;
    return entities.create(
      EntityRecordDraft(
        entityType: 'task_resources',
        parentId: taskId,
        title: displayTitle,
        status: 'available',
        data: {
          'task_occurrence_id': taskId,
          'name': displayTitle,
          'resource_type': 'url',
          'storage_location': 'url',
          'url': normalized,
          'privacy_state': 'private',
        },
        syncPayload: {
          'task_occurrence_id': taskId,
          'task_template_id': null,
          'roadmap_id': null,
          'name': displayTitle,
          'resource_type': 'url',
          'description': '',
          'storage_location': 'url',
          'storage_path': normalized,
          'local_path': null,
          'privacy_state': 'private',
          'open_count': 0,
        },
      ),
    );
  }

  Future<String> addBook({
    required String taskId,
    required String title,
    String author = '',
    int? totalPages,
    int startPage = 1,
    int? targetEndPage,
    DateTime? targetDate,
  }) async {
    final resourceId = await entities.create(
      EntityRecordDraft(
        entityType: 'task_resources',
        parentId: taskId,
        title: title,
        status: 'available',
        data: {
          'task_occurrence_id': taskId,
          'name': title.trim(),
          'resource_type': 'book',
          'author': author.trim(),
          'storage_location': 'physical',
          'privacy_state': 'private',
        },
        syncPayload: {
          'task_occurrence_id': taskId,
          'task_template_id': null,
          'roadmap_id': null,
          'name': title.trim(),
          'resource_type': 'book',
          'description': author.trim(),
          'storage_location': 'physical',
          'storage_path': null,
          'local_path': null,
          'privacy_state': 'private',
          'open_count': 0,
        },
      ),
    );
    await entities.create(
      EntityRecordDraft(
        entityType: 'reading_targets',
        parentId: taskId,
        secondaryParentId: resourceId,
        title: title,
        status: 'active',
        data: {
          'task_occurrence_id': taskId,
          'resource_id': resourceId,
          'title': title.trim(),
          'author': author.trim(),
          'total_pages': totalPages,
          'start_page': startPage,
          'target_end_page': targetEndPage ?? totalPages,
          'target_date': targetDate == null ? null : _dateOnly(targetDate),
          'count_rereads': false,
          'current_page': startPage,
          'unique_pages': <int>[],
          'reread_pages': <int>[],
          'reading_duration_ms': 0,
        },
        syncPayload: {
          'task_occurrence_id': taskId,
          'resource_id': resourceId,
          'title': title.trim(),
          'author': author.trim(),
          'total_pages': totalPages,
          'start_page': startPage,
          'target_end_page': targetEndPage ?? totalPages,
          'target_date': targetDate == null ? null : _dateOnly(targetDate),
          'count_rereads': false,
        },
      ),
    );
    return resourceId;
  }

  Future<void> open(LocalEntityRecord record) async {
    final data = entities.decode(record);
    final localPath = data['local_path'] as String?;
    if (localPath == null || !File(localPath).existsSync()) {
      throw const FileSystemException(
        'This file is not available on this device',
      );
    }
    await OpenFilex.open(localPath);
    data['open_count'] = ((data['open_count'] as num?)?.toInt() ?? 0) + 1;
    data['last_opened_at'] = DateTime.now().toUtc().toIso8601String();
    await entities.update(record, data: data, synchronize: false);
  }

  Future<File> _copyToAppStorage(
    String taskId,
    File source,
    String fileName,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(
      path.join(support.path, 'task_resources', taskId),
    );
    await directory.create(recursive: true);
    final destination = path.join(
      directory.path,
      '${_uuid.v4()}_${_safeFileName(fileName)}',
    );
    return source.copy(destination);
  }

  String _resourceType(String name) {
    return switch (path.extension(name).toLowerCase()) {
      '.pdf' => 'pdf',
      '.epub' => 'epub',
      '.png' || '.jpg' || '.jpeg' || '.webp' || '.gif' => 'image',
      '.mp3' || '.wav' || '.m4a' || '.ogg' => 'audio',
      '.mp4' || '.mkv' || '.webm' => 'video',
      '.doc' || '.docx' || '.odt' => 'document',
      '.xls' || '.xlsx' || '.ods' || '.csv' => 'spreadsheet',
      _ => 'file',
    };
  }

  String _contentType(String name) {
    return switch (path.extension(name).toLowerCase()) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.mp4' => 'video/mp4',
      '.json' => 'application/json',
      '.txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _dateOnly(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

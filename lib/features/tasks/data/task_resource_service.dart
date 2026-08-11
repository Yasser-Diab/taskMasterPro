import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';
import 'installed_application_service.dart';
import '../domain/task_resource_launch.dart';

String normalizeTaskResourceUrl(String value) {
  final trimmed = value.trim();
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    throw const FormatException('Enter a valid HTTP or HTTPS website address');
  }
  return uri.toString();
}

bool isTaskWebsiteResourceType(String? resourceType) =>
    resourceType == 'url' || resourceType == 'website';

String? taskWebsiteResourceUrl(Map<String, Object?> data) {
  if (!isTaskWebsiteResourceType(data['resource_type'] as String?)) {
    return null;
  }
  final value = data['url'] as String? ?? data['storage_path'] as String? ?? '';
  try {
    return normalizeTaskResourceUrl(value);
  } on FormatException {
    return null;
  }
}

TaskResourceLaunchMode configuredTaskResourceLaunchMode(
  LocalTask task, [
  Map<String, Object?> resource = const {},
]) {
  Map<String, Object?> configuration;
  try {
    final decoded = jsonDecode(task.dataJson);
    configuration = decoded is Map
        ? decoded.map((key, value) => MapEntry('$key', value))
        : const {};
  } catch (_) {
    configuration = const {};
  }
  return TaskResourceLaunchMode.fromKey(
    resource['launch_mode'] ?? configuration['resource_launch_mode'],
  );
}

class TaskResourceService {
  TaskResourceService({required this.entities, required this.client});

  final EntityRecordRepository entities;
  final SupabaseClient client;
  static const _uuid = Uuid();
  static const _resourceChannel = MethodChannel('taskmasterpro/resources');

  Future<TaskResourceLaunchRequest?> preferredWebsiteLaunch(
    LocalTask task,
  ) async {
    final configuration = _taskConfiguration(task);
    if (configuration['auto_open_resource'] == false) return null;
    final taskMode = configuredTaskResourceLaunchMode(task);
    if (taskMode == TaskResourceLaunchMode.disabled) return null;
    final resources = await entities.list(
      entityType: 'task_resources',
      parentId: task.id,
    );
    final websites = <(LocalEntityRecord, Map<String, Object?>, Uri)>[];
    for (final resource in resources) {
      final data = entities.decode(resource);
      final value = taskWebsiteResourceUrl(data);
      final url = value == null ? null : Uri.tryParse(value);
      if (url != null) websites.add((resource, data, url));
    }
    if (websites.isEmpty) return null;
    final selected =
        websites.where((item) => item.$2['is_primary'] == true).firstOrNull ??
        websites.first;
    final resourceMode = configuredTaskResourceLaunchMode(task, selected.$2);
    if (resourceMode == TaskResourceLaunchMode.disabled) return null;
    return TaskResourceLaunchRequest(
      taskId: task.id,
      resourceId: selected.$1.id,
      title: selected.$1.title,
      url: selected.$3,
      mode: resourceMode,
    );
  }

  Future<TaskResourceLaunchOutcome?> launchPreferredWebsite({
    required LocalTask task,
    required FutureOr<void> Function(String url) openInApp,
  }) async {
    final request = await preferredWebsiteLaunch(task);
    if (request == null) return null;
    return launchWebsite(request: request, openInApp: openInApp);
  }

  Future<TaskResourceLaunchOutcome> launchWebsite({
    required TaskResourceLaunchRequest request,
    required FutureOr<void> Function(String url) openInApp,
  }) async {
    TaskResourceLaunchOutcome outcome;
    if (request.mode == TaskResourceLaunchMode.inApp) {
      await Future<void>.sync(() => openInApp(request.url.toString()));
      outcome = TaskResourceLaunchOutcome(opened: true, mode: request.mode);
    } else {
      final preferredPackage =
          request.mode == TaskResourceLaunchMode.externalApp
          ? await _preferredAndroidApplicationPackage(request.taskId)
          : null;
      outcome = await launchExternalResourceWithFallback(
        url: request.url,
        mode: request.mode,
        openInstalledApp: (url) =>
            _openInstalledApplication(url, preferredPackage: preferredPackage),
        openBrowser: _openExternalBrowser,
      );
    }
    if (outcome.opened) {
      unawaited(_recordWebsiteOpen(request.resourceId));
    }
    return outcome;
  }

  Future<TaskResourceLaunchOutcome> launchWebsiteRecord({
    required LocalTask task,
    required LocalEntityRecord resource,
    required TaskResourceLaunchMode mode,
    required FutureOr<void> Function(String url) openInApp,
  }) async {
    final data = entities.decode(resource);
    final value = taskWebsiteResourceUrl(data);
    final url = value == null ? null : Uri.tryParse(value);
    if (url == null) {
      return TaskResourceLaunchOutcome(opened: false, mode: mode);
    }
    return launchWebsite(
      request: TaskResourceLaunchRequest(
        taskId: task.id,
        resourceId: resource.id,
        title: resource.title,
        url: url,
        mode: mode,
      ),
      openInApp: openInApp,
    );
  }

  Future<bool> _openInstalledApplication(
    Uri url, {
    String? preferredPackage,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final result = await _resourceChannel
            .invokeMapMethod<String, Object?>('openResourceUrl', {
              'url': url.toString(),
              'target': 'app',
              'preferredPackage': ?preferredPackage,
            });
        if (result?['opened'] == true) return true;
      } on MissingPluginException {
        // Fall through for widget tests and older installations.
      } on PlatformException {
        // A missing app handler is a normal reason to use the browser.
      }
    }
    try {
      return await launchUrl(
        url,
        mode: LaunchMode.externalNonBrowserApplication,
      );
    } catch (_) {
      return false;
    }
  }

  Future<String?> _preferredAndroidApplicationPackage(String taskId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final rules = await entities.list(
      entityType: 'application_rules',
      parentId: taskId,
    );
    for (final rule in rules) {
      if (rule.status != 'active') continue;
      final ruleData = _flattenEntityData(entities.decode(rule));
      final applicationId = ruleData['application_id'] as String?;
      if (applicationId == null) continue;
      final catalog = await entities.get(applicationId);
      if (catalog == null) continue;
      final catalogData = _flattenEntityData(entities.decode(catalog));
      if ((catalogData['platform'] as String?)?.toLowerCase() != 'android') {
        continue;
      }
      final packageName = androidPackageNameFromApplicationIdentifier(
        (catalogData['application_identifier'] as String?) ?? '',
      );
      if (packageName != null) return packageName;
    }
    return null;
  }

  Map<String, Object?> _flattenEntityData(Map<String, Object?> value) {
    final nested = value['data'];
    return nested is Map
        ? <String, Object?>{...value, ...Map<String, Object?>.from(nested)}
        : value;
  }

  Future<bool> _openExternalBrowser(Uri url) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final result = await _resourceChannel.invokeMapMethod<String, Object?>(
          'openResourceUrl',
          {'url': url.toString(), 'target': 'browser'},
        );
        if (result?['opened'] == true) return true;
      } on MissingPluginException {
        // Fall through to url_launcher.
      } on PlatformException {
        // The platform default below is the final safe fallback.
      }
    }
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _recordWebsiteOpen(String resourceId) async {
    final record = await entities.get(resourceId);
    if (record == null) return;
    final data = entities.decode(record);
    data['open_count'] = ((data['open_count'] as num?)?.toInt() ?? 0) + 1;
    data['last_opened_at'] = DateTime.now().toUtc().toIso8601String();
    await entities.updateLocalData(record, data: data);
  }

  Map<String, Object?> _taskConfiguration(LocalTask task) {
    try {
      final value = jsonDecode(task.dataJson);
      return value is Map
          ? value.map((key, value) => MapEntry('$key', value))
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

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
    TaskResourceLaunchMode launchMode = TaskResourceLaunchMode.inApp,
    double position = 0,
  }) {
    final normalized = normalizeTaskResourceUrl(url);
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
          'launch_mode': launchMode.key,
          'position': position,
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
          'data': {
            'url': normalized,
            'launch_mode': launchMode.key,
            'position': position,
          },
        },
      ),
    );
  }

  Future<void> updateUrl({
    required LocalEntityRecord resource,
    required String url,
    required String title,
    required TaskResourceLaunchMode launchMode,
    required double position,
  }) async {
    final normalized = normalizeTaskResourceUrl(url);
    final displayTitle = title.trim().isEmpty
        ? Uri.parse(normalized).host
        : title.trim();
    final data = entities.decode(resource)
      ..['name'] = displayTitle
      ..['resource_type'] = 'url'
      ..['storage_location'] = 'url'
      ..['storage_path'] = normalized
      ..['url'] = normalized
      ..['launch_mode'] = launchMode.key
      ..['position'] = position;
    await entities.update(
      resource,
      title: displayTitle,
      status: 'available',
      data: data,
      syncPayload: {
        'name': displayTitle,
        'resource_type': 'url',
        'description': data['description'] ?? '',
        'storage_location': 'url',
        'storage_path': normalized,
        'local_path': null,
        'privacy_state': data['privacy_state'] ?? 'private',
        'data': {
          'url': normalized,
          'launch_mode': launchMode.key,
          'position': position,
        },
      },
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
    await entities.updateLocalData(record, data: data);
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

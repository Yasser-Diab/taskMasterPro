import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';

class AccountExportResult {
  const AccountExportResult({required this.path, required this.usedPicker});

  final String path;
  final bool usedPicker;
}

class AccountExportService {
  AccountExportService(this.database, this.client);

  final AppDatabase database;
  final SupabaseClient client;

  Future<AccountExportResult> export() async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before exporting account data.');
    }

    final payload = <String, Object?>{
      'format': 'taskmaster-pro-account-export',
      'format_version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'account': {
        'id': user.id,
        'email': user.email,
        'created_at': user.createdAt,
        'metadata': user.userMetadata,
      },
      'profiles': [
        for (final row in await (database.select(
          database.localProfiles,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'settings': [
        for (final row in await (database.select(
          database.localAppSettings,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'domains': [
        for (final row in await (database.select(
          database.localDomains,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'tasks': [
        for (final row in await (database.select(
          database.localTasks,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'roadmaps': [
        for (final row in await (database.select(
          database.localRoadmaps,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'runtime_states': [
        for (final row in await (database.select(
          database.localRuntimeStates,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'entity_records': [
        for (final row in await (database.select(
          database.localEntityRecords,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'activity_segments': [
        for (final row in await (database.select(
          database.localActivitySegments,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'activity_attributions': [
        for (final row in await (database.select(
          database.localAttributions,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'activity_contributions': [
        for (final row in await (database.select(
          database.localContributions,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'activity_review_queue': [
        for (final row in await (database.select(
          database.localActivityReviews,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
      'pending_sync_commands': [
        for (final row in await (database.select(
          database.localOutboxCommands,
        )..where((row) => row.userId.equals(user.id))).get())
          row.toJson(),
      ],
    };

    const encoder = JsonEncoder.withIndent('  ');
    final bytes = Uint8List.fromList(utf8.encode(encoder.convert(payload)));
    final date = DateTime.now().toLocal();
    final fileName =
        'taskmaster-pro-export-'
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}.json';

    try {
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save TaskMaster Pro account export',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: bytes,
      );
      if (savedPath != null) {
        return AccountExportResult(path: savedPath, usedPicker: true);
      }
    } catch (_) {
      // Some Android document providers do not expose saveFile.
    }

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return AccountExportResult(path: file.path, usedPicker: false);
  }
}

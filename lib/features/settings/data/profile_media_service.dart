import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileImageSelection {
  const ProfileImageSelection({
    required this.localPath,
    required this.fileName,
    required this.contentType,
  });

  final String localPath;
  final String fileName;
  final String contentType;
}

class ProfileMediaService {
  ProfileMediaService(this.client);

  final SupabaseClient client;

  Future<ProfileImageSelection?> chooseAndStore(String userId) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose profile picture',
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) return null;

    final source = File(sourcePath);
    final bytes = await source.length();
    if (bytes > 5 * 1024 * 1024) {
      throw const FileSystemException(
        'Profile pictures must be smaller than 5 MB',
      );
    }

    final extension = path.extension(sourcePath).toLowerCase();
    final normalizedExtension = switch (extension) {
      '.jpg' || '.jpeg' => '.jpg',
      '.png' => '.png',
      '.webp' => '.webp',
      _ => throw const FileSystemException('Choose a JPG, PNG, or WebP image'),
    };
    final support = await getApplicationSupportDirectory();
    final avatarDirectory = Directory(path.join(support.path, 'avatars'));
    await avatarDirectory.create(recursive: true);
    final localPath = path.join(
      avatarDirectory.path,
      '$userId$normalizedExtension',
    );
    await source.copy(localPath);
    return ProfileImageSelection(
      localPath: localPath,
      fileName: '$userId/avatar$normalizedExtension',
      contentType: switch (normalizedExtension) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        _ => 'image/jpeg',
      },
    );
  }

  Future<String> upload(ProfileImageSelection selection) async {
    await client.storage
        .from('avatars')
        .upload(
          selection.fileName,
          File(selection.localPath),
          fileOptions: FileOptions(
            upsert: true,
            contentType: selection.contentType,
            cacheControl: '3600',
          ),
        );
    return selection.fileName;
  }

  Future<String?> signedUrl(String storagePath) async {
    if (storagePath.isEmpty || storagePath.startsWith('http')) {
      return storagePath.isEmpty ? null : storagePath;
    }
    try {
      return await client.storage
          .from('avatars')
          .createSignedUrl(storagePath, 60 * 60);
    } catch (_) {
      return null;
    }
  }
}

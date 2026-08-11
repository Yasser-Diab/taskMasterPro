import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
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

  Future<ProfileImageSelection?> chooseAndStore(
    String userId, {
    bool useCamera = false,
    required String dialogTitle,
  }) async {
    final String? sourcePath;
    if (useCamera && Platform.isAndroid) {
      sourcePath = (await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
        requestFullMetadata: false,
      ))?.path;
    } else {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: dialogTitle,
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      sourcePath = result?.files.single.path;
    }
    if (sourcePath == null) return null;

    final source = File(sourcePath);
    final bytes = await source.length();
    if (bytes > 5 * 1024 * 1024) {
      throw const FileSystemException(
        'Profile pictures must be smaller than 5 MB',
      );
    }

    final extension = path.extension(sourcePath).toLowerCase();
    if (!{'.jpg', '.jpeg', '.png', '.webp'}.contains(extension)) {
      throw const FileSystemException('Choose a JPG, PNG, or WebP image');
    }
    final support = await getApplicationSupportDirectory();
    final avatarDirectory = Directory(path.join(support.path, 'avatars'));
    await avatarDirectory.create(recursive: true);
    final localPath = path.join(
      avatarDirectory.path,
      '$userId-${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    final processed = await Isolate.run(
      () => _prepareAvatar(source.readAsBytesSync()),
    );
    await File(localPath).writeAsBytes(processed, flush: true);
    return ProfileImageSelection(
      localPath: localPath,
      fileName: '$userId/avatar.jpg',
      contentType: 'image/jpeg',
    );
  }

  static Uint8List _prepareAvatar(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FileSystemException('This image could not be opened');
    }
    final oriented = img.bakeOrientation(decoded);
    final square = img.copyResizeCropSquare(oriented, size: 512);
    return Uint8List.fromList(img.encodeJpg(square, quality: 86));
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
            cacheControl: '60',
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

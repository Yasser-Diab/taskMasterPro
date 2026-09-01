import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/release_config.dart';

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.assets,
    this.publishedAt,
    this.isComingSoon = false,
  });

  final String version;
  final String title;
  final String notes;
  final Uri pageUrl;
  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;
  final bool isComingSoon;

  ReleaseAsset? installerForCurrentPlatform() {
    final extension = Platform.isAndroid ? '.apk' : '.exe';
    for (final asset in assets) {
      if (asset.name.toLowerCase().endsWith(extension)) return asset;
    }
    return null;
  }

  ReleaseAsset? checksumFor(ReleaseAsset installer) {
    final expected = '${installer.name}.sha256'.toLowerCase();
    for (final asset in assets) {
      if (asset.name.toLowerCase() == expected) return asset;
    }
    return null;
  }
}

class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> currentVersion() async {
    return (await PackageInfo.fromPlatform()).version;
  }

  Future<AppRelease?> checkForUpdate() async {
    if (!Platform.isAndroid && !Platform.isWindows) return null;
    final current = await currentVersion();
    final response = await _client.get(
      Uri.parse(ReleaseConfig.latestReleaseApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'DayVector-Updater',
      },
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'GitHub release check returned ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String? ?? '').trim();
    final version = tag.toLowerCase().startsWith('v') ? tag.substring(1) : tag;
    if (version.isEmpty || _compareVersions(version, current) <= 0) return null;

    final assets = <ReleaseAsset>[];
    for (final value in json['assets'] as List<dynamic>? ?? const []) {
      final asset = value as Map<String, dynamic>;
      final url = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
      if (url == null) continue;
      assets.add(
        ReleaseAsset(
          name: asset['name'] as String? ?? 'download',
          downloadUrl: url,
          size: (asset['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    return AppRelease(
      version: version,
      title: json['name'] as String? ?? 'DayVector $tag',
      notes: json['body'] as String? ?? '',
      pageUrl:
          Uri.tryParse(json['html_url'] as String? ?? '') ??
          Uri.parse(ReleaseConfig.releasesPage),
      assets: assets,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
    );
  }

  Future<AppRelease> releaseNotesForInstalledVersion({
    String localeCode = 'en',
  }) async {
    final version = await currentVersion();
    final tag = 'v$version';
    final uri = Uri.parse(
      'https://api.github.com/repos/Yasser-Diab/taskMasterPro/releases/tags/$tag',
    );
    final response = await _client
        .get(
          uri,
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'DayVector-Release-Notes',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['tag_name'] == tag &&
          json['draft'] != true &&
          json['prerelease'] != true) {
        return _releaseFromJson(json, version);
      }
    }

    if (response.statusCode == 404) {
      final latestResponse = await _client
          .get(
            Uri.parse(ReleaseConfig.latestReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
              'User-Agent': 'DayVector-Release-Notes',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (latestResponse.statusCode == 404) {
        // GitHub has no published release yet. The installed build is still
        // valid, but its notes must not be guessed from a manifest or an
        // unrelated fallback.
        return _comingSoon(version, localeCode);
      }
      if (latestResponse.statusCode >= 200 && latestResponse.statusCode < 300) {
        final latest = jsonDecode(latestResponse.body) as Map<String, dynamic>;
        final latestTag = (latest['tag_name'] as String? ?? '').trim();
        final latestVersion = latestTag.toLowerCase().startsWith('v')
            ? latestTag.substring(1)
            : latestTag;
        if (latestVersion.isNotEmpty &&
            _compareVersions(version, latestVersion) > 0) {
          return _comingSoon(version, localeCode);
        }
      }
    }
    throw HttpException(
      'Release notes are unavailable for the installed version',
    );
  }

  AppRelease _comingSoon(String version, String localeCode) {
    final notes = switch (localeCode) {
      'ar' =>
        '# قريبًا!\n\n'
            'هذا الإصدار أحدث من أحدث إصدار منشور. ستظهر ملاحظات الإصدار هنا بمجرد نشرها.',
      'de' =>
        '# Demnächst!\n\n'
            'Diese installierte Version ist neuer als die zuletzt veröffentlichte Version. Die Versionshinweise erscheinen hier, sobald sie veröffentlicht wurden.',
      _ =>
        '# Coming soon!\n\n'
            'This installed version is newer than the latest published release. Its release notes will appear here as soon as they are published.',
    };
    return AppRelease(
      version: version,
      title: 'DayVector v$version',
      notes: notes,
      pageUrl: Uri.parse(ReleaseConfig.releasesPage),
      assets: const [],
      isComingSoon: true,
    );
  }

  AppRelease _releaseFromJson(Map<String, dynamic> json, String version) {
    final assets = <ReleaseAsset>[];
    for (final value in json['assets'] as List<dynamic>? ?? const []) {
      final asset = value as Map<String, dynamic>;
      final url = Uri.tryParse(asset['browser_download_url'] as String? ?? '');
      if (url == null) continue;
      assets.add(
        ReleaseAsset(
          name: asset['name'] as String? ?? 'download',
          downloadUrl: url,
          size: (asset['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return AppRelease(
      version: version,
      title: json['name'] as String? ?? 'DayVector v$version',
      notes: json['body'] as String? ?? '',
      pageUrl:
          Uri.tryParse(json['html_url'] as String? ?? '') ??
          Uri.parse(
            'https://github.com/Yasser-Diab/taskMasterPro/releases/tag/v$version',
          ),
      assets: assets,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
    );
  }

  Future<void> downloadAndOpenInstaller(
    AppRelease release, {
    required void Function(double value) onProgress,
  }) async {
    final installer = release.installerForCurrentPlatform();
    if (installer == null) {
      throw const FileSystemException(
        'This release does not include an installer for this device',
      );
    }

    final directory = Directory(
      '${(await getTemporaryDirectory()).path}'
      '${Platform.pathSeparator}taskmaster-pro-update',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${installer.name}',
    );

    final request = http.Request('GET', installer.downloadUrl)
      ..headers.addAll(const {
        'Accept': 'application/octet-stream',
        'User-Agent': 'DayVector-Updater',
      });
    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Installer download returned ${response.statusCode}');
    }

    final total = response.contentLength ?? installer.size;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress((received / total).clamp(0, 1));
      }
    } finally {
      await sink.close();
    }

    await _verifyChecksumIfAvailable(release, installer, file);
    onProgress(1);
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done) {
      throw FileSystemException(result.message, file.path);
    }
  }

  Future<void> _verifyChecksumIfAvailable(
    AppRelease release,
    ReleaseAsset installer,
    File file,
  ) async {
    final checksumAsset = release.checksumFor(installer);
    if (checksumAsset == null) return;
    final response = await _client.get(
      checksumAsset.downloadUrl,
      headers: const {'User-Agent': 'DayVector-Updater'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const FileSystemException('Unable to verify the update checksum');
    }

    final expected = response.body.trim().split(RegExp(r'\s+')).first;
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (expected.toLowerCase() != actual.toLowerCase()) {
      await file.delete();
      throw const FileSystemException(
        'The downloaded update did not pass its integrity check',
      );
    }
  }

  int _compareVersions(String left, String right) {
    final a = _versionParts(left);
    final b = _versionParts(right);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  List<int> _versionParts(String input) {
    final core = input.split(RegExp(r'[-+]')).first;
    return core
        .split('.')
        .map((value) => int.tryParse(value) ?? 0)
        .toList(growable: false);
  }
}

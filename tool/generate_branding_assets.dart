import 'dart:io';

import 'package:path/path.dart' as path;

/// Copies the approved DayVector brand package into every platform surface.
///
/// Release builds run this before validation so a stale launcher, tray,
/// notification, splash, or in-app logo cannot slip into an artifact.
void main() {
  final root = Directory.current.absolute;
  final source = Directory(path.join(root.path, 'DayVectorNewBranding'));
  if (!source.existsSync()) {
    stderr.writeln('Missing approved DayVectorNewBranding package.');
    exitCode = 64;
    return;
  }

  _copyFile(
    source,
    '01_Master_Artwork/DayVector_Lockup_Horizontal.svg',
    root,
    'media/app-logo/DayVector_Horizontal.svg',
  );
  _copyFile(
    source,
    '01_Master_Artwork/DayVector_Lockup_Dark.svg',
    root,
    'media/app-logo/DayVector_Horizontal_Dark.svg',
  );
  _copyFile(
    source,
    '02_Master_PNG/DayVector_Horizontal_2400.png',
    root,
    'media/app-logo/DayVector_Horizontal_840.png',
  );
  _copyFile(
    source,
    '04_Lockups_PNG/DayVector_Horizontal_Light_600.png',
    root,
    'media/app-logo/DayVector_Horizontal_Light_600.png',
  );
  _copyFile(
    source,
    '04_Lockups_PNG/DayVector_Horizontal_Dark_600.png',
    root,
    'media/app-logo/DayVector_Horizontal_Dark_600.png',
  );
  _copyFile(
    source,
    '03_Symbol_PNG/DayVector_Symbol_Approved_128.png',
    root,
    'media/app-logo/DayVector_Symbol_128.png',
  );
  _copyFile(
    source,
    '01_Master_Artwork/DayVector_Symbol_Approved_Exact.svg',
    root,
    'media/app-logo/DayVector_Symbol.svg',
  );
  _copyFile(
    source,
    '06_Windows/DayVector_App.ico',
    root,
    'windows/runner/resources/app_icon.ico',
  );
  _copyFile(
    source,
    '06_Windows/DayVector_Tray.ico',
    root,
    'windows/runner/resources/tray_icon.ico',
  );

  for (final version in const ['v26', 'v33']) {
    _copyFile(
      source,
      '05_Android/adaptive/ic_launcher.xml',
      root,
      'android/app/src/main/res/mipmap-anydpi-$version/ic_launcher.xml',
    );
    _copyFile(
      source,
      '05_Android/adaptive/ic_launcher.xml',
      root,
      'android/app/src/main/res/mipmap-anydpi-$version/ic_launcher_round.xml',
    );
  }
  const legacySizes = <String, int>{
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in legacySizes.entries) {
    for (final name in const ['ic_launcher.png', 'ic_launcher_round.png']) {
      _copyFile(
        source,
        '05_Android/legacy/ic_launcher_${entry.key}_${entry.value}.png',
        root,
        'android/app/src/main/res/mipmap-${entry.key}/$name',
      );
    }
  }
  const notificationSizes = <String, int>{
    'mdpi': 24,
    'hdpi': 36,
    'xhdpi': 48,
    'xxhdpi': 72,
    'xxxhdpi': 96,
  };
  for (final entry in notificationSizes.entries) {
    _copyFile(
      source,
      '05_Android/notification/'
          'ic_stat_dayvector_${entry.key}_${entry.value}.png',
      root,
      'android/app/src/main/res/drawable-${entry.key}/ic_notification.png',
    );
    _copyFile(
      source,
      '05_Android/notification/'
          'ic_stat_dayvector_${entry.key}_${entry.value}.png',
      root,
      'android/app/src/main/res/drawable-${entry.key}/ic_stat_dayvector.png',
    );
  }
  _deleteFile(
    root,
    'android/app/src/main/res/drawable/ic_launcher_foreground.xml',
  );
  _deleteFile(
    root,
    'android/app/src/main/res/drawable/ic_launcher_monochrome.xml',
  );
  _copyFile(
    source,
    '05_Android/adaptive/ic_launcher_foreground_432.png',
    root,
    'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png',
  );
  _copyFile(
    source,
    '05_Android/adaptive/ic_launcher_monochrome_432.png',
    root,
    'android/app/src/main/res/drawable-nodpi/ic_launcher_monochrome.png',
  );
  _copyFile(
    source,
    '09_Splash/DayVector_Splash_Light_1080x1920.png',
    root,
    'android/app/src/main/res/drawable-nodpi/dayvector_splash.png',
  );
  _copyFile(
    source,
    '09_Splash/DayVector_Splash_Dark_1080x1920.png',
    root,
    'android/app/src/main/res/drawable-night-nodpi/dayvector_splash.png',
  );

  _copyFile(
    source,
    '01_Master_Artwork/DayVector_Symbol_Approved_Exact.svg',
    root,
    'landing-page/assets/brand/dayvector-symbol.svg',
  );
  _copyFile(
    source,
    '01_Master_Artwork/DayVector_Lockup_Horizontal.svg',
    root,
    'landing-page/assets/brand/dayvector-horizontal.svg',
  );
  _copyFile(
    source,
    '01_Master_Artwork/DayVector_Lockup_Dark.svg',
    root,
    'landing-page/assets/brand/dayvector-horizontal-dark.svg',
  );
  for (final file in const [
    'android-chrome-192x192.png',
    'android-chrome-512x512.png',
    'apple-touch-icon.png',
    'favicon-16x16.png',
    'favicon-32x32.png',
    'favicon.ico',
  ]) {
    _copyFile(source, '07_Web_Favicon/$file', root, 'landing-page/$file');
  }
  _copyFile(
    source,
    '01_Master_Artwork/DayVector_Symbol_Approved_Exact.svg',
    root,
    'landing-page/favicon.svg',
  );
  _copyFile(
    source,
    '08_Social/DayVector_OpenGraph_1200x630.png',
    root,
    'landing-page/social-preview-1200x630.png',
  );
  _copyFile(
    source,
    '08_Social/DayVector_Social_Square_1080.png',
    root,
    'landing-page/social-avatar-1024.png',
  );
}

void _copyFile(
  Directory sourceRoot,
  String sourceRelative,
  Directory targetRoot,
  String targetRelative,
) {
  final source = File(
    path.joinAll([sourceRoot.path, ...sourceRelative.split('/')]),
  );
  if (!source.existsSync()) {
    throw StateError('Missing approved branding asset: ${source.path}');
  }
  final target = File(
    path.joinAll([targetRoot.path, ...targetRelative.split('/')]),
  );
  target.parent.createSync(recursive: true);
  source.copySync(target.path);
  stdout.writeln(path.relative(target.path));
}

void _deleteFile(Directory targetRoot, String targetRelative) {
  final target = File(
    path.joinAll([targetRoot.path, ...targetRelative.split('/')]),
  );
  if (!target.existsSync()) return;
  target.deleteSync();
  stdout.writeln('${path.relative(target.path)} (removed stale asset)');
}

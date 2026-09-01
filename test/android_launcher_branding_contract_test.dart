import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _hash(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  final root = Directory.current.path;
  final brand = '$root/DayVectorNewBranding';
  final resources = '$root/android/app/src/main/res';

  test(
    'every Android launcher density matches the approved DayVector pack',
    () {
      for (final density in const [
        'mdpi',
        'hdpi',
        'xhdpi',
        'xxhdpi',
        'xxxhdpi',
      ]) {
        final size = const {
          'mdpi': 48,
          'hdpi': 72,
          'xhdpi': 96,
          'xxhdpi': 144,
          'xxxhdpi': 192,
        }[density]!;
        for (final name in const ['ic_launcher.png', 'ic_launcher_round.png']) {
          final approved =
              '$brand/05_Android/legacy/ic_launcher_${density}_$size.png';
          final packaged = '$resources/mipmap-$density/$name';
          expect(File(approved).existsSync(), isTrue, reason: approved);
          expect(_hash(packaged), _hash(approved), reason: packaged);
        }
      }
    },
  );

  test('adaptive, monochrome, and notification art use DayVector assets', () {
    final approvedAdaptive = File(
      '$brand/05_Android/adaptive/ic_launcher.xml',
    ).readAsStringSync();
    for (final version in const ['v26', 'v33']) {
      final adaptive = File(
        '$resources/mipmap-anydpi-$version/ic_launcher.xml',
      ).readAsStringSync();
      expect(adaptive, approvedAdaptive, reason: version);
      expect(adaptive, contains('@drawable/ic_launcher_foreground'));
      expect(adaptive, contains('@drawable/ic_launcher_monochrome'));
    }

    expect(
      _hash('$resources/drawable-nodpi/ic_launcher_foreground.png'),
      _hash('$brand/05_Android/adaptive/ic_launcher_foreground_432.png'),
    );
    expect(
      _hash('$resources/drawable-nodpi/ic_launcher_monochrome.png'),
      _hash('$brand/05_Android/adaptive/ic_launcher_monochrome_432.png'),
    );

    for (final density in const [
      'mdpi',
      'hdpi',
      'xhdpi',
      'xxhdpi',
      'xxxhdpi',
    ]) {
      final size = const {
        'mdpi': 24,
        'hdpi': 36,
        'xhdpi': 48,
        'xxhdpi': 72,
        'xxxhdpi': 96,
      }[density]!;
      final approved =
          '$brand/05_Android/notification/'
          'ic_stat_dayvector_${density}_$size.png';
      final packaged = '$resources/drawable-$density/ic_notification.png';
      expect(_hash(packaged), _hash(approved), reason: packaged);
    }
  });

  test(
    'manifest and splash expose DayVector without changing app identity',
    () {
      final manifest = File(
        '$root/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:label="@string/app_name"'));
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
      expect(manifest, contains('android:scheme="pro.taskmaster.app"'));

      final strings = File('$resources/values/strings.xml').readAsStringSync();
      expect(strings, contains('<string name="app_name">DayVector</string>'));
      final splash = File(
        '$resources/drawable/launch_background.xml',
      ).readAsStringSync();
      expect(splash, contains('@drawable/dayvector_splash'));
    },
  );
}

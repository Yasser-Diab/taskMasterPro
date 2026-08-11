import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

const _densitySizes = <String, ({int launcher, int adaptive})>{
  'mdpi': (launcher: 48, adaptive: 108),
  'hdpi': (launcher: 72, adaptive: 162),
  'xhdpi': (launcher: 96, adaptive: 216),
  'xxhdpi': (launcher: 144, adaptive: 324),
  'xxxhdpi': (launcher: 192, adaptive: 432),
};

const _notificationHashes = <String, String>{
  'mdpi': 'c631a8fef230dc665bfa93939439d5bc9d3aaef5b70a83979178e72886224423',
  'hdpi': 'fc101eee9ab6fd2d19feaaee2349040b543f893c03e0b2de27a583c48e17b725',
  'xhdpi': '044b7794e71bb312ca7f37971add169747c28ebf84cdac30b1aea0ed68b78466',
  'xxhdpi': '430c23f7a59f0c2bfe94b4e8571e4c247a197902298768200abd26ac70fc63b1',
  'xxxhdpi': '185859e248a8b6405ec31e71315b4b9796f9fd09374eb2644555d5f390864dae',
};

void main() {
  final root = Directory.current;
  final sourceFile = File(
    '${root.path}/media/icons-badges_source/Android_app_badge-gold.png',
  );
  final resourceRoot = '${root.path}/android/app/src/main/res';

  test('approved gold badge is the Android legacy launcher artwork', () {
    expect(sourceFile.existsSync(), isTrue);
    final source = image.decodePng(sourceFile.readAsBytesSync());
    expect(source, isNotNull);

    final shortestSide = math.min(source!.width, source.height);
    final side = (shortestSide * 0.90).round();
    final crop = image.copyCrop(
      source,
      x: (source.width / 2 - side / 2).round().clamp(0, source.width - side),
      y: (source.height * 0.515 - side / 2).round().clamp(
        0,
        source.height - side,
      ),
      width: side,
      height: side,
    );

    for (final entry in _densitySizes.entries) {
      final path = '$resourceRoot/mipmap-${entry.key}/ic_launcher.png';
      final launcher = image.decodePng(File(path).readAsBytesSync());
      expect(launcher, isNotNull, reason: path);
      expect(launcher!.width, entry.value.launcher, reason: path);
      expect(launcher.height, entry.value.launcher, reason: path);

      final expected = image.copyResize(
        crop,
        width: entry.value.launcher,
        height: entry.value.launcher,
        interpolation: image.Interpolation.cubic,
      );
      final expectedComposite = image.Image(
        width: entry.value.launcher,
        height: entry.value.launcher,
        numChannels: 4,
      );
      image.compositeImage(expectedComposite, expected);
      final start = entry.value.launcher ~/ 4;
      final end = entry.value.launcher - start;
      final step = math.max(1, entry.value.launcher ~/ 12);
      for (var y = start; y < end; y += step) {
        for (var x = start; x < end; x += step) {
          final actualPixel = launcher.getPixel(x, y);
          final expectedPixel = expectedComposite.getPixel(x, y);
          expect(
            (actualPixel.r - expectedPixel.r).abs(),
            lessThanOrEqualTo(2),
            reason: '$path red channel at ($x, $y)',
          );
          expect(
            (actualPixel.g - expectedPixel.g).abs(),
            lessThanOrEqualTo(2),
            reason: '$path green channel at ($x, $y)',
          );
          expect(
            (actualPixel.b - expectedPixel.b).abs(),
            lessThanOrEqualTo(2),
            reason: '$path blue channel at ($x, $y)',
          );
          expect(
            (actualPixel.a - expectedPixel.a).abs(),
            lessThanOrEqualTo(1),
            reason: '$path alpha channel at ($x, $y)',
          );
        }
      }
    }
  });

  test('adaptive badge stays centered inside the Android safe zone', () {
    for (final entry in _densitySizes.entries) {
      final size = entry.value.adaptive;
      final path =
          '$resourceRoot/mipmap-${entry.key}/ic_launcher_foreground.png';
      final foreground = image.decodePng(File(path).readAsBytesSync());
      expect(foreground, isNotNull, reason: path);
      expect(foreground!.width, size, reason: path);
      expect(foreground.height, size, reason: path);

      var minX = size;
      var minY = size;
      var maxX = -1;
      var maxY = -1;
      for (final pixel in foreground) {
        if (pixel.a == 0) {
          continue;
        }
        minX = math.min(minX, pixel.x);
        minY = math.min(minY, pixel.y);
        maxX = math.max(maxX, pixel.x);
        maxY = math.max(maxY, pixel.y);
      }

      final safeZone = (size * 66 / 108).floor();
      expect(maxX - minX + 1, lessThanOrEqualTo(safeZone), reason: path);
      expect(maxY - minY + 1, lessThanOrEqualTo(safeZone), reason: path);
      expect(
        (minX + maxX) / 2,
        closeTo((size - 1) / 2, math.max(2, size * 0.01)),
        reason: path,
      );
      expect(
        (minY + maxY) / 2,
        closeTo((size - 1) / 2, math.max(2, size * 0.01)),
        reason: path,
      );

      final backgroundPath =
          '$resourceRoot/mipmap-${entry.key}/ic_launcher_background.png';
      final background = image.decodePng(
        File(backgroundPath).readAsBytesSync(),
      );
      expect(background, isNotNull, reason: backgroundPath);
      expect(background!.width, size, reason: backgroundPath);
      expect(background.height, size, reason: backgroundPath);
      expect(background.every((pixel) => pixel.a == 255), isTrue);
    }
  });

  test(
    'manifest launcher and recent-app icon point at generated resources',
    () {
      final manifest = File(
        '${root.path}/android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
      expect(
        manifest,
        contains('android:roundIcon="@mipmap/ic_launcher_round"'),
      );

      for (final version in const ['v26', 'v33']) {
        final adaptive = File(
          '$resourceRoot/mipmap-anydpi-$version/ic_launcher.xml',
        ).readAsStringSync();
        expect(
          adaptive,
          contains('@mipmap/ic_launcher_foreground'),
          reason: version,
        );
        expect(
          adaptive,
          contains('@mipmap/ic_launcher_background'),
          reason: version,
        );
      }
    },
  );

  test(
    'launcher change does not replace the monochrome notification glyph',
    () {
      for (final entry in _notificationHashes.entries) {
        final path = '$resourceRoot/drawable-${entry.key}/ic_notification.png';
        expect(
          sha256.convert(File(path).readAsBytesSync()).toString(),
          entry.value,
          reason: path,
        );
      }
    },
  );
}

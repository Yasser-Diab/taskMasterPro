import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as image;

final _brandNavy = image.ColorRgba8(5, 20, 43, 255);
final _androidBadgeBackground = image.ColorRgba8(15, 9, 2, 255);
final _transparent = image.ColorRgba8(0, 0, 0, 0);
final _white = image.ColorRgba8(255, 255, 255, 255);

const _androidLauncherSourceName = 'Android_app_badge-gold.png';
const _androidBadgeCropFraction = 0.90;
const _androidBadgeVerticalCenter = 0.515;
const _androidAdaptiveSafeZoneFraction = 66 / 108;

const _androidDensities = <String, ({int launcher, int adaptive, int glyph})>{
  'mdpi': (launcher: 48, adaptive: 108, glyph: 24),
  'hdpi': (launcher: 72, adaptive: 162, glyph: 36),
  'xhdpi': (launcher: 96, adaptive: 216, glyph: 48),
  'xxhdpi': (launcher: 144, adaptive: 324, glyph: 72),
  'xxxhdpi': (launcher: 192, adaptive: 432, glyph: 96),
};

void main() {
  final root = Directory.current.absolute;
  final pubspec = File(_path(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    stderr.writeln(
      'Run this generator from the TaskMaster Pro repository root.',
    );
    exitCode = 64;
    return;
  }

  final sourceDirectory = _path(root.path, 'media', 'icons-badges_source');
  final primary = _readApprovedSource(
    _path(sourceDirectory, 'Compact_logo 1.png'),
  );
  final androidBadge = _readApprovedSource(
    _path(sourceDirectory, _androidLauncherSourceName),
    trimTransparent: false,
  );
  final onLight = _readApprovedSource(
    _path(sourceDirectory, 'solid-dark-logo.png'),
  );
  final onDark = _readApprovedSource(
    _path(sourceDirectory, 'solid-light-logo.png'),
  );
  final gold = _readApprovedSource(_path(sourceDirectory, 'gold-compact.png'));

  _writeWindowsIcons(root.path, primary);
  _writeAndroidIcons(
    root.path,
    launcherBadge: androidBadge,
    notificationMark: primary,
  );
  _writeSplashAndThemeVariants(root.path, onLight, onDark, gold, primary);
}

image.Image _readApprovedSource(String path, {bool trimTransparent = true}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Missing approved branding source: $path');
  }
  final decoded = image.decodePng(file.readAsBytesSync());
  if (decoded == null) {
    throw StateError('Could not decode approved branding source: $path');
  }
  return trimTransparent
      ? image.trim(decoded, mode: image.TrimMode.transparent)
      : decoded;
}

void _writeWindowsIcons(String root, image.Image primary) {
  _writeIco(
    _path(root, 'windows', 'runner', 'resources', 'app_icon.ico'),
    const [16, 20, 24, 32, 40, 48, 64, 128, 256],
    (size) => _badge(primary, size),
  );
  _writeIco(
    _path(root, 'windows', 'runner', 'resources', 'tray_icon.ico'),
    const [16, 20, 24, 32, 48],
    (size) => _transparentMark(primary, size, occupancy: 0.92),
  );
}

void _writeAndroidIcons(
  String root, {
  required image.Image launcherBadge,
  required image.Image notificationMark,
}) {
  final resourceRoot = _path(root, 'android', 'app', 'src', 'main', 'res');
  final approvedBadge = _cropApprovedAndroidBadge(launcherBadge);
  for (final entry in _androidDensities.entries) {
    final density = entry.key;
    final sizes = entry.value;
    final mipmap = _path(resourceRoot, 'mipmap-$density');
    final drawable = _path(resourceRoot, 'drawable-$density');

    _writePng(
      _path(mipmap, 'ic_launcher.png'),
      _androidLegacyBadge(approvedBadge, sizes.launcher),
    );
    _writePng(
      _path(mipmap, 'ic_launcher_round.png'),
      _androidLegacyRoundBadge(approvedBadge, sizes.launcher),
    );
    _writePng(
      _path(mipmap, 'ic_launcher_foreground.png'),
      _androidAdaptiveForeground(approvedBadge, sizes.adaptive),
    );
    _writePng(
      _path(mipmap, 'ic_launcher_background.png'),
      _solidCanvas(sizes.adaptive, _androidBadgeBackground),
    );
    _writePng(
      _path(drawable, 'ic_launcher_monochrome.png'),
      _monochromeMark(notificationMark, sizes.adaptive, occupancy: 0.58),
    );
    _writePng(
      _path(drawable, 'ic_notification.png'),
      _monochromeMark(notificationMark, sizes.glyph, occupancy: 0.82),
    );
  }
}

/// Crops the approved landscape source to the authored rounded-square badge.
///
/// The source deliberately contains presentation space around the badge. This
/// crop removes only that space; it does not redraw, recolor, or substitute the
/// supplied artwork.
image.Image _cropApprovedAndroidBadge(image.Image source) {
  final shortestSide = math.min(source.width, source.height);
  final side = (shortestSide * _androidBadgeCropFraction).round();
  final centerX = source.width / 2;
  final centerY = source.height * _androidBadgeVerticalCenter;
  return image.copyCrop(
    source,
    x: (centerX - side / 2).round().clamp(0, source.width - side),
    y: (centerY - side / 2).round().clamp(0, source.height - side),
    width: side,
    height: side,
  );
}

image.Image _androidLegacyBadge(image.Image badge, int size) {
  final resized = image.copyResize(
    badge,
    width: size,
    height: size,
    interpolation: image.Interpolation.cubic,
  );
  return _maskedBadge(resized, radiusFraction: 0.22);
}

image.Image _androidLegacyRoundBadge(image.Image badge, int size) {
  final resized = image.copyResize(
    badge,
    width: size,
    height: size,
    interpolation: image.Interpolation.cubic,
  );
  final mask = _solidCanvas(size, _transparent);
  image.fillCircle(
    mask,
    x: size ~/ 2,
    y: size ~/ 2,
    radius: size ~/ 2,
    color: _white,
    antialias: true,
  );
  final result = _solidCanvas(size, _transparent);
  image.compositeImage(
    result,
    resized,
    mask: mask,
    maskChannel: image.Channel.alpha,
  );
  return result;
}

image.Image _androidAdaptiveForeground(image.Image badge, int size) {
  // Android's guaranteed unmasked safe zone is 66 dp inside the 108 dp
  // adaptive-icon viewport. Keep the complete approved badge inside it so
  // circles, squircles, rounded squares, and OEM masks never cut the check or
  // hourglass away.
  final badgeSize = math.max(
    1,
    (size * _androidAdaptiveSafeZoneFraction).floor(),
  );
  final resized = image.copyResize(
    badge,
    width: badgeSize,
    height: badgeSize,
    interpolation: image.Interpolation.cubic,
  );
  final clipped = _maskedBadge(resized, radiusFraction: 0.22);
  final result = _solidCanvas(size, _transparent);
  image.compositeImage(
    result,
    clipped,
    dstX: (size - badgeSize) ~/ 2,
    dstY: (size - badgeSize) ~/ 2,
  );
  return result;
}

image.Image _maskedBadge(image.Image badge, {required double radiusFraction}) {
  final mask = _solidCanvas(badge.width, _transparent);
  image.fillRect(
    mask,
    x1: 0,
    y1: 0,
    x2: badge.width - 1,
    y2: badge.height - 1,
    radius: badge.width * radiusFraction,
    color: _white,
  );
  final result = _solidCanvas(badge.width, _transparent);
  image.compositeImage(
    result,
    badge,
    mask: mask,
    maskChannel: image.Channel.alpha,
  );
  return result;
}

void _writeSplashAndThemeVariants(
  String root,
  image.Image onLight,
  image.Image onDark,
  image.Image gold,
  image.Image primary,
) {
  final resourceRoot = _path(root, 'android', 'app', 'src', 'main', 'res');
  _writePng(
    _path(resourceRoot, 'drawable-nodpi', 'taskmaster_splash.png'),
    _transparentMark(onLight, 512, occupancy: 0.72),
  );
  _writePng(
    _path(resourceRoot, 'drawable-night-nodpi', 'taskmaster_splash.png'),
    _transparentMark(onDark, 512, occupancy: 0.72),
  );

  final flutterAssets = _path(root, 'media', 'app-logo');
  _writePng(
    _path(flutterAssets, 'TaskMaster_Pro_Compact_Primary.png'),
    _transparentMark(primary, 512, occupancy: 0.90),
  );
  _writePng(
    _path(flutterAssets, 'TaskMaster_Pro_Compact_On_Light.png'),
    _transparentMark(onLight, 512, occupancy: 0.90),
  );
  _writePng(
    _path(flutterAssets, 'TaskMaster_Pro_Compact_On_Dark.png'),
    _transparentMark(onDark, 512, occupancy: 0.90),
  );
  _writePng(
    _path(flutterAssets, 'TaskMaster_Pro_Compact_Gold.png'),
    _transparentMark(gold, 512, occupancy: 0.90),
  );
}

image.Image _badge(image.Image source, int size) {
  final canvas = _solidCanvas(size, _transparent);
  final inset = math.max(1, (size * 0.025).round());
  image.fillRect(
    canvas,
    x1: inset,
    y1: inset,
    x2: size - inset - 1,
    y2: size - inset - 1,
    radius: size * 0.22,
    color: _brandNavy,
  );
  return _placeMark(canvas, source, occupancy: 0.76);
}

image.Image _transparentMark(
  image.Image source,
  int size, {
  required double occupancy,
}) =>
    _placeMark(_solidCanvas(size, _transparent), source, occupancy: occupancy);

image.Image _monochromeMark(
  image.Image source,
  int size, {
  required double occupancy,
}) {
  final colored = _transparentMark(source, size, occupancy: occupancy);
  final result = _solidCanvas(size, _transparent);
  for (final pixel in colored) {
    if (pixel.a == 0) {
      continue;
    }
    result.setPixelRgba(
      pixel.x,
      pixel.y,
      _white.r,
      _white.g,
      _white.b,
      pixel.a,
    );
  }
  return result;
}

image.Image _placeMark(
  image.Image canvas,
  image.Image source, {
  required double occupancy,
}) {
  final maximum = canvas.width * occupancy;
  final scale = math.min(maximum / source.width, maximum / source.height);
  final width = math.max(1, (source.width * scale).round());
  final height = math.max(1, (source.height * scale).round());
  final resized = image.copyResize(
    source,
    width: width,
    height: height,
    interpolation: image.Interpolation.cubic,
  );
  image.compositeImage(
    canvas,
    resized,
    dstX: (canvas.width - width) ~/ 2,
    dstY: (canvas.height - height) ~/ 2,
  );
  return canvas;
}

image.Image _solidCanvas(int size, image.Color color) {
  final canvas = image.Image(width: size, height: size, numChannels: 4);
  return image.fill(canvas, color: color);
}

void _writePng(String path, image.Image value) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(image.encodePng(value, level: 9), flush: true);
  stdout.writeln('${_relative(path)} ${value.width}x${value.height} PNG');
}

void _writeIco(
  String path,
  List<int> sizes,
  image.Image Function(int size) render,
) {
  final first = render(sizes.first);
  for (final size in sizes.skip(1)) {
    first.addFrame(render(size));
  }
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(image.encodeIco(first), flush: true);
  stdout.writeln('${_relative(path)} ${sizes.join('/')} ICO');
}

String _path(
  String first, [
  String? second,
  String? third,
  String? fourth,
  String? fifth,
  String? sixth,
  String? seventh,
]) {
  return <String?>[
    first,
    second,
    third,
    fourth,
    fifth,
    sixth,
    seventh,
  ].whereType<String>().join(Platform.pathSeparator);
}

String _relative(String path) => path.replaceFirst(
  '${Directory.current.absolute.path}${Platform.pathSeparator}',
  '',
);

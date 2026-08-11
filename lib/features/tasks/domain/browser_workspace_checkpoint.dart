import 'dart:convert';

/// A deliberately small, privacy-preserving browser resume checkpoint.
///
/// It contains only the state needed to return a task workspace to a lesson:
/// the page address/title, page position, an optional media timestamp, and the
/// browser's reported zoom scale.  It never serializes DOM content, form data,
/// cookies, credentials, or the page's back/forward history.
class BrowserWorkspaceCheckpoint {
  const BrowserWorkspaceCheckpoint({
    this.url,
    this.title,
    this.scrollX,
    this.scrollY,
    this.mediaPositionSeconds,
    this.zoomScale,
    this.updatedAt,
  });

  final String? url;
  final String? title;
  final double? scrollX;
  final double? scrollY;
  final double? mediaPositionSeconds;
  final double? zoomScale;
  final DateTime? updatedAt;

  /// Reads the JSONB value stored by the browser-tab record.  Malformed,
  /// unexpected, or legacy values are ignored rather than breaking a tab.
  factory BrowserWorkspaceCheckpoint.fromStored(Object? raw) {
    final values = _mapFrom(raw);
    if (values == null) return const BrowserWorkspaceCheckpoint();
    return BrowserWorkspaceCheckpoint(
      url: _boundedText(values['url'], 4096),
      title: _boundedText(values['title'], 512),
      scrollX: _boundedNumber(values['scroll_x'], minimum: 0, maximum: 1e9),
      scrollY: _boundedNumber(values['scroll_y'], minimum: 0, maximum: 1e9),
      mediaPositionSeconds: _boundedNumber(
        values['media_position_seconds'],
        minimum: 0,
        maximum: 31557600,
      ),
      zoomScale: _boundedNumber(
        values['zoom_scale'],
        minimum: 0.25,
        maximum: 4,
      ),
      updatedAt: _date(values['updated_at']),
    );
  }

  /// Parses the result returned by WebView JavaScript.  The Windows WebView2
  /// plugin and Android WebView expose JSON results differently, so accepting
  /// both a Map and a JSON string keeps the platform boundary intentionally
  /// narrow.
  factory BrowserWorkspaceCheckpoint.fromJavaScript(Object? raw) {
    return BrowserWorkspaceCheckpoint.fromStored(raw);
  }

  bool get isEmpty =>
      url == null &&
      title == null &&
      scrollX == null &&
      scrollY == null &&
      mediaPositionSeconds == null &&
      zoomScale == null;

  /// Updates known fields without letting a page erase durable information
  /// simply because a WebView omitted an optional value on one callback.
  BrowserWorkspaceCheckpoint mergedWith(BrowserWorkspaceCheckpoint incoming) {
    return BrowserWorkspaceCheckpoint(
      url: incoming.url ?? url,
      title: incoming.title ?? title,
      scrollX: incoming.scrollX ?? scrollX,
      scrollY: incoming.scrollY ?? scrollY,
      mediaPositionSeconds:
          incoming.mediaPositionSeconds ?? mediaPositionSeconds,
      zoomScale: incoming.zoomScale ?? zoomScale,
      updatedAt: incoming.updatedAt ?? updatedAt,
    );
  }

  BrowserWorkspaceCheckpoint withMetadata({String? url, String? title}) {
    return BrowserWorkspaceCheckpoint(
      url: _boundedText(url, 4096) ?? this.url,
      title: _boundedText(title, 512) ?? this.title,
      scrollX: scrollX,
      scrollY: scrollY,
      mediaPositionSeconds: mediaPositionSeconds,
      zoomScale: zoomScale,
      updatedAt: updatedAt,
    );
  }

  BrowserWorkspaceCheckpoint stamped(DateTime time) {
    return BrowserWorkspaceCheckpoint(
      url: url,
      title: title,
      scrollX: scrollX,
      scrollY: scrollY,
      mediaPositionSeconds: mediaPositionSeconds,
      zoomScale: zoomScale,
      updatedAt: time.toUtc(),
    );
  }

  /// The payload is intentionally stable: [updatedAt] does not decide whether
  /// a checkpoint changed, avoiding writes just because a periodic local
  /// capture happened while the user stayed on the same page.
  bool sameContent(BrowserWorkspaceCheckpoint other) {
    return url == other.url &&
        title == other.title &&
        scrollX == other.scrollX &&
        scrollY == other.scrollY &&
        mediaPositionSeconds == other.mediaPositionSeconds &&
        zoomScale == other.zoomScale;
  }

  /// Restoring a position after an authentication redirect or to a different
  /// page can be surprising.  A checkpoint is therefore eligible only for the
  /// same scheme/host/path; query and fragment changes are deliberately
  /// ignored because learning sites commonly append tracking parameters.
  bool matchesPage(String pageUrl) {
    final saved = Uri.tryParse(url ?? '');
    final page = Uri.tryParse(pageUrl);
    if (saved == null ||
        page == null ||
        saved.host.isEmpty ||
        page.host.isEmpty) {
      return false;
    }
    return saved.scheme.toLowerCase() == page.scheme.toLowerCase() &&
        saved.host.toLowerCase() == page.host.toLowerCase() &&
        _normalizedPath(saved.path) == _normalizedPath(page.path);
  }

  Map<String, Object?> toStorage() {
    return <String, Object?>{
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (scrollX != null) 'scroll_x': scrollX,
      if (scrollY != null) 'scroll_y': scrollY,
      if (mediaPositionSeconds != null)
        'media_position_seconds': mediaPositionSeconds,
      if (zoomScale != null) 'zoom_scale': zoomScale,
      if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
    };
  }
}

/// Captures only the active document's resume markers.  This script is polled
/// on a modest cadence and never installs a scroll listener, so scrolling does
/// not turn into a stream of database writes or synchronization traffic.
const browserWorkspaceCheckpointCaptureScript = r'''
(() => {
  const mediaElements = Array.from(document.querySelectorAll('video, audio'));
  const firstMedia = mediaElements.find(
    (element) => !element.paused && Number.isFinite(element.currentTime),
  ) || mediaElements.find((element) => Number.isFinite(element.currentTime));
  const viewportScale = window.visualViewport &&
      Number.isFinite(window.visualViewport.scale)
    ? window.visualViewport.scale
    : 1;
  return JSON.stringify({
    url: window.location.href,
    title: document.title || '',
    scroll_x: Math.max(0, Number(window.scrollX || window.pageXOffset || 0)),
    scroll_y: Math.max(0, Number(window.scrollY || window.pageYOffset || 0)),
    media_position_seconds: firstMedia ? Number(firstMedia.currentTime) : null,
    zoom_scale: viewportScale,
  });
})()
''';

/// Builds a conservative restore operation.  It does not autoplay media or
/// write to form controls.  The WebView owns native zoom; callers may restore
/// it where their platform exposes a safe native zoom setter.
String buildBrowserWorkspaceCheckpointRestoreScript(
  BrowserWorkspaceCheckpoint checkpoint,
) {
  final encoded = jsonEncode(checkpoint.toStorage());
  return '''
(() => {
  const saved = $encoded;
  const normalizedPath = (path) => path && path !== '' ? path : '/';
  let expected;
  try {
    expected = new URL(saved.url || '');
  } catch (_) {
    return false;
  }
  if (expected.origin !== window.location.origin ||
      normalizedPath(expected.pathname) !== normalizedPath(window.location.pathname)) {
    return false;
  }
  const restore = () => {
    if (Number.isFinite(saved.scroll_x) || Number.isFinite(saved.scroll_y)) {
      window.scrollTo(
        Number.isFinite(saved.scroll_x) ? saved.scroll_x : window.scrollX,
        Number.isFinite(saved.scroll_y) ? saved.scroll_y : window.scrollY,
      );
    }
    if (!Number.isFinite(saved.media_position_seconds)) return;
    const mediaElements = Array.from(document.querySelectorAll('video, audio'));
    const media = mediaElements.find((element) => !element.paused) || mediaElements[0];
    if (!media) return;
    const seek = () => {
      try {
        const maximum = Number.isFinite(media.duration)
          ? Math.max(0, media.duration - 0.05)
          : saved.media_position_seconds;
        media.currentTime = Math.min(Math.max(0, saved.media_position_seconds), maximum);
      } catch (_) {
        // The page can replace its media element while it initializes.  The
        // next regular checkpoint remains usable even if this best-effort seek
        // is unavailable.
      }
    };
    if (media.readyState >= 1) {
      seek();
    } else {
      media.addEventListener('loadedmetadata', seek, { once: true });
    }
  };
  requestAnimationFrame(() => requestAnimationFrame(restore));
  return true;
})()
''';
}

Map<String, dynamic>? _mapFrom(Object? raw) {
  Object? decoded = raw;
  // Android may return the JSON string as a JSON-quoted string, whereas the
  // Windows plugin returns the decoded JavaScript value. Accept both without
  // giving page-provided values unlimited recursive parsing work.
  for (var attempt = 0; attempt < 2 && decoded is String; attempt++) {
    try {
      decoded = jsonDecode(decoded);
    } catch (_) {
      return null;
    }
  }
  if (decoded is! Map) return null;
  return Map<String, dynamic>.from(decoded);
}

String? _boundedText(Object? raw, int maximumLength) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;
  return value.length <= maximumLength
      ? value
      : value.substring(0, maximumLength);
}

double? _boundedNumber(
  Object? raw, {
  required double minimum,
  required double maximum,
}) {
  final value = raw is num
      ? raw.toDouble()
      : double.tryParse(raw?.toString() ?? '');
  if (value == null || !value.isFinite) return null;
  final bounded = value.clamp(minimum, maximum).toDouble();
  // Sub-pixel/clock jitter is not meaningful resume state.  Rounding makes
  // equality stable and avoids syncing a new value for insignificant changes.
  return double.parse(bounded.toStringAsFixed(2));
}

DateTime? _date(Object? raw) {
  final value = raw?.toString();
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value)?.toUtc();
}

String _normalizedPath(String path) => path.isEmpty ? '/' : path;

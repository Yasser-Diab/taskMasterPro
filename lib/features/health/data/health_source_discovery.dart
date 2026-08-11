/// A privacy-bounded projection of the Android Health Sources bridge.
///
/// The platform is deliberately responsible for deciding whether a paired
/// Bluetooth device is a health wearable.  Flutter must never turn an
/// arbitrary nearby device into a Health Source merely because it advertised
/// a BLE service.  This type additionally keeps the Bluetooth address out of
/// the presentation layer; it is retained only as the opaque bridge key used
/// for an explicit direct-capability check.
class PairedHealthWearable {
  const PairedHealthWearable({
    required this.bridgeId,
    required this.displayName,
    required this.isConnected,
    required this.capabilityState,
    required this.capabilities,
    this.inspectionError,
  });

  final String bridgeId;
  final String displayName;
  final bool isConnected;
  final String capabilityState;
  final List<String> capabilities;
  final String? inspectionError;

  PairedHealthWearable copyWithPlatformInspection(
    Map<String, Object?> inspection,
  ) {
    final nextCapabilities =
        (inspection['capabilities'] as List?)?.whereType<String>().toList() ??
        capabilities;
    return PairedHealthWearable(
      bridgeId: bridgeId,
      displayName: displayName,
      isConnected: inspection['connected'] as bool? ?? isConnected,
      capabilityState:
          inspection['capabilityState'] as String? ?? capabilityState,
      capabilities: List.unmodifiable(nextCapabilities),
      inspectionError: inspection['inspectionError'] as String?,
    );
  }

  /// Reject malformed bridge values as well as anything that the native
  /// classifier did not explicitly mark as both paired and health-related.
  /// This is a defence in depth check: the native method only returns those
  /// devices, but a stale or modified platform response must not leak random
  /// Bluetooth devices into the health UI.
  static List<PairedHealthWearable> fromPlatformValues(
    Iterable<Object?> values,
  ) {
    final wearables = <PairedHealthWearable>[];
    final seen = <String>{};
    for (final value in values) {
      if (value is! Map) continue;
      final map = Map<String, Object?>.from(value);
      if (map['healthDevice'] != true || map['bonded'] != true) continue;
      final bridgeId = (map['address'] as String?)?.trim();
      if (bridgeId == null || bridgeId.isEmpty || !seen.add(bridgeId)) {
        continue;
      }
      final rawName = (map['name'] as String?)?.trim();
      final capabilities =
          (map['capabilities'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      wearables.add(
        PairedHealthWearable(
          bridgeId: bridgeId,
          displayName: rawName ?? '',
          isConnected: map['connected'] == true,
          capabilityState: (map['capabilityState'] as String?) ?? 'not_checked',
          capabilities: List.unmodifiable(capabilities),
          inspectionError: map['inspectionError'] as String?,
        ),
      );
    }
    wearables.sort((left, right) {
      final connected =
          (right.isConnected ? 1 : 0) - (left.isConnected ? 1 : 0);
      return connected != 0
          ? connected
          : left.displayName.compareTo(right.displayName);
    });
    return List.unmodifiable(wearables);
  }
}

/// Converts Health Connect source labels to safe user-facing application
/// names.  Health Connect sometimes reports a package identifier instead of a
/// label; that identifier must never become a report or Health Sources label.
String? healthApplicationDisplayName(String rawSource) {
  final raw = rawSource.trim();
  if (raw.isEmpty) return null;
  const names = <String, String>{
    'com.huawei.health': 'Huawei Health',
    'com.nothing.smartcenter': 'Nothing X',
    'com.samsung.android.app.shealth': 'Samsung Health',
    'com.google.android.apps.fitness': 'Google Fit',
    'com.google.android.apps.healthdata': 'Health Connect',
    'com.fitbit.fitbitmobile': 'Fitbit',
    'com.garmin.android.apps.connectmobile': 'Garmin Connect',
    'com.withings.wiscale2': 'Withings',
    'com.polar.polarflow': 'Polar Flow',
    'com.huami.watch.hmwatchmanager': 'Zepp',
    'com.xiaomi.hm.health': 'Zepp Life',
  };
  final normalized = raw.toLowerCase();
  final known = names[normalized];
  if (known != null) return known;
  if (_looksLikePackageIdentifier(normalized)) return null;
  return raw;
}

/// Returns actual third-party contributors only.  Health Connect is its own
/// source card, so a provider list must not duplicate it or show an internal
/// Android package id as if it were an application name.
Set<String> observedHealthApplicationSources(Iterable<String> sources) {
  final result = <String>{};
  for (final raw in sources) {
    final label = healthApplicationDisplayName(raw);
    if (label == null || label == 'Health Connect') continue;
    result.add(label);
  }
  return result;
}

bool _looksLikePackageIdentifier(String value) {
  return RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z0-9_]+){1,}$').hasMatch(value);
}

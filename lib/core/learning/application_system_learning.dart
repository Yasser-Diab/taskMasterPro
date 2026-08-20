import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const applicationSystemLearningOptInKey =
    'taskmaster.activity.community_learning_opt_in.v1';
const _applicationSystemLearningSecretKey =
    'taskmaster.activity.community_learning_secret.v1';
const _applicationSystemLearningCacheKey =
    'taskmaster.activity.community_learning_cache.v1';

/// This is a separate, aggregate-only project. It must never receive account
/// credentials or any TaskMaster task, title, URL, path, activity, or session.
abstract final class ApplicationSystemLearningConfig {
  static const projectRef = 'iejbogkqknldxoyepvun';
  static const url = 'https://$projectRef.supabase.co';

  /// A Supabase publishable key is public by design. Keeping it in a build
  /// define lets the aggregate service remain disabled until its isolated
  /// migration has been reviewed and deployed.
  static const publishableKey = String.fromEnvironment(
    'TASKMASTER_LEARNING_SUPABASE_KEY',
    defaultValue: 'sb_publishable_fbgL1lczsWo3sRfsvdO2ZQ_up5cH9CZ',
  );

  static bool get isConfigured => publishableKey.startsWith('sb_publishable_');
}

abstract interface class ApplicationSystemLearningPreferences {
  Future<bool> isOptedIn();

  Future<void> setOptedIn(bool value);
}

class SharedPreferencesApplicationSystemLearningPreferences
    implements ApplicationSystemLearningPreferences {
  SharedPreferencesApplicationSystemLearningPreferences(this.preferences);

  final SharedPreferences preferences;

  @override
  Future<bool> isOptedIn() async =>
      preferences.getBool(applicationSystemLearningOptInKey) ?? false;

  @override
  Future<void> setOptedIn(bool value) async {
    await preferences.setBool(applicationSystemLearningOptInKey, value);
  }
}

abstract interface class ApplicationLearningSecretStore {
  Future<List<int>> readOrCreateSecret();
}

class SecureApplicationLearningSecretStore
    implements ApplicationLearningSecretStore {
  SecureApplicationLearningSecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static final Random _random = Random.secure();

  @override
  Future<List<int>> readOrCreateSecret() async {
    final existing = await _storage.read(
      key: _applicationSystemLearningSecretKey,
    );
    if (existing != null && existing.isNotEmpty) {
      try {
        final bytes = base64Url.decode(base64Url.normalize(existing));
        if (bytes.length == 32) return bytes;
      } on FormatException {
        // Replace malformed legacy/local data with a fresh anonymous secret.
      }
    }
    final secret = List<int>.generate(32, (_) => _random.nextInt(256));
    await _storage.write(
      key: _applicationSystemLearningSecretKey,
      value: base64UrlEncode(secret).replaceAll('=', ''),
    );
    return secret;
  }
}

class ApplicationSystemConsensus {
  const ApplicationSystemConsensus({
    required this.sampleSize,
    required this.systemShare,
    required this.confidenceLowerBound,
    required this.suggestsSystemActivity,
  });

  final int sampleSize;
  final double systemShare;
  final double confidenceLowerBound;
  final bool suggestsSystemActivity;

  Map<String, Object?> toJson() => {
    'sample_size': sampleSize,
    'system_share': systemShare,
    'confidence_lower_bound': confidenceLowerBound,
    'suggests_system_activity': suggestsSystemActivity,
  };

  static ApplicationSystemConsensus? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final sampleSize = (map['sample_size'] as num?)?.toInt();
    final systemShare = (map['system_share'] as num?)?.toDouble();
    final lower = (map['confidence_lower_bound'] as num?)?.toDouble();
    final suggests = map['suggests_system_activity'] as bool?;
    if (sampleSize == null ||
        sampleSize < 20 ||
        systemShare == null ||
        lower == null ||
        suggests == null) {
      return null;
    }
    return ApplicationSystemConsensus(
      sampleSize: sampleSize,
      systemShare: systemShare.clamp(0, 1).toDouble(),
      confidenceLowerBound: lower.clamp(0, 1).toDouble(),
      suggestsSystemActivity: suggests,
    );
  }
}

abstract interface class ApplicationSystemLearningGateway {
  Future<void> submitVote({
    required String platform,
    required String appKeyHash,
    required String voterTokenHash,
    required bool isSystemActivity,
  });

  Future<ApplicationSystemConsensus?> readConsensus({
    required String platform,
    required String appKeyHash,
  });
}

class SupabaseApplicationSystemLearningGateway
    implements ApplicationSystemLearningGateway {
  SupabaseApplicationSystemLearningGateway(this.client);

  final SupabaseClient client;

  @override
  Future<void> submitVote({
    required String platform,
    required String appKeyHash,
    required String voterTokenHash,
    required bool isSystemActivity,
  }) async {
    await client.rpc(
      'submit_application_system_vote',
      params: {
        'p_platform': platform,
        'p_app_key_hash': appKeyHash,
        'p_voter_token_hash': voterTokenHash,
        'p_is_system_activity': isSystemActivity,
      },
    );
  }

  @override
  Future<ApplicationSystemConsensus?> readConsensus({
    required String platform,
    required String appKeyHash,
  }) async {
    final response = await client.rpc(
      'get_application_system_consensus',
      params: {'p_platform': platform, 'p_app_key_hash': appKeyHash},
    );
    final Object? row = response is List
        ? (response.isEmpty ? null : response.first)
        : response;
    return ApplicationSystemConsensus.fromJson(row);
  }
}

class ApplicationSystemLearningCache {
  ApplicationSystemLearningCache(
    this.preferences, {
    this.maximumEntries = 64,
    this.timeToLive = const Duration(days: 7),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SharedPreferences preferences;
  final int maximumEntries;
  final Duration timeToLive;
  final DateTime Function() _now;

  Future<ApplicationSystemConsensus?> read(String key) async {
    final entries = _readEntries();
    final raw = entries[key];
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final cachedAt = DateTime.tryParse(map['cached_at'] as String? ?? '');
    if (cachedAt == null || _now().toUtc().difference(cachedAt) > timeToLive) {
      entries.remove(key);
      await _writeEntries(entries);
      return null;
    }
    return ApplicationSystemConsensus.fromJson(map['consensus']);
  }

  Future<void> write(String key, ApplicationSystemConsensus consensus) async {
    final entries = _readEntries();
    entries[key] = {
      'cached_at': _now().toUtc().toIso8601String(),
      'consensus': consensus.toJson(),
    };
    if (entries.length > maximumEntries) {
      final ordered = entries.entries.toList()
        ..sort((left, right) {
          String cachedAt(MapEntry<String, Object?> entry) {
            final value = entry.value;
            return value is Map ? value['cached_at'] as String? ?? '' : '';
          }

          return cachedAt(left).compareTo(cachedAt(right));
        });
      for (final entry in ordered.take(entries.length - maximumEntries)) {
        entries.remove(entry.key);
      }
    }
    await _writeEntries(entries);
  }

  Map<String, Object?> _readEntries() {
    final raw = preferences.getString(_applicationSystemLearningCacheKey);
    if (raw == null) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on FormatException {
      return <String, Object?>{};
    }
  }

  Future<void> _writeEntries(Map<String, Object?> entries) async {
    await preferences.setString(
      _applicationSystemLearningCacheKey,
      jsonEncode(entries),
    );
  }
}

class ApplicationSystemLearningService {
  ApplicationSystemLearningService({
    required this.preferences,
    required this.secretStore,
    required this.gateway,
    required this.cache,
  });

  final ApplicationSystemLearningPreferences preferences;
  final ApplicationLearningSecretStore secretStore;
  final ApplicationSystemLearningGateway gateway;
  final ApplicationSystemLearningCache cache;

  /// Sends a best-effort anonymous vote only after an explicit local choice.
  /// Network failure never blocks or rolls back that local classification.
  Future<void> submitExplicitChoice({
    required String platform,
    required String applicationIdentifier,
    required bool isSystemActivity,
  }) async {
    if (!await preferences.isOptedIn()) return;
    final identity = applicationLearningIdentity(
      platform: platform,
      applicationIdentifier: applicationIdentifier,
    );
    if (identity == null) return;
    try {
      final secret = await secretStore.readOrCreateSecret();
      final token = Hmac(sha256, secret).convert(
        utf8.encode('taskmaster-system-vote-v1:${identity.appKeyHash}'),
      );
      await gateway
          .submitVote(
            platform: identity.platform,
            appKeyHash: identity.appKeyHash,
            voterTokenHash: token.toString(),
            isSystemActivity: isSystemActivity,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Community learning is optional and must never break Activity review.
    }
  }

  /// Returns only a visible "possible system activity" suggestion. It never
  /// changes classification, and a local remembered rule suppresses lookup.
  Future<ApplicationSystemConsensus?> possibleSystemSuggestion({
    required String platform,
    required String applicationIdentifier,
    required bool hasLocalRememberedRule,
  }) async {
    if (hasLocalRememberedRule || !await preferences.isOptedIn()) return null;
    final identity = applicationLearningIdentity(
      platform: platform,
      applicationIdentifier: applicationIdentifier,
    );
    if (identity == null) return null;
    final cacheKey = '${identity.platform}:${identity.appKeyHash}';
    final cached = await cache.read(cacheKey);
    if (cached != null) {
      return cached.suggestsSystemActivity ? cached : null;
    }
    try {
      final consensus = await gateway
          .readConsensus(
            platform: identity.platform,
            appKeyHash: identity.appKeyHash,
          )
          .timeout(const Duration(seconds: 3));
      if (consensus == null) return null;
      await cache.write(cacheKey, consensus);
      return consensus.suggestsSystemActivity ? consensus : null;
    } catch (_) {
      return null;
    }
  }
}

class ApplicationLearningSource {
  const ApplicationLearningSource({
    required this.platform,
    required this.applicationIdentifier,
  });

  final String platform;
  final String applicationIdentifier;
}

/// Extracts only an executable basename or Android package. Window titles,
/// paths, URLs, task identifiers and the rest of raw capture metadata are not
/// accepted by the aggregate-learning boundary.
ApplicationLearningSource? applicationLearningSourceForCapture({
  required String sourceType,
  required String? processName,
  required String rawMetadataJson,
}) {
  final platform = sourceType.startsWith('android') ? 'android' : 'windows';
  String? packageName;
  try {
    final decoded = jsonDecode(rawMetadataJson);
    if (decoded is Map) {
      packageName = decoded['package_name'] as String?;
    }
  } on FormatException {
    // A valid process name still provides a privacy-safe Windows fallback.
  }
  final identifier = platform == 'android' ? packageName : processName;
  if (identifier == null || identifier.trim().isEmpty) return null;
  return ApplicationLearningSource(
    platform: platform,
    applicationIdentifier: identifier,
  );
}

class ApplicationLearningIdentity {
  const ApplicationLearningIdentity({
    required this.platform,
    required this.appKeyHash,
  });

  final String platform;
  final String appKeyHash;
}

ApplicationLearningIdentity? applicationLearningIdentity({
  required String platform,
  required String applicationIdentifier,
}) {
  final normalizedPlatform = platform.trim().toLowerCase();
  if (normalizedPlatform != 'windows' && normalizedPlatform != 'android') {
    return null;
  }
  var identifier = applicationIdentifier.trim().toLowerCase();
  if (normalizedPlatform == 'windows') {
    identifier = identifier.replaceAll('\\', '/').split('/').last;
  }
  if (identifier.isEmpty || identifier.length > 256) return null;
  final safeIdentifier = normalizedPlatform == 'android'
      ? identifier.replaceAll(RegExp('[^a-z0-9._-]'), '')
      : identifier.replaceAll(RegExp('[^a-z0-9._ -]'), '');
  if (safeIdentifier.isEmpty) return null;
  final appHash = sha256
      .convert(
        utf8.encode(
          'taskmaster-learning-app-v1:$normalizedPlatform:$safeIdentifier',
        ),
      )
      .toString();
  return ApplicationLearningIdentity(
    platform: normalizedPlatform,
    appKeyHash: appHash,
  );
}

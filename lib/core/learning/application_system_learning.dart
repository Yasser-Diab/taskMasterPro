import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

const applicationSystemLearningOptInKey =
    'taskmaster.activity.community_learning_opt_in.v1';
const _applicationSystemLearningSecretKey =
    'taskmaster.activity.community_learning_secret.v1';
const _applicationSystemLearningCacheKey =
    'taskmaster.activity.community_learning_cache.v1';

/// Aggregate learning lives on the current DayVector backend, but its RPCs
/// accept only hashes and one anonymous, per-app ballot. They never receive an
/// account ID, task, title, URL, path, activity interval, or session record.
abstract final class ApplicationSystemLearningConfig {
  static const projectRef = SupabaseConfig.projectRef;
  static const url = SupabaseConfig.url;

  /// A Supabase publishable key is public by design. Keeping it in a build
  /// define lets the aggregate service remain disabled until its isolated
  /// migration has been reviewed and deployed.
  static const publishableKey = SupabaseConfig.publishableKey;

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

/// A privacy-safe extension of the original system-app learning boundary.
/// Implementations receive a normalized category and usefulness flag, never
/// a human-readable application identifier.
abstract interface class ApplicationCategoryLearningGateway {
  Future<void> submitCategoryVote({
    required String platform,
    required String appKeyHash,
    required String voterTokenHash,
    required String category,
    required bool isUseful,
  });

  Future<ApplicationCategoryConsensus?> readCategoryConsensus({
    required String platform,
    required String appKeyHash,
  });
}

class SupabaseApplicationSystemLearningGateway
    implements
        ApplicationSystemLearningGateway,
        ApplicationCategoryLearningGateway {
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

  @override
  Future<void> submitCategoryVote({
    required String platform,
    required String appKeyHash,
    required String voterTokenHash,
    required String category,
    required bool isUseful,
  }) async {
    await client.rpc(
      'submit_application_category_vote',
      params: {
        'p_platform': platform,
        'p_app_key_hash': appKeyHash,
        'p_voter_token_hash': voterTokenHash,
        'p_category': category,
        'p_is_useful': isUseful,
      },
    );
  }

  @override
  Future<ApplicationCategoryConsensus?> readCategoryConsensus({
    required String platform,
    required String appKeyHash,
  }) async {
    final response = await client.rpc(
      'get_application_category_consensus',
      params: {'p_platform': platform, 'p_app_key_hash': appKeyHash},
    );
    final Object? row = response is List
        ? (response.isEmpty ? null : response.first)
        : response;
    return ApplicationCategoryConsensus.fromJson(row);
  }
}

/// Anonymous aggregate evidence. It is intentionally conservative: the
/// server returns a row only once at least 20 independent installations agree.
class ApplicationCategoryConsensus {
  const ApplicationCategoryConsensus({
    required this.sampleSize,
    required this.category,
    required this.isUseful,
    required this.confidenceLowerBound,
  });

  final int sampleSize;
  final String category;
  final bool isUseful;
  final double confidenceLowerBound;

  static const supportedCategories = <String>{
    'productivity',
    'development',
    'research',
    'communication',
    'education',
    'design',
    'finance',
    'system',
    'entertainment',
    'social',
    'other',
  };

  static ApplicationCategoryConsensus? fromJson(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, Object?>.from(value);
    final sampleSize = (map['sample_size'] as num?)?.toInt();
    final category = map['category'] as String?;
    final isUseful = map['is_useful'] as bool?;
    final lower = (map['confidence_lower_bound'] as num?)?.toDouble();
    if (sampleSize == null ||
        sampleSize < 20 ||
        category == null ||
        !supportedCategories.contains(category) ||
        isUseful == null ||
        lower == null) {
      return null;
    }
    return ApplicationCategoryConsensus(
      sampleSize: sampleSize,
      category: category,
      isUseful: isUseful,
      confidenceLowerBound: lower.clamp(0, 1).toDouble(),
    );
  }

  /// A proposal only. The Activity review remains visible and a local rule
  /// always wins over anonymous aggregate evidence.
  String get suggestedClassification {
    if (category == 'system') return 'system_activity';
    if (!isUseful) return 'distraction';
    return switch (category) {
      'research' || 'education' => 'passive_useful_activity',
      'productivity' ||
      'development' ||
      'communication' ||
      'design' ||
      'finance' => 'supporting_work',
      _ => 'passive_useful_activity',
    };
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
    this.categoryGateway,
  });

  final ApplicationSystemLearningPreferences preferences;
  final ApplicationLearningSecretStore secretStore;
  final ApplicationSystemLearningGateway gateway;
  final ApplicationSystemLearningCache cache;
  final ApplicationCategoryLearningGateway? categoryGateway;

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

  /// Submits an anonymous category/usefulness vote after the person has made
  /// an explicit Activity review choice. This is best effort and opt-in; it
  /// cannot affect the local decision if the network is unavailable.
  Future<void> submitExplicitClassification({
    required String platform,
    required String applicationIdentifier,
    required String classification,
  }) async {
    final assessment = _assessmentForClassification(classification);
    final categoryService = categoryGateway;
    if (assessment == null ||
        categoryService == null ||
        !await preferences.isOptedIn()) {
      return;
    }
    final identity = applicationLearningIdentity(
      platform: platform,
      applicationIdentifier: applicationIdentifier,
    );
    if (identity == null) return;
    try {
      final secret = await secretStore.readOrCreateSecret();
      final token = Hmac(sha256, secret).convert(
        utf8.encode('dayvector-category-vote-v1:${identity.appKeyHash}'),
      );
      await categoryService
          .submitCategoryVote(
            platform: identity.platform,
            appKeyHash: identity.appKeyHash,
            voterTokenHash: token.toString(),
            category: assessment.category,
            isUseful: assessment.isUseful,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // A local review must never be blocked by optional aggregate learning.
    }
  }

  /// Returns a conservative aggregate proposal for an unknown application.
  /// It is never a final classification and is ignored when a local rule is
  /// already available.
  Future<ApplicationCategoryConsensus?> possibleCategorySuggestion({
    required String platform,
    required String applicationIdentifier,
    required bool hasLocalRememberedRule,
  }) async {
    final categoryService = categoryGateway;
    if (categoryService == null ||
        hasLocalRememberedRule ||
        !await preferences.isOptedIn()) {
      return null;
    }
    final identity = applicationLearningIdentity(
      platform: platform,
      applicationIdentifier: applicationIdentifier,
    );
    if (identity == null) return null;
    try {
      return await categoryService
          .readCategoryConsensus(
            platform: identity.platform,
            appKeyHash: identity.appKeyHash,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
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

({String category, bool isUseful})? _assessmentForClassification(
  String classification,
) {
  return switch (classification) {
    'system_activity' => (category: 'system', isUseful: false),
    'direct_task_work' ||
    'supporting_work' => (category: 'productivity', isUseful: true),
    'passive_useful_activity' ||
    'research' ||
    'learning' ||
    'reading' => (category: 'research', isUseful: true),
    'communication' => (category: 'communication', isUseful: true),
    'distraction' => (category: 'entertainment', isUseful: false),
    'unrelated' ||
    'generally_unrelated' => (category: 'other', isUseful: false),
    'user_application' => (category: 'other', isUseful: true),
    _ => null,
  };
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

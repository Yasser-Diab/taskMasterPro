import 'package:uuid/uuid.dart';

import '../../../core/data/entity_record_repository.dart';
import '../../../core/database/app_database.dart';

/// The user-facing matching boundary for a website rule.
///
/// These values are deliberately stable serialized keys.  They are persisted
/// with each rule, instead of inferring a meaning from a URL at every device.
enum WebsiteMatchScope {
  page,
  section,
  host,
  site;

  String get key => name;

  static WebsiteMatchScope fromKey(String? value) => switch (value) {
    'page' => WebsiteMatchScope.page,
    'section' => WebsiteMatchScope.section,
    'site' => WebsiteMatchScope.site,
    _ => WebsiteMatchScope.host,
  };
}

/// A URL normalized for Activity matching, not for navigation.
///
/// The original URL stays in [originalUrl] for user-visible detail.  Identity
/// ignores protocol, `www.`, fragments, trailing slashes and known tracking
/// query parameters so that ordinary navigation does not silently break a
/// trusted task relationship.
class NormalizedWebsiteAddress {
  const NormalizedWebsiteAddress._({
    required this.originalUrl,
    required this.host,
    required this.registrableDomain,
    required this.normalizedPath,
    required this.normalizedQuery,
  });

  final String originalUrl;
  final String host;
  final String registrableDomain;
  final String normalizedPath;
  final String normalizedQuery;

  String get canonicalUrl =>
      '$host$normalizedPath${normalizedQuery.isEmpty ? '' : '?$normalizedQuery'}';

  /// The current directory is the conservative meaning of "section".  It
  /// avoids treating every page in a site as equivalent while still retaining
  /// lesson/article children.  Users can choose "Entire site" when that is
  /// the intended relationship.
  String get sectionPath {
    if (normalizedPath == '/') return '/';
    final segments = normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length < 2) return normalizedPath;
    return '/${segments.take(segments.length - 1).join('/')}';
  }

  String patternFor(WebsiteMatchScope scope) => switch (scope) {
    WebsiteMatchScope.page => canonicalUrl,
    WebsiteMatchScope.section => '$host$sectionPath/*',
    WebsiteMatchScope.host => '$host/*',
    WebsiteMatchScope.site => '$registrableDomain/*',
  };

  String connectionKey(WebsiteMatchScope scope) =>
      '${scope.key}:${patternFor(scope)}';

  static NormalizedWebsiteAddress parse(String raw) {
    final trimmed = raw.trim();
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.trim().isEmpty) {
      throw const FormatException(
        'Enter a valid HTTP or HTTPS website address',
      );
    }
    final host = _normalizedHost(uri.host);
    if (host.isEmpty) {
      throw const FormatException(
        'Enter a valid HTTP or HTTPS website address',
      );
    }
    return NormalizedWebsiteAddress._(
      originalUrl: uri.replace(fragment: '').toString(),
      host: host,
      registrableDomain: _registrableDomain(host),
      normalizedPath: _normalizedPath(uri.path),
      normalizedQuery: _normalizedQuery(uri.queryParametersAll),
    );
  }

  static NormalizedWebsiteAddress? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return parse(raw);
    } on FormatException {
      return null;
    }
  }

  static String _normalizedHost(String value) {
    var host = value.trim().toLowerCase();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  static String _normalizedPath(String value) {
    final parts = <String>[];
    for (final rawPart in value.split('/')) {
      if (rawPart.isEmpty || rawPart == '.') continue;
      if (rawPart == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(rawPart);
    }
    return parts.isEmpty ? '/' : '/${parts.join('/')}';
  }

  static String _normalizedQuery(Map<String, List<String>> values) {
    final entries = <(String, String)>[];
    for (final entry in values.entries) {
      if (_isTrackingParameter(entry.key)) continue;
      for (final value in entry.value) {
        entries.add((entry.key, value));
      }
    }
    entries.sort((left, right) {
      final keyOrder = left.$1.compareTo(right.$1);
      return keyOrder == 0 ? left.$2.compareTo(right.$2) : keyOrder;
    });
    return entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.$1)}=${Uri.encodeQueryComponent(entry.$2)}',
        )
        .join('&');
  }

  static bool _isTrackingParameter(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized.startsWith('utm_') ||
        const {
          'gclid',
          'dclid',
          'fbclid',
          'msclkid',
          'mc_cid',
          'mc_eid',
          '_hsenc',
          '_hsmi',
        }.contains(normalized);
  }

  static String _registrableDomain(String host) {
    if (_isIpAddress(host) || host == 'localhost' || !host.contains('.')) {
      return host;
    }
    final parts = host.split('.').where((part) => part.isNotEmpty).toList();
    if (parts.length < 3) return parts.join('.');
    final suffix = parts.sublist(parts.length - 2).join('.');
    // A compact, intentionally conservative public-suffix list covers the
    // common multi-label suffixes encountered by this product without turning
    // an internal host into a cross-site wildcard.  Unknown suffixes retain
    // the normal last-two-label behaviour.
    const twoLabelSuffixes = {
      'ac.uk',
      'co.uk',
      'gov.uk',
      'ltd.uk',
      'me.uk',
      'net.uk',
      'org.uk',
      'plc.uk',
      'sch.uk',
      'com.au',
      'net.au',
      'org.au',
      'edu.au',
      'gov.au',
      'co.nz',
      'org.nz',
      'net.nz',
      'co.jp',
      'ne.jp',
      'or.jp',
      'com.br',
      'com.mx',
      'com.tr',
      'co.in',
      'firm.in',
      'net.in',
      'org.in',
    };
    if (twoLabelSuffixes.contains(suffix) && parts.length >= 3) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return suffix;
  }

  static bool _isIpAddress(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');
}

/// Stable UUID v5 identity for an explicit website relationship.  It is
/// scoped to a task, so the same website can be connected to many tasks while
/// reconnecting it on another device still produces one logical row.
String websiteRuleIdFor({
  required String userId,
  required String taskOccurrenceId,
  required NormalizedWebsiteAddress address,
  required WebsiteMatchScope scope,
}) => const Uuid().v5(
  Namespace.url.value,
  'https://taskmasterpro.app/account/$userId/task/$taskOccurrenceId/'
  'website/${address.connectionKey(scope)}',
);

Map<String, Object?> flattenWebsiteRuleData(Map<String, Object?> value) {
  final nested = value['data'];
  return nested is Map
      ? <String, Object?>{...value, ...Map<String, Object?>.from(nested)}
      : value;
}

WebsiteMatchScope websiteRuleScope(Map<String, Object?> rule) =>
    WebsiteMatchScope.fromKey(
      flattenWebsiteRuleData(rule)['match_scope'] as String?,
    );

String? websiteRuleConnectionKey(Map<String, Object?> rule) {
  final data = flattenWebsiteRuleData(rule);
  final explicit = data['connection_key'] as String?;
  if (explicit?.trim().isNotEmpty == true) return explicit!.trim();
  final scope = websiteRuleScope(data);
  final address = NormalizedWebsiteAddress.tryParse(
    data['canonical_url'] as String? ??
        data['url_pattern'] as String? ??
        data['domain'] as String?,
  );
  return address?.connectionKey(scope);
}

bool websiteRuleMatches({
  required Map<String, Object?> rule,
  String? url,
  String? domain,
}) {
  final data = flattenWebsiteRuleData(rule);
  final candidate =
      NormalizedWebsiteAddress.tryParse(url) ??
      NormalizedWebsiteAddress.tryParse(domain);
  if (candidate == null) return false;
  final scope = websiteRuleScope(data);
  final ruleHost =
      (data['host'] as String?)?.trim().toLowerCase() ??
      NormalizedWebsiteAddress.tryParse(data['domain'] as String?)?.host;
  final ruleDomain =
      (data['registrable_domain'] as String?)?.trim().toLowerCase() ??
      NormalizedWebsiteAddress.tryParse(
        data['domain'] as String?,
      )?.registrableDomain;
  final rulePath =
      (data['normalized_path'] as String?)?.trim().isNotEmpty == true
      ? (data['normalized_path'] as String).trim()
      : '/';
  final ruleSection =
      (data['section_path'] as String?)?.trim().isNotEmpty == true
      ? (data['section_path'] as String).trim()
      : rulePath;
  switch (scope) {
    case WebsiteMatchScope.page:
      final canonical = (data['canonical_url'] as String?)?.trim();
      return canonical != null && canonical.isNotEmpty
          ? candidate.canonicalUrl == canonical
          : candidate.host == ruleHost && candidate.normalizedPath == rulePath;
    case WebsiteMatchScope.section:
      if (candidate.host != ruleHost) return false;
      return ruleSection == '/' ||
          candidate.normalizedPath == ruleSection ||
          candidate.normalizedPath.startsWith('$ruleSection/');
    case WebsiteMatchScope.host:
      return candidate.host == ruleHost;
    case WebsiteMatchScope.site:
      return ruleDomain != null &&
          (candidate.host == ruleDomain ||
              candidate.host.endsWith('.$ruleDomain'));
  }
}

int websiteRuleSpecificity(Map<String, Object?> rule) =>
    switch (websiteRuleScope(rule)) {
      WebsiteMatchScope.page => 4,
      WebsiteMatchScope.section => 3,
      WebsiteMatchScope.host => 2,
      WebsiteMatchScope.site => 1,
    };

/// Returns one safe automatic rule, or `null` when a website is linked to
/// several competing tasks.  That deliberately leaves the Activity row for a
/// user allocation instead of crediting the same physical period twice.
Map<String, Object?>? selectWebsiteRuleForActivity(
  Iterable<Map<String, Object?>> rules, {
  String? url,
  String? domain,
  String? sourceTaskId,
}) {
  final matching = rules.where((rule) {
    final data = flattenWebsiteRuleData(rule);
    final status = (data['status'] as String?)?.toLowerCase();
    return (status == null || status == 'active' || status == 'trusted') &&
        data['automatic_credit'] == true &&
        data['target_type'] == 'task_occurrence' &&
        data['target_id'] is String &&
        data['contribution_type'] is String &&
        websiteRuleMatches(rule: data, url: url, domain: domain);
  }).toList();
  if (matching.isEmpty) return null;

  final sourceMatches = sourceTaskId == null
      ? const <Map<String, Object?>>[]
      : matching
            .where(
              (rule) =>
                  flattenWebsiteRuleData(rule)['target_id'] == sourceTaskId,
            )
            .toList();
  final candidates = sourceMatches.isNotEmpty ? sourceMatches : matching;
  final targetIds = candidates
      .map((rule) => flattenWebsiteRuleData(rule)['target_id'] as String)
      .toSet();
  if (targetIds.length != 1) return null;
  candidates.sort(
    (left, right) =>
        websiteRuleSpecificity(right).compareTo(websiteRuleSpecificity(left)),
  );
  return flattenWebsiteRuleData(candidates.first);
}

class WebsiteRuleConnection {
  const WebsiteRuleConnection({
    required this.id,
    required this.address,
    required this.scope,
  });

  final String id;
  final NormalizedWebsiteAddress address;
  final WebsiteMatchScope scope;
}

/// Local-first façade for a persistent many-to-many website relationship.
class WebsiteRuleService {
  WebsiteRuleService({required this.entities});

  final EntityRecordRepository entities;

  Future<WebsiteRuleConnection> connectToTask({
    required String taskId,
    required String url,
    required WebsiteMatchScope scope,
  }) async {
    final address = NormalizedWebsiteAddress.parse(url);
    final id = websiteRuleIdFor(
      userId: entities.userId,
      taskOccurrenceId: taskId,
      address: address,
      scope: scope,
    );
    final data = _localData(taskId: taskId, address: address, scope: scope);
    final payload = _syncPayload(
      taskId: taskId,
      address: address,
      scope: scope,
      data: data,
    );

    final existing = await _semanticExisting(
      taskId: taskId,
      connectionKey: address.connectionKey(scope),
    );
    if (existing != null) {
      final existingData = flattenWebsiteRuleData(entities.decode(existing));
      if (!_hasCurrentWebsiteSemantics(existingData, data) ||
          existing.status != 'active') {
        await entities.update(
          existing,
          title: _title(address),
          status: 'active',
          data: data,
          syncPayload: payload,
        );
      }
      return WebsiteRuleConnection(
        id: existing.id,
        address: address,
        scope: scope,
      );
    }

    final deleted = await entities.getIncludingDeleted(id);
    if (deleted?.deletedAt != null) {
      await entities.restore(
        id,
        title: _title(address),
        status: 'active',
        parentId: taskId,
        data: data,
        syncPayload: payload,
      );
    } else {
      await entities.create(
        EntityRecordDraft(
          id: id,
          entityType: 'website_rules',
          parentId: taskId,
          title: _title(address),
          status: 'active',
          data: data,
          syncPayload: payload,
        ),
      );
    }
    return WebsiteRuleConnection(id: id, address: address, scope: scope);
  }

  Future<LocalEntityRecord?> _semanticExisting({
    required String taskId,
    required String connectionKey,
  }) async {
    final rules = await entities.list(
      entityType: 'website_rules',
      parentId: taskId,
    );
    for (final rule in rules) {
      if (websiteRuleConnectionKey(entities.decode(rule)) == connectionKey) {
        return rule;
      }
    }
    return null;
  }

  Map<String, Object?> _localData({
    required String taskId,
    required NormalizedWebsiteAddress address,
    required WebsiteMatchScope scope,
  }) => {
    'domain': scope == WebsiteMatchScope.site
        ? address.registrableDomain
        : address.host,
    'url_pattern': address.patternFor(scope),
    'scope_type': 'task',
    'scope_id': taskId,
    'classification': 'direct_task_work',
    'target_type': 'task_occurrence',
    'target_id': taskId,
    'contribution_type': 'active_work_seconds',
    // A user explicitly connected this scope to this task. Automatic credit
    // remains safe because [selectWebsiteRuleForActivity] refuses ambiguous
    // multi-task matches.
    'automatic_credit': true,
    'priority': 200,
    'match_scope': scope.key,
    'registrable_domain': address.registrableDomain,
    'host': address.host,
    'normalized_path': address.normalizedPath,
    'section_path': address.sectionPath,
    'canonical_url': address.canonicalUrl,
    'original_url': address.originalUrl,
    'connection_key': address.connectionKey(scope),
    'normalization_version': 1,
  };

  Map<String, Object?> _syncPayload({
    required String taskId,
    required NormalizedWebsiteAddress address,
    required WebsiteMatchScope scope,
    required Map<String, Object?> data,
  }) => {
    'domain': scope == WebsiteMatchScope.site
        ? address.registrableDomain
        : address.host,
    'url_pattern': address.patternFor(scope),
    'scope_type': 'task',
    'scope_id': taskId,
    'classification': 'direct_task_work',
    'target_type': 'task_occurrence',
    'target_id': taskId,
    'contribution_type': 'active_work_seconds',
    'automatic_credit': true,
    'priority': 200,
    'data': data,
  };

  bool _hasCurrentWebsiteSemantics(
    Map<String, Object?> current,
    Map<String, Object?> expected,
  ) {
    for (final key in [
      'connection_key',
      'match_scope',
      'registrable_domain',
      'host',
      'normalized_path',
      'section_path',
      'canonical_url',
      'target_id',
    ]) {
      if (current[key] != expected[key]) return false;
    }
    return current['automatic_credit'] == true;
  }

  String _title(NormalizedWebsiteAddress address) => address.registrableDomain;
}

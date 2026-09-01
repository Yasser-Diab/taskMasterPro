import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/features/tasks/data/installed_application_service.dart';
import 'package:taskmaster_pro/features/tasks/data/website_rule_service.dart';

void main() {
  Map<String, Object?> rule({
    required String taskId,
    required WebsiteMatchScope scope,
    required NormalizedWebsiteAddress address,
  }) => {
    'status': 'active',
    'scope_type': 'task',
    'scope_id': taskId,
    'target_type': 'task_occurrence',
    'target_id': taskId,
    'classification': 'direct_task_work',
    'contribution_type': 'active_work_seconds',
    'automatic_credit': true,
    'data': {
      'match_scope': scope.key,
      'connection_key': address.connectionKey(scope),
      'registrable_domain': address.registrableDomain,
      'host': address.host,
      'normalized_path': address.normalizedPath,
      'section_path': address.sectionPath,
      'canonical_url': address.canonicalUrl,
    },
  };

  test('website normalization keeps one freeCodeCamp site identity', () {
    final address = NormalizedWebsiteAddress.parse(
      'http://www.freecodecamp.org/learn/javascript-v9/?utm_source=test#lesson',
    );

    expect(address.host, 'freecodecamp.org');
    expect(address.registrableDomain, 'freecodecamp.org');
    expect(address.normalizedPath, '/learn/javascript-v9');
    expect(address.normalizedQuery, isEmpty);
    expect(address.canonicalUrl, 'freecodecamp.org/learn/javascript-v9');
  });

  test('page, section, host, and site scopes have distinct safe matches', () {
    final address = NormalizedWebsiteAddress.parse(
      'https://www.freecodecamp.org/learn/javascript-v9/lesson/example',
    );
    final page = rule(
      taskId: 'task-1',
      scope: WebsiteMatchScope.page,
      address: address,
    );
    final section = rule(
      taskId: 'task-1',
      scope: WebsiteMatchScope.section,
      address: address,
    );
    final host = rule(
      taskId: 'task-1',
      scope: WebsiteMatchScope.host,
      address: address,
    );
    final site = rule(
      taskId: 'task-1',
      scope: WebsiteMatchScope.site,
      address: address,
    );

    expect(
      websiteRuleMatches(
        rule: page,
        url:
            'https://freecodecamp.org/learn/javascript-v9/lesson/example?utm_campaign=x',
      ),
      isTrue,
    );
    expect(
      websiteRuleMatches(
        rule: page,
        url: 'https://freecodecamp.org/learn/javascript-v9/lesson/next',
      ),
      isFalse,
    );
    expect(
      websiteRuleMatches(
        rule: section,
        url: 'https://freecodecamp.org/learn/javascript-v9/lesson/next',
      ),
      isTrue,
    );
    expect(
      websiteRuleMatches(
        rule: host,
        url: 'https://forum.freecodecamp.org/t/topic',
      ),
      isFalse,
    );
    expect(
      websiteRuleMatches(
        rule: site,
        url: 'https://forum.freecodecamp.org/t/topic',
      ),
      isTrue,
    );
  });

  test(
    'website identity is stable per task and preserves many-to-many links',
    () {
      final first = NormalizedWebsiteAddress.parse(
        'https://www.freecodecamp.org/learn/?utm_source=one',
      );
      final second = NormalizedWebsiteAddress.parse(
        'http://freecodecamp.org/learn/#top',
      );
      final firstId = websiteRuleIdFor(
        userId: 'owner',
        taskOccurrenceId: 'task-programming',
        address: first,
        scope: WebsiteMatchScope.site,
      );
      final secondId = websiteRuleIdFor(
        userId: 'owner',
        taskOccurrenceId: 'task-programming',
        address: second,
        scope: WebsiteMatchScope.site,
      );
      final anotherTaskId = websiteRuleIdFor(
        userId: 'owner',
        taskOccurrenceId: 'task-german',
        address: second,
        scope: WebsiteMatchScope.site,
      );

      expect(firstId, secondId);
      expect(anotherTaskId, isNot(firstId));
    },
  );

  test('ambiguous site rules never automatically double-credit activity', () {
    final address = NormalizedWebsiteAddress.parse('https://freecodecamp.org');
    final programming = rule(
      taskId: 'task-programming',
      scope: WebsiteMatchScope.site,
      address: address,
    );
    final german = rule(
      taskId: 'task-german',
      scope: WebsiteMatchScope.site,
      address: address,
    );

    expect(
      selectWebsiteRuleForActivity([
        programming,
        german,
      ], url: 'https://www.freecodecamp.org/learn/javascript-v9/'),
      isNull,
    );
    expect(
      selectWebsiteRuleForActivity(
        [programming, german],
        url: 'https://www.freecodecamp.org/learn/javascript-v9/',
        sourceTaskId: 'task-programming',
      )?['target_id'],
      'task-programming',
    );
  });

  test('application resource labels do not expose technical identifiers', () {
    expect(
      normalizedApplicationDisplayName('pro.taskmanager.com'),
      'DayVector',
    );
    expect(normalizedApplicationDisplayName('exe.chrome'), 'Google Chrome');
    expect(normalizedApplicationDisplayName('Code.exe'), 'Visual Studio Code');
    expect(normalizedApplicationDisplayName('com.duolingo'), 'Duolingo');
    expect(
      resolvedApplicationDisplayName(
        displayNameSnapshot: 'pro.taskmaster.app',
        rawIdentifier: 'pro.taskmaster.app',
        unknownLabel: 'Unknown application',
      ),
      'DayVector',
    );
  });

  test(
    'cross-platform task links stay visible and state their availability',
    () {
      expect(
        taskApplicationAvailability(
          linkedPlatform: 'android',
          currentPlatform: 'windows',
        ),
        TaskApplicationAvailability.androidDeviceRequired,
      );
      expect(
        taskApplicationAvailability(
          linkedPlatform: 'windows',
          currentPlatform: 'android',
        ),
        TaskApplicationAvailability.windowsDeviceRequired,
      );
      expect(
        taskApplicationAvailability(
          linkedPlatform: 'android',
          currentPlatform: 'android',
        ),
        TaskApplicationAvailability.available,
      );
    },
  );

  test('website connection migration is a narrowly owner-scoped definer RPC', () {
    final migration = File(
      'supabase/migrations/20260810134735_v0028_normalized_task_website_rules.sql',
    ).readAsStringSync();
    expect(migration, contains('connect_website_to_task'));
    expect(migration, contains("owner_id uuid := (select auth.uid())"));
    expect(migration, contains('processed_commands'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(
      migration,
      contains('private.canonical_task_website_rule'),
      reason:
          'The server, not a stale client payload, must derive the semantic identity.',
    );
    expect(
      migration,
      contains('website_rules_active_task_connection_key_unique'),
      reason: 'One live task/site/scope relationship must have a database key.',
    );
    expect(migration, contains('rule_id_bound_to_other_relationship'));
    expect(
      migration,
      contains('supplied_rule_found := found'),
      reason:
          'An allocated ID must be bound to the requested relationship before a semantic duplicate can be accepted.',
    );
    expect(migration, contains('stale_rule_revision'));
    expect(
      migration,
      contains("'taskmaster.allow_tombstone_restore'"),
      reason:
          'The trusted restore path must opt in to the tombstone guard explicitly.',
    );
    expect(
      migration,
      contains('before insert or update on public.website_rules'),
    );
    expect(
      migration,
      contains("'task_website_scope_not_available'"),
      reason:
          'Generic writes must verify that the task scope is live and owned by the rule owner.',
    );
    expect(
      migration,
      isNot(contains("p_data ->> 'connection_key'")),
      reason: 'Client-provided connection keys are not a canonical identity.',
    );
    // `private.normalize_task_website_host` is intentionally not executable
    // by client roles. The public entry point must therefore be a limited
    // definer function, with an explicit caller/device/task ownership gate.
    expect(migration, contains('security definer'));
    expect(migration, contains("if owner_id is null then"));
    expect(migration, contains("device.user_id = owner_id"));
    expect(migration, contains("task.user_id = owner_id"));
    expect(
      migration,
      contains(
        'revoke all on function private.normalize_task_website_host(text)',
      ),
    );
    expect(
      migration,
      contains("revoke all on function public.connect_website_to_task"),
    );
    expect(migration, contains('to authenticated;'));
    final connectRpc = migration.substring(
      migration.indexOf(
        'create or replace function public.connect_website_to_task',
      ),
    );
    expect(
      connectRpc.indexOf('from public.processed_commands as command'),
      lessThan(connectRpc.indexOf('from public.task_occurrences as task')),
      reason:
          'A retry must deduplicate before a later task deletion can turn an accepted command into a failure.',
    );
  });

  test(
    'task website rules use the atomic sync dispatch and keep their domain label',
    () {
      final syncService = File(
        'lib/core/sync/sync_service.dart',
      ).readAsStringSync();

      expect(syncService, contains("'connect_website_to_task'"));
      expect(syncService, contains("command.entityType == 'website_rules' &&"));
      expect(syncService, contains('_applyAcceptedTaskWebsiteRule'));
      expect(syncService, contains("row['domain'] as String?"));
    },
  );
}

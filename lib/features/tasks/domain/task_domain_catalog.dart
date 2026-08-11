import 'package:uuid/uuid.dart';

class BuiltInTaskDomain {
  const BuiltInTaskDomain({
    required this.key,
    required this.canonicalName,
    required this.iconName,
    required this.colorValue,
  });

  final String key;
  final String canonicalName;
  final String iconName;
  final int colorValue;
}

/// Language-independent built-in task areas.
///
/// Each account receives its own rows because tasks and custom domains are
/// protected by account RLS. IDs are UUID v5 values derived from the
/// authenticated user ID and [BuiltInTaskDomain.key], so two offline devices
/// converge on the same row instead of creating login-time duplicates.
abstract final class TaskDomainCatalog {
  static const definitions = <BuiltInTaskDomain>[
    BuiltInTaskDomain(
      key: 'work',
      canonicalName: 'Work',
      iconName: 'work',
      colorValue: 0xFF4169E1,
    ),
    BuiltInTaskDomain(
      key: 'learning',
      canonicalName: 'Learning',
      iconName: 'school',
      colorValue: 0xFF00A88F,
    ),
    BuiltInTaskDomain(
      key: 'reading',
      canonicalName: 'Reading',
      iconName: 'book',
      colorValue: 0xFF8E5BB7,
    ),
    BuiltInTaskDomain(
      key: 'health',
      canonicalName: 'Health',
      iconName: 'health',
      colorValue: 0xFFE55353,
    ),
    BuiltInTaskDomain(
      key: 'personal',
      canonicalName: 'Personal',
      iconName: 'person',
      colorValue: 0xFFE29B2D,
    ),
    BuiltInTaskDomain(
      key: 'family',
      canonicalName: 'Family',
      iconName: 'family_restroom',
      colorValue: 0xFFB05CC6,
    ),
    BuiltInTaskDomain(
      key: 'household',
      canonicalName: 'Household',
      iconName: 'home',
      colorValue: 0xFF6B8E23,
    ),
    BuiltInTaskDomain(
      key: 'finance',
      canonicalName: 'Finance',
      iconName: 'account_balance_wallet',
      colorValue: 0xFF2E8B57,
    ),
    BuiltInTaskDomain(
      key: 'fitness',
      canonicalName: 'Fitness',
      iconName: 'fitness_center',
      colorValue: 0xFFEF6C57,
    ),
    BuiltInTaskDomain(
      key: 'projects',
      canonicalName: 'Projects',
      iconName: 'rocket_launch',
      colorValue: 0xFF5064C9,
    ),
    BuiltInTaskDomain(
      key: 'errands',
      canonicalName: 'Errands',
      iconName: 'shopping_bag',
      colorValue: 0xFF9A7042,
    ),
  ];

  static String idFor(String userId, String domainKey) => const Uuid().v5(
    Namespace.url.value,
    'https://taskmasterpro.app/account/$userId/task-domain/$domainKey',
  );

  static String? builtInKeyForId(String userId, String domainId) {
    for (final definition in definitions) {
      if (idFor(userId, definition.key) == domainId) return definition.key;
    }
    return null;
  }

  static String localizationKey(String domainKey) =>
      'task_domain_builtin_$domainKey';
}

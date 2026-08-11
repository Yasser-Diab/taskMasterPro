abstract final class SupabaseConfig {
  /// This is deliberately a project identity, not a user/account identity.
  /// It is used to scope local databases, outboxes, auth persistence and PKCE
  /// verifiers so a clean project can never replay the prior project's cache.
  static const projectRef = 'tmvarulrujkmibqpqoeo';

  static const url = 'https://$projectRef.supabase.co';

  /// Supabase publishable keys are intentionally safe for public clients.
  /// Secret and service-role keys must never be added to Flutter code.
  static const publishableKey =
      'sb_publishable_DgXGTat_sy_LHAzxTS3eqA_LNm2cZ6B';

  /// Only used locally to clear stale session material during a deliberate
  /// backend cutover. It is a public project reference, never a secret.
  static const legacyProjectRefs = <String>{'iejbogkqknldxoyepvun'};

  static const authCallback = 'pro.taskmaster.app://auth-callback';
  static const realtimeTopicPrefix = 'taskmaster:user:';
}

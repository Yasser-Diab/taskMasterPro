abstract final class SupabaseConfig {
  static const url = 'https://iejbogkqknldxoyepvun.supabase.co';

  /// Supabase publishable keys are intentionally safe for public clients.
  /// Secret and service-role keys must never be added to Flutter code.
  static const publishableKey =
      'sb_publishable_fbgL1lczsWo3sRfsvdO2ZQ_up5cH9CZ';

  static const authCallback = 'pro.taskmaster.app://auth-callback';
  static const realtimeTopicPrefix = 'taskmaster:user:';
}

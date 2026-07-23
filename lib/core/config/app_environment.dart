import 'app_config.dart';

class AppEnvironment {
  const AppEnvironment._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const environmentName = String.fromEnvironment(
    'TASKMASTER_ENV',
    defaultValue: 'development',
  );
  static const projectRef = String.fromEnvironment(
    'SUPABASE_PROJECT_REF',
    defaultValue: '',
  );

  static SupabaseTarget? get supabaseTarget {
    if (supabaseUrl.trim().isEmpty || supabasePublishableKey.trim().isEmpty) {
      return null;
    }
    return const SupabaseTarget(
      url: supabaseUrl,
      publicKey: supabasePublishableKey,
    );
  }
}

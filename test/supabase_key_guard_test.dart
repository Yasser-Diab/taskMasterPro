import 'package:flutter_test/flutter_test.dart';
import 'package:personal_task_manager/core/security/supabase_key_guard.dart';

void main() {
  group('SupabaseKeyGuard', () {
    test('accepts Supabase HTTPS project URLs', () {
      expect(
        SupabaseKeyGuard.validateUrl('https://example.supabase.co'),
        isNull,
      );
    });

    test('rejects non-HTTPS URLs', () {
      expect(
        SupabaseKeyGuard.validateUrl('http://example.supabase.co'),
        isNotNull,
      );
    });

    test('rejects database connection strings', () {
      expect(
        SupabaseKeyGuard.validatePublicClientKey(
          'postgresql://postgres:pass@db.example/postgres',
        ),
        isNotNull,
      );
    });

    test('rejects Supabase secret keys', () {
      expect(
        SupabaseKeyGuard.validatePublicClientKey('sb_secret_not_for_clients'),
        isNotNull,
      );
    });
  });
}

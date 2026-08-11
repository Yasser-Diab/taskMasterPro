import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/account/owner_bootstrap.dart';
import 'package:taskmaster_pro/core/config/supabase_config.dart';
import 'package:taskmaster_pro/core/database/app_database.dart';

void main() {
  group('account-local isolation', () {
    test('uses a distinct durable namespace for each authenticated user', () {
      const accountA = '0aaee13a-9c58-4dee-bd5b-488bd6cc6712';
      const accountB = '4bd3e32d-1dcd-48ed-9f64-9099675047f1';

      expect(
        localDatabaseNameForAccount(accountA),
        isNot(localDatabaseNameForAccount(accountB)),
      );
      expect(
        localDatabaseNameForAccount(accountA),
        equals('taskmaster_${SupabaseConfig.projectRef}_$accountA'),
      );
      expect(
        localDatabaseNameForAccount(null),
        equals('taskmaster_${SupabaseConfig.projectRef}_signed_out'),
      );
    });

    test('account-scoped cache keys cannot collide across sign-ins', () {
      const accountA = 'account-a';
      const accountB = 'account-b';

      expect(localAppSettingsId(accountA), isNot(localAppSettingsId(accountB)));
      expect(
        localRuntimeStateId(accountA),
        isNot(localRuntimeStateId(accountB)),
      );
    });

    test('there is no implicit owner bootstrap in a normal build', () {
      expect(mayBootstrapOwnerContent('any-authenticated-user-id'), isFalse);
    });
  });
}

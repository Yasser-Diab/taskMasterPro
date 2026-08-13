import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/account/account_context.dart';

void main() {
  test(
    'account transition stops writers before closing and is serialized',
    () async {
      final coordinator = AccountDatabaseTransitionCoordinator();
      final events = <String>[];

      Future<void> select(String account) => coordinator.select(
        account,
        stopSync: () async {
          events.add('$account:sync');
        },
        stopActivity: () async {
          events.add('$account:activity');
        },
        closeDatabase: () async {
          events.add('$account:database');
        },
        activate: (value) => events.add('$account:activate:$value'),
      );

      await Future.wait([select('account-a'), select('account-b')]);

      expect(events, [
        'account-a:sync',
        'account-a:activity',
        'account-a:database',
        'account-a:activate:account-a',
        'account-b:sync',
        'account-b:activity',
        'account-b:database',
        'account-b:activate:account-b',
      ]);
      expect(coordinator.activeAccountId, 'account-b');
    },
  );

  test('failed transition is surfaced and a later retry can proceed', () async {
    final coordinator = AccountDatabaseTransitionCoordinator();

    await expectLater(
      coordinator.select(
        'account-a',
        stopSync: () async {},
        stopActivity: () async => throw StateError('collector still active'),
        closeDatabase: () async => fail('database must remain open'),
        activate: (_) => fail('account must not rotate'),
      ),
      throwsStateError,
    );

    await coordinator.select(
      'account-a',
      stopSync: () async {},
      stopActivity: () async {},
      closeDatabase: () async {},
      activate: (_) {},
    );
    expect(coordinator.activeAccountId, 'account-a');
  });
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskmaster_pro/core/localization/app_localizations.dart';
import 'package:taskmaster_pro/core/sync/sync_service.dart';
import 'package:taskmaster_pro/features/shell/presentation/home_shell.dart';

void main() {
  test(
    'shell subscribes before reading sync health so idle is not missed',
    () async {
      var current = SyncHealth.syncing;
      final changes = StreamController<SyncHealth>.broadcast(
        sync: true,
        onListen: () => current = SyncHealth.idle,
      );
      addTearDown(changes.close);

      final first = await synchronizedSyncHealthStream(
        readCurrent: () => current,
        changes: changes.stream,
      ).first;

      expect(first, SyncHealth.idle);
    },
  );

  test('only genuine syncing presentation rotates', () {
    final syncing = shellSyncIndicatorPresentation(SyncHealth.syncing);
    final waiting = shellSyncIndicatorPresentation(SyncHealth.waiting);
    final synced = shellSyncIndicatorPresentation(SyncHealth.idle);
    final attention = shellSyncIndicatorPresentation(SyncHealth.attention);
    final offline = shellSyncIndicatorPresentation(SyncHealth.offline);

    expect(syncing.icon, Icons.sync_rounded);
    expect(syncing.animate, isTrue);
    expect(waiting.icon, Icons.cloud_upload_outlined);
    expect(waiting.labelKey, 'sync_waiting_changes');
    expect(waiting.animate, isFalse);
    expect(synced.icon, Icons.check_circle_outline_rounded);
    expect(synced.labelKey, 'sync_all_changes');
    expect(synced.animate, isFalse);
    expect(attention.animate, isFalse);
    expect(offline.icon, isNull);
    expect(offline.labelKey, 'sync_offline_compact');
    expect(offline.animate, isFalse);
  });

  test('footer labels exist in all three languages', () {
    for (final locale in const [Locale('en'), Locale('ar'), Locale('de')]) {
      final localizations = AppLocalizations(locale);
      expect(localizations.text('sync_all_changes').trim(), isNotEmpty);
      expect(localizations.text('sync_offline_compact').trim(), isNotEmpty);
      expect(localizations.text('sync_waiting_changes').trim(), isNotEmpty);
      expect(localizations.text('sync_all_changes'), isNot('sync_all_changes'));
      expect(
        localizations.text('sync_offline_compact'),
        isNot('sync_offline_compact'),
      );
      expect(
        localizations.text('sync_waiting_changes'),
        isNot('sync_waiting_changes'),
      );
    }
  });
}

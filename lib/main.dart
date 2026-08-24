import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/taskmaster_app.dart';
import 'core/config/backend_target_cutover.dart';
import 'core/config/supabase_config.dart';
import 'core/notifications/notification_sounds.dart';
import 'core/platform/android_home_widget_service.dart';
import 'core/platform/background_execution_action_service.dart';
import 'core/platform/windows_shell_service.dart';
import 'core/sync/sync_service.dart';
import 'features/auth/presentation/password_recovery_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    initializeDateFormatting('en'),
    initializeDateFormatting('ar'),
    initializeDateFormatting('de'),
  ]);

  // This happens before Supabase initialization, so an app update pointing at
  // a clean project cannot restore an old session, replay an old outbox or
  // leave alarms from the old canonical state alive.
  final targetStore = await SharedPreferencesBackendTargetStore.open();
  await localNotificationService.initialize();
  await BackendTargetCutover(
    targetProjectRef: SupabaseConfig.projectRef,
    legacyProjectRefs: SupabaseConfig.legacyProjectRefs,
    store: targetStore,
  ).prepare(
    stopSync: SyncService.stopAllForBackendCutover,
    cancelNotifications: localNotificationService.cancelAllForBackendCutover,
  );

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: SharedPreferencesLocalStorage(
        persistSessionKey: BackendTargetCutover.sessionStorageKeyForProject(
          SupabaseConfig.projectRef,
        ),
      ),
      pkceAsyncStorage: ProjectScopedGotrueAsyncStorage(
        store: targetStore,
        projectRef: SupabaseConfig.projectRef,
      ),
    ),
  );
  passwordRecoveryController.start(Supabase.instance.client.auth);
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.signedOut) {
      unawaited(AndroidHomeWidgetService.instance.clear());
    }
  });
  WindowsShellService.instance;

  runApp(const ProviderScope(child: TaskMasterApp()));
}

/// Android starts this entrypoint in a service-owned FlutterEngine after a
/// widget or notification control is pressed. It intentionally does not call
/// runApp and therefore cannot open or foreground TaskMaster Pro.
@pragma('vm:entry-point')
Future<void> taskMasterBackgroundActionMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await BackgroundExecutionActionService.runPendingAndroidAction();
}

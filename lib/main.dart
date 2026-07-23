import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app/task_master_app.dart';
import 'core/config/app_settings_store.dart';
import 'core/config/supabase_service.dart';
import 'core/platform/app_lifecycle_service.dart';
import 'core/platform/app_notification_service.dart';
import 'core/platform/interaction_feedback_service.dart';
import 'core/platform/health_data_service.dart';
import 'core/time/time_zone_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final settingsStore = AppSettingsStore();
  final initialConfig = await settingsStore.load();
  final supabaseService = SupabaseService();
  unawaited(supabaseService.initialize(initialConfig));
  final lifecycleService = AppLifecycleService();
  await lifecycleService.initialize();
  await lifecycleService.applyWindowPreferences(initialConfig);
  final feedbackService = InteractionFeedbackService();
  await feedbackService.initialize(initialConfig);
  final notificationService = AppNotificationService();
  final timeZoneService = AppTimeZoneController();
  await timeZoneService.initialize();
  timeZoneService.configure(initialConfig, locale: initialConfig.locale);
  final healthDataService = HealthDataService(supabaseService);
  healthDataService.keepDataLocal = initialConfig.healthDataLocalOnly;
  await healthDataService.initialize();

  runApp(
    TaskMasterApp(
      feedbackService: feedbackService,
      initialConfig: initialConfig,
      initialLinks: args,
      lifecycleService: lifecycleService,
      notificationService: notificationService,
      settingsStore: settingsStore,
      supabaseService: supabaseService,
      timeZoneService: timeZoneService,
      healthDataService: healthDataService,
    ),
  );
}

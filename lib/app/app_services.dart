import 'package:flutter/widgets.dart';

import '../core/config/app_config.dart';
import '../core/config/supabase_service.dart';
import '../core/platform/app_lifecycle_service.dart';
import '../core/platform/app_notification_service.dart';
import '../core/platform/interaction_feedback_service.dart';
import '../core/platform/health_data_service.dart';
import '../core/time/time_zone_service.dart';

typedef AppConfigUpdater = Future<String?> Function(AppConfig config);

class AppServices extends InheritedWidget {
  const AppServices({
    required this.config,
    required this.feedbackService,
    required this.lifecycleService,
    required this.notificationService,
    required this.updateConfig,
    required this.supabaseService,
    required this.timeZoneService,
    required this.healthDataService,
    required super.child,
    super.key,
  });

  final AppConfig config;
  final InteractionFeedbackService feedbackService;
  final AppLifecycleService lifecycleService;
  final AppNotificationService notificationService;
  final AppConfigUpdater updateConfig;
  final SupabaseService supabaseService;
  final TimeZoneService timeZoneService;
  final HealthDataService healthDataService;

  static AppServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices was not found in the widget tree.');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) {
    return config != oldWidget.config ||
        lifecycleService != oldWidget.lifecycleService ||
        feedbackService != oldWidget.feedbackService ||
        notificationService != oldWidget.notificationService ||
        timeZoneService != oldWidget.timeZoneService ||
        healthDataService != oldWidget.healthDataService ||
        supabaseService != oldWidget.supabaseService;
  }
}

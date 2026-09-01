import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/localization/app_localizations.dart';
import '../core/navigation/app_route_observer.dart';
import '../core/providers.dart';
import '../core/theme/app_theme.dart';
import '../core/updates/update_prompt.dart';
import '../features/auth/presentation/auth_gate.dart';

class TaskMasterApp extends ConsumerWidget {
  const TaskMasterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).value;
    final themeKey = TaskMasterThemeKey.fromKey(settings?.themeKey ?? 'system');
    final accent = Color(settings?.accentColor ?? 0xFF4F46E5);
    final localeCode = settings?.localeCode ?? 'en';

    final ThemeData lightTheme;
    final ThemeData darkTheme;
    final ThemeMode themeMode;
    switch (themeKey) {
      case TaskMasterThemeKey.golden:
        lightTheme = TaskMasterTheme.golden();
        darkTheme = TaskMasterTheme.golden();
        themeMode = ThemeMode.light;
      case TaskMasterThemeKey.dark:
        lightTheme = TaskMasterTheme.light(accent: accent);
        darkTheme = TaskMasterTheme.dark(accent: accent);
        themeMode = ThemeMode.dark;
      case TaskMasterThemeKey.light:
        lightTheme = TaskMasterTheme.light(accent: accent);
        darkTheme = TaskMasterTheme.dark(accent: accent);
        themeMode = ThemeMode.light;
      case TaskMasterThemeKey.system:
        lightTheme = TaskMasterTheme.light(accent: accent);
        darkTheme = TaskMasterTheme.dark(accent: accent);
        themeMode = ThemeMode.system;
    }

    return MaterialApp(
      title: 'DayVector',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: Locale(localeCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      navigatorObservers: [appRouteObserver],
      home: UpdatePrompt(child: AuthGate(themeKey: themeKey)),
    );
  }
}

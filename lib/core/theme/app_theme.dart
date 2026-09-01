import 'package:flutter/material.dart';

enum TaskMasterThemeKey {
  system,
  light,
  dark,
  golden;

  static TaskMasterThemeKey fromKey(String value) {
    return TaskMasterThemeKey.values.firstWhere(
      (theme) => theme.name == value,
      orElse: () => TaskMasterThemeKey.system,
    );
  }
}

abstract final class TaskMasterTheme {
  static const gold = Color(0xFFF5B942);
  static const blue = Color(0xFF4F46E5);
  static const green = Color(0xFF20C6A4);

  static ThemeData light({Color accent = blue}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: const Color(0xFFF7F9FC),
    );
    return _build(scheme, const Color(0xFFFFFFFF), golden: false);
  }

  static ThemeData dark({Color accent = blue}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: const Color(0xFF101828),
    );
    return _build(scheme, const Color(0xFF182235), golden: false);
  }

  static ThemeData golden() {
    const scheme = ColorScheme.dark(
      primary: gold,
      onPrimary: Color(0xFF211900),
      secondary: Color(0xFFE8B923),
      onSecondary: Color(0xFF211900),
      surface: Color(0xFF17150F),
      onSurface: Color(0xFFF6EED6),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
    );
    return _build(scheme, const Color(0xFF201D14), golden: true);
  }

  static ThemeData _build(
    ColorScheme scheme,
    Color cardColor, {
    required bool golden,
  }) {
    final textTheme = Typography.material2021(platform: TargetPlatform.android)
        .black
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          fontFamily: 'Segoe UI',
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      textTheme: textTheme,
      cardColor: cardColor,
      visualDensity: VisualDensity.standard,
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: cardColor,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: golden
                ? gold.withValues(alpha: 0.24)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cardColor,
        indicatorColor: scheme.primaryContainer,
        labelType: NavigationRailLabelType.all,
        groupAlignment: -0.8,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardColor,
        indicatorColor: scheme.primaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

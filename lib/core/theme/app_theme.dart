import 'package:flutter/material.dart';

import '../config/app_config.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light({required bool highContrast}) {
    return _build(
      brightness: Brightness.light,
      background: const Color(0xFFF4F7FB),
      surface: Colors.white,
      elevated: const Color(0xFFEAF0F8),
      primary: const Color(0xFF2563EB),
      accent: const Color(0xFF0EA5E9),
      text: const Color(0xFF162033),
      muted: const Color(0xFF667085),
      highContrast: highContrast,
    );
  }

  static ThemeData darkBlue({required bool highContrast}) {
    return _build(
      brightness: Brightness.dark,
      background: const Color(0xFF08111F),
      surface: const Color(0xFF101C2E),
      elevated: const Color(0xFF18263A),
      primary: const Color(0xFF3B82F6),
      accent: const Color(0xFF22D3EE),
      text: const Color(0xFFF3F7FC),
      muted: const Color(0xFF94A3B8),
      highContrast: highContrast,
    );
  }

  static ThemeData blackGold({required bool highContrast}) {
    return _build(
      brightness: Brightness.dark,
      background: const Color(0xFF0B0B0C),
      surface: const Color(0xFF151517),
      elevated: const Color(0xFF222225),
      primary: const Color(0xFFD4AF37),
      accent: const Color(0xFFB99645),
      text: const Color(0xFFF5F5F5),
      muted: const Color(0xFF9CA3AF),
      highContrast: highContrast,
    );
  }

  static ThemeData forChoice(
    AppThemeChoice choice, {
    required bool highContrast,
  }) {
    return switch (choice) {
      AppThemeChoice.darkBlue => darkBlue(highContrast: highContrast),
      AppThemeChoice.blackGold => blackGold(highContrast: highContrast),
      AppThemeChoice.light => light(highContrast: highContrast),
    };
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color elevated,
    required Color primary,
    required Color accent,
    required Color text,
    required Color muted,
    required bool highContrast,
  }) {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          secondary: accent,
          surface: surface,
          error: const Color(0xFFEF4444),
          onPrimary: brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          onSecondary: brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          onSurface: text,
        );

    final borderColor = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: highContrast ? 0.2 : 0.08)
        : const Color(0xFFD7DEE8);

    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: background,
      canvasColor: background,
      dividerColor: borderColor,
      cardTheme: CardThemeData(
        color: surface,
        elevation: brightness == Brightness.dark ? 0 : 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: elevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: borderColor),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: IconThemeData(color: primary),
        selectedLabelTextStyle: TextStyle(color: primary),
        unselectedIconTheme: IconThemeData(color: muted),
        unselectedLabelTextStyle: TextStyle(color: muted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: baseTheme.textTheme.apply(bodyColor: text, displayColor: text),
      extensions: <ThemeExtension<dynamic>>[
        AppColors(
          elevated: elevated,
          mutedText: muted,
          border: borderColor,
          success: const Color(0xFF22C55E),
          warning: const Color(0xFFF59E0B),
          info: accent,
        ),
      ],
    );
  }
}

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.elevated,
    required this.mutedText,
    required this.border,
    required this.success,
    required this.warning,
    required this.info,
  });

  final Color elevated;
  final Color mutedText;
  final Color border;
  final Color success;
  final Color warning;
  final Color info;

  @override
  AppColors copyWith({
    Color? elevated,
    Color? mutedText,
    Color? border,
    Color? success,
    Color? warning,
    Color? info,
  }) {
    return AppColors(
      elevated: elevated ?? this.elevated,
      mutedText: mutedText ?? this.mutedText,
      border: border ?? this.border,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    return AppColors(
      elevated: Color.lerp(elevated, other.elevated, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      border: Color.lerp(border, other.border, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension AppColorContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

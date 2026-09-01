import 'package:flutter/material.dart';

import 'app_theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    required this.themeKey,
    this.height = 58,
    this.fit = BoxFit.contain,
    this.symbolOnly = false,
    super.key,
  });

  final TaskMasterThemeKey themeKey;
  final double height;
  final BoxFit fit;
  final bool symbolOnly;

  String _asset(BuildContext context) {
    final resolved = themeKey == TaskMasterThemeKey.system
        ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
              ? TaskMasterThemeKey.dark
              : TaskMasterThemeKey.light)
        : themeKey;
    if (symbolOnly) return 'media/app-logo/DayVector_Symbol_128.png';
    return switch (resolved) {
      TaskMasterThemeKey.dark =>
        'media/app-logo/DayVector_Horizontal_Dark_600.png',
      TaskMasterThemeKey.golden ||
      TaskMasterThemeKey.light ||
      TaskMasterThemeKey.system =>
        'media/app-logo/DayVector_Horizontal_Light_600.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'DayVector',
      image: true,
      child: Image.asset(
        _asset(context),
        height: height,
        fit: fit,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'DayVector',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

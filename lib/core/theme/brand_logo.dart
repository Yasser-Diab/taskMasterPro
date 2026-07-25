import 'package:flutter/material.dart';

import 'app_theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({
    required this.themeKey,
    this.height = 58,
    this.fit = BoxFit.contain,
    super.key,
  });

  final TaskMasterThemeKey themeKey;
  final double height;
  final BoxFit fit;

  String _asset(BuildContext context) {
    final resolved = themeKey == TaskMasterThemeKey.system
        ? (MediaQuery.platformBrightnessOf(context) == Brightness.dark
              ? TaskMasterThemeKey.dark
              : TaskMasterThemeKey.light)
        : themeKey;
    return switch (resolved) {
      TaskMasterThemeKey.golden =>
        'media/app-logo/TaskMaster_Pro_Black_Gold_Transparent_main-logo.png',
      TaskMasterThemeKey.dark =>
        'media/app-logo/TaskMaster_Pro_Blue_Dark_Transparent.png',
      TaskMasterThemeKey.light =>
        'media/app-logo/TaskMaster_Pro_Light_Transparent.png',
      TaskMasterThemeKey.system =>
        'media/app-logo/TaskMaster_Pro_Light_Transparent.png',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'TaskMaster Pro',
      image: true,
      child: Image.asset(
        _asset(context),
        height: height,
        fit: fit,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, _, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'TaskMaster Pro',
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

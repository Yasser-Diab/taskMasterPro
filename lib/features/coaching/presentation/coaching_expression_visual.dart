import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/adaptive_coaching_service.dart';

/// Theme-aware rendering for the DayVector coaching expression pack.
///
/// The SVGs contain geometry only. Applying the semantic accent here keeps the
/// same illustration legible in light, dark-blue, and black-and-gold themes.
class CoachingExpressionVisual extends StatelessWidget {
  const CoachingExpressionVisual({
    required this.expression,
    required this.semanticLabel,
    required this.accent,
    this.size = 160,
    this.background,
    this.border,
    this.borderRadius = 28,
    super.key,
  });

  final CoachingExpression expression;
  final String semanticLabel;
  final Color accent;
  final double size;
  final Color? background;
  final Color? border;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveBackground =
        background ??
        Color.alphaBlend(
          accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.12
                : 0.08,
          ),
          scheme.surfaceContainer,
        );
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: MediaQuery.maybeOf(context)?.disableAnimations == true
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: Curves.easeInOutCubic,
          width: size,
          height: size * 0.75,
          padding: EdgeInsets.all(size * 0.075),
          decoration: BoxDecoration(
            color: effectiveBackground,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color:
                  border ??
                  Color.lerp(
                    accent,
                    scheme.outlineVariant,
                    0.48,
                  )!.withValues(alpha: 0.82),
            ),
          ),
          child: SvgPicture.asset(
            expression.assetPath,
            key: ValueKey(expression),
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }
}

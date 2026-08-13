import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';

/// Visual roles used by the compact Activity classification pills shown on
/// the product website. The role is semantic so light, dark and golden themes
/// can preserve the same meaning without exposing database enum values.
enum ActivityBadgeTone {
  productive,
  research,
  communication,
  needsReview,
  negative,
  neutral,
}

@visibleForTesting
ActivityBadgeTone activityBadgeTone(String classification) {
  return switch (classification) {
    'direct_task_work' || 'supporting_work' => ActivityBadgeTone.productive,
    'research' ||
    'learning' ||
    'reading' ||
    'passive_useful_activity' => ActivityBadgeTone.research,
    'communication' => ActivityBadgeTone.communication,
    'unclassified' ||
    'unknown' ||
    'requires_review' => ActivityBadgeTone.needsReview,
    'distraction' ||
    'unrelated' ||
    'generally_unrelated' => ActivityBadgeTone.negative,
    _ => ActivityBadgeTone.neutral,
  };
}

String activityClassificationLabel(
  AppLocalizations l10n,
  String classification,
) {
  return switch (classification) {
    'direct_task_work' => l10n.text('classification_productive'),
    'supporting_work' => l10n.text('activity_supporting_work'),
    'research' => l10n.text('classification_research'),
    'communication' => l10n.text('classification_communication'),
    'learning' => l10n.text('classification_learning'),
    'reading' ||
    'passive_useful_activity' => l10n.text('activity_useful_reading'),
    'distraction' => l10n.text('activity_mark_distraction'),
    'unrelated' => l10n.text('classification_not_related'),
    'generally_unrelated' => l10n.text('activity_generally_unrelated'),
    'system_activity' => l10n.text('system_activity'),
    'possible_system_activity' => l10n.text('possible_system_activity'),
    'user_application' => l10n.text('user_application'),
    'idle' || 'technical_idle' => l10n.text('activity_idle'),
    _ => l10n.text('activity_needs_review'),
  };
}

String? activitySuggestionLabel(AppLocalizations l10n, String? source) {
  return switch (source) {
    'learned_from_usage' => l10n.text('activity_learned_from_usage'),
    'taskmaster_suggestion' => l10n.text('activity_suggested_by_taskmaster'),
    _ => null,
  };
}

/// Compact classification treatment shared by Activity review and a task's
/// Activity panel. It mirrors the official Productive / Research /
/// Communication / Needs review pills instead of using a generic Material
/// [Chip], whose default padding and neutral foreground obscured the state.
class ActivityClassificationBadge extends StatelessWidget {
  const ActivityClassificationBadge({
    required this.classification,
    this.maxWidth = 144,
    super.key,
  });

  final String classification;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = activityClassificationLabel(l10n, classification);
    final colors = _colorsFor(
      activityBadgeTone(classification),
      Theme.of(context),
    );
    return Semantics(
      label: '${l10n.text('activity_classification')}: $label',
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.foreground,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
      ),
    );
  }
}

/// Secondary provenance tag. These tags are deliberately quieter than the
/// classification badge so a suggestion never looks like a confirmed fact.
class ActivitySuggestionBadge extends StatelessWidget {
  const ActivitySuggestionBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.72),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 13, color: scheme.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

({Color foreground, Color background}) _colorsFor(
  ActivityBadgeTone tone,
  ThemeData theme,
) {
  final dark = theme.brightness == Brightness.dark;
  final foreground = switch (tone) {
    ActivityBadgeTone.productive =>
      dark ? const Color(0xFF4ED49C) : const Color(0xFF167A55),
    ActivityBadgeTone.research =>
      dark ? const Color(0xFF69BAFF) : const Color(0xFF1267A8),
    ActivityBadgeTone.communication =>
      dark ? const Color(0xFF4BD4DD) : const Color(0xFF007781),
    ActivityBadgeTone.needsReview =>
      dark ? const Color(0xFFF2B84B) : const Color(0xFF8A5A00),
    ActivityBadgeTone.negative => theme.colorScheme.error,
    ActivityBadgeTone.neutral => theme.colorScheme.onSurfaceVariant,
  };
  return (
    foreground: foreground,
    background: foreground.withValues(alpha: dark ? 0.12 : 0.10),
  );
}

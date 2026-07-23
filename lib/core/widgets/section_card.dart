import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.action,
    super.key,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon case final icon?) ...[
                  Icon(
                    icon,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ),
                if (action != null) Flexible(child: action!),
              ],
            ),
            const SizedBox(height: 12),
            DefaultTextStyle.merge(
              style: TextStyle(color: colors.mutedText),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import '../platform/app_notification_service.dart';
import '../theme/app_theme.dart';

class AppNotificationHost extends StatelessWidget {
  const AppNotificationHost({
    required this.service,
    required this.child,
    super.key,
  });

  final AppNotificationService service;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final message = service.current;
            if (message == null) {
              return const SizedBox.shrink();
            }
            return PositionedDirectional(
              start: 16,
              end: 16,
              bottom: 16,
              child: SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Dismissible(
                      key: ValueKey(message.id),
                      direction: DismissDirection.horizontal,
                      onDismissed: (_) => service.dismiss(),
                      child: MouseRegion(
                        onEnter: (_) => service.pause(),
                        onExit: (_) => service.resume(),
                        child: Focus(
                          onFocusChange: (focused) {
                            if (focused) {
                              service.pause();
                            } else {
                              service.resume();
                            }
                          },
                          child: _NotificationCard(
                            service: service,
                            message: message,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.service, required this.message});

  final AppNotificationService service;
  final AppNotificationMessage message;

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(context, message.level);
    final icon = _iconFor(message.level);
    final seconds = service.secondsRemaining;
    final isPersistent = message.duration == null;

    return Card(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(message.message)),
                if (message.action != null)
                  TextButton(
                    onPressed: service.runAction,
                    child: Text(message.action!.label),
                  ),
                IconButton(
                  tooltip: context.text('close'),
                  onPressed: service.dismiss,
                  icon: const Icon(Icons.close_outlined),
                ),
              ],
            ),
            if (!isPersistent) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: service.progress,
                      minHeight: 4,
                      color: color,
                      backgroundColor: color.withValues(alpha: 0.16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$seconds ${context.text(seconds == 1 ? 'second' : 'seconds')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.appColors.mutedText,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _colorFor(BuildContext context, AppNotificationLevel level) {
    return switch (level) {
      AppNotificationLevel.info => Theme.of(context).colorScheme.primary,
      AppNotificationLevel.success => context.appColors.success,
      AppNotificationLevel.warning => context.appColors.warning,
      AppNotificationLevel.error => Theme.of(context).colorScheme.error,
    };
  }

  IconData _iconFor(AppNotificationLevel level) {
    return switch (level) {
      AppNotificationLevel.info => Icons.info_outline,
      AppNotificationLevel.success => Icons.check_circle_outline,
      AppNotificationLevel.warning => Icons.warning_amber_outlined,
      AppNotificationLevel.error => Icons.error_outline,
    };
  }
}

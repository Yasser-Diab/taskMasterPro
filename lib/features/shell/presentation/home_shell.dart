import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/providers.dart';
import '../../../core/sync/sync_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/brand_logo.dart';
import '../../activity/presentation/activity_review_screen.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../roadmaps/presentation/roadmaps_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../tasks/presentation/tasks_screen.dart';

final syncHealthProvider = StreamProvider<SyncHealth>(
  (ref) => ref.watch(syncServiceProvider).health,
);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.user, required this.themeKey, super.key});

  final User user;
  final TaskMasterThemeKey themeKey;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final destinations = [
      (Icons.dashboard_outlined, Icons.dashboard, l10n.text('dashboard')),
      (Icons.task_alt_outlined, Icons.task_alt, l10n.text('tasks')),
      (Icons.route_outlined, Icons.route, l10n.text('roadmaps')),
      (Icons.insights_outlined, Icons.insights, l10n.text('activity')),
      (Icons.settings_outlined, Icons.settings, l10n.text('settings')),
    ];
    final pages = [
      DashboardScreen(user: widget.user),
      const TasksScreen(),
      const RoadmapsScreen(),
      const ActivityReviewScreen(),
      SettingsScreen(user: widget.user),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 900;
        if (!useRail) {
          return Scaffold(
            body: SafeArea(
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.$1),
                    selectedIcon: Icon(destination.$2),
                    label: destination.$3,
                  ),
              ],
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                Container(
                  width: 248,
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: BorderDirectional(
                      end: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                        child: BrandLogo(themeKey: widget.themeKey, height: 54),
                      ),
                      Expanded(
                        child: NavigationRail(
                          extended: true,
                          minExtendedWidth: 248,
                          selectedIndex: _selectedIndex,
                          onDestinationSelected: (index) =>
                              setState(() => _selectedIndex = index),
                          leading: const SizedBox(height: 12),
                          destinations: [
                            for (final destination in destinations)
                              NavigationRailDestination(
                                icon: Icon(destination.$1),
                                selectedIcon: Icon(destination.$2),
                                label: Text(destination.$3),
                              ),
                          ],
                        ),
                      ),
                      const _CompactActiveTaskBar(),
                      const _SyncFooter(),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(index: _selectedIndex, children: pages),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SyncFooter extends ConsumerWidget {
  const _SyncFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(syncHealthProvider).value ?? SyncHealth.idle;
    final (icon, key, color) = switch (health) {
      SyncHealth.offline => (
        Icons.cloud_off_outlined,
        'sync_offline',
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      SyncHealth.syncing => (
        Icons.sync,
        'sync_syncing',
        Theme.of(context).colorScheme.primary,
      ),
      SyncHealth.attention => (
        Icons.sync_problem,
        'sync_attention',
        Theme.of(context).colorScheme.error,
      ),
      SyncHealth.idle => (
        Icons.cloud_done_outlined,
        'sync_idle',
        TaskMasterTheme.green,
      ),
    };
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.text(key),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactActiveTaskBar extends ConsumerWidget {
  const _CompactActiveTaskBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(taskRepositoryProvider);
    return StreamBuilder(
      stream: repository.watchRuntime(),
      builder: (context, runtimeSnapshot) {
        final runtime = runtimeSnapshot.data;
        if (runtime == null || runtime.activeTaskId == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      runtime.state == 'running'
                          ? Icons.play_circle
                          : Icons.pause_circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Active execution',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

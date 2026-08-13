import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/account/account_context.dart';
import '../../../core/platform/windows_shell_service.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import '../../onboarding/presentation/android_permission_setup_gate.dart';
import '../../shell/presentation/home_shell.dart';
import 'auth_screen.dart';
import 'password_recovery_controller.dart';
import 'password_recovery_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({required this.themeKey, super.key});

  final TaskMasterThemeKey themeKey;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate>
    with WidgetsBindingObserver {
  String? _preparedUserId;
  String? _signedOutTrayLocale;
  Future<void>? _preparation;
  final _accountTransition = AccountDatabaseTransitionCoordinator();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        ref.read(supabaseClientProvider).auth.currentUser == null) {
      return;
    }
    // A resume can be emitted by window focus, a permission sheet, or the
    // OAuth browser. It is not evidence of a missed remote change, so never
    // reinstall routines or run an authoritative pull here. The sync service
    // already observes connectivity and only retries an interrupted Realtime
    // join with bounded backoff.
    unawaited(() async {
      try {
        await ref.read(syncServiceProvider).recoverAfterResume();
      } catch (_) {
        // Connectivity and canonical state are retried by the normal sync
        // lifecycle; resume must never surface a synchronization dialog.
      }
    }());
  }

  Future<void> _selectAccount(String? userId) {
    // Stop and await every writer before closing the old account database.
    // Riverpod disposes dependent providers independently, so relying on
    // provider disposal order allowed Activity's final sample to race
    // Drift's query-stream teardown during sign-out/account switching.
    final sync = ref.read(syncServiceProvider);
    final activity = ref.read(activityCaptureServiceProvider);
    final database = ref.read(databaseProvider);
    return _accountTransition.select(
      userId,
      stopSync: sync.stop,
      stopActivity: activity.dispose,
      closeDatabase: database.close,
      activate: (selectedUserId) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        if (!mounted) return;
        ref.read(activeAccountIdProvider.notifier).select(selectedUserId);
      },
    );
  }

  Future<void> _prepare(User user) {
    if (_preparedUserId == user.id && _preparation != null) {
      return _preparation!;
    }
    _preparedUserId = user.id;
    _preparation = () async {
      await _selectAccount(user.id);
      if (!mounted) return;
      final settings = ref.read(settingsRepositoryProvider);
      await settings.ensureLocalAccount(user);
      await settings.refreshDeviceTimeZoneIfAutomatic();
      // Built-in task areas are account-scoped, deterministic records. This
      // idempotent pass also upgrades existing accounts that completed
      // onboarding before the full default catalogue was introduced.
      await ref.read(taskRepositoryProvider).seedStarterDomains();
      // Remote registration, realtime and outbox draining must never block an
      // already authenticated user from opening their local workspace.
      unawaited(() async {
        try {
          await ref.read(syncServiceProvider).start();
          // A new device begins with an empty account database. Run the
          // source-bound installer after the initial canonical pull so the
          // imported plan marker is available on this first launch.
          final routineResult = await ref
              .read(ownerRoutineInstallerProvider)
              .ensureInstalled();
          final generated = await ref
              .read(recurrenceServiceProvider)
              .generateUpcoming();
          if (routineResult.changed || generated > 0) {
            await ref.read(syncServiceProvider).drainOutbox();
          }
          await ref.read(activityCaptureServiceProvider).start();
        } catch (_) {
          // Connectivity, recurrence generation and permission-dependent
          // capture retry on the next lifecycle recovery without holding the
          // local workspace hostage.
        }
      }());
    }();
    return _preparation!;
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: passwordRecoveryController,
      builder: (context, recoveringPassword, _) => StreamBuilder<AuthState>(
        stream: client.auth.onAuthStateChange,
        initialData: AuthState(
          AuthChangeEvent.initialSession,
          client.auth.currentSession,
        ),
        builder: (context, snapshot) {
          final session = snapshot.data?.session ?? client.auth.currentSession;
          if (session == null) {
            unawaited(_selectAccount(null));
            _preparedUserId = null;
            _preparation = null;
            final localeCode =
                ref.read(appSettingsProvider).value?.localeCode ?? 'en';
            if (_signedOutTrayLocale != localeCode) {
              _signedOutTrayLocale = localeCode;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                unawaited(
                  WindowsShellService.instance.updateTray(
                    WindowsTrayState(
                      signedIn: false,
                      hasActiveTask: false,
                      taskPaused: false,
                      breakActive: false,
                      activeTask: '',
                      elapsed: '',
                      syncLabel: '',
                      syncAttention: false,
                      localeCode: localeCode,
                    ),
                  ),
                );
              });
            }
            return AuthScreen(themeKey: widget.themeKey);
          }
          _signedOutTrayLocale = null;

          if (recoveringPassword) {
            return PasswordRecoveryScreen(email: session.user.email ?? '');
          }

          return FutureBuilder<void>(
            future: _prepare(session.user),
            builder: (context, preparation) {
              if (preparation.hasError) {
                return _GateError(
                  onRetry: () {
                    setState(() {
                      _preparation = null;
                      _preparedUserId = null;
                    });
                  },
                );
              }
              if (preparation.connectionState != ConnectionState.done) {
                return const _GateLoading();
              }

              final settings = ref.watch(settingsRepositoryProvider);
              return StreamBuilder(
                stream: settings.watchProfile(session.user.id),
                builder: (context, profileSnapshot) {
                  final profile = profileSnapshot.data;
                  if (profile == null) return const _GateLoading();
                  if (!profile.onboardingCompleted) {
                    return OnboardingScreen(user: session.user);
                  }
                  return AndroidPermissionSetupGate(
                    userId: session.user.id,
                    child: HomeShell(
                      user: session.user,
                      themeKey: widget.themeKey,
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _GateLoading extends StatelessWidget {
  const _GateLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class _GateError extends StatelessWidget {
  const _GateError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 42,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.text('auth_preparation_attention'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.text('auth_preparation_detail'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: Text(context.l10n.text('retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

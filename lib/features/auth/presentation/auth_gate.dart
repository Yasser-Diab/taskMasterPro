import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/presentation/onboarding_screen.dart';
import '../../settings/data/settings_repository.dart';
import '../../shell/presentation/home_shell.dart';
import 'auth_screen.dart';

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({required this.themeKey, super.key});

  final TaskMasterThemeKey themeKey;

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  String? _preparedUserId;
  Future<void>? _preparation;

  Future<void> _prepare(User user, SettingsRepository settings) {
    if (_preparedUserId == user.id && _preparation != null) {
      return _preparation!;
    }
    _preparedUserId = user.id;
    _preparation = () async {
      await settings.ensureLocalAccount(user);
      // Remote registration, realtime and outbox draining must never block an
      // already authenticated user from opening their local workspace.
      unawaited(() async {
        try {
          await ref.read(syncServiceProvider).start();
        } catch (_) {
          // The periodic connectivity listener retries when the network or
          // Supabase becomes available again.
        }
      }());
      unawaited(() async {
        try {
          final generated = await ref
              .read(recurrenceServiceProvider)
              .generateUpcoming();
          if (generated > 0) {
            unawaited(ref.read(syncServiceProvider).drainOutbox());
          }
          await ref.read(activityCaptureServiceProvider).start();
        } catch (_) {
          // Recurrence generation and permission-dependent capture retry on
          // the next launch without holding the local workspace hostage.
        }
      }());
    }();
    return _preparation!;
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(supabaseClientProvider);
    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? client.auth.currentSession;
        if (session == null) {
          _preparedUserId = null;
          _preparation = null;
          return AuthScreen(themeKey: widget.themeKey);
        }

        final settings = ref.watch(settingsRepositoryProvider);
        return FutureBuilder<void>(
          future: _prepare(session.user, settings),
          builder: (context, preparation) {
            if (preparation.hasError) {
              return _GateError(
                message: preparation.error.toString(),
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

            return StreamBuilder(
              stream: settings.watchProfile(session.user.id),
              builder: (context, profileSnapshot) {
                final profile = profileSnapshot.data;
                if (profile == null) return const _GateLoading();
                if (!profile.onboardingCompleted) {
                  return OnboardingScreen(user: session.user);
                }
                return HomeShell(user: session.user, themeKey: widget.themeKey);
              },
            );
          },
        );
      },
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
  const _GateError({required this.message, required this.onRetry});

  final String message;
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
                    'Account preparation needs attention',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
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

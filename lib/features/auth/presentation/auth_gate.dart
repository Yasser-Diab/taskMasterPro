import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase/supabase.dart';

import '../../../core/config/supabase_service.dart';
import '../../../core/deep_links/deep_link_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../dashboard/presentation/home_shell.dart';
import '../../onboarding/presentation/onboarding_wizard.dart';
import 'create_new_password_screen.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.supabaseService,
    this.initialLinks = const [],
    super.key,
  });

  final SupabaseService supabaseService;
  final List<String> initialLinks;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _linkSubscription;
  SupabaseClient? _subscribedClient;
  late final DeepLinkService _deepLinkService;
  final List<String> _pendingLinks = [];

  @override
  void initState() {
    super.initState();
    _deepLinkService = DeepLinkService(
      commandLineArguments: widget.initialLinks,
    );
    widget.supabaseService.addListener(_handleServiceChange);
    _subscribeToAuthChanges();
    _startDeepLinks();
  }

  @override
  void didUpdateWidget(AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.supabaseService != widget.supabaseService) {
      oldWidget.supabaseService.removeListener(_handleServiceChange);
      widget.supabaseService.addListener(_handleServiceChange);
      _subscribeToAuthChanges();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _linkSubscription?.cancel();
    _deepLinkService.dispose();
    widget.supabaseService.removeListener(_handleServiceChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.supabaseService.isPasswordRecoveryPending) {
      return CreateNewPasswordScreen(supabaseService: widget.supabaseService);
    }
    final startup = widget.supabaseService.startupState;
    return switch (startup.status) {
      AppStartupStatus.initializing ||
      AppStartupStatus.loadingAccount => const PreparingWorkspaceScreen(),
      AppStartupStatus.signedOut => LoginScreen(
        supabaseService: widget.supabaseService,
      ),
      AppStartupStatus.needsOnboarding => const OnboardingWizard(),
      AppStartupStatus.ready => HomeShell(
        supabaseService: widget.supabaseService,
      ),
      AppStartupStatus.recoverableError => StartupErrorScreen(
        supabaseService: widget.supabaseService,
        error: startup.error,
      ),
    };
  }

  void _subscribeToAuthChanges() {
    final client = widget.supabaseService.clientOrNull;
    if (identical(client, _subscribedClient)) {
      return;
    }

    _authSubscription?.cancel();
    _subscribedClient = client;
    if (client == null) {
      return;
    }
    _authSubscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          widget.supabaseService.markPasswordRecoveryPending();
        } else if (state.event == AuthChangeEvent.signedOut ||
            state.session == null) {
          widget.supabaseService.markSignedOutFromAuthEvent();
        } else {
          switch (state.event) {
            case AuthChangeEvent.initialSession:
            case AuthChangeEvent.signedIn:
            case AuthChangeEvent.userUpdated:
              unawaited(
                widget.supabaseService.resolveStartupState(force: true),
              );
              break;
            case AuthChangeEvent.tokenRefreshed:
              break;
            default:
              break;
          }
        }
        if (mounted) {
          setState(() {});
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        widget.supabaseService.markStartupError(error);
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  void _handleServiceChange() {
    _subscribeToAuthChanges();
    _processPendingLinks();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startDeepLinks() async {
    _pendingLinks.addAll(await _deepLinkService.initialLinks());
    _linkSubscription = _deepLinkService.linkStream.listen(_handleDeepLink);
    _processPendingLinks();
  }

  void _handleDeepLink(String link) {
    _pendingLinks.add(link);
    _processPendingLinks();
  }

  Future<void> _processPendingLinks() async {
    if (!widget.supabaseService.isInitialized || _pendingLinks.isEmpty) {
      return;
    }
    final links = List<String>.from(_pendingLinks);
    _pendingLinks.clear();
    for (final link in links) {
      await widget.supabaseService.handleAuthDeepLink(link);
    }
  }
}

class PreparingWorkspaceScreen extends StatelessWidget {
  const PreparingWorkspaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.text('appName'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 18),
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  context.text('preparingWorkspace'),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    required this.supabaseService,
    required this.error,
    super.key,
  });

  final SupabaseService supabaseService;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 18),
                Text(
                  context.text('startupErrorTitle'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  context.text('startupErrorMessage'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () =>
                      supabaseService.resolveStartupState(force: true),
                  icon: const Icon(Icons.refresh_outlined),
                  label: Text(context.text('retry')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

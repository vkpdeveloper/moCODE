import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../screens/projects_screen.dart';
import '../screens/open_project_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/device_connection_screen.dart';
import '../screens/payment_checkout_screen.dart';
import '../screens/agent_selection_screen.dart';
import '../screens/model_picker_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/account_deletion_request_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this.ref) {
    ref.listen<AccessGateStatus>(accessGateStatusProvider, (_, _) {
      notifyListeners();
    });
    ref.listen<SettingsState>(settingsProvider, (_, _) {
      notifyListeners();
    });
    ref.listen<SelectedAgentState>(selectedAgentProvider, (_, _) {
      notifyListeners();
    });
  }

  final Ref ref;
}

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) {
  final notifier = _RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = ref.watch(_routerRefreshProvider);

  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final accessGateStatus = ref.read(accessGateStatusProvider);
      final settings = ref.read(settingsProvider);
      final selectedAgent = ref.read(selectedAgentProvider);
      final path = state.uri.path;
      final isConnect = path == '/connect';
      final isAgents = path == '/agents';
      final isSettings = path == '/settings';
      final isPaymentCheckout = path == '/payment/checkout';
      final isSplash = path == '/splash';
      final isAccountDeletion = path == '/account-deletion-request';
      final isConnectionRoute = isConnect || isAgents || isSplash;
      final isGateRoute =
          isSettings ||
          isPaymentCheckout ||
          isSplash ||
          isAccountDeletion ||
          isConnect ||
          isAgents;

      if (!settings.isLoaded) {
        return isSplash ? null : '/splash';
      }

      if (!settings.hasSelectedDevice &&
          !(isConnectionRoute ||
              isSettings ||
              isPaymentCheckout ||
              isAccountDeletion)) {
        return '/connect';
      }

      if (!settings.hasSelectedDevice && isAgents) {
        return '/connect';
      }

      if (settings.hasSelectedDevice && !selectedAgent.isLoaded) {
        return isSplash ? null : '/splash';
      }

      if (settings.hasSelectedDevice &&
          !selectedAgent.hasSelection &&
          !(isConnectionRoute ||
              isSettings ||
              isPaymentCheckout ||
              isAccountDeletion)) {
        return '/agents';
      }

      if (accessGateStatus == AccessGateStatus.loading) {
        return isGateRoute ? null : '/splash';
      }

      if (accessGateStatus != AccessGateStatus.granted && !isGateRoute) {
        return '/settings';
      }

      if (accessGateStatus == AccessGateStatus.granted && isPaymentCheckout) {
        return '/projects';
      }

      if (settings.hasSelectedDevice &&
          selectedAgent.hasSelection &&
          accessGateStatus == AccessGateStatus.granted &&
          isConnect) {
        return '/projects';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/connect',
        builder: (context, state) => const DeviceConnectionScreen(),
      ),
      GoRoute(
        path: '/agents',
        builder: (context, state) => const AgentSelectionScreen(),
      ),
      GoRoute(
        path: '/account-deletion-request',
        builder: (context, state) => const AccountDeletionRequestScreen(),
      ),
      GoRoute(
        path: '/projects',
        builder: (context, state) => const ProjectsScreen(),
      ),
      GoRoute(
        path: '/projects/open',
        builder: (context, state) => const OpenProjectScreen(),
      ),
      GoRoute(
        path: '/sessions',
        builder: (context, state) => const SessionsScreen(),
      ),
      GoRoute(path: '/chat', builder: (context, state) => const ChatScreen()),
      GoRoute(
        path: '/chat/:sessionId',
        builder: (context, state) =>
            ChatScreen(sessionId: state.pathParameters['sessionId']),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) {
          final extra = state.extra;
          final refreshPaymentOnOpen =
              extra is Map<String, dynamic> && extra['refreshPayment'] == true;
          return SettingsScreen(refreshPaymentOnOpen: refreshPaymentOnOpen);
        },
      ),
      GoRoute(
        path: '/payment/checkout',
        builder: (context, state) => const PaymentCheckoutScreen(),
      ),
      GoRoute(
        path: '/models',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            final mode = extra['mode'];
            return ModelPickerScreen(mode: mode is String ? mode : null);
          }
          return const ModelPickerScreen();
        },
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});

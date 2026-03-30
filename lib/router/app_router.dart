import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../screens/projects_screen.dart';
import '../screens/open_project_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/model_picker_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/account_deletion_request_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final accessGateStatus = ref.watch(accessGateStatusProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final path = state.uri.path;
      final isSettings = path == '/settings';
      final isSplash = path == '/splash';
      final isAccountDeletion = path == '/account-deletion-request';
      final isGateRoute = isSettings || isSplash || isAccountDeletion;

      if (accessGateStatus == AccessGateStatus.loading) {
        return isGateRoute ? null : '/settings';
      }

      if (accessGateStatus != AccessGateStatus.granted && !isGateRoute) {
        return '/settings';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
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
        builder: (context, state) => const SettingsScreen(),
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
});

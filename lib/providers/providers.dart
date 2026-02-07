import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart' hide HealthInfo, ProviderListResponse;
import '../models/app_models.dart' as app_models;
import '../models/provider.dart';
import '../services/api_client.dart';
import '../services/app_service.dart';
import '../services/session_service.dart';
import '../services/message_service.dart';
import '../services/project_service.dart';
import '../services/provider_service.dart';
import '../services/event_service.dart';

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsState {
  final String serverUrl;
  final String serverHost;
  final int serverPort;

  const SettingsState({
    this.serverUrl = 'http://127.0.0.1:4096',
    this.serverHost = '127.0.0.1',
    this.serverPort = 4096,
  });

  SettingsState copyWith({
    String? serverUrl,
    String? serverHost,
    int? serverPort,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('server_host') ?? '127.0.0.1';
    final port = prefs.getInt('server_port') ?? 4096;
    state = SettingsState(
      serverHost: host,
      serverPort: port,
      serverUrl: 'http://$host:$port',
    );
  }

  Future<void> updateServer(String host, int port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_host', host);
    await prefs.setInt('server_port', port);
    state = SettingsState(
      serverHost: host,
      serverPort: port,
      serverUrl: 'http://$host:$port',
    );
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

// ---------------------------------------------------------------------------
// API Client
// ---------------------------------------------------------------------------

final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsProvider);
  final client = ApiClient(baseUrl: settings.serverUrl);
  return client;
});

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final appServiceProvider = Provider<AppService>((ref) {
  return AppService(ref.watch(apiClientProvider));
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(ref.watch(apiClientProvider));
});

final messageServiceProvider = Provider<MessageService>((ref) {
  return MessageService(ref.watch(apiClientProvider));
});

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref.watch(apiClientProvider));
});

final providerServiceProvider = Provider<ProviderService>((ref) {
  return ProviderService(ref.watch(apiClientProvider));
});

final eventServiceProvider = Provider<EventService>((ref) {
  return EventService(ref.watch(apiClientProvider));
});

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------

final projectsProvider = FutureProvider<List<Project>>((ref) {
  final projectService = ref.watch(projectServiceProvider);
  return projectService.listProjects();
});

final selectedProjectProvider = StateProvider<Project?>((ref) => null);

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

final sessionsProvider = FutureProvider<List<Session>>((ref) {
  final selectedProject = ref.watch(selectedProjectProvider);
  final sessionService = ref.watch(sessionServiceProvider);
  return sessionService.listSessions(directory: selectedProject?.worktree);
});

final selectedSessionProvider = StateProvider<Session?>((ref) => null);

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

final messagesProvider = FutureProvider<List<MessageWrapper>>((ref) async {
  final session = ref.watch(selectedSessionProvider);
  if (session == null) return [];
  final messageService = ref.watch(messageServiceProvider);
  return messageService.getMessages(session.id, directory: session.directory);
});

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

final healthProvider = FutureProvider<app_models.HealthInfo>((ref) {
  final appService = ref.watch(appServiceProvider);
  return appService.getHealth();
});

// ---------------------------------------------------------------------------
// VCS Info
// ---------------------------------------------------------------------------

final vcsInfoProvider = FutureProvider<app_models.VcsInfo>((ref) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.getVcsInfo(directory: project?.worktree);
});

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

final commandsProvider = FutureProvider<List<app_models.Command>>((ref) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.listCommands(directory: project?.worktree);
});

// ---------------------------------------------------------------------------
// Providers List
// ---------------------------------------------------------------------------

final providersListProvider = FutureProvider<ProviderListResponse>((ref) {
  final providerService = ref.watch(providerServiceProvider);
  return providerService.listProviders();
});

// ---------------------------------------------------------------------------
// Model / Mode Selection
// ---------------------------------------------------------------------------

final selectedModelProvider =
    StateProvider<Map<String, String>?>((ref) => null);

final sessionModeProvider = StateProvider<String>((ref) => 'plan');

final activeModelProvider = Provider<Map<String, String>?>((ref) {
  final selected = ref.watch(selectedModelProvider);
  if (selected != null) return selected;

  final providersAsync = ref.watch(providersListProvider);
  return providersAsync.whenOrNull(
    data: (providerList) {
      final defaults = providerList.defaults;
      final defaultModel = defaults['default'] ?? defaults.values.firstOrNull;
      if (defaultModel == null) return null;

      final parts = defaultModel.split('/');
      if (parts.length >= 2) {
        return {
          'providerID': parts[0],
          'modelID': parts.sublist(1).join('/'),
        };
      }
      return null;
    },
  );
});

// ---------------------------------------------------------------------------
// Session Status
// ---------------------------------------------------------------------------

final sessionStatusProvider =
    FutureProvider<Map<String, dynamic>>((ref) {
  final project = ref.watch(selectedProjectProvider);
  final sessionService = ref.watch(sessionServiceProvider);
  return sessionService.getSessionStatus(directory: project?.worktree);
});

// ---------------------------------------------------------------------------
// Skills
// ---------------------------------------------------------------------------

final skillsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.listSkills(directory: project?.worktree);
});

// ---------------------------------------------------------------------------
// File Search
// ---------------------------------------------------------------------------

final fileSearchProvider =
    FutureProvider.family<List<String>, String>((ref, query) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.findFiles(query: query, directory: project?.worktree);
});

// ---------------------------------------------------------------------------
// Agents
// ---------------------------------------------------------------------------

final agentsProvider = FutureProvider<List<app_models.Agent>>((ref) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.listAgents(directory: project?.worktree);
});

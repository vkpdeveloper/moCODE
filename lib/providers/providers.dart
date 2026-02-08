import 'dart:async';
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
import '../services/file_service.dart';
import '../services/path_service.dart';
import '../services/preferences_service.dart';
import '../services/permission_service.dart';
import '../services/question_service.dart';
import '../services/session_diff_service.dart';
import '../services/todo_service.dart';

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

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier();
  },
);

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

final pathServiceProvider = Provider<PathService>((ref) {
  return PathService(ref.watch(apiClientProvider));
});

final fileServiceProvider = Provider<FileService>((ref) {
  return FileService(ref.watch(apiClientProvider));
});

final providerServiceProvider = Provider<ProviderService>((ref) {
  return ProviderService(ref.watch(apiClientProvider));
});

final eventServiceProvider = Provider<EventService>((ref) {
  return EventService(ref.watch(apiClientProvider));
});

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService(ref.watch(apiClientProvider));
});

final questionServiceProvider = Provider<QuestionService>((ref) {
  return QuestionService(ref.watch(apiClientProvider));
});

final sessionDiffServiceProvider = Provider<SessionDiffService>((ref) {
  return SessionDiffService(ref.watch(apiClientProvider));
});

final todoServiceProvider = Provider<TodoService>((ref) {
  return TodoService(ref.watch(apiClientProvider));
});

final preferencesServiceProvider = Provider<PreferencesService>((ref) {
  return PreferencesService();
});

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------

final projectsProvider = FutureProvider<List<Project>>((ref) {
  final projectService = ref.watch(projectServiceProvider);
  return projectService.listProjects();
});

class PathInfoNotifier extends StateNotifier<AsyncValue<PathInfo>> {
  final PathService _pathService;

  PathInfoNotifier(this._pathService) : super(const AsyncValue.loading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final info = await _pathService.getPaths();
      if (!mounted) return;
      state = AsyncValue.data(info);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }
}

final pathInfoProvider =
    StateNotifierProvider<PathInfoNotifier, AsyncValue<PathInfo>>((ref) {
      return PathInfoNotifier(ref.watch(pathServiceProvider));
    });

final fileListProvider =
    FutureProvider.family<List<String>, ({String path, String directory})>((
      ref,
      args,
    ) {
      final fileService = ref.watch(fileServiceProvider);
      return fileService.listFiles(path: args.path, directory: args.directory);
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
// Session Status
// ---------------------------------------------------------------------------

final sessionStatusProvider = StreamProvider<Map<String, dynamic>>((ref) {
  final sessionService = ref.watch(sessionServiceProvider);
  final project = ref.watch(selectedProjectProvider);
  final controller = StreamController<Map<String, dynamic>>();

  Future<void> fetch() async {
    if (controller.isClosed) return;
    try {
      final status = await sessionService.getSessionStatus(
        directory: project?.worktree,
      );
      if (!controller.isClosed) {
        controller.add(status);
      }
    } catch (_) {
      // ignore status polling errors
    }
  }

  // Initial fetch
  fetch();

  final timer = Timer.periodic(const Duration(seconds: 4), (_) => fetch());

  ref.onDispose(() {
    timer.cancel();
    controller.close();
  });

  return controller.stream;
});

// ---------------------------------------------------------------------------
// Session Diff
// ---------------------------------------------------------------------------

class SessionDiffState {
  final String? sessionID;
  final List<FileDiff> diffs;
  final bool isLoading;
  final String? error;

  const SessionDiffState({
    this.sessionID,
    this.diffs = const [],
    this.isLoading = false,
    this.error,
  });

  SessionDiffState copyWith({
    String? sessionID,
    List<FileDiff>? diffs,
    bool? isLoading,
    String? error,
  }) {
    return SessionDiffState(
      sessionID: sessionID ?? this.sessionID,
      diffs: diffs ?? this.diffs,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SessionDiffNotifier extends StateNotifier<SessionDiffState> {
  final SessionDiffService _sessionDiffService;

  SessionDiffNotifier(this._sessionDiffService)
    : super(const SessionDiffState());

  Future<void> loadDiff(
    String sessionID, {
    String? directory,
    String? messageID,
  }) async {
    state = state.copyWith(sessionID: sessionID, isLoading: true, error: null);
    try {
      final diffs = await _sessionDiffService.getDiff(
        sessionID,
        directory: directory,
        messageID: messageID,
      );
      state = state.copyWith(
        sessionID: sessionID,
        diffs: diffs,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        sessionID: sessionID,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void setDiff(String sessionID, List<FileDiff> diffs) {
    state = state.copyWith(
      sessionID: sessionID,
      diffs: diffs,
      isLoading: false,
      error: null,
    );
  }

  void clear() {
    state = const SessionDiffState();
  }
}

final sessionDiffProvider =
    StateNotifierProvider<SessionDiffNotifier, SessionDiffState>((ref) {
      return SessionDiffNotifier(ref.watch(sessionDiffServiceProvider));
    });

// ---------------------------------------------------------------------------
// Todos
// ---------------------------------------------------------------------------

class TodosState {
  final String? sessionID;
  final List<Todo> todos;
  final bool isLoading;
  final String? error;

  const TodosState({
    this.sessionID,
    this.todos = const [],
    this.isLoading = false,
    this.error,
  });

  TodosState copyWith({
    String? sessionID,
    List<Todo>? todos,
    bool? isLoading,
    String? error,
  }) {
    return TodosState(
      sessionID: sessionID ?? this.sessionID,
      todos: todos ?? this.todos,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class TodosNotifier extends StateNotifier<TodosState> {
  final TodoService _todoService;

  TodosNotifier(this._todoService) : super(const TodosState());

  Future<void> loadTodos(String sessionID, {String? directory}) async {
    state = state.copyWith(sessionID: sessionID, isLoading: true, error: null);
    try {
      final todos = await _todoService.getTodos(
        sessionID,
        directory: directory,
      );
      state = state.copyWith(
        sessionID: sessionID,
        todos: todos,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        sessionID: sessionID,
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void setTodos(String sessionID, List<Todo> todos) {
    state = state.copyWith(
      sessionID: sessionID,
      todos: todos,
      isLoading: false,
      error: null,
    );
  }

  void clear() {
    state = const TodosState();
  }
}

final todosProvider = StateNotifierProvider<TodosNotifier, TodosState>((ref) {
  return TodosNotifier(ref.watch(todoServiceProvider));
});

// ---------------------------------------------------------------------------
// Edited Files
// ---------------------------------------------------------------------------

class EditedFilesNotifier extends StateNotifier<List<EditedFileEntry>> {
  EditedFilesNotifier() : super(const []);

  void record(String path, {String? kind, int? timestamp}) {
    final now = timestamp ?? DateTime.now().millisecondsSinceEpoch;
    final index = state.indexWhere((entry) => entry.path == path);
    if (index == -1) {
      state = [
        EditedFileEntry(path: path, updatedAt: now, kind: kind),
        ...state,
      ];
      return;
    }
    final updated = state[index].copyWith(
      updatedAt: now,
      kind: kind ?? state[index].kind,
    );
    final next = List<EditedFileEntry>.from(state);
    next
      ..removeAt(index)
      ..insert(0, updated);
    state = next;
  }

  void clear() {
    state = const [];
  }
}

final editedFilesProvider =
    StateNotifierProvider<EditedFilesNotifier, List<EditedFileEntry>>((ref) {
      return EditedFilesNotifier();
    });

// ---------------------------------------------------------------------------
// Pty Sessions
// ---------------------------------------------------------------------------

class PtyState {
  final Map<String, PtyInfo> items;

  const PtyState({this.items = const {}});

  PtyState copyWith({Map<String, PtyInfo>? items}) {
    return PtyState(items: items ?? this.items);
  }
}

class PtyNotifier extends StateNotifier<PtyState> {
  PtyNotifier() : super(const PtyState());

  void upsert(PtyInfo info) {
    final next = Map<String, PtyInfo>.from(state.items);
    next[info.id] = info;
    state = state.copyWith(items: next);
  }

  void updateExit(String id, int exitCode) {
    final existing = state.items[id];
    if (existing == null) return;
    upsert(existing.copyWith(status: 'exited', exitCode: exitCode));
  }

  void remove(String id) {
    if (!state.items.containsKey(id)) return;
    final next = Map<String, PtyInfo>.from(state.items);
    next.remove(id);
    state = state.copyWith(items: next);
  }

  void clear() {
    state = const PtyState();
  }
}

final ptyProvider = StateNotifierProvider<PtyNotifier, PtyState>((ref) {
  return PtyNotifier();
});

// ---------------------------------------------------------------------------
// Session Error
// ---------------------------------------------------------------------------

class SessionErrorState {
  final String? sessionID;
  final String? message;
  final String? name;

  const SessionErrorState({this.sessionID, this.message, this.name});

  SessionErrorState copyWith({
    String? sessionID,
    String? message,
    String? name,
  }) {
    return SessionErrorState(
      sessionID: sessionID ?? this.sessionID,
      message: message ?? this.message,
      name: name ?? this.name,
    );
  }
}

class SessionErrorNotifier extends StateNotifier<SessionErrorState> {
  SessionErrorNotifier() : super(const SessionErrorState());

  void setError({String? sessionID, String? message, String? name}) {
    state = SessionErrorState(
      sessionID: sessionID,
      message: message,
      name: name,
    );
  }

  void clear() {
    state = const SessionErrorState();
  }
}

final sessionErrorProvider =
    StateNotifierProvider<SessionErrorNotifier, SessionErrorState>((ref) {
      return SessionErrorNotifier();
    });

// ---------------------------------------------------------------------------
// VCS Branch
// ---------------------------------------------------------------------------

final vcsBranchProvider = StateProvider<String?>((ref) => null);

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

final messagesProvider = FutureProvider<List<MessageWrapper>>((ref) async {
  final session = ref.watch(selectedSessionProvider);
  if (session == null) return [];
  final messageService = ref.watch(messageServiceProvider);
  return messageService.getMessages(session.id, directory: session.directory);
});

class ActiveSessionsNotifier extends StateNotifier<Map<String, String>> {
  final PreferencesService _preferencesService;
  static const int _maxActiveSessions = 5;

  ActiveSessionsNotifier(this._preferencesService) : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final sessions = await _preferencesService.getActiveSessions();
    if (sessions.length <= _maxActiveSessions) {
      state = sessions;
      return;
    }
    final trimmed = <String, String>{};
    var kept = 0;
    for (final entry in sessions.entries) {
      if (kept >= _maxActiveSessions) {
        await _preferencesService.clearSessionActive(entry.key);
        continue;
      }
      trimmed[entry.key] = entry.value;
      kept += 1;
    }
    state = trimmed;
  }

  Future<void> markActive(String sessionId, String directory) async {
    await _preferencesService.markSessionActive(sessionId, directory);
    final next = Map<String, String>.from(state);
    if (next.containsKey(sessionId)) {
      next.remove(sessionId);
    }
    next[sessionId] = directory;
    while (next.length > _maxActiveSessions) {
      final oldest = next.keys.first;
      next.remove(oldest);
      await _preferencesService.clearSessionActive(oldest);
    }
    state = next;
  }

  Future<void> clearActive(String sessionId) async {
    await _preferencesService.clearSessionActive(sessionId);
    if (!state.containsKey(sessionId)) return;
    final next = Map<String, String>.from(state);
    next.remove(sessionId);
    state = next;
  }

  Future<void> clearAllActive() async {
    await _preferencesService.clearActiveSessions();
    state = const {};
  }
}

final activeSessionsProvider =
    StateNotifierProvider<ActiveSessionsNotifier, Map<String, String>>((ref) {
      return ActiveSessionsNotifier(ref.watch(preferencesServiceProvider));
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

// ---------------------------------------------------------------------------
// Model / Mode Selection
// ---------------------------------------------------------------------------

final selectedModelProvider = StateProvider<Map<String, String>?>(
  (ref) => null,
);

final sessionModeProvider = StateProvider<String>((ref) => 'plan');

class DefaultModelNotifier extends StateNotifier<Map<String, String>?> {
  final PreferencesService _preferencesService;

  DefaultModelNotifier(this._preferencesService) : super(null) {
    _load();
  }

  Future<void> _load() async {
    final model = await _preferencesService.getDefaultModel();
    if (model != null) {
      state = model;
    }
  }

  Future<void> setModel(String providerId, String modelId) async {
    await _preferencesService.saveDefaultModel(providerId, modelId);
    state = {'providerID': providerId, 'modelID': modelId};
  }

  Future<void> clearModel() async {
    await _preferencesService.clearDefaultModel();
    state = null;
  }
}

final defaultModelProvider =
    StateNotifierProvider<DefaultModelNotifier, Map<String, String>?>((ref) {
      return DefaultModelNotifier(ref.watch(preferencesServiceProvider));
    });

class ProjectModelState {
  final Map<String, String>? model;
  final bool isLoading;
  final String? projectId;

  const ProjectModelState({
    required this.model,
    this.isLoading = false,
    this.projectId,
  });
}

class ProjectModelNotifier extends StateNotifier<ProjectModelState> {
  final PreferencesService _preferencesService;

  ProjectModelNotifier(this._preferencesService)
    : super(const ProjectModelState(model: null, isLoading: true));

  Future<void> load(String projectId) async {
    state = ProjectModelState(
      model: null,
      isLoading: true,
      projectId: projectId,
    );
    final model = await _preferencesService.getProjectModel(projectId);
    state = ProjectModelState(
      model: model,
      isLoading: false,
      projectId: projectId,
    );
  }

  Future<void> setModel(
    String projectId,
    String providerId,
    String modelId,
  ) async {
    await _preferencesService.saveProjectModel(projectId, providerId, modelId);
    state = ProjectModelState(
      model: {'providerID': providerId, 'modelID': modelId},
      isLoading: false,
      projectId: projectId,
    );
  }

  Future<void> clearModel(String projectId) async {
    await _preferencesService.clearProjectModel(projectId);
    state = ProjectModelState(
      model: null,
      isLoading: false,
      projectId: projectId,
    );
  }
}

final projectModelProvider =
    StateNotifierProvider<ProjectModelNotifier, ProjectModelState>((ref) {
      return ProjectModelNotifier(ref.watch(preferencesServiceProvider));
    });

final activeModelProvider = Provider<Map<String, String>?>((ref) {
  // 1. Session specific model (if set in current session view)
  final selected = ref.watch(selectedModelProvider);
  if (selected != null) return selected;

  // 2. Project default model (persisted)
  final projectModel = ref.watch(projectModelProvider).model;
  if (projectModel != null) return projectModel;

  // 3. User default model (persisted)
  final defaultModel = ref.watch(defaultModelProvider);
  if (defaultModel != null) return defaultModel;

  return null;
});

// ---------------------------------------------------------------------------
// Skills
// ---------------------------------------------------------------------------

final skillsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.listSkills(directory: project?.worktree);
});

// ---------------------------------------------------------------------------
// File Search
// ---------------------------------------------------------------------------

final fileSearchProvider = FutureProvider.family<List<String>, String>((
  ref,
  query,
) {
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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart' hide HealthInfo, ProviderListResponse;
import '../models/app_models.dart' as app_models;
import '../models/provider.dart';
import '../config/app_env.dart';

import '../services/api_client.dart';
import '../services/account_api_client.dart';
import '../services/auth_service.dart';
import '../services/app_service.dart';
import '../services/account_service.dart';
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
import '../services/pty_service.dart';

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsState {
  final String serverUrl;
  final String serverHost;
  final int serverPort;
  final bool isLoaded;

  const SettingsState({
    this.serverUrl = 'http://127.0.0.1:4096',
    this.serverHost = '127.0.0.1',
    this.serverPort = 4096,
    this.isLoaded = false,
  });

  SettingsState copyWith({
    String? serverUrl,
    String? serverHost,
    int? serverPort,
    bool? isLoaded,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  Future<void>? _loading;

  SettingsNotifier() : super(const SettingsState()) {
    ensureLoaded();
  }

  Future<void> ensureLoaded() {
    final existing = _loading;
    if (existing != null) return existing;
    final next = _load();
    _loading = next;
    return next;
  }

  Future<void> reload() async {
    _loading = _load();
    await _loading;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('server_host') ?? '127.0.0.1';
    final port = prefs.getInt('server_port') ?? 4096;
    state = SettingsState(
      serverHost: host,
      serverPort: port,
      serverUrl: 'http://$host:$port',
      isLoaded: true,
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
      isLoaded: true,
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
  ref.listen<SettingsState>(settingsProvider, (prev, next) {
    if (prev?.serverUrl == next.serverUrl) return;
    client.updateBaseUrl(next.serverUrl);
  });
  return client;
});

final accountApiClientProvider = Provider<AccountApiClient>((ref) {
  return AccountApiClient(baseUrl: AppEnv.accountApiBaseUrl);
});

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn.instance;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(
    ref.watch(firebaseAuthProvider),
    ref.watch(googleSignInProvider),
    AppEnv.googleServerClientId,
  );
});

final accountServiceProvider = Provider<AccountService>((ref) {
  return AccountService(ref.watch(accountApiClientProvider));
});

final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges();
});

final firebaseUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).valueOrNull;
});

final idTokenProvider = FutureProvider<String?>((ref) async {
  final user = ref.watch(firebaseUserProvider);
  return user?.getIdToken();
});

final accountProfileProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final idToken = await ref.watch(idTokenProvider.future);
  if (idToken == null) {
    return null;
  }
  final accountService = ref.watch(accountServiceProvider);
  return accountService.fetchMe(idToken);
});

final billingStatusProvider = FutureProvider<Map<String, dynamic>?>((
  ref,
) async {
  final idToken = await ref.watch(idTokenProvider.future);
  if (idToken == null) {
    return null;
  }
  final accountService = ref.watch(accountServiceProvider);
  return accountService.fetchBillingStatus(idToken);
});

enum AccessGateStatus { loading, signedOut, unpaid, granted }

final accessGateStatusProvider = Provider<AccessGateStatus>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth.isLoading) return AccessGateStatus.loading;
  final user = auth.valueOrNull;
  if (user == null) return AccessGateStatus.signedOut;

  final billing = ref.watch(billingStatusProvider);
  if (billing.isLoading) return AccessGateStatus.loading;
  final unlocked = billing.valueOrNull?['oneTimeUnlocked'] == true;
  return unlocked ? AccessGateStatus.granted : AccessGateStatus.unpaid;
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

class _NormalizedEvent {
  final String type;
  final Map<String, dynamic> properties;

  const _NormalizedEvent({
    required this.type,
    required this.properties,
  });
}

class GlobalEventCoordinator {
  final Ref _ref;
  final Map<String, StreamSubscription<Map<String, dynamic>>> _subscriptions =
      {};
  Set<String> _directories = const {};
  Timer? _sessionsRefreshTimer;

  GlobalEventCoordinator(this._ref);

  void syncDirectories(Set<String> directories) {
    final next = directories.where((value) => value.isNotEmpty).toSet();
    if (setEquals(_directories, next)) return;
    final eventService = _ref.read(eventServiceProvider);

    for (final directory in next) {
      if (_subscriptions.containsKey(directory)) continue;
      _subscriptions[directory] = eventService
          .subscribe(directory: directory)
          .listen(_handleRawEvent, onError: (Object error) {
            debugPrint('[GlobalEventCoordinator] stream error: $error');
          });
    }

    final toRemove = _subscriptions.keys
        .where((directory) => !next.contains(directory))
        .toList();
    for (final directory in toRemove) {
      _subscriptions.remove(directory)?.cancel();
    }

    _directories = next;
  }

  void dispose() {
    _sessionsRefreshTimer?.cancel();
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _handleRawEvent(Map<String, dynamic> raw) {
    final event = _normalize(raw);
    if (event == null) return;

    if (event.type == '__reconnected__') {
      _onReconnected();
      return;
    }
    if (event.type == 'session.created' || event.type == 'session.updated') {
      _handleSessionUpsert(event.properties);
      return;
    }
    if (event.type == 'session.deleted') {
      _handleSessionDeleted(event.properties);
      return;
    }
    if (event.type == 'session.status') {
      _handleSessionStatus(event.properties);
      return;
    }
    if (event.type == 'session.idle') {
      _handleSessionIdle(event.properties);
      return;
    }
    if (event.type == 'message.updated') {
      _handleMessageUpdated(event.properties);
      return;
    }
    if (event.type == 'message.part.updated') {
      _handleMessagePartUpdated(event.properties);
      return;
    }
    if (event.type == 'message.removed') {
      _handleMessageRemoved(event.properties);
      return;
    }
    if (event.type == 'message.part.removed') {
      _handleMessagePartRemoved(event.properties);
      return;
    }
    if (event.type == 'todo.updated') {
      _handleTodoUpdated(event.properties);
      return;
    }
    if (event.type == 'session.diff') {
      _handleSessionDiff(event.properties);
      return;
    }
    if (event.type == 'session.error') {
      _handleSessionError(event.properties);
      return;
    }
    if (event.type == 'vcs.branch.updated') {
      _handleBranchUpdated(event.properties);
      return;
    }
    if (event.type == 'pty.created') {
      _handlePtyCreated(event.properties);
      return;
    }
    if (event.type == 'pty.updated') {
      _handlePtyUpdated(event.properties);
      return;
    }
    if (event.type == 'pty.exited') {
      _handlePtyExited(event.properties);
      return;
    }
    if (event.type == 'pty.deleted') {
      _handlePtyDeleted(event.properties);
      return;
    }
  }

  _NormalizedEvent? _normalize(Map<String, dynamic> raw) {
    final payloadRaw = raw['payload'];
    final payload = payloadRaw is Map<String, dynamic>
        ? payloadRaw
        : payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : raw;

    final type = payload['type']?.toString();
    if (type == null || type.isEmpty) return null;

    final propertiesRaw = payload['properties'];
    final properties = propertiesRaw is Map<String, dynamic>
        ? propertiesRaw
        : propertiesRaw is Map
        ? Map<String, dynamic>.from(propertiesRaw)
        : <String, dynamic>{};

    return _NormalizedEvent(
      type: type,
      properties: properties,
    );
  }

  void _onReconnected() {
    _scheduleSessionsRefresh(immediate: true);
    _ref.invalidate(sessionStatusProvider);
    final session = _ref.read(selectedSessionProvider);
    unawaited(_ref.read(messagesProvider.notifier).loadForSession(session));
  }

  void _handleSessionUpsert(Map<String, dynamic> properties) {
    final infoRaw = properties['info'];
    if (infoRaw is! Map) return;
    try {
      final session = Session.fromJson(Map<String, dynamic>.from(infoRaw));
      final selected = _ref.read(selectedSessionProvider);
      if (selected != null && selected.id == session.id) {
        _ref.read(selectedSessionProvider.notifier).state = session;
      }
      _scheduleSessionsRefresh();
    } catch (error) {
      debugPrint('[GlobalEventCoordinator] session parse error: $error');
    }
  }

  void _handleSessionDeleted(Map<String, dynamic> properties) {
    final infoRaw = properties['info'];
    if (infoRaw is! Map) return;
    final deletedId = infoRaw['id']?.toString();
    if (deletedId == null || deletedId.isEmpty) return;
    final selected = _ref.read(selectedSessionProvider);
    if (selected != null && selected.id == deletedId) {
      _ref.read(selectedSessionProvider.notifier).state = null;
      unawaited(_ref.read(messagesProvider.notifier).loadForSession(null));
    }
    unawaited(_ref.read(activeSessionsProvider.notifier).clearActive(deletedId));
    _scheduleSessionsRefresh();
  }

  void _scheduleSessionsRefresh({bool immediate = false}) {
    _sessionsRefreshTimer?.cancel();
    if (immediate) {
      _ref.invalidate(sessionsProvider);
      return;
    }
    _sessionsRefreshTimer = Timer(const Duration(milliseconds: 180), () {
      _ref.invalidate(sessionsProvider);
    });
  }

  void _handleSessionStatus(Map<String, dynamic> properties) {
    final sessionID = properties['sessionID']?.toString();
    if (sessionID == null || sessionID.isEmpty) return;
    _ref
        .read(sessionStatusProvider.notifier)
        .upsertStatus(sessionID, properties['status']);
  }

  void _handleSessionIdle(Map<String, dynamic> properties) {
    final sessionID = properties['sessionID']?.toString();
    if (sessionID == null || sessionID.isEmpty) return;
    _ref.read(sessionStatusProvider.notifier).markIdle(sessionID);
  }

  void _handleMessageUpdated(Map<String, dynamic> properties) {
    final infoRaw = properties['info'];
    if (infoRaw is! Map) return;
    try {
      final info = MessageInfo.fromJson(Map<String, dynamic>.from(infoRaw));
      final selected = _ref.read(selectedSessionProvider);
      if (selected == null || selected.id != info.sessionID) return;
      _ref.read(messagesProvider.notifier).upsertMessage(info);
    } catch (error) {
      debugPrint('[GlobalEventCoordinator] message parse error: $error');
    }
  }

  void _handleMessagePartUpdated(Map<String, dynamic> properties) {
    final partRaw = properties['part'];
    if (partRaw is! Map) return;
    try {
      final part = Part.fromJson(Map<String, dynamic>.from(partRaw));
      final selected = _ref.read(selectedSessionProvider);
      if (selected == null || selected.id != part.sessionID) return;
      final delta = properties['delta'] is String
          ? properties['delta'] as String
          : null;
      _ref.read(messagesProvider.notifier).upsertPart(part, delta: delta);
    } catch (error) {
      debugPrint('[GlobalEventCoordinator] part parse error: $error');
    }
  }

  void _handleMessageRemoved(Map<String, dynamic> properties) {
    final sessionID = properties['sessionID']?.toString();
    final messageID = properties['messageID']?.toString();
    if (sessionID == null || messageID == null) return;
    final selected = _ref.read(selectedSessionProvider);
    if (selected == null || selected.id != sessionID) return;
    _ref.read(messagesProvider.notifier).removeMessage(messageID);
  }

  void _handleMessagePartRemoved(Map<String, dynamic> properties) {
    final sessionID = properties['sessionID']?.toString();
    final messageID = properties['messageID']?.toString();
    final partID = properties['partID']?.toString();
    if (sessionID == null || messageID == null || partID == null) return;
    final selected = _ref.read(selectedSessionProvider);
    if (selected == null || selected.id != sessionID) return;
    _ref.read(messagesProvider.notifier).removePart(messageID, partID);
  }

  void _handleTodoUpdated(Map<String, dynamic> properties) {
    final sessionID = properties['sessionID']?.toString();
    final todosRaw = properties['todos'];
    if (sessionID == null || todosRaw is! List) return;
    final selected = _ref.read(selectedSessionProvider);
    if (selected == null || selected.id != sessionID) return;
    final todos = todosRaw
        .whereType<Map<String, dynamic>>()
        .map(Todo.fromJson)
        .toList();
    _ref.read(todosProvider.notifier).setTodos(sessionID, todos);
  }

  void _handleSessionDiff(Map<String, dynamic> properties) {
    final sessionID = properties['sessionID']?.toString();
    final diffRaw = properties['diff'];
    if (sessionID == null || diffRaw is! List) return;
    final selected = _ref.read(selectedSessionProvider);
    if (selected == null || selected.id != sessionID) return;
    final diff = diffRaw
        .whereType<Map<String, dynamic>>()
        .map(FileDiff.fromJson)
        .toList();
    _ref.read(sessionDiffProvider.notifier).setDiff(sessionID, diff);
  }

  void _handleSessionError(Map<String, dynamic> properties) {
    final sessionID = properties['sessionID']?.toString();
    final selected = _ref.read(selectedSessionProvider);
    if (selected != null && sessionID != null && selected.id != sessionID) return;
    final error = properties['error'];
    String? message;
    String? name;
    if (error is Map<String, dynamic>) {
      name = error['name']?.toString();
      final data = error['data'];
      if (data is Map<String, dynamic>) {
        message = data['message']?.toString();
      }
    }
    _ref
        .read(sessionErrorProvider.notifier)
        .setError(sessionID: sessionID, message: message, name: name);
  }

  void _handleBranchUpdated(Map<String, dynamic> properties) {
    final branch = properties['branch']?.toString();
    _ref.read(vcsBranchProvider.notifier).state = branch;
  }

  void _handlePtyCreated(Map<String, dynamic> properties) {
    final info = properties['info'];
    if (info is! Map<String, dynamic>) return;
    try {
      _ref.read(ptyProvider.notifier).upsert(PtyInfo.fromJson(info));
    } catch (_) {}
  }

  void _handlePtyUpdated(Map<String, dynamic> properties) {
    final info = properties['info'];
    if (info is! Map<String, dynamic>) return;
    try {
      _ref.read(ptyProvider.notifier).upsert(PtyInfo.fromJson(info));
    } catch (_) {}
  }

  void _handlePtyExited(Map<String, dynamic> properties) {
    final id = properties['id']?.toString();
    if (id == null || id.isEmpty) return;
    final exitCode = (properties['exitCode'] as num?)?.toInt() ?? 0;
    _ref.read(ptyProvider.notifier).updateExit(id, exitCode);
  }

  void _handlePtyDeleted(Map<String, dynamic> properties) {
    final id = properties['id']?.toString();
    if (id == null || id.isEmpty) return;
    _ref.read(ptyProvider.notifier).remove(id);
  }
}

final globalEventCoordinatorProvider = Provider<GlobalEventCoordinator>((ref) {
  final coordinator = GlobalEventCoordinator(ref);

  Set<String> computeDirectories() {
    final directories = <String>{};
    final selectedProject = ref.read(selectedProjectProvider);
    if (selectedProject != null) {
      directories.add(selectedProject.worktree);
    }
    final selectedSession = ref.read(selectedSessionProvider);
    if (selectedSession != null) {
      directories.add(selectedSession.directory);
    }
    directories.addAll(ref.read(activeSessionsProvider).values);
    return directories;
  }

  void sync() {
    coordinator.syncDirectories(computeDirectories());
  }

  ref.listen<Project?>(selectedProjectProvider, (_, _) => sync());
  ref.listen<Session?>(selectedSessionProvider, (_, _) => sync());
  ref.listen<Map<String, String>>(activeSessionsProvider, (_, _) => sync());
  sync();

  ref.onDispose(coordinator.dispose);
  return coordinator;
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

final ptyServiceProvider = Provider<PtyService>((ref) {
  return PtyService(ref.watch(apiClientProvider));
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

final sortedProjectsProvider = Provider<AsyncValue<List<Project>>>((ref) {
  final projectsAsync = ref.watch(projectsProvider);
  return projectsAsync.whenData((projects) {
    final sorted = List<Project>.from(projects)
      ..sort((a, b) => b.time.updated!.compareTo(a.time.updated!));
    return sorted;
  });
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

class SessionStatusNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final SessionService _sessionService;
  String? _directory;

  SessionStatusNotifier(this._sessionService) : super(const AsyncValue.loading());

  Future<void> loadForDirectory(String? directory) async {
    _directory = directory;
    if (directory == null) {
      state = const AsyncValue.data({});
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    final directory = _directory;
    if (directory == null) {
      state = const AsyncValue.data({});
      return;
    }
    try {
      final status = await _sessionService.getSessionStatus(directory: directory);
      if (!mounted || directory != _directory) return;
      state = AsyncValue.data(status);
    } catch (e, st) {
      if (!mounted || directory != _directory) return;
      final previous = state.valueOrNull;
      if (previous != null) {
        state = AsyncValue.data(previous);
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void upsertStatus(String sessionID, dynamic status) {
    final next = Map<String, dynamic>.from(state.valueOrNull ?? const {});
    if (status is Map<String, dynamic>) {
      next[sessionID] = status;
    } else if (status is String) {
      next[sessionID] = {'type': status};
    } else {
      next[sessionID] = {'type': status?.toString() ?? 'busy'};
    }
    state = AsyncValue.data(next);
  }

  void markIdle(String sessionID) {
    final next = Map<String, dynamic>.from(state.valueOrNull ?? const {});
    next[sessionID] = {'type': 'idle'};
    state = AsyncValue.data(next);
  }
}

final sessionStatusProvider =
    StateNotifierProvider<SessionStatusNotifier, AsyncValue<Map<String, dynamic>>>(
      (ref) {
        final notifier = SessionStatusNotifier(ref.watch(sessionServiceProvider));
        ref.listen<Project?>(selectedProjectProvider, (previous, next) {
          unawaited(notifier.loadForDirectory(next?.worktree));
        }, fireImmediately: true);

        final timer = Timer.periodic(const Duration(seconds: 4), (_) {
          unawaited(notifier.refresh());
        });
        ref.onDispose(timer.cancel);
        return notifier;
      },
    );

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

class CommandRunsState {
  final Map<String, CommandRun> items;

  const CommandRunsState({this.items = const {}});

  CommandRunsState copyWith({Map<String, CommandRun>? items}) {
    return CommandRunsState(items: items ?? this.items);
  }
}

class CommandRunsNotifier extends StateNotifier<CommandRunsState> {
  CommandRunsNotifier() : super(const CommandRunsState());

  void upsert(CommandRun run) {
    final next = Map<String, CommandRun>.from(state.items);
    next[run.id] = run;
    state = state.copyWith(items: next);
  }

  void appendOutput(String id, String chunk) {
    if (chunk.isEmpty) return;
    final existing = state.items[id];
    if (existing == null) return;
    upsert(existing.copyWith(output: '${existing.output}$chunk'));
  }

  void updateStatus(
    String id, {
    String? status,
    int? exitCode,
    int? completedAt,
  }) {
    final existing = state.items[id];
    if (existing == null) return;
    upsert(
      existing.copyWith(
        status: status ?? existing.status,
        exitCode: exitCode ?? existing.exitCode,
        completedAt: completedAt ?? existing.completedAt,
      ),
    );
  }

  void clear() {
    state = const CommandRunsState();
  }
}

final commandRunsProvider =
    StateNotifierProvider<CommandRunsNotifier, CommandRunsState>((ref) {
      return CommandRunsNotifier();
    });

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

final activeCommandRunProvider = StateProvider<String?>((ref) => null);

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

class MessagesState {
  final List<MessageWrapper> messages;
  final bool isLoading;
  final String? error;

  const MessagesState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
  });

  MessagesState copyWith({
    List<MessageWrapper>? messages,
    bool? isLoading,
    Object? error = _messagesNoChange,
  }) {
    return MessagesState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _messagesNoChange) ? this.error : error as String?,
    );
  }
}

const Object _messagesNoChange = Object();

class MessagesNotifier extends StateNotifier<MessagesState> {
  final MessageService _messageService;
  int _loadToken = 0;
  final Map<String, List<_PendingPartUpdate>> _pendingPartsByMessage = {};

  MessagesNotifier(this._messageService) : super(const MessagesState());

  Future<void> loadForSession(Session? session) async {
    final token = ++_loadToken;
    if (session == null) {
      state = const MessagesState();
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final messages = await _messageService.getMessages(
        session.id,
        directory: session.directory,
      );
      if (!mounted || token != _loadToken) return;
      state = state.copyWith(messages: messages, isLoading: false, error: null);
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void upsertMessage(MessageInfo info) {
    final current = List<MessageWrapper>.from(state.messages);
    final index = current.indexWhere((message) => message.info.id == info.id);
    if (index >= 0) {
      current[index] = MessageWrapper(info: info, parts: current[index].parts);
    } else {
      current.add(MessageWrapper(info: info, parts: const []));
      current.sort((a, b) => _messageCreatedAt(a.info).compareTo(_messageCreatedAt(b.info)));
    }
    _applyPendingParts(current, info.id);
    state = state.copyWith(messages: current, error: null);
  }

  void upsertPart(Part part, {String? delta}) {
    final current = List<MessageWrapper>.from(state.messages);
    final messageIndex = current.indexWhere(
      (message) => message.info.id == part.messageID,
    );
    if (messageIndex < 0) {
      _pendingPartsByMessage.putIfAbsent(part.messageID, () => []).add(
        _PendingPartUpdate(part: part, delta: delta),
      );
      return;
    }

    final existing = current[messageIndex];
    final parts = List<Part>.from(existing.parts);
    final partIndex = parts.indexWhere((candidate) => candidate.id == part.id);

    if (partIndex < 0) {
      parts.add(_applyDelta(part, delta));
    } else {
      parts[partIndex] = _mergePart(parts[partIndex], part, delta);
    }

    current[messageIndex] = MessageWrapper(info: existing.info, parts: parts);
    state = state.copyWith(messages: current, error: null);
  }

  void removeMessage(String messageID) {
    final next = state.messages
        .where((message) => message.info.id != messageID)
        .toList();
    _pendingPartsByMessage.remove(messageID);
    state = state.copyWith(messages: next, error: null);
  }

  void removePart(String messageID, String partID) {
    final current = List<MessageWrapper>.from(state.messages);
    final messageIndex = current.indexWhere(
      (message) => message.info.id == messageID,
    );
    if (messageIndex < 0) return;
    final existing = current[messageIndex];
    final parts = existing.parts.where((part) => part.id != partID).toList();
    current[messageIndex] = MessageWrapper(info: existing.info, parts: parts);
    state = state.copyWith(messages: current, error: null);
  }

  Part _mergePart(Part previous, Part incoming, String? delta) {
    if (previous is TextPart && incoming is TextPart) {
      if (incoming.text.isNotEmpty && incoming.text != previous.text) {
        return incoming;
      }
      if (delta == null || delta.isEmpty) return incoming;
      return TextPart(
        id: incoming.id,
        sessionID: incoming.sessionID,
        messageID: incoming.messageID,
        text: '${previous.text}$delta',
        synthetic: incoming.synthetic,
        ignored: incoming.ignored,
        time: incoming.time,
        metadata: incoming.metadata,
      );
    }
    return _applyDelta(incoming, delta);
  }

  Part _applyDelta(Part incoming, String? delta) {
    if (incoming is! TextPart) {
      return incoming;
    }
    if (incoming.text.isNotEmpty) return incoming;
    if (delta == null || delta.isEmpty) return incoming;

    return TextPart(
      id: incoming.id,
      sessionID: incoming.sessionID,
      messageID: incoming.messageID,
      text: incoming.text.isEmpty ? delta : incoming.text,
      synthetic: incoming.synthetic,
      ignored: incoming.ignored,
      time: incoming.time,
      metadata: incoming.metadata,
    );
  }

  int _messageCreatedAt(MessageInfo info) {
    if (info is UserMessageInfo) return info.time.created;
    if (info is AssistantMessageInfo) return info.time.created;
    return 0;
  }

  void _applyPendingParts(List<MessageWrapper> messages, String messageID) {
    final pending = _pendingPartsByMessage.remove(messageID);
    if (pending == null || pending.isEmpty) return;
    final messageIndex = messages.indexWhere(
      (message) => message.info.id == messageID,
    );
    if (messageIndex < 0) return;

    var existing = messages[messageIndex];
    for (final update in pending) {
      final parts = List<Part>.from(existing.parts);
      final partIndex = parts.indexWhere((part) => part.id == update.part.id);
      if (partIndex < 0) {
        parts.add(_applyDelta(update.part, update.delta));
      } else {
        parts[partIndex] = _mergePart(parts[partIndex], update.part, update.delta);
      }
      existing = MessageWrapper(info: existing.info, parts: parts);
    }

    messages[messageIndex] = existing;
  }
}

class _PendingPartUpdate {
  final Part part;
  final String? delta;

  const _PendingPartUpdate({required this.part, required this.delta});
}

final messagesProvider = StateNotifierProvider<MessagesNotifier, MessagesState>((
  ref,
) {
  final notifier = MessagesNotifier(ref.watch(messageServiceProvider));
  ref.listen<Session?>(selectedSessionProvider, (previous, next) {
    final previousId = previous?.id;
    final nextId = next?.id;
    if (previousId == nextId) return;
    unawaited(notifier.loadForSession(next));
  }, fireImmediately: true);
  return notifier;
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

class SessionModeNotifier extends StateNotifier<String> {
  final PreferencesService _preferencesService;
  final Map<String, String> _sessionModes = {};
  final Set<String> _hydratedFromMessages = {};
  final Map<String, String> _persistDesired = {};
  final Set<String> _persistInFlight = {};
  String? _activeSessionId;
  int _loadToken = 0;
  static const String _defaultMode = 'build';

  SessionModeNotifier(this._preferencesService) : super(_defaultMode);

  String _normalizeMode(String mode) {
    final normalized = mode.trim().toLowerCase();
    if (normalized == 'plan' || normalized == 'build') {
      return normalized;
    }
    return _defaultMode;
  }

  void setActiveSession(String? sessionId) {
    _activeSessionId = sessionId;
    if (sessionId == null) {
      if (state != _defaultMode) {
        state = _defaultMode;
      }
      return;
    }
    final cachedMode = _sessionModes[sessionId] ?? _defaultMode;
    if (state != cachedMode) {
      state = cachedMode;
    }
    unawaited(_loadMode(sessionId));
  }

  Future<void> setModeForCurrentSession(String mode) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      final normalized = _normalizeMode(mode);
      if (state != normalized) {
        state = normalized;
      }
      return;
    }
    await setModeForSession(sessionId, mode);
  }

  Future<void> setModeForSession(String sessionId, String mode) async {
    final normalized = _normalizeMode(mode);
    _sessionModes[sessionId] = normalized;
    if (_activeSessionId == sessionId && state != normalized) {
      state = normalized;
    }
    _persistDesired[sessionId] = normalized;
    _schedulePersist(sessionId);
  }

  void resetMessageHydration(String sessionId) {
    _hydratedFromMessages.remove(sessionId);
  }

  Future<void> hydrateFromMessages(
    String sessionId,
    List<MessageWrapper> messages,
  ) async {
    if (_hydratedFromMessages.contains(sessionId)) return;
    _hydratedFromMessages.add(sessionId);
    final mode = _extractModeFromMessages(messages);
    if (mode == null) return;
    await setModeForSession(sessionId, mode);
  }

  String? _extractModeFromMessages(List<MessageWrapper> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final info = messages[i].info;
      if (info is UserMessageInfo) {
        final agent = info.agent;
        if (agent != null && agent.trim().isNotEmpty) {
          return _normalizeMode(agent);
        }
      }
      if (info is AssistantMessageInfo && info.mode.trim().isNotEmpty) {
        return _normalizeMode(info.mode);
      }
    }
    return null;
  }

  void _schedulePersist(String sessionId) {
    if (_persistInFlight.contains(sessionId)) return;
    unawaited(_flushPersist(sessionId));
  }

  Future<void> _flushPersist(String sessionId) async {
    _persistInFlight.add(sessionId);
    try {
      while (true) {
        final mode = _persistDesired.remove(sessionId);
        if (mode == null) break;
        await _preferencesService.saveSessionMode(sessionId, mode);
      }
    } finally {
      _persistInFlight.remove(sessionId);
      if (_persistDesired.containsKey(sessionId)) {
        _schedulePersist(sessionId);
      }
    }
  }

  Future<void> _loadMode(String sessionId) async {
    final token = ++_loadToken;
    final savedMode = await _preferencesService.getSessionMode(sessionId);
    if (token != _loadToken) return;
    if (savedMode == null || savedMode.isEmpty) return;
    final normalized = _normalizeMode(savedMode);
    final currentMode = _sessionModes[sessionId];
    if (currentMode != null && currentMode != normalized) {
      return;
    }
    _sessionModes[sessionId] = normalized;
    if (_activeSessionId == sessionId && state != normalized) {
      state = normalized;
    }
  }
}

final sessionModeProvider =
    StateNotifierProvider<SessionModeNotifier, String>((ref) {
      final notifier = SessionModeNotifier(ref.watch(preferencesServiceProvider));
      ref.listen<Session?>(selectedSessionProvider, (previous, next) {
        final previousId = previous?.id;
        final nextId = next?.id;
        if (previousId == nextId) return;
        notifier.setActiveSession(nextId);
      }, fireImmediately: true);
      return notifier;
    });

class DefaultModelNotifier extends StateNotifier<Map<String, String>?> {
  final PreferencesService _preferencesService;

  DefaultModelNotifier(this._preferencesService) : super(null) {
    _load();
  }

  Future<void> preload() async {
    if (state != null) return;
    await _load();
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

  Future<void> preload(String projectId) async {
    if (state.projectId == projectId && !state.isLoading) return;
    await load(projectId);
  }

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
// App preload
// ---------------------------------------------------------------------------

final appPreloadProvider = FutureProvider<bool>((ref) async {
  final settingsNotifier = ref.read(settingsProvider.notifier);
  await settingsNotifier.ensureLoaded();
  final settings = ref.read(settingsProvider);
  if (!settings.isLoaded) return true;

  ref.read(apiClientProvider);
  ref.read(pathInfoProvider);
  ref.read(authStateProvider);

  var hadError = false;
  Future<void> safe(Future<dynamic> future) async {
    try {
      await future;
    } catch (_) {
      hadError = true;
    }
  }

  final settingsState = ref.read(settingsProvider);
  if (settingsState.isLoaded) {
    final currentUrl = settingsState.serverUrl;
    final preloaded = ref.read(apiClientProvider);
    if (preloaded.baseUrl != currentUrl) {
      preloaded.updateBaseUrl(currentUrl);
    }
  }

  await Future.wait([
    safe(ref.read(healthProvider.future)),
    safe(ref.read(projectsProvider.future)),
    safe(ref.read(defaultModelProvider.notifier).preload()),
    safe(ref.read(accountProfileProvider.future)),
    safe(ref.read(billingStatusProvider.future)),
  ]);

  return hadError;
});

final settingsReloadProvider = FutureProvider<void>((ref) async {
  final notifier = ref.read(settingsProvider.notifier);
  await notifier.reload();
});

// ---------------------------------------------------------------------------
// Favourite Models
// ---------------------------------------------------------------------------

class FavouriteModelsNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  final PreferencesService _preferencesService;

  FavouriteModelsNotifier(this._preferencesService) : super([]) {
    _load();
  }

  Future<void> _load() async {
    final favourites = await _preferencesService.getFavouriteModels();
    state = favourites;
  }

  Future<void> addFavourite(Map<String, dynamic> model) async {
    await _preferencesService.addFavouriteModel(model);
    await _load();
  }

  Future<void> removeFavourite(String providerId, String modelId) async {
    await _preferencesService.removeFavouriteModel(providerId, modelId);
    await _load();
  }

  Future<void> toggleFavourite(Map<String, dynamic> model) async {
    final providerId = model['providerId'] as String;
    final modelId = model['modelId'] as String;
    if (isFavourite(providerId, modelId)) {
      await removeFavourite(providerId, modelId);
    } else {
      await addFavourite(model);
    }
  }

  bool isFavourite(String providerId, String modelId) {
    return state.any(
      (f) => f['providerId'] == providerId && f['modelId'] == modelId,
    );
  }
}

final favouriteModelsProvider =
    StateNotifierProvider<FavouriteModelsNotifier, List<Map<String, dynamic>>>((
      ref,
    ) {
      return FavouriteModelsNotifier(ref.watch(preferencesServiceProvider));
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

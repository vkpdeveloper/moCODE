import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/models.dart' hide HealthInfo, ProviderListResponse;
import '../models/acp_models.dart';
import '../models/app_models.dart' as app_models;
import '../models/cli_device.dart';
import '../models/provider.dart';
import '../models/resource_item.dart';
import '../models/session_control.dart';
import '../config/app_env.dart';

import '../services/api_client.dart';
import '../services/account_api_client.dart';
import '../services/app_logger.dart';
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
import '../services/in_app_update_service.dart';
import '../services/asr_service.dart';
import '../services/lan_discovery_service.dart';

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsState {
  final String serverUrl;
  final String serverHost;
  final int serverPort;
  final String? authToken;
  final String? connectedDeviceName;
  final String? connectedDeviceId;
  final bool isLoaded;
  final bool useNerdFont;

  const SettingsState({
    this.serverUrl = 'http://127.0.0.1:4058',
    this.serverHost = '127.0.0.1',
    this.serverPort = 4058,
    this.authToken,
    this.connectedDeviceName,
    this.connectedDeviceId,
    this.isLoaded = false,
    this.useNerdFont = true,
  });

  bool get hasSelectedDevice =>
      connectedDeviceName != null && serverHost.isNotEmpty && serverPort > 0;

  String? get selectedConnectionKey {
    if (!hasSelectedDevice) {
      return null;
    }
    return connectedDeviceId ?? '$serverHost:$serverPort';
  }

  SettingsState copyWith({
    String? serverUrl,
    String? serverHost,
    int? serverPort,
    Object? authToken = _settingsNoChange,
    Object? connectedDeviceName = _settingsNoChange,
    Object? connectedDeviceId = _settingsNoChange,
    bool? isLoaded,
    bool? useNerdFont,
  }) {
    return SettingsState(
      serverUrl: serverUrl ?? this.serverUrl,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      authToken: identical(authToken, _settingsNoChange)
          ? this.authToken
          : authToken as String?,
      connectedDeviceName: identical(connectedDeviceName, _settingsNoChange)
          ? this.connectedDeviceName
          : connectedDeviceName as String?,
      connectedDeviceId: identical(connectedDeviceId, _settingsNoChange)
          ? this.connectedDeviceId
          : connectedDeviceId as String?,
      isLoaded: isLoaded ?? this.isLoaded,
      useNerdFont: useNerdFont ?? this.useNerdFont,
    );
  }
}

const Object _settingsNoChange = Object();

class SettingsNotifier extends StateNotifier<SettingsState> {
  final PreferencesService _preferencesService;
  Future<void>? _loading;

  SettingsNotifier(this._preferencesService) : super(const SettingsState()) {
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
    await _preferencesService.consumeCliReselectionRequest();
    await _preferencesService.clearSelectedCliDevice();
    final useNerdFont = await _preferencesService.getUseNerdFont();
    AppLogger.instance.info(
      'Settings loaded',
      scope: 'settings',
      data: {'useNerdFont': useNerdFont},
    );
    state = SettingsState(isLoaded: true, useNerdFont: useNerdFont);
  }

  Future<void> selectCliDevice(DiscoveredCliDevice device) async {
    final stored = device.toStored();
    await _preferencesService.savePairedCliDevice(stored);
    await _preferencesService.selectCliDevice(stored);
    AppLogger.instance.info(
      'CLI device selected',
      scope: 'settings',
      data: stored,
    );
    state = state.copyWith(
      serverHost: device.host,
      serverPort: device.port,
      serverUrl: device.baseUrl,
      authToken: device.token,
      connectedDeviceName: device.deviceName,
      connectedDeviceId: device.pairedDeviceId,
      isLoaded: true,
    );
  }

  Future<void> requestDeviceChangeOnNextLaunch() async {
    await _preferencesService.requestCliReselectionOnNextLaunch();
    AppLogger.instance.info(
      'CLI device reselection requested',
      scope: 'settings',
    );
  }

  Future<void> updateNerdFont(bool useNerdFont) async {
    await _preferencesService.setUseNerdFont(useNerdFont);
    state = state.copyWith(useNerdFont: useNerdFont);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    return SettingsNotifier(ref.watch(preferencesServiceProvider));
  },
);

class SelectedAgentState {
  final String? connectionKey;
  final String? agentId;
  final String? agentName;
  final bool isLoaded;

  const SelectedAgentState({
    this.connectionKey,
    this.agentId,
    this.agentName,
    this.isLoaded = false,
  });

  bool get hasSelection => agentId != null && agentId!.isNotEmpty;

  SelectedAgentState copyWith({
    Object? connectionKey = _settingsNoChange,
    Object? agentId = _settingsNoChange,
    Object? agentName = _settingsNoChange,
    bool? isLoaded,
  }) {
    return SelectedAgentState(
      connectionKey: identical(connectionKey, _settingsNoChange)
          ? this.connectionKey
          : connectionKey as String?,
      agentId: identical(agentId, _settingsNoChange)
          ? this.agentId
          : agentId as String?,
      agentName: identical(agentName, _settingsNoChange)
          ? this.agentName
          : agentName as String?,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class SelectedAgentNotifier extends StateNotifier<SelectedAgentState> {
  SelectedAgentNotifier(this._preferencesService)
    : super(const SelectedAgentState());

  final PreferencesService _preferencesService;
  int _loadToken = 0;

  Future<void> loadForConnection(String? connectionKey) async {
    final token = ++_loadToken;
    if (connectionKey == null || connectionKey.isEmpty) {
      state = const SelectedAgentState(isLoaded: true);
      return;
    }

    state = SelectedAgentState(connectionKey: connectionKey, isLoaded: false);
    final selected = await _preferencesService.getSelectedAgent(connectionKey);
    if (token != _loadToken) {
      return;
    }

    state = SelectedAgentState(
      connectionKey: connectionKey,
      agentId: selected?['agentId'] as String?,
      agentName: selected?['agentName'] as String?,
      isLoaded: true,
    );
  }

  Future<void> selectAgent({
    required String connectionKey,
    required app_models.Agent agent,
  }) async {
    await _preferencesService.saveSelectedAgent(
      connectionKey,
      agentId: agent.mode ?? '',
      agentName: agent.name,
    );
    AppLogger.instance.info(
      'Agent selected',
      scope: 'agent',
      data: {
        'connectionKey': connectionKey,
        'agentId': agent.mode,
        'agentName': agent.name,
      },
    );
    state = SelectedAgentState(
      connectionKey: connectionKey,
      agentId: agent.mode,
      agentName: agent.name,
      isLoaded: true,
    );
  }

  Future<void> clearSelection(String? connectionKey) async {
    if (connectionKey != null && connectionKey.isNotEmpty) {
      await _preferencesService.clearSelectedAgent(connectionKey);
    }
    AppLogger.instance.info(
      'Agent selection cleared',
      scope: 'agent',
      data: {'connectionKey': connectionKey},
    );
    state = SelectedAgentState(connectionKey: connectionKey, isLoaded: true);
  }
}

final selectedAgentProvider =
    StateNotifierProvider<SelectedAgentNotifier, SelectedAgentState>((ref) {
      final notifier = SelectedAgentNotifier(
        ref.watch(preferencesServiceProvider),
      );
      ref.listen<SettingsState>(settingsProvider, (previous, next) {
        final previousKey = previous?.selectedConnectionKey;
        final nextKey = next.selectedConnectionKey;
        if (previousKey == nextKey) {
          return;
        }
        unawaited(notifier.loadForConnection(nextKey));
      }, fireImmediately: true);
      return notifier;
    });

// ---------------------------------------------------------------------------
// API Client
// ---------------------------------------------------------------------------

final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsProvider);
  final client = ApiClient(
    baseUrl: settings.serverUrl,
    bearerToken: settings.authToken,
  );
  ref.listen<SettingsState>(settingsProvider, (prev, next) {
    if (prev?.serverUrl != next.serverUrl) {
      client.updateBaseUrl(next.serverUrl);
    }
    if (prev?.authToken != next.authToken) {
      client.updateBearerToken(next.authToken);
    }
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

final asrServiceProvider = Provider<AsrService>((ref) {
  return AsrService(ref.watch(accountApiClientProvider));
});

final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges();
});

final firebaseUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.hasValue ? authState.value : null;
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
  final user = auth.hasValue ? auth.value : null;
  if (user == null) return AccessGateStatus.signedOut;

  final billing = ref.watch(billingStatusProvider);
  if (billing.isLoading) return AccessGateStatus.loading;
  final billingValue = billing.hasValue ? billing.value : null;
  final unlocked = billingValue?['oneTimeUnlocked'] == true;
  return unlocked ? AccessGateStatus.granted : AccessGateStatus.unpaid;
});

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

final appServiceProvider = Provider<AppService>((ref) {
  return AppService(ref.watch(apiClientProvider));
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    ref.watch(apiClientProvider),
    ref.watch(eventServiceProvider),
  );
});

final messageServiceProvider = Provider<MessageService>((ref) {
  return MessageService(
    ref.watch(apiClientProvider),
    ref.watch(eventServiceProvider),
  );
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
  return ProviderService();
});

final eventServiceProvider = Provider<EventService>((ref) {
  final service = EventService(ref.watch(apiClientProvider));
  ref.listen<SettingsState>(settingsProvider, (previous, next) {
    final serverChanged = previous?.serverUrl != next.serverUrl;
    final tokenChanged = previous?.authToken != next.authToken;
    if (serverChanged || tokenChanged) {
      service.resetConnection();
    }
  });
  ref.onDispose(service.dispose);
  return service;
});

class _NormalizedEvent {
  final String type;
  final Map<String, dynamic> payload;

  const _NormalizedEvent({required this.type, required this.payload});
}

Map<String, dynamic>? _asEventObject(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

List<Todo> _todosFromPlanEntry(AcpSessionEntry entry) {
  final payload = _asEventObject(entry.payload);
  final update = _asEventObject(payload?['update']) ?? payload;
  final entries = update?['entries'];
  if (entries is! List) {
    return const <Todo>[];
  }
  return entries
      .whereType<Map<String, dynamic>>()
      .map(
        (item) => Todo(
          id:
              item['id']?.toString() ??
              '${item['content']?.toString() ?? 'todo'}:${item['status']?.toString() ?? 'pending'}',
          content: item['content']?.toString() ?? '',
          status: item['status']?.toString() ?? 'pending',
          priority: item['priority']?.toString() ?? 'normal',
        ),
      )
      .where((todo) => todo.content.trim().isNotEmpty)
      .toList(growable: false);
}

List<FileDiff> _diffsFromEntry(AcpSessionEntry entry) {
  final payload = _asEventObject(entry.payload);
  final update = _asEventObject(payload?['update']) ?? payload;
  final diffs = update?['diff'];
  if (diffs is! List) {
    return const <FileDiff>[];
  }
  return diffs
      .whereType<Map<String, dynamic>>()
      .map(FileDiff.fromJson)
      .toList(growable: false);
}

class GlobalEventCoordinator {
  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Set<String> _sessionIds = const {};
  Timer? _sessionsRefreshTimer;

  GlobalEventCoordinator(this._ref) {
    _subscription = _ref
        .read(eventServiceProvider)
        .subscribe()
        .listen(
          _handleRawEvent,
          onError: (Object error) {
            AppLogger.instance.error(
              'Global event stream error',
              scope: 'events',
              error: error,
            );
          },
        );
  }

  void syncSessionIds(Set<String> sessionIds) {
    final next = sessionIds.where((value) => value.isNotEmpty).toSet();
    if (setEquals(_sessionIds, next)) {
      return;
    }
    _ref.read(eventServiceProvider).setSubscribedSessionIds(next);
    _sessionIds = next;
  }

  void dispose() {
    _sessionsRefreshTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
  }

  _NormalizedEvent? _normalize(Map<String, dynamic> raw) {
    final payloadRaw = raw['payload'];
    final payload = payloadRaw is Map<String, dynamic>
        ? payloadRaw
        : payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : <String, dynamic>{};

    final type = raw['type']?.toString();
    if (type == null || type.isEmpty) return null;

    return _NormalizedEvent(type: type, payload: payload);
  }

  void _onReconnected() {
    _scheduleSessionsRefresh(immediate: true);
    _ref.invalidate(sessionStatusProvider);
    unawaited(_ref.read(sessionModeProvider.notifier).refreshCurrentSession());
    unawaited(_ref.read(sessionControlProvider.notifier).refresh());
    _ref.invalidate(commandsProvider);
    final session = _ref.read(selectedSessionProvider);
    unawaited(_ref.read(messagesProvider.notifier).loadForSession(session));
  }

  void _scheduleSessionsRefresh({bool immediate = false}) {
    _sessionsRefreshTimer?.cancel();
    if (immediate) {
      _ref.invalidate(sessionsProvider);
      _ref.invalidate(projectsProvider);
      return;
    }
    _sessionsRefreshTimer = Timer(const Duration(milliseconds: 180), () {
      _ref.invalidate(sessionsProvider);
      _ref.invalidate(projectsProvider);
    });
  }

  void _handleSessionUpdate(Map<String, dynamic> payload) {
    final sessionId = payload['sessionId']?.toString();
    final entryRaw = payload['entry'];
    if (sessionId == null || sessionId.isEmpty || entryRaw is! Map) {
      return;
    }

    final entry = AcpSessionEntry.fromJson(Map<String, dynamic>.from(entryRaw));
    final selected = _ref.read(selectedSessionProvider);
    if (selected != null && selected.id == sessionId) {
      _ref.read(messagesProvider.notifier).appendEntry(selected, entry);
      if (entry.kind == 'available_commands_update' ||
          entry.kind == 'config_option_update' ||
          entry.kind == 'current_mode_update') {
        unawaited(
          _ref.read(sessionModeProvider.notifier).refreshCurrentSession(),
        );
        unawaited(_ref.read(sessionControlProvider.notifier).refresh());
        _ref.invalidate(commandsProvider);
      }
      if (entry.kind == 'plan') {
        _ref
            .read(todosProvider.notifier)
            .setTodos(sessionId, _todosFromPlanEntry(entry));
      }
      if (entry.kind == 'session_diff_update') {
        _ref
            .read(sessionDiffProvider.notifier)
            .setDiff(sessionId, _diffsFromEntry(entry));
      }
      if (entry.kind == 'session_info_update') {
        final payload = entry.payload;
        final entryPayload = payload is Map
            ? Map<String, dynamic>.from(payload)
            : null;
        final update = entryPayload?['update'];
        final updateObject = update is Map<String, dynamic>
            ? update
            : update is Map
            ? Map<String, dynamic>.from(update)
            : null;
        final nextTitle = updateObject?['title']?.toString();
        if (nextTitle != null && nextTitle.trim().isNotEmpty) {
          _ref.read(selectedSessionProvider.notifier).state = Session(
            id: selected.id,
            slug: selected.slug,
            projectID: selected.projectID,
            agentID: selected.agentID,
            status: selected.status,
            directory: selected.directory,
            parentID: selected.parentID,
            summary: selected.summary,
            share: selected.share,
            title: nextTitle,
            version: selected.version,
            time: selected.time,
            revert: selected.revert,
          );
        }
      }
    }

    _scheduleSessionsRefresh();
  }

  void _handleDaemonWarning(Map<String, dynamic> payload) {
    final error = payload['error']?.toString();
    if (error == null || error.isEmpty) {
      return;
    }
    _ref.read(sessionErrorProvider.notifier).setError(message: error);
  }

  void _handleRawEvent(Map<String, dynamic> raw) {
    final event = _normalize(raw);
    if (event == null) {
      return;
    }
    switch (event.type) {
      case '__reconnected__':
        _onReconnected();
        break;
      case 'session_update':
        _handleSessionUpdate(event.payload);
        break;
      case 'daemon_warning':
        _handleDaemonWarning(event.payload);
        break;
    }
  }
}

final globalEventCoordinatorProvider = Provider<GlobalEventCoordinator>((ref) {
  final coordinator = GlobalEventCoordinator(ref);

  Set<String> computeSessionIds() {
    final sessionIds = <String>{};
    final selectedSession = ref.read(selectedSessionProvider);
    if (selectedSession != null) {
      sessionIds.add(selectedSession.id);
    }
    sessionIds.addAll(ref.read(activeSessionsProvider).keys);
    return sessionIds;
  }

  void sync() {
    coordinator.syncSessionIds(computeSessionIds());
  }

  ref.listen<Session?>(selectedSessionProvider, (_, _) => sync());
  ref.listen<Map<String, String>>(activeSessionsProvider, (_, _) => sync());
  sync();

  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService(
    ref.watch(apiClientProvider),
    ref.watch(eventServiceProvider),
  );
});

final questionServiceProvider = Provider<QuestionService>((ref) {
  return QuestionService(
    ref.watch(apiClientProvider),
    ref.watch(eventServiceProvider),
  );
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

final lanDiscoveryServiceProvider = Provider<LanDiscoveryService>((ref) {
  return LanDiscoveryService(ref.watch(preferencesServiceProvider));
});

final inAppUpdateServiceProvider = Provider<InAppUpdateService>((ref) {
  return InAppUpdateService();
});

final updateAvailableProvider = StateProvider<bool>((ref) => false);

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
  final selectedAgent = ref.watch(selectedAgentProvider);
  final sessionService = ref.watch(sessionServiceProvider);
  return sessionService.listSessions(
    agentID: selectedAgent.agentId,
    projectID: selectedProject?.id,
    directory: selectedProject?.worktree,
  );
});

final selectedSessionProvider = StateProvider<Session?>((ref) => null);

// ---------------------------------------------------------------------------
// Session Status
// ---------------------------------------------------------------------------

class SessionStatusNotifier
    extends StateNotifier<AsyncValue<Map<String, dynamic>>> {
  final SessionService _sessionService;
  String? _directory;

  SessionStatusNotifier(this._sessionService)
    : super(const AsyncValue.loading());

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
      final status = await _sessionService.getSessionStatus(
        directory: directory,
      );
      if (!mounted || directory != _directory) return;
      state = AsyncValue.data(status);
    } catch (e, st) {
      if (!mounted || directory != _directory) return;
      final previous = state.hasValue ? state.value : null;
      if (previous != null) {
        state = AsyncValue.data(previous);
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void upsertStatus(String sessionID, dynamic status) {
    final currentStatus = state.hasValue ? state.value : null;
    final next = Map<String, dynamic>.from(currentStatus ?? const {});
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
    final currentStatus = state.hasValue ? state.value : null;
    final next = Map<String, dynamic>.from(currentStatus ?? const {});
    next[sessionID] = {'type': 'idle'};
    state = AsyncValue.data(next);
  }
}

final sessionStatusProvider =
    StateNotifierProvider<
      SessionStatusNotifier,
      AsyncValue<Map<String, dynamic>>
    >((ref) {
      final notifier = SessionStatusNotifier(ref.watch(sessionServiceProvider));
      ref.listen<Project?>(selectedProjectProvider, (previous, next) {
        unawaited(notifier.loadForDirectory(next?.worktree));
      }, fireImmediately: true);

      final timer = Timer.periodic(const Duration(seconds: 4), (_) {
        unawaited(notifier.refresh());
      });
      ref.onDispose(timer.cancel);
      return notifier;
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
      error: identical(error, _messagesNoChange)
          ? this.error
          : error as String?,
    );
  }
}

const Object _messagesNoChange = Object();

class MessagesNotifier extends StateNotifier<MessagesState> {
  final MessageService _messageService;
  int _loadToken = 0;
  String? _loadedSessionId;
  List<AcpSessionEntry> _entries = const [];

  MessagesNotifier(this._messageService) : super(const MessagesState());

  Future<void> loadForSession(Session? session) async {
    final token = ++_loadToken;
    if (session == null) {
      _loadedSessionId = null;
      _entries = const [];
      state = const MessagesState();
      return;
    }

    state = state.copyWith(isLoading: true, error: null);
    try {
      final snapshot = await _messageService.getSnapshot(session.id);
      if (!mounted || token != _loadToken) return;
      _loadedSessionId = session.id;
      _entries = snapshot.entries;
      state = state.copyWith(
        messages: messageWrappersFromAcpSnapshot(snapshot),
        isLoading: false,
        error: null,
      );
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void appendEntry(Session session, AcpSessionEntry entry) {
    if (_loadedSessionId != session.id) {
      return;
    }
    final existingIndex = _entries.indexWhere((item) => item.id == entry.id);
    if (existingIndex >= 0) {
      _entries = [
        ..._entries.take(existingIndex),
        entry,
        ..._entries.skip(existingIndex + 1),
      ];
    } else {
      _entries = [..._entries, entry]
        ..sort((left, right) => left.seq.compareTo(right.seq));
    }
    state = state.copyWith(
      messages: messageWrappersFromAcpSnapshot(
        AcpSessionSnapshot(session: session, entries: _entries),
      ),
      error: null,
    );
  }
}

final messagesProvider = StateNotifierProvider<MessagesNotifier, MessagesState>(
  (ref) {
    final notifier = MessagesNotifier(ref.watch(messageServiceProvider));
    ref.listen<Session?>(selectedSessionProvider, (previous, next) {
      final previousId = previous?.id;
      final nextId = next?.id;
      if (previousId == nextId) return;
      unawaited(notifier.loadForSession(next));
    }, fireImmediately: true);
    return notifier;
  },
);

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
  final session = ref.watch(selectedSessionProvider);
  if (session == null) {
    return Future.value(const <app_models.Command>[]);
  }
  final sessionService = ref.watch(sessionServiceProvider);
  return sessionService.listCommands(session.id);
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

final selectedModelProvider = StateProvider<Map<String, String>?>(
  (ref) => null,
);

bool _isUsableModelSelection(Map<String, String>? model) {
  if (model == null) {
    return false;
  }
  final providerId = model['providerID']?.trim() ?? '';
  final modelId = model['modelID']?.trim() ?? '';
  if (providerId.isEmpty || modelId.isEmpty) {
    return false;
  }
  return providerId != 'local';
}

class SessionModeNotifier extends StateNotifier<String> {
  final SessionService _sessionService;
  final Map<String, String> _sessionModes = {};
  String? _activeSessionId;
  int _loadToken = 0;
  static const String _defaultMode = 'build';

  SessionModeNotifier(this._sessionService) : super(_defaultMode);

  String _normalizeMode(String mode) {
    final normalized = mode.trim();
    if (normalized.isEmpty) {
      return _defaultMode;
    }
    return normalized;
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
    unawaited(refreshSession(sessionId));
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
    await _sessionService.setSessionMode(sessionId, modeId: normalized);
    applyRemoteMode(sessionId, normalized);
  }

  Future<void> refreshCurrentSession() async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      return;
    }
    await refreshSession(sessionId);
  }

  Future<void> refreshSession(String sessionId) async {
    final token = ++_loadToken;
    try {
      final control = await _sessionService.getSessionControl(sessionId);
      if (token != _loadToken) {
        return;
      }
      final remoteMode = control.currentModeId;
      if (remoteMode == null || remoteMode.trim().isEmpty) {
        return;
      }
      applyRemoteMode(sessionId, remoteMode);
    } catch (_) {
      if (token != _loadToken) {
        return;
      }
    }
  }

  void applyRemoteMode(String sessionId, String mode) {
    final normalized = _normalizeMode(mode);
    _sessionModes[sessionId] = normalized;
    if (_activeSessionId == sessionId && state != normalized) {
      state = normalized;
    }
  }

  void resetMessageHydration(String _) {}

  Future<void> hydrateFromMessages(
    String _,
    List<MessageWrapper> unusedMessages,
  ) async {}
}

class SessionControlState {
  final SessionControl? control;
  final bool isLoading;
  final String? error;

  const SessionControlState({this.control, this.isLoading = false, this.error});

  SessionControlState copyWith({
    SessionControl? control,
    bool? isLoading,
    Object? error = _messagesNoChange,
  }) {
    return SessionControlState(
      control: control ?? this.control,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _messagesNoChange)
          ? this.error
          : error as String?,
    );
  }
}

class SessionControlNotifier extends StateNotifier<SessionControlState> {
  SessionControlNotifier(this._sessionService)
    : super(const SessionControlState());

  final SessionService _sessionService;
  String? _activeSessionId;
  int _loadToken = 0;

  Future<void> loadForSession(Session? session) async {
    final token = ++_loadToken;
    _activeSessionId = session?.id;
    if (session == null) {
      state = const SessionControlState();
      return;
    }

    state = const SessionControlState(isLoading: true);
    try {
      final control = await _sessionService.getSessionControl(session.id);
      if (!mounted || token != _loadToken) {
        return;
      }
      state = SessionControlState(control: control, isLoading: false);
    } catch (e) {
      if (!mounted || token != _loadToken) {
        return;
      }
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      return;
    }
    try {
      final control = await _sessionService.getSessionControl(sessionId);
      if (!mounted || sessionId != _activeSessionId) {
        return;
      }
      state = SessionControlState(control: control, isLoading: false);
    } catch (e) {
      if (!mounted || sessionId != _activeSessionId) {
        return;
      }
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> setConfigOption({
    required String configId,
    bool? boolValue,
    String? valueId,
  }) async {
    final sessionId = _activeSessionId;
    if (sessionId == null) {
      return;
    }
    final control = await _sessionService.setSessionConfigOption(
      sessionId,
      configId: configId,
      boolValue: boolValue,
      valueId: valueId,
    );
    if (!mounted || sessionId != _activeSessionId) {
      return;
    }
    state = SessionControlState(control: control, isLoading: false);
  }
}

final sessionModeProvider = StateNotifierProvider<SessionModeNotifier, String>((
  ref,
) {
  final notifier = SessionModeNotifier(ref.watch(sessionServiceProvider));
  ref.listen<Session?>(selectedSessionProvider, (previous, next) {
    final previousId = previous?.id;
    final nextId = next?.id;
    if (previousId == nextId) return;
    notifier.setActiveSession(nextId);
  }, fireImmediately: true);
  return notifier;
});

final sessionControlProvider =
    StateNotifierProvider<SessionControlNotifier, SessionControlState>((ref) {
      final notifier = SessionControlNotifier(
        ref.watch(sessionServiceProvider),
      );
      ref.listen<Session?>(selectedSessionProvider, (previous, next) {
        final previousId = previous?.id;
        final nextId = next?.id;
        if (previousId == nextId) return;
        unawaited(notifier.loadForSession(next));
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
  if (_isUsableModelSelection(selected)) return selected;

  // 2. Project default model (persisted)
  final projectModel = ref.watch(projectModelProvider).model;
  if (_isUsableModelSelection(projectModel)) return projectModel;

  // 3. User default model (persisted)
  final defaultModel = ref.watch(defaultModelProvider);
  if (_isUsableModelSelection(defaultModel)) return defaultModel;

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

final fileSearchProvider = FutureProvider.family<List<ResourceItem>, String>((
  ref,
  query,
) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.findResources(query: query, directory: project?.worktree);
});

// ---------------------------------------------------------------------------
// Agents
// ---------------------------------------------------------------------------

final agentsProvider = FutureProvider<List<app_models.Agent>>((ref) {
  final project = ref.watch(selectedProjectProvider);
  final appService = ref.watch(appServiceProvider);
  return appService.listAgents(directory: project?.worktree);
});

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/message.dart';
import '../models/permission_request.dart';
import '../models/question_request.dart';
import '../models/session.dart';
import '../models/todo.dart';
import '../models/file_diff.dart';
import '../models/part.dart';
import '../models/command_run.dart';
import '../models/pty.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_parts.dart';
import '../widgets/session_busy_indicator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String? sessionId;

  const ChatScreen({super.key, this.sessionId});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  ProviderSubscription<Session?>? _sessionSub;
  ProviderSubscription<MessagesState>? _messagesSub;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _statusSub;
  bool _isBusy = false;
  bool _permissionDialogVisible = false;
  bool _questionDialogVisible = false;
  List<MessageWrapper> _cachedMessages = const [];
  String? _cachedSessionId;
  bool _hasLoadedMessages = false;
  String? _modelSyncSessionId;
  bool _didSyncModelFromMessages = false;
  String? _modeSyncSessionId;
  bool _didSyncModeFromMessages = false;
  bool _isSidebarOpen = false;
  bool _showScrollToBottom = false;
  bool _isPinnedToBottom = true;
  bool _isUndoRedoInFlight = false;
  bool _didInitialScroll = false;
  final GlobalKey _chatInputKey = GlobalKey();
  final List<MessageWrapper> _optimisticMessages = [];
  int? _optimisticBaseCount;
  String? _optimisticMessageId;
  bool _isSyncing = false;
  bool _syncMessagesReady = false;
  bool _syncStatusReady = false;
  Timer? _syncTimeout;
  int _syncToken = 0;
  int _bootstrapToken = 0;
  final Set<String> _bootstrappedSessions = {};
  String? _todosSessionId;
  String? _diffSessionId;
  String? _vcsSessionId;
  StreamSubscription? _ptyStreamSub;
  WebSocketChannel? _ptyChannel;
  String? _activeRunId;

  AssistantMessageInfo _commandMessageInfo(
    CommandOutputPart part,
    String sessionId,
  ) {
    return AssistantMessageInfo(
      id: 'command_${part.id}',
      sessionID: sessionId,
      time: MessageTime(
        created: part.time?.start ?? DateTime.now().millisecondsSinceEpoch,
        completed: part.time?.end ?? part.time?.start,
      ),
      modelID: 'command',
      providerID: 'local',
      mode: 'build',
      cost: 0.0,
      tokens: MessageTokens(
        input: 0,
        output: 0,
        reasoning: 0,
        cache: MessageCacheTokens(read: 0, write: 0),
      ),
    );
  }

  MessageWrapper? _buildCommandMessage(List<Part> parts, Session? session) {
    if (parts.isEmpty || parts.first is! CommandOutputPart) return null;
    final part = parts.first as CommandOutputPart;
    final sessionId = session?.id ?? part.sessionID;
    return MessageWrapper(
      info: _commandMessageInfo(part, sessionId),
      parts: parts,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToEvents();
    _listenToSessionChanges();
    _listenToMessageUpdates();
    _listenToStatusUpdates();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetId = widget.sessionId;
      final current = ref.read(selectedSessionProvider);
      if (targetId != null && targetId.isNotEmpty) {
        if (current == null || current.id != targetId) {
          _ensureSelectedSession(targetId);
          return;
        }
      }
      if (current != null) {
        _handleSessionSelected(current);
      }
    });
  }

  @override
  void dispose() {
    _syncTimeout?.cancel();
    _eventSub?.cancel();
    _sessionSub?.close();
    _messagesSub?.close();
    _statusSub?.close();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _ptyStreamSub?.cancel();
    _ptyChannel?.sink.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSync();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isNearBottom = _isNearBottom();
    final shouldShow = !isNearBottom;
    var nextPinned = _isPinnedToBottom;
    if (isNearBottom && !_isPinnedToBottom) {
      nextPinned = true;
    } else if (!isNearBottom && _isPinnedToBottom) {
      nextPinned = false;
    }
    if (_showScrollToBottom != shouldShow || nextPinned != _isPinnedToBottom) {
      setState(() {
        _showScrollToBottom = shouldShow;
        _isPinnedToBottom = nextPinned;
      });
    }
  }

  void _subscribeToEvents() {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;

    final eventService = ref.read(eventServiceProvider);
    _eventSub = eventService.subscribe(directory: project.worktree).listen((
      event,
    ) {
      try {
        final type = event['type'] as String? ?? '';

        // SSE reconnected — full sync to catch up on missed events
        if (type == '__reconnected__') {
          final session = ref.read(selectedSessionProvider);
          if (session != null) {
            _refreshAfterReconnect(session);
          }
          return;
        }

        if (type == 'permission.asked') {
          final props = event['properties'];
          if (props is Map<String, dynamic>) {
            _handlePermissionAsked(props);
          }
        } else if (type == 'permission.updated' ||
            type == 'permission.replied') {
          _handlePermissionUpdated(event['properties']);
        } else if (type == 'question.asked') {
          final props = event['properties'];
          if (props is Map<String, dynamic>) {
            _handleQuestionAsked(props);
          }
        } else if (type == 'question.replied' || type == 'question.rejected') {
          _handleQuestionUpdated(event['properties']);
        } else if (type == 'session.status') {
          _handleSessionStatusEvent(event['properties']);
        } else if (type == 'session.idle') {
          _handleSessionIdleEvent(event['properties']);
        } else if (type == 'session.deleted') {
          _handleSessionDeleted(event['properties']);
        } else if (type == 'tui.prompt.append') {
          _handlePromptAppend(event['properties']);
        } else if (type == 'tui.command.execute') {
          _handleCommandExecuted(event['properties']);
        } else if (type == 'command.executed') {
          _handleCommandExecuted(event['properties']);
        } else if (type == 'tui.toast.show') {
          _handleToastEvent(event['properties']);
        }
      } catch (e) {
        debugPrint('[ChatScreen] Event error: $e\nRaw event: $event');
      }
    });
  }

  void _listenToSessionChanges() {
    _sessionSub = ref.listenManual<Session?>(selectedSessionProvider, (
      prev,
      next,
    ) {
      if (next != null && (prev == null || prev.id != next.id)) {
        _handleSessionSelected(next);
      } else if (next == null) {
        _bootstrappedSessions.clear();
      }
    });
  }

  Future<void> _ensureSelectedSession(String sessionId) async {
    final project = ref.read(selectedProjectProvider);
    try {
      final session = await ref
          .read(sessionServiceProvider)
          .getSession(sessionId, directory: project?.worktree);
      ref.read(selectedSessionProvider.notifier).state = session;
      await _refreshAfterReconnect(session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load session: $e')));
    }
  }

  void _handleSessionSelected(Session session) {
    _resetSessionState(session.id);
    _bootstrappedSessions.remove(session.id);
    _scheduleSessionBootstrap(session);
  }

  Future<void> _refreshAfterReconnect(Session session) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await ref.read(messagesProvider.notifier).loadForSession(session);
    await _loadTodos(session, force: true);
    await _loadSessionDiff(session, force: true);
    await _loadVcsBranch(session, force: true);
  }

  void _scheduleSessionBootstrap(Session session) {
    if (_bootstrappedSessions.contains(session.id)) return;
    _bootstrappedSessions.add(session.id);
    final token = ++_bootstrapToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 120), () async {
        if (!mounted || token != _bootstrapToken) return;
        await _bootstrapSession(session);
      });
    });
  }

  Future<void> _bootstrapSession(Session session) async {
    _startSync();
    ref.read(todosProvider.notifier).clear();
    ref.read(sessionErrorProvider.notifier).clear();
    ref.read(ptyProvider.notifier).clear();
    ref.read(commandRunsProvider.notifier).clear();
    ref.read(activeCommandRunProvider.notifier).state = null;
    ref.read(sessionDiffProvider.notifier).clear();
    ref.read(vcsBranchProvider.notifier).state = null;
    await _loadProjectModel(session.projectID, session.id);
    await _loadSessionModel(session.id);
    unawaited(_loadPendingPermissions());
    unawaited(_loadPendingQuestions());
    unawaited(_loadTodos(session));
    unawaited(_loadSessionDiff(session));
    unawaited(_loadVcsBranch(session));
  }

  void _markSessionActive() {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (!_isBusy) return;
    ref
        .read(activeSessionsProvider.notifier)
        .markActive(session.id, session.directory);
  }

  void _releaseActiveSession(String sessionId) {
    ref.read(activeSessionsProvider.notifier).clearActive(sessionId);
  }

  void _listenToStatusUpdates() {
    _statusSub = ref.listenManual<AsyncValue<Map<String, dynamic>>>(
      sessionStatusProvider,
      (prev, next) {
        if (!mounted) return;
        if (_isSyncing) {
          _syncStatusReady = true;
          _completeSyncIfReady();
        }
        final session = ref.read(selectedSessionProvider);
        if (session == null) return;
        final statusMap = next.valueOrNull;
        if (statusMap == null) return;
        final isBusy = _isBusyStatus(statusMap[session.id], fallback: false);
        if (mounted && _isBusy != isBusy) {
          setState(() {
            _isBusy = isBusy;
          });
        }
        if (!isBusy) {
          _releaseActiveSession(session.id);
        }
      },
    );
  }

  String? _statusType(dynamic info) {
    if (info is Map<String, dynamic>) {
      return info['type']?.toString();
    }
    if (info is String) return info;
    return info?.toString();
  }

  bool _isBusyStatus(dynamic info, {required bool fallback}) {
    final type = _statusType(info);
    if (type == null || type.isEmpty) return fallback;
    return type != 'idle';
  }

  void _handleSessionStatusEvent(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    final sessionID = props['sessionID']?.toString();
    if (sessionID == null || sessionID != session.id) return;
    final status = props['status'];
    ref.read(sessionStatusProvider.notifier).upsertStatus(sessionID, status);
    final isBusy = _isBusyStatus(status, fallback: true);
    if (mounted && _isBusy != isBusy) {
      setState(() => _isBusy = isBusy);
    }
    if (!isBusy) {
      _releaseActiveSession(sessionID);
    }
  }

  void _handleSessionIdleEvent(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    final sessionID = props['sessionID']?.toString();
    if (sessionID == null || sessionID != session.id) return;
    ref.read(sessionStatusProvider.notifier).markIdle(sessionID);
    if (mounted && _isBusy) {
      setState(() => _isBusy = false);
    }
    _releaseActiveSession(sessionID);
  }

  void _listenToMessageUpdates() {
    _messagesSub = ref.listenManual<MessagesState>(
      messagesProvider,
      (MessagesState? prev, MessagesState next) {
        final session = ref.read(selectedSessionProvider);
        final nextMessages = next.messages;
        if (session != null) {
          _updateCachedMessages(session.id, nextMessages);
          _syncSelectedModelFromMessages(session, nextMessages);
          _syncSessionModeFromMessages(session, nextMessages);
        }

        if (_isSyncing && !next.isLoading) {
          _syncMessagesReady = true;
          _completeSyncIfReady();
        }

        final prevLength = prev?.messages.length ?? 0;
        final nextLength = next.messages.length;
        if (nextLength > prevLength) {
          _scrollToBottom();
        } else if (_isPinnedToBottom) {
          _scrollToBottom();
        }
      },
    );
  }

  bool _isCurrentSessionEvent(dynamic props) {
    if (props is! Map<String, dynamic>) return false;
    final sessionId = props['sessionID']?.toString();
    final session = ref.read(selectedSessionProvider);
    if (session == null || sessionId == null) return false;
    return sessionId == session.id;
  }

  void _handleTodoUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    final sessionId = props['sessionID']?.toString();
    if (sessionId != session.id) return;
    final todosRaw = props['todos'];
    if (todosRaw is! List) return;
    final todos = todosRaw
        .whereType<Map<String, dynamic>>()
        .map((item) => Todo.fromJson(item))
        .toList();
    ref.read(todosProvider.notifier).setTodos(session.id, todos);
  }

  void _handleBranchUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final branch = props['branch']?.toString();
    ref.read(vcsBranchProvider.notifier).state = branch;
  }

  void _handlePromptAppend(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final text = props['text']?.toString();
    if (text == null || text.isEmpty) return;
    if (!mounted) return;
    ChatInput.appendText(context, text);
  }

  void _handleCommandExecuted(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final name = props['name']?.toString() ?? props['command']?.toString();
    if (name == null || name.isEmpty) return;
    final args = props['arguments']?.toString();
    if (mounted) {
      final label = args != null && args.isNotEmpty
          ? 'Command executed: $name $args'
          : 'Command executed: $name';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(label)));
    }
  }

  void _restoreDraft(String text, List<Map<String, dynamic>>? fileParts) {
    if (!mounted) return;
    ChatInput.restoreDraft(
      _chatInputKey.currentContext ?? context,
      text,
      fileParts ?? const <Map<String, dynamic>>[],
    );
  }

  void _handleToastEvent(dynamic props) {
    if (!mounted) return;
    if (props is! Map<String, dynamic>) return;
    final message = props['message']?.toString();
    if (message == null || message.isEmpty) return;
    final title = props['title']?.toString();
    final variant = props['variant']?.toString() ?? 'info';
    final durationMs = (props['duration'] as num?)?.toInt();
    final color = _toastColor(variant);
    final snackText = title != null && title.isNotEmpty
        ? '$title: $message'
        : message;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(snackText),
        backgroundColor: color,
        duration: Duration(milliseconds: durationMs ?? 2800),
      ),
    );
  }

  void _startSync() {
    if (!mounted) return;
    _syncToken++;
    final token = _syncToken;
    _syncTimeout?.cancel();
    setState(() {
      _isSyncing = true;
      _syncMessagesReady = false;
      _syncStatusReady = false;
    });
    final session = ref.read(selectedSessionProvider);
    unawaited(ref.read(messagesProvider.notifier).loadForSession(session));
    ref.invalidate(sessionStatusProvider);
    _syncTimeout = Timer(const Duration(seconds: 8), () {
      if (!mounted || token != _syncToken) return;
      setState(() {
        _isSyncing = false;
        _syncStatusReady = false;
        _syncMessagesReady = false;
      });
    });
  }

  void _completeSyncIfReady() {
    if (!_isSyncing) return;
    if (!_syncMessagesReady || !_syncStatusReady) return;
    _syncTimeout?.cancel();
    setState(() {
      _isSyncing = false;
      _syncStatusReady = false;
      _syncMessagesReady = false;
    });
  }

  void _handlePtyCreated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final info = props['info'];
    if (info is! Map<String, dynamic>) return;
    final pty = PtyInfo.fromJson(info);
    ref.read(ptyProvider.notifier).upsert(pty);
  }

  void _handlePtyUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final info = props['info'];
    if (info is! Map<String, dynamic>) return;
    final pty = PtyInfo.fromJson(info);
    ref.read(ptyProvider.notifier).upsert(pty);
    final runId = _activeRunId;
    if (runId != null && pty.id == runId) {
      ref
          .read(commandRunsProvider.notifier)
          .updateStatus(runId, status: pty.status, exitCode: pty.exitCode);
    }
  }

  void _handlePtyExited(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final id = props['id']?.toString();
    if (id == null || id.isEmpty) return;
    final exitCode = (props['exitCode'] as num?)?.toInt() ?? 0;
    ref.read(ptyProvider.notifier).updateExit(id, exitCode);
    ref
        .read(commandRunsProvider.notifier)
        .updateStatus(
          id,
          status: 'exited',
          exitCode: exitCode,
          completedAt: DateTime.now().millisecondsSinceEpoch,
        );
  }

  void _handlePtyDeleted(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final id = props['id']?.toString();
    if (id == null || id.isEmpty) return;
    ref.read(ptyProvider.notifier).remove(id);
    if (_activeRunId == id) {
      ref.read(activeCommandRunProvider.notifier).state = null;
      _activeRunId = null;
    }
  }

  void _handleSessionError(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final sessionId = props['sessionID']?.toString();
    final error = props['error'];
    String? message;
    String? name;
    if (error is Map<String, dynamic>) {
      name = error['name']?.toString();
      final data = error['data'];
      if (data is Map<String, dynamic>) {
        message = data['message']?.toString();
      }
    }
    ref
        .read(sessionErrorProvider.notifier)
        .setError(sessionID: sessionId, message: message, name: name);
    if (mounted) {
      final display = message ?? name ?? 'Session error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(display), backgroundColor: AppTheme.error),
      );
    }
  }

  void _handleSessionDiff(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final diffsRaw = props['diff'];
    if (diffsRaw is! List) return;
    final diffs = diffsRaw
        .whereType<Map<String, dynamic>>()
        .map((item) => FileDiff.fromJson(item))
        .toList();
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    ref.read(sessionDiffProvider.notifier).setDiff(session.id, diffs);
  }

  void _handleSessionDeleted(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final info = props['info'];
    if (info is! Map<String, dynamic>) return;
    final deletedId = info['id']?.toString();
    if (deletedId == null || deletedId.isEmpty) return;
    _releaseActiveSession(deletedId);
    final session = ref.read(selectedSessionProvider);
    if (session != null && session.id == deletedId) {
      ref.read(selectedSessionProvider.notifier).state = null;
      if (mounted) {
        context.go('/sessions');
      }
    }
  }

  Color _toastColor(String variant) {
    return switch (variant) {
      'success' => AppTheme.success,
      'warning' => AppTheme.warning,
      'error' => AppTheme.error,
      _ => AppTheme.info,
    };
  }

  void _resetSessionState(String sessionId) {
    if (!mounted) return;
    setState(() {
      _cachedSessionId = sessionId;
      _cachedMessages = const [];
      _isBusy = false;
      _optimisticMessages.clear();
      _optimisticBaseCount = null;
      _optimisticMessageId = null;
      _hasLoadedMessages = false;
      _permissionDialogVisible = false;
      _questionDialogVisible = false;
      _showScrollToBottom = false;
      _isPinnedToBottom = true;
    });
    _todosSessionId = null;
    _diffSessionId = null;
    _vcsSessionId = null;
    _modelSyncSessionId = sessionId;
    _didSyncModelFromMessages = false;
    _modeSyncSessionId = sessionId;
    _didSyncModeFromMessages = false;
    _didInitialScroll = false;
    _activeRunId = null;
    _ptyStreamSub?.cancel();
    _ptyStreamSub = null;
    _ptyChannel?.sink.close();
    _ptyChannel = null;
    ref.read(commandRunsProvider.notifier).clear();
  }

  Future<void> _loadPendingPermissions() async {
    final project = ref.read(selectedProjectProvider);
    final session = ref.read(selectedSessionProvider);
    if (project == null || session == null) return;
    if (_permissionDialogVisible) return;
    try {
      final permissionService = ref.read(permissionServiceProvider);
      final pending = await permissionService.listPending(
        directory: project.worktree,
      );
      if (!mounted || pending.isEmpty) return;
      final matches = pending
          .where((request) => request.sessionID == session.id)
          .toList();
      if (matches.isEmpty) return;
      await _showPermissionDialog(matches.first);
    } catch (_) {
      // ignore permission polling failures
    }
  }

  Future<void> _loadPendingQuestions() async {
    final project = ref.read(selectedProjectProvider);
    final session = ref.read(selectedSessionProvider);
    if (project == null || session == null) return;
    if (_questionDialogVisible) return;
    try {
      final questionService = ref.read(questionServiceProvider);
      final pending = await questionService.listPending(
        directory: project.worktree,
      );
      if (!mounted || pending.isEmpty) return;
      final matches = pending
          .where((request) => request.sessionID == session.id)
          .toList();
      if (matches.isEmpty) return;
      await _showQuestionDialog(matches.first);
    } catch (_) {
      // ignore question polling failures
    }
  }

  void _handlePermissionAsked(Map<String, dynamic> props) {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_permissionDialogVisible) return;
    if (props['sessionID'] != session.id) return;
    _showPermissionDialog(PermissionRequest.fromJson(props));
  }

  void _handlePermissionUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (props['sessionID'] != session.id) return;
    _loadPendingPermissions();
  }

  void _handleQuestionAsked(Map<String, dynamic> props) {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_questionDialogVisible) return;
    if (props['sessionID'] != session.id) return;
    _showQuestionDialog(QuestionRequest.fromJson(props));
  }

  void _handleQuestionUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (props['sessionID'] != session.id) return;
    _loadPendingQuestions();
  }

  String _formatPermissionTitle(PermissionRequest request) {
    final permission = request.permission.trim();
    if (permission.isEmpty) return 'Permission requested';
    final parts = permission.split('.');
    if (parts.isEmpty) return 'Permission requested';
    final label = parts.last.replaceAll('_', ' ');
    return 'Allow ${label.toUpperCase()}?';
  }

  String _buildPermissionDescription(PermissionRequest request) {
    final buffer = StringBuffer();
    if (request.patterns.isNotEmpty) {
      buffer.write('Patterns: ${request.patterns.join(', ')}');
    }
    if (request.always.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write('Always: ${request.always.join(', ')}');
    }
    return buffer.isEmpty
        ? 'Assistant needs your approval.'
        : buffer.toString();
  }

  Future<void> _respondToPermission(
    PermissionRequest request,
    String reply,
  ) async {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;
    try {
      final permissionService = ref.read(permissionServiceProvider);
      await permissionService.reply(
        request.id,
        reply: reply,
        directory: project.worktree,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Permission failed: $e')));
      }
    }
  }

  Future<void> _respondToQuestion(
    QuestionRequest request,
    List<List<String>> answers,
  ) async {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;
    try {
      final questionService = ref.read(questionServiceProvider);
      await questionService.reply(
        request.id,
        answers: answers,
        directory: project.worktree,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Question reply failed: $e')));
      }
    }
  }

  Future<void> _rejectQuestion(QuestionRequest request) async {
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;
    try {
      final questionService = ref.read(questionServiceProvider);
      await questionService.reject(request.id, directory: project.worktree);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Question reject failed: $e')));
      }
    }
  }

  Future<void> _showQuestionDialog(QuestionRequest request) async {
    if (!mounted) return;
    _questionDialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _QuestionDialog(
          request: request,
          onSubmit: (answers) async {
            Navigator.of(context).pop();
            await _respondToQuestion(request, answers);
          },
          onReject: () async {
            Navigator.of(context).pop();
            await _rejectQuestion(request);
          },
        );
      },
    );
    if (mounted) {
      setState(() {
        _questionDialogVisible = false;
      });
      _loadPendingQuestions();
    }
  }

  Future<void> _showPermissionDialog(PermissionRequest request) async {
    if (!mounted) return;
    _permissionDialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatPermissionTitle(request),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _buildPermissionDescription(request),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _respondToPermission(request, 'reject');
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                        ),
                        child: const Text(
                          'DENY',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _respondToPermission(request, 'once');
                        },
                        child: const Text(
                          'ONCE',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _respondToPermission(request, 'always');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: AppTheme.textPrimary,
                        ),
                        child: const Text(
                          'ALWAYS',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (mounted) {
      setState(() {
        _permissionDialogVisible = false;
      });
      _loadPendingPermissions();
    }
  }

  void _updateCachedMessages(String sessionId, List<MessageWrapper> messages) {
    if (!mounted) return;
    final shouldUpdate =
        _cachedSessionId != sessionId || !identical(_cachedMessages, messages);
    if (shouldUpdate || !_hasLoadedMessages) {
      setState(() {
        _cachedSessionId = sessionId;
        _cachedMessages = messages;
        if (_optimisticBaseCount != null &&
            _optimisticMessageId != null &&
            messages.length > _optimisticBaseCount!) {
          _optimisticMessages.removeWhere(
            (msg) => msg.info.id == _optimisticMessageId,
          );
          _optimisticBaseCount = null;
          _optimisticMessageId = null;
        }
        _hasLoadedMessages = true;
      });
      if (!_didInitialScroll && messages.isNotEmpty) {
        _didInitialScroll = true;
        _scrollToBottom(animated: false, force: true);
      }
    }
  }

  void _syncSelectedModelFromMessages(
    Session session,
    List<MessageWrapper> messages,
  ) {
    if (_modelSyncSessionId != session.id) {
      _modelSyncSessionId = session.id;
      _didSyncModelFromMessages = false;
    }
    if (_didSyncModelFromMessages || messages.isEmpty) return;

    String? providerId;
    String? modelId;

    for (var i = messages.length - 1; i >= 0; i--) {
      final info = messages[i].info;
      if (info is AssistantMessageInfo) {
        if (info.providerID.isNotEmpty && info.modelID.isNotEmpty) {
          providerId = info.providerID;
          modelId = info.modelID;
          break;
        }
      } else if (info is UserMessageInfo) {
        final model = info.model;
        if (model != null && model.providerID.isNotEmpty) {
          providerId = model.providerID;
          modelId = model.modelID;
          break;
        }
      }
    }

    if (providerId == null || modelId == null) return;

    final current = ref.read(selectedModelProvider);
    if (current == null ||
        current['providerID'] != providerId ||
        current['modelID'] != modelId) {
      ref.read(selectedModelProvider.notifier).state = {
        'providerID': providerId,
        'modelID': modelId,
      };
      ref
          .read(preferencesServiceProvider)
          .saveSessionModel(session.id, providerId, modelId);
    }
    _didSyncModelFromMessages = true;
  }

  void _syncSessionModeFromMessages(
    Session session,
    List<MessageWrapper> messages,
  ) {
    if (_modeSyncSessionId != session.id) {
      _modeSyncSessionId = session.id;
      _didSyncModeFromMessages = false;
    }
    if (_didSyncModeFromMessages || messages.isEmpty) return;

    String? mode;

    for (var i = messages.length - 1; i >= 0; i--) {
      final info = messages[i].info;
      if (info is UserMessageInfo) {
        final agent = info.agent?.trim();
        if (agent != null && agent.isNotEmpty) {
          mode = agent;
          break;
        }
      }
    }

    if (mode == null) return;

    final current = ref.read(sessionModeProvider);
    if (current != mode) {
      unawaited(
        ref.read(sessionModeProvider.notifier).setModeForCurrentSession(mode),
      );
    }
    _didSyncModeFromMessages = true;
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 120;
  }

  void _scrollToBottom({bool animated = true, bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (!force && !_isPinnedToBottom) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(maxExtent);
      }
    });
  }

  String _optimisticId() {
    return 'optimistic_${DateTime.now().microsecondsSinceEpoch}';
  }

  MessageWrapper _buildOptimisticMessage({
    required String sessionId,
    required String messageId,
    required String text,
    required List<Map<String, dynamic>>? fileParts,
    required Map<String, dynamic> model,
    required String mode,
  }) {
    final created = DateTime.now().millisecondsSinceEpoch;
    final info = UserMessageInfo(
      id: messageId,
      sessionID: sessionId,
      time: MessageTime(created: created, completed: created),
      agent: mode,
      model: MessageModel(
        providerID: model['providerID']?.toString() ?? '',
        modelID: model['modelID']?.toString() ?? '',
      ),
    );

    final parts = <Part>[];

    if (fileParts != null) {
      for (final part in fileParts) {
        parts.add(
          FilePart(
            id: _optimisticId(),
            sessionID: sessionId,
            messageID: messageId,
            mime: part['mime']?.toString() ?? 'text/plain',
            filename: part['filename']?.toString(),
            url: part['url']?.toString() ?? '',
            source: part['source'] is Map<String, dynamic>
                ? Map<String, dynamic>.from(part['source'] as Map)
                : null,
          ),
        );
      }
    }

    if (text.isNotEmpty) {
      parts.add(
        TextPart(
          id: _optimisticId(),
          sessionID: sessionId,
          messageID: messageId,
          text: text,
          synthetic: true,
        ),
      );
    }

    return MessageWrapper(info: info, parts: parts);
  }

  Widget _buildMessagesPanel({
    required List<MessageWrapper> displayMessages,
    required MessagesState messagesState,
    required bool isInitialLoading,
    required String mode,
    List<Part> extraParts = const [],
  }) {
    final session = ref.watch(selectedSessionProvider);
    final statusAsync = ref.watch(sessionStatusProvider);
    final isSessionBusy = statusAsync.maybeWhen(
      data: (status) {
        if (session == null) return false;
        final info = status[session.id];
        if (info is Map<String, dynamic>) {
          return info['type'] == 'busy' || info['type'] == 'retry';
        }
        if (info is String) {
          return info == 'busy' || info == 'retry';
        }
        return false;
      },
      orElse: () => false,
    );

    final busyLabel = () {
      if (session == null) return 'Session busy';
      final info = statusAsync.valueOrNull?[session.id];
      if (info is Map<String, dynamic>) {
        final message = info['message']?.toString();
        final attempt = info['attempt'];
        if (message != null && message.isNotEmpty) {
          return message;
        }
        if (attempt != null) {
          return 'Retrying (attempt $attempt)';
        }
      }
      return 'Session busy';
    }();

    final hasExtraParts = extraParts.isNotEmpty;

    if (messagesState.error != null &&
        displayMessages.isEmpty &&
        !hasExtraParts) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error: ${messagesState.error}',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                final session = ref.read(selectedSessionProvider);
                unawaited(
                  ref.read(messagesProvider.notifier).loadForSession(session),
                );
              },
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    if (displayMessages.isEmpty && !hasExtraParts) {
      if (isInitialLoading && !_isBusy) {
        return const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }

      if (_isBusy || isSessionBusy) {
        return Column(
          children: [
            SessionBusyIndicator(label: busyLabel),
            const Spacer(),
          ],
        );
      }

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
              ),
              child: Icon(Icons.terminal, size: 32, color: AppTheme.accent),
            ),
            const SizedBox(height: 16),
            const Text(
              'Start a conversation',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Mode: ${mode.toUpperCase()}',
              style: TextStyle(
                color: mode == 'plan' ? AppTheme.info : AppTheme.accent,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    final items = List<MessageWrapper>.from(displayMessages);
    if (hasExtraParts) {
      final commandMessage = _buildCommandMessage(extraParts, session);
      if (commandMessage != null) {
        final commandTime = _messageCreatedAt(commandMessage);
        final insertIndex = items.indexWhere(
          (msg) => _messageCreatedAt(msg) > commandTime,
        );
        if (insertIndex == -1) {
          items.add(commandMessage);
        } else {
          items.insert(insertIndex, commandMessage);
        }
      }
    }

    final listWidget = ListView.builder(
      controller: _scrollController,
      cacheExtent: 800,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final msg = items[index];
        return RepaintBoundary(
          child: KeyedSubtree(
            key: ValueKey(msg.info.id),
            child: _buildMessage(msg),
          ),
        );
      },
    );

    Widget listWithButton = Stack(
      children: [
        listWidget,
        if (_showScrollToBottom)
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: AppTheme.surface,
              shape: const CircleBorder(
                side: BorderSide(color: AppTheme.border),
              ),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isPinnedToBottom = true;
                    _showScrollToBottom = false;
                  });
                  _scrollToBottom(force: true);
                },
                customBorder: const CircleBorder(),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return listWithButton;
  }

  int _messageCreatedAt(MessageWrapper msg) {
    final info = msg.info;
    if (info is UserMessageInfo) return info.time.created;
    if (info is AssistantMessageInfo) return info.time.created;
    return 0;
  }

  Widget _buildSidebar({
    required SessionErrorState errorState,
    required String? activeRunId,
    required Map<String, CommandRun> commandRuns,
  }) {
    final tabs = const [
      Tab(text: 'TERMINAL'),
    ];

    return Container(
      width: 280,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          if (errorState.message != null || errorState.name != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.15),
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.error.withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Text(
                errorState.message ?? errorState.name ?? 'Session error',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          Expanded(
            child: DefaultTabController(
              length: tabs.length,
              child: Column(
                children: [
                  TabBar(
                    tabs: tabs,
                    labelColor: AppTheme.textPrimary,
                    unselectedLabelColor: AppTheme.textTertiary,
                    indicatorColor: AppTheme.accent,
                    labelStyle: const TextStyle(fontSize: 10, letterSpacing: 1),
                  ),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _buildTerminalTab(
                          activeRunId: activeRunId,
                          runs: commandRuns,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarToggle() {
    return IconButton(
      icon: Icon(
        _isSidebarOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
        size: 20,
      ),
      onPressed: () {
        setState(() => _isSidebarOpen = !_isSidebarOpen);
      },
      tooltip: 'Sidebar',
    );
  }

  Widget _buildTerminalTab({
    required String? activeRunId,
    required Map<String, CommandRun> runs,
  }) {
    if (activeRunId == null) {
      return const Center(
        child: Text(
          'No running commands',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    final run = runs[activeRunId];
    if (run == null) {
      return const Center(
        child: Text(
          'No output yet',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    Color statusColor;
    if (run.status == 'running') {
      statusColor = AppTheme.warning;
    } else if (run.exitCode == 0) {
      statusColor = AppTheme.success;
    } else if (run.exitCode != null) {
      statusColor = AppTheme.error;
    } else {
      statusColor = AppTheme.textTertiary;
    }
    final header = [run.command, ...run.args].join(' ');
    final output = _stripAnsi(run.output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal, size: 14, color: AppTheme.info),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      header,
                      style: GoogleFonts.jetBrainsMono(
                        textStyle: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 11,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: statusColor),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      run.status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                run.cwd,
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: AppTheme.surfaceVariant,
            child: SelectableText(
              output.isEmpty ? 'Running...' : output,
              style: GoogleFonts.jetBrainsMono(
                textStyle: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              Text(
                run.exitCode == null ? '' : 'Exit ${run.exitCode}',
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 14),
                onPressed: output.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: output));
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Output copied.')),
                        );
                      },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy output',
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _stripAnsi(String input) {
    final ansiRegex = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
    return input.replaceAll(ansiRegex, '');
  }

  Future<bool> _sendMessage(
    String text, {
    List<Map<String, dynamic>>? fileParts,
  }) async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return false;

    final model = ref.read(activeModelProvider);
    final mode = ref.read(sessionModeProvider);

    final parts = <Map<String, dynamic>>[];

    if (fileParts != null) {
      parts.addAll(fileParts);
    }

    parts.add({'type': 'text', 'text': text});

    if (model == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No model selected. Pick a model first.'),
          ),
        );
      }
      return false;
    }

    final messageId = _optimisticId();
    final currentCount = ref.read(messagesProvider).messages.length;
    try {
      final optimistic = _buildOptimisticMessage(
        sessionId: session.id,
        messageId: messageId,
        text: text,
        fileParts: fileParts,
        model: model,
        mode: mode,
      );
      if (mounted) {
        setState(() {
          _optimisticMessages.add(optimistic);
          _optimisticBaseCount = currentCount;
          _optimisticMessageId = messageId;
        });
        _scrollToBottom();
      }
      setState(() => _isBusy = true);
      _markSessionActive();

      final messageService = ref.read(messageServiceProvider);
      await messageService.sendMessageAsync(
        session.id,
        parts: parts,
        providerID: model['providerID'],
        modelID: model['modelID'],
        agent: mode,
        directory: session.directory,
      );

      if (currentCount == 0) {
        ref.invalidate(projectsProvider);
      }
      _scrollToBottom();
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
        _restoreDraft(text, fileParts);
        setState(() {
          _optimisticMessages.removeWhere((msg) => msg.info.id == messageId);
          _optimisticBaseCount = null;
          _optimisticMessageId = null;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
      return false;
    }
  }

  Future<void> _sendCommand(String command, String arguments) async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (command == 'run') {
      await _executeShellCommand(arguments);
      return;
    }
    final mode = ref.read(sessionModeProvider);

    try {
      setState(() => _isBusy = true);
      _markSessionActive();

      final messageService = ref.read(messageServiceProvider);
      await messageService.sendCommand(
        session.id,
        command: command,
        arguments: arguments,
        agent: mode,
        directory: session.directory,
      );

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _executeShellCommand(String input) async {
    final session = ref.read(selectedSessionProvider);
    final project = ref.read(selectedProjectProvider);
    if (session == null || project == null) return;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    final tokens = _splitCommand(trimmed);
    if (tokens.isEmpty) return;
    final command = tokens.first;
    final args = tokens.skip(1).toList();
    final cwd = project.worktree;


    try {
      setState(() => _isBusy = true);
      _markSessionActive();

      final ptyService = ref.read(ptyServiceProvider);
      final pty = await ptyService.createPty(
        command: command,
        args: args,
        cwd: cwd,
        title: trimmed,
        directory: project.worktree,
      );

      final run = CommandRun(
        id: pty.id,
        command: command,
        args: args,
        cwd: cwd,
        status: pty.status,
        output: '',
        startedAt: DateTime.now().millisecondsSinceEpoch,
        exitCode: pty.exitCode,
      );
      ref.read(commandRunsProvider.notifier).upsert(run);
      ref.read(ptyProvider.notifier).upsert(pty);
      ref.read(activeCommandRunProvider.notifier).state = pty.id;
      _activeRunId = pty.id;

      unawaited(_connectPtyStream(pty.id, directory: project.worktree));

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() => _isBusy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Command failed: $e')));
      }
    }
  }

  Future<void> _connectPtyStream(String ptyId, {String? directory}) async {
    await _ptyStreamSub?.cancel();
    _ptyChannel?.sink.close();
    final ptyService = ref.read(ptyServiceProvider);
    final channel = ptyService.connect(ptyId, directory: directory);
    _ptyChannel = channel;
    _ptyStreamSub = channel.stream.listen(
      (event) {
        if (event == null) return;
        String chunk;
        if (event is List<int>) {
          chunk = utf8.decode(event);
        } else {
          chunk = event.toString();
        }
        if (chunk.isEmpty) return;
        ref.read(commandRunsProvider.notifier).appendOutput(ptyId, chunk);
        if (_isPinnedToBottom) {
          _scrollToBottom();
        }
      },
      onError: (_) {},
      onDone: () {
        if (_ptyChannel == channel) {
          _ptyChannel = null;
        }
        if (mounted) {
          setState(() => _isBusy = false);
        }
      },
      cancelOnError: false,
    );
  }

  List<String> _splitCommand(String input) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else {
          buffer.write(ch);
        }
        continue;
      }
      if (ch == '\'' || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(ch);
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  Future<void> _abortSession() async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;

    try {
      final sessionService = ref.read(sessionServiceProvider);
      await sessionService.abortSession(
        session.id,
        directory: session.directory,
      );
      setState(() => _isBusy = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to abort: $e')));
      }
    }
  }

  Future<void> _loadSessionModel(String sessionId) async {
    final prefs = ref.read(preferencesServiceProvider);
    final savedModel = await prefs.getSessionModel(sessionId);
    // Logic:
    // If we have a saved model for this session, set it as selected.
    // If NOT, we ensure selectedModelProvider is null so it falls back to default.
    // IMPORTANT: We only set state if it's different to avoid loops if this is called repeatedly.
    // But since this is a one-off load, we can just set it.

    // However, if the user explicitly cleared it in this session before (in memory), we might overwrite?
    // But since _loadSessionModel is intended to be called on session switch, it's fine.

    final current = ref.read(selectedModelProvider);
    if (savedModel == null) {
      if (current != null) {
        ref.read(selectedModelProvider.notifier).state = null;
      }
      return;
    }
    if (current == null ||
        current['providerID'] != savedModel['providerID'] ||
        current['modelID'] != savedModel['modelID']) {
      ref.read(selectedModelProvider.notifier).state = savedModel;
    }
  }

  Future<void> _loadProjectModel(String projectId, String sessionId) async {
    await ref.read(projectModelProvider.notifier).preload(projectId);
    final projectModel = ref.read(projectModelProvider).model;
    if (projectModel == null) return;
    final prefs = ref.read(preferencesServiceProvider);
    final savedSessionModel = await prefs.getSessionModel(sessionId);
    if (savedSessionModel != null) return;
    final current = ref.read(selectedModelProvider);
    if (current == null) {
      ref.read(selectedModelProvider.notifier).state = projectModel;
    }
  }

  Future<void> _loadTodos(Session session, {bool force = false}) async {
    if (!force && _todosSessionId == session.id) return;
    _todosSessionId = session.id;
    await ref
        .read(todosProvider.notifier)
        .loadTodos(session.id, directory: session.directory);
  }

  Future<void> _loadSessionDiff(Session session, {bool force = false}) async {
    if (!force && _diffSessionId == session.id) return;
    _diffSessionId = session.id;
    await ref
        .read(sessionDiffProvider.notifier)
        .loadDiff(session.id, directory: session.directory);
  }

  Future<void> _loadVcsBranch(Session session, {bool force = false}) async {
    if (!force && _vcsSessionId == session.id) return;
    _vcsSessionId = session.id;
    final project = ref.read(selectedProjectProvider);
    if (project == null) return;
    try {
      final info = await ref
          .read(appServiceProvider)
          .getVcsInfo(directory: project.worktree);
      ref.read(vcsBranchProvider.notifier).state = info.branch;
    } catch (_) {
      // ignore vcs failures
    }
  }

  Future<void> _revertMessage(MessageWrapper msg) async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_isUndoRedoInFlight) return;
    setState(() => _isUndoRedoInFlight = true);
    try {
      final sessionService = ref.read(sessionServiceProvider);
      final updated = await sessionService.revertSession(
        session.id,
        messageID: msg.info.id,
        directory: session.directory,
      );
      ref.read(selectedSessionProvider.notifier).state = updated;
      await ref.read(messagesProvider.notifier).loadForSession(updated);
      ref.read(sessionDiffProvider.notifier).clear();
      await _loadSessionDiff(updated);
      await _loadTodos(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message effects reverted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Undo failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUndoRedoInFlight = false);
      }
    }
  }

  Future<void> _unrevertSession(Session session) async {
    if (_isUndoRedoInFlight) return;
    setState(() => _isUndoRedoInFlight = true);
    try {
      final sessionService = ref.read(sessionServiceProvider);
      final updated = await sessionService.unrevertSession(
        session.id,
        directory: session.directory,
      );
      ref.read(selectedSessionProvider.notifier).state = updated;
      await ref.read(messagesProvider.notifier).loadForSession(updated);
      ref.read(sessionDiffProvider.notifier).clear();
      await _loadSessionDiff(updated);
      await _loadTodos(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message effects restored.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Redo failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isUndoRedoInFlight = false);
      }
    }
  }

  Widget _buildMessageActions({
    required bool canUndo,
    required bool canRedo,
    required VoidCallback onUndo,
    required VoidCallback onRedo,
  }) {
    return Wrap(
      spacing: 4,
      children: [
        IconButton(
          icon: const Icon(Icons.undo, size: 14),
          onPressed: canUndo ? onUndo : null,
          tooltip: 'Undo message effects',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          icon: const Icon(Icons.redo, size: 14),
          onPressed: canRedo ? onRedo : null,
          tooltip: 'Redo message effects',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(selectedSessionProvider);
    final messagesState = ref.watch(messagesProvider);
    final mode = ref.watch(sessionModeProvider);
    final activeModel = ref.watch(activeModelProvider);
    final statusAsync = ref.watch(sessionStatusProvider);

    final errorState = ref.watch(sessionErrorProvider);
    final activeRunId = ref.watch(activeCommandRunProvider);
    final commandRuns = ref.watch(commandRunsProvider).items;
    final activeRun = activeRunId != null ? commandRuns[activeRunId] : null;

    final messages = messagesState.messages;
    final baseMessages = _cachedMessages.isNotEmpty
        ? _cachedMessages
        : messages;
    final displayMessages = _optimisticMessages.isNotEmpty
        ? [...baseMessages, ..._optimisticMessages]
        : baseMessages;
    final isInitialLoading = messagesState.isLoading && !_hasLoadedMessages;
    final isSessionBusy = statusAsync.maybeWhen(
      data: (status) {
        if (session == null) return false;
        final info = status[session.id];
        if (info is Map<String, dynamic>) {
          return info['type'] == 'busy' || info['type'] == 'retry';
        }
        if (info is String) {
          return info == 'busy' || info == 'retry';
        }
        return false;
      },
      orElse: () => false,
    );

    if (session == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => context.go('/sessions'),
          ),
        ),
        body: const Center(
          child: Text(
            'No session selected',
            style: TextStyle(color: AppTheme.textTertiary),
          ),
        ),
      );
    }

    final commandParts = <Part>[];
    if (activeRun != null) {
      commandParts.add(
        CommandOutputPart(
          id: activeRun.id,
          sessionID: session.id,
          messageID: activeRun.id,
          command: activeRun.command,
          args: activeRun.args,
          cwd: activeRun.cwd,
          status: activeRun.status,
          exitCode: activeRun.exitCode,
          time: PartTime(
            start: activeRun.startedAt,
            end: activeRun.completedAt,
          ),
          metadata: {'output': activeRun.output},
        ),
      );
    }

    final effectiveBusy = _isBusy || isSessionBusy || _isSyncing;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => context.go('/sessions'),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.title.isEmpty ? 'New Session' : session.title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  color: effectiveBusy ? AppTheme.warning : AppTheme.success,
                ),
                const SizedBox(width: 4),
                Text(
                  _isSyncing
                      ? 'Syncing...'
                      : effectiveBusy
                      ? (mode == 'plan' ? 'Planning...' : 'Building...')
                      : 'Ready${(activeModel != null) ? " • ${activeModel['modelID']}" : ""}',
                  style: TextStyle(
                    fontSize: 10,
                    color: effectiveBusy
                        ? AppTheme.warning
                        : AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          GestureDetector(
              onTap: () {
                final newMode = mode == 'plan' ? 'build' : 'plan';
                unawaited(
                  ref
                      .read(sessionModeProvider.notifier)
                      .setModeForCurrentSession(newMode),
                );
              },
            child: Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: mode == 'plan'
                    ? AppTheme.info.withValues(alpha: 0.15)
                    : AppTheme.accent.withValues(alpha: 0.15),
                border: Border.all(
                  color: mode == 'plan' ? AppTheme.info : AppTheme.accent,
                ),
              ),
              child: Text(
                mode.toUpperCase(),
                style: TextStyle(
                  color: mode == 'plan' ? AppTheme.info : AppTheme.accent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          _buildSidebarToggle(),
          IconButton(
            icon: const Icon(Icons.swap_horiz, size: 20),
            onPressed: () {
              context.push('/models', extra: {'mode': 'session'});
            },
            tooltip: 'Models',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildMessagesPanel(
                    displayMessages: displayMessages,
                    messagesState: messagesState,
                    isInitialLoading: isInitialLoading,
                    mode: mode,
                    extraParts: commandParts,
                  ),
                ),
                if (_isSidebarOpen)
                  _buildSidebar(
                    errorState: errorState,
                    activeRunId: activeRunId,
                    commandRuns: commandRuns,
                  ),
              ],
            ),
          ),
          if (effectiveBusy)
            Container(
              width: double.infinity,
              height: 2,
              color: AppTheme.border,
              child: LinearProgressIndicator(
                backgroundColor: AppTheme.border,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
              ),
            ),
          RepaintBoundary(
            child: ChatInput(
              key: _chatInputKey,
              onSendMessage: _sendMessage,
              onSendCommand: _sendCommand,
              onStop: _abortSession,
              isBusy: effectiveBusy,
              enabled: !effectiveBusy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(MessageWrapper msg) {
    final isUser = msg.info.role == 'user';
    final session = ref.watch(selectedSessionProvider);
    final isAssistant = msg.info.role == 'assistant';
    final isOptimistic = _optimisticMessages.any(
      (candidate) => candidate.info.id == msg.info.id,
    );
    final isCommandMessage =
        isAssistant &&
        msg.info is AssistantMessageInfo &&
        (msg.info as AssistantMessageInfo).providerID == 'local' &&
        (msg.info as AssistantMessageInfo).modelID == 'command';
    final canUndo =
        isAssistant &&
        !isCommandMessage &&
        !_isBusy &&
        !_isUndoRedoInFlight &&
        session != null;
    final canRedo =
        isAssistant &&
        !isCommandMessage &&
        !_isBusy &&
        !_isUndoRedoInFlight &&
        session?.revert?.messageID == msg.info.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Role header
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  width: 4,
                  height: 12,
                  color: isUser ? AppTheme.info : AppTheme.accent,
                ),
                Text(
                  isUser ? 'YOU' : 'ASSISTANT',
                  style: TextStyle(
                    color: isUser ? AppTheme.info : AppTheme.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                if (isUser && isOptimistic)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      border: Border.all(color: AppTheme.warning),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'SENDING',
                      style: TextStyle(
                        color: AppTheme.warning,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                if (!isUser && msg.info is AssistantMessageInfo)
                  Text(
                    (msg.info as AssistantMessageInfo).modelID,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (isAssistant)
                  _buildMessageActions(
                    canUndo: canUndo,
                    canRedo: canRedo,
                    onUndo: () => _revertMessage(msg),
                    onRedo: session == null
                        ? () {}
                        : () => _unrevertSession(session),
                  ),
              ],
            ),
          ),
          // Parts
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: isUser ? AppTheme.userBubble : AppTheme.assistantBubble,
              border: Border(
                left: BorderSide(
                  color: isUser
                      ? AppTheme.info.withValues(alpha: 0.3)
                      : AppTheme.accent.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: MessagePartsWidget(parts: msg.parts, isUser: isUser),
          ),
          // Cost info for assistant
          if (!isUser &&
              msg.info is AssistantMessageInfo &&
              !isCommandMessage) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    '\$${(msg.info as AssistantMessageInfo).cost.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                  Text(
                    '${(msg.info as AssistantMessageInfo).tokens.input + (msg.info as AssistantMessageInfo).tokens.output} tokens',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                  if ((msg.info as AssistantMessageInfo).mode.isNotEmpty)
                    Text(
                      (msg.info as AssistantMessageInfo).mode.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionDialog extends StatefulWidget {
  final QuestionRequest request;
  final Future<void> Function(List<List<String>> answers) onSubmit;
  final Future<void> Function() onReject;

  const _QuestionDialog({
    required this.request,
    required this.onSubmit,
    required this.onReject,
  });

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  late List<List<String>> _answers;
  late List<String?> _customAnswers;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _answers = widget.request.questions.map((_) => <String>[]).toList();
    _customAnswers = List<String?>.filled(
      widget.request.questions.length,
      null,
      growable: true,
    );
  }

  bool _isMultiple(QuestionInfo question) => question.multiple ?? false;

  bool _allowsCustom(QuestionInfo question) => question.custom ?? true;

  void _toggleSelection(int index, String label) {
    final question = widget.request.questions[index];
    final current = List<String>.from(_answers[index]);
    if (_isMultiple(question)) {
      if (current.contains(label)) {
        current.remove(label);
      } else {
        current.add(label);
      }
    } else {
      current
        ..clear()
        ..add(label);
    }
    setState(() {
      _answers[index] = current;
      if (!_allowsCustom(question)) return;
      if (current.isNotEmpty && _customAnswers[index]?.isNotEmpty == true) {
        _customAnswers[index] = null;
      }
    });
  }

  void _setCustomAnswer(int index, String value) {
    setState(() {
      _customAnswers[index] = value.trim().isEmpty ? null : value.trim();
      if (_customAnswers[index] != null && _answers[index].isNotEmpty) {
        _answers[index] = [];
      }
    });
  }

  bool _canSubmit() {
    for (var i = 0; i < widget.request.questions.length; i++) {
      final hasChoice = _answers[i].isNotEmpty;
      final hasCustom = _customAnswers[i] != null;
      if (!hasChoice && !hasCustom) return false;
    }
    return true;
  }

  List<List<String>> _buildAnswers() {
    return List<List<String>>.generate(widget.request.questions.length, (i) {
      final custom = _customAnswers[i];
      if (custom != null && custom.isNotEmpty) {
        return [custom];
      }
      return List<String>.from(_answers[i]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Questions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(widget.request.questions.length, (i) {
                    final question = widget.request.questions[i];
                    final allowCustom = _allowsCustom(question);
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: i == widget.request.questions.length - 1
                            ? 0
                            : 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            question.header,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            question.question,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Column(
                            children: question.options.map((option) {
                              final isSelected = _answers[i].contains(
                                option.label,
                              );
                              return InkWell(
                                onTap: () => _toggleSelection(i, option.label),
                                child: Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.accent.withValues(
                                            alpha: 0.12,
                                          )
                                        : AppTheme.surface,
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.accent
                                          : AppTheme.border,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        option.label,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? AppTheme.accent
                                              : AppTheme.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        option.description,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textTertiary,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          if (allowCustom) ...[
                            const SizedBox(height: 6),
                            TextField(
                              onChanged: (value) => _setCustomAnswer(i, value),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Type your own answer',
                                hintStyle: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textTertiary,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: AppTheme.border,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: AppTheme.border,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(
                                    color: AppTheme.accent,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () async {
                            setState(() => _isSubmitting = true);
                            await widget.onReject();
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                    ),
                    child: const Text('REJECT', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting || !_canSubmit()
                        ? null
                        : () async {
                            setState(() => _isSubmitting = true);
                            await widget.onSubmit(_buildAnswers());
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.textPrimary,
                    ),
                    child: const Text('SUBMIT', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

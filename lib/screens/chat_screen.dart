import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/message.dart';
import '../models/permission_request.dart';
import '../models/question_request.dart';
import '../models/session.dart';
import '../models/todo.dart';
import '../models/pty.dart';
import '../models/file_diff.dart';
import '../models/part.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/chat_input.dart';
import '../widgets/file_changes_tree.dart';
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
  ProviderSubscription<AsyncValue<List<MessageWrapper>>>? _messagesSub;
  ProviderSubscription<AsyncValue<Map<String, dynamic>>>? _statusSub;
  ProviderSubscription<String>? _sessionModeSub;
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
  bool _isUndoRedoInFlight = false;
  bool _didInitialScroll = false;
  Timer? _refreshTimer;
  final GlobalKey _chatInputKey = GlobalKey();
  final List<MessageWrapper> _optimisticMessages = [];
  int? _optimisticBaseCount;
  String? _optimisticMessageId;
  bool _isSyncing = false;
  bool _syncMessagesReady = false;
  bool _syncStatusReady = false;
  Timer? _syncTimeout;
  int _syncToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToEvents();
    _listenToSessionChanges();
    _listenToMessageUpdates();
    _listenToStatusUpdates();
    _listenToSessionMode();
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
        _startSync();
        _handleSessionSelected(current);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _syncTimeout?.cancel();
    _eventSub?.cancel();
    _sessionSub?.close();
    _messagesSub?.close();
    _statusSub?.close();
    _sessionModeSub?.close();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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
    if (_showScrollToBottom == isNearBottom) {
      setState(() => _showScrollToBottom = !isNearBottom);
    }
  }

  void _debouncedRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        ref.invalidate(messagesProvider);
        _refreshTimer = null;
      }
    });
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

        if (type == 'message.updated' ||
            type == 'message.removed' ||
            type == 'message.part.updated' ||
            type == 'message.part.removed') {
          _debouncedRefresh();
        } else if (type == 'permission.asked') {
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
        } else if (type == 'session.updated') {
          ref.invalidate(sessionsProvider);
          final session = ref.read(selectedSessionProvider);
          if (session != null) {
            ref
                .read(sessionServiceProvider)
                .getSession(session.id, directory: session.directory)
                .then((updated) {
                  ref.read(selectedSessionProvider.notifier).state = updated;
                });
          }
        } else if (type == 'session.created') {
          ref.invalidate(sessionsProvider);
        } else if (type == 'session.status') {
          final props = event['properties'];
          if (!_isCurrentSessionEvent(props)) return;
          String? statusStr;
          if (props is Map<String, dynamic>) {
            final status = props['status'];
            if (status is Map<String, dynamic>) {
              statusStr = status['type']?.toString();
            } else {
              statusStr = status is String ? status : status?.toString();
            }
          }
          if (mounted) {
            setState(() {
              _isBusy = statusStr != null && statusStr != 'idle';
            });
          }
          if (_isBusy) {
            _markSessionActive();
          }
          if (_isBusy) {
            _debouncedRefresh();
          }
        } else if (type == 'session.idle') {
          if (!_isCurrentSessionEvent(event['properties'])) return;
          if (mounted) {
            setState(() => _isBusy = false);
          }
          _debouncedRefresh();
        } else if (type == 'session.deleted') {
          _handleSessionDeleted(event['properties']);
          ref.invalidate(sessionsProvider);
        } else if (type == 'session.compacted') {
          if (!_isCurrentSessionEvent(event['properties'])) return;
          _debouncedRefresh();
        } else if (type == 'session.error') {
          _handleSessionError(event['properties']);
        } else if (type == 'session.diff') {
          _handleSessionDiff(event['properties']);
        } else if (type == 'todo.updated') {
          _handleTodoUpdated(event['properties']);
        } else if (type == 'vcs.branch.updated') {
          _handleBranchUpdated(event['properties']);
        } else if (type == 'tui.prompt.append') {
          _handlePromptAppend(event['properties']);
        } else if (type == 'tui.command.execute') {
          _handleCommandExecuted(event['properties']);
        } else if (type == 'command.executed') {
          _handleCommandExecuted(event['properties']);
        } else if (type == 'tui.toast.show') {
          _handleToastEvent(event['properties']);
        } else if (type == 'pty.created') {
          _handlePtyCreated(event['properties']);
        } else if (type == 'pty.updated') {
          _handlePtyUpdated(event['properties']);
        } else if (type == 'pty.exited') {
          _handlePtyExited(event['properties']);
        } else if (type == 'pty.deleted') {
          _handlePtyDeleted(event['properties']);
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
    _startSync();
    ref.read(sessionModeProvider.notifier).state = 'plan';
    ref.read(todosProvider.notifier).clear();
    ref.read(sessionErrorProvider.notifier).clear();
    ref.read(ptyProvider.notifier).clear();
    ref.read(sessionDiffProvider.notifier).clear();
    ref.read(vcsBranchProvider.notifier).state = null;
    _loadProjectModel(session.projectID, session.id);
    _loadSessionModel(session.id);
    _loadPendingPermissions();
    _loadPendingQuestions();
    _loadTodos(session);
    _loadSessionDiff(session);
    _loadVcsBranch(session);
  }

  Future<void> _refreshAfterReconnect(Session session) async {
    ref.invalidate(messagesProvider);
    await _loadTodos(session);
    await _loadSessionDiff(session);
    await _loadVcsBranch(session);
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

  void _listenToSessionMode() {
    _sessionModeSub = ref.listenManual<String>(sessionModeProvider, (
      prev,
      next,
    ) {
      final session = ref.read(selectedSessionProvider);
      if (session == null) return;
      if (prev == next) return;
      ref.read(preferencesServiceProvider).saveSessionMode(session.id, next);
    });
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
        final info = next.valueOrNull?[session.id];
        String? statusType;
        if (info is Map<String, dynamic>) {
          statusType = info['type']?.toString();
        } else if (info is String) {
          statusType = info;
        }
        if (statusType != null && mounted) {
          setState(() {
            _isBusy = statusType != 'idle';
          });
        }
      },
    );
  }

  void _listenToMessageUpdates() {
    _messagesSub = ref.listenManual<AsyncValue<List<MessageWrapper>>>(
      messagesProvider,
      (prev, next) {
        final session = ref.read(selectedSessionProvider);
        final nextMessages = next.valueOrNull;
        if (session != null && nextMessages != null) {
          _updateCachedMessages(session.id, nextMessages);
          _syncSelectedModelFromMessages(session, nextMessages);
          _syncSessionModeFromMessages(session, nextMessages);
        }

        if (_isSyncing && nextMessages != null) {
          _syncMessagesReady = true;
          _completeSyncIfReady();
        }

        final prevLength = prev?.valueOrNull?.length ?? 0;
        final nextLength = next.valueOrNull?.length ?? 0;
        if (nextLength > prevLength) {
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
    ref.invalidate(messagesProvider);
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
    ref.read(ptyProvider.notifier).upsert(PtyInfo.fromJson(info));
  }

  void _handlePtyUpdated(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final info = props['info'];
    if (info is! Map<String, dynamic>) return;
    ref.read(ptyProvider.notifier).upsert(PtyInfo.fromJson(info));
  }

  void _handlePtyExited(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final id = props['id']?.toString();
    if (id == null || id.isEmpty) return;
    final exitCode = (props['exitCode'] as num?)?.toInt() ?? 0;
    ref.read(ptyProvider.notifier).updateExit(id, exitCode);
  }

  void _handlePtyDeleted(dynamic props) {
    if (props is! Map<String, dynamic>) return;
    if (!_isCurrentSessionEvent(props)) return;
    final id = props['id']?.toString();
    if (id == null || id.isEmpty) return;
    ref.read(ptyProvider.notifier).remove(id);
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
      _optimisticMessages.clear();
      _optimisticBaseCount = null;
      _optimisticMessageId = null;
      _hasLoadedMessages = false;
      _permissionDialogVisible = false;
      _questionDialogVisible = false;
    });
    _modelSyncSessionId = sessionId;
    _didSyncModelFromMessages = false;
    _modeSyncSessionId = sessionId;
    _didSyncModeFromMessages = false;
    _didInitialScroll = false;
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
      ref.read(sessionModeProvider.notifier).state = mode;
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
      if (!force && !_isNearBottom()) return;
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
    required AsyncValue<List<MessageWrapper>> messagesAsync,
    required bool isInitialLoading,
    required String mode,
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

    if (messagesAsync.hasError && displayMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Error: ${messagesAsync.error}',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(messagesProvider),
              child: const Text('RETRY'),
            ),
          ],
        ),
      );
    }

    if (displayMessages.isEmpty) {
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

    final listWidget = ListView.builder(
      controller: _scrollController,
      cacheExtent: 800,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: displayMessages.length,
      itemBuilder: (context, index) {
        final msg = displayMessages[index];
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
                onTap: _scrollToBottom,
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

  Widget _buildSidebar({required SessionErrorState errorState}) {
    final todosState = ref.watch(todosProvider);
    final ptyState = ref.watch(ptyProvider);
    final ptys = ptyState.items.values.toList()
      ..sort((a, b) {
        final titleA = a.title.isNotEmpty ? a.title : a.command;
        final titleB = b.title.isNotEmpty ? b.title : b.command;
        return titleA.compareTo(titleB);
      });
    final tabs = const [
      Tab(text: 'CHANGES'),
      Tab(text: 'TODOS'),
      Tab(text: 'PTY'),
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
                        _buildChangesTab(),
                        _buildTodosTab(todosState),
                        _buildPtyTab(ptys),
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
    final todos = ref.watch(todosProvider).todos;
    final pendingCount = todos.where((todo) {
      final status = todo.status.toLowerCase();
      return status == 'in_progress' ||
          status == 'inprogress' ||
          status == 'pending' ||
          status == 'todo';
    }).length;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            _isSidebarOpen ? Icons.view_sidebar : Icons.view_sidebar_outlined,
            size: 20,
          ),
          onPressed: () {
            setState(() => _isSidebarOpen = !_isSidebarOpen);
          },
          tooltip: 'Sidebar',
        ),
        if (pendingCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.warning,
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                pendingCount > 99 ? '99+' : pendingCount.toString(),
                style: const TextStyle(
                  fontSize: 8,
                  color: AppTheme.background,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChangesTab() {
    final diffState = ref.watch(sessionDiffProvider);
    if (diffState.isLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (diffState.error != null) {
      return Center(
        child: Text(
          'Diff error: ${diffState.error}',
          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      );
    }

    return FileChangesTree(diffs: diffState.diffs);
  }

  Widget _buildTodosTab(TodosState todosState) {
    if (todosState.isLoading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (todosState.todos.isEmpty) {
      return const Center(
        child: Text(
          'No todos',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: todosState.todos.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final todo = todosState.todos[index];
        final status = todo.status.toUpperCase();
        final priority = todo.priority.toUpperCase();

        // Determine status color based on status value
        Color statusColor;
        switch (todo.status.toLowerCase()) {
          case 'in_progress':
          case 'inprogress':
          case 'pending':
            statusColor = AppTheme.warning;
          case 'done':
          case 'completed':
          case 'complete':
            statusColor = AppTheme.success;
          default:
            statusColor = AppTheme.textTertiary;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              todo.content,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  priority,
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildPtyTab(List<PtyInfo> ptys) {
    if (ptys.isEmpty) {
      return const Center(
        child: Text(
          'No ptys',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: ptys.length,
      separatorBuilder: (_, __) => const Divider(height: 16),
      itemBuilder: (context, index) {
        final pty = ptys[index];
        final title = pty.title.isNotEmpty ? pty.title : pty.command;
        final exitCode = pty.exitCode;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              pty.cwd,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: pty.status == 'running'
                        ? AppTheme.success
                        : AppTheme.textTertiary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  pty.status.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'PID ${pty.pid}',
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 9,
                  ),
                ),
                if (exitCode != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'EXIT $exitCode',
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
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
    final currentCount =
        ref.read(messagesProvider).valueOrNull?.length ??
        _cachedMessages.length;
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

      ref.invalidate(messagesProvider);
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

      ref.invalidate(messagesProvider);
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
    await ref.read(projectModelProvider.notifier).load(projectId);
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

  Future<void> _loadTodos(Session session) async {
    await ref
        .read(todosProvider.notifier)
        .loadTodos(session.id, directory: session.directory);
  }

  Future<void> _loadSessionDiff(Session session) async {
    await ref
        .read(sessionDiffProvider.notifier)
        .loadDiff(session.id, directory: session.directory);
  }

  Future<void> _loadVcsBranch(Session session) async {
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
      ref.invalidate(messagesProvider);
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
      ref.invalidate(messagesProvider);
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
    final messagesAsync = ref.watch(messagesProvider);
    final mode = ref.watch(sessionModeProvider);
    final activeModel = ref.watch(activeModelProvider);
    final statusAsync = ref.watch(sessionStatusProvider);

    final errorState = ref.watch(sessionErrorProvider);

    final messages = messagesAsync.valueOrNull ?? const <MessageWrapper>[];
    final baseMessages = _cachedMessages.isNotEmpty
        ? _cachedMessages
        : messages;
    final displayMessages = _optimisticMessages.isNotEmpty
        ? [...baseMessages, ..._optimisticMessages]
        : baseMessages;
    final isInitialLoading = messagesAsync.isLoading && !_hasLoadedMessages;
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
              ref.read(sessionModeProvider.notifier).state = newMode;
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
                    messagesAsync: messagesAsync,
                    isInitialLoading: isInitialLoading,
                    mode: mode,
                  ),
                ),
                if (_isSidebarOpen) _buildSidebar(errorState: errorState),
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
    final canUndo =
        isAssistant && !_isBusy && !_isUndoRedoInFlight && session != null;
    final canRedo =
        isAssistant &&
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
          if (!isUser && msg.info is AssistantMessageInfo) ...[
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

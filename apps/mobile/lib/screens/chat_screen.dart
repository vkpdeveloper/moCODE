import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/acp_models.dart';
import '../models/message.dart';
import '../models/permission_request.dart';
import '../models/question_request.dart';
import '../models/session.dart';
import '../models/session_control.dart';
import '../models/todo.dart';
import '../models/file_diff.dart';
import '../models/part.dart';
import '../providers/providers.dart';
import '../providers/ssh_provider.dart';
import '../services/app_logger.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_parts.dart';
import '../widgets/message_widgets.dart';
import '../widgets/session_busy_indicator.dart';
import '../widgets/ssh_connection_dialog.dart';
import 'terminal_page.dart';
import '../widgets/connection_choice_sheet.dart';
import 'sftp_page.dart';

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
    final eventService = ref.read(eventServiceProvider);
    _eventSub = eventService.subscribe().listen((event) {
      try {
        final type = event['type'] as String? ?? '';
        if (type == '__reconnected__') {
          final session = ref.read(selectedSessionProvider);
          if (session != null) {
            _refreshAfterReconnect(session);
          }
          return;
        }

        if (type == 'permission_request') {
          final payload = event['payload'];
          if (payload is Map<String, dynamic>) {
            _handlePermissionRequest(payload);
          }
        } else if (type == 'question_request') {
          final payload = event['payload'];
          if (payload is Map<String, dynamic>) {
            _handleQuestionRequest(payload);
          }
        } else if (type == 'daemon_warning') {
          final payload = event['payload'];
          final error = payload is Map<String, dynamic>
              ? payload['error']?.toString()
              : null;
          if (error != null && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
          }
        }
      } catch (e) {
        AppLogger.instance.error(
          'Chat event handling failed',
          scope: 'chat',
          data: {'event': event},
          error: e,
        );
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
        final statusMap = next.hasValue ? next.value : null;
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

  void _listenToMessageUpdates() {
    _messagesSub = ref.listenManual<MessagesState>(messagesProvider, (
      MessagesState? prev,
      MessagesState next,
    ) {
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
    });
  }

  void _restoreDraft(String text, List<Map<String, dynamic>>? fileParts) {
    if (!mounted) return;
    ChatInput.restoreDraft(
      _chatInputKey.currentContext ?? context,
      text,
      fileParts ?? const <Map<String, dynamic>>[],
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
    ref.read(sessionModeProvider.notifier).resetMessageHydration(sessionId);
    _didInitialScroll = false;
  }

  Future<void> _loadPendingPermissions() async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_permissionDialogVisible) return;
    try {
      final permissionService = ref.read(permissionServiceProvider);
      final pending = await permissionService.listPending(
        sessionID: session.id,
      );
      if (!mounted || pending.isEmpty) return;
      await _showPermissionDialog(pending.first);
    } catch (_) {
      // ignore permission polling failures
    }
  }

  Future<void> _loadPendingQuestions() async {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_questionDialogVisible) return;
    try {
      final questionService = ref.read(questionServiceProvider);
      final pending = await questionService.listPending(sessionID: session.id);
      if (!mounted || pending.isEmpty) return;
      await _showQuestionDialog(pending.first);
    } catch (_) {
      // ignore question polling failures
    }
  }

  void _handlePermissionRequest(Map<String, dynamic> payload) {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_permissionDialogVisible) return;
    if (payload['sessionId']?.toString() != session.id) return;
    final requestRaw = payload['request'];
    if (requestRaw is! Map) return;
    final permission = permissionRequestFromAcp(
      requestId: payload['requestId']?.toString() ?? '',
      sessionId: session.id,
      request: Map<String, dynamic>.from(requestRaw),
    );
    _showPermissionDialog(permission);
  }

  void _handleQuestionRequest(Map<String, dynamic> payload) {
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    if (_questionDialogVisible) return;
    if (payload['sessionId']?.toString() != session.id) return;
    final requestRaw = payload['request'];
    if (requestRaw is! Map) return;
    final question = QuestionRequest.fromJson({
      ...Map<String, dynamic>.from(requestRaw),
      'id': payload['requestId']?.toString() ?? '',
      'sessionID': session.id,
    });
    _showQuestionDialog(question);
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
    final session = ref.read(selectedSessionProvider);
    if (session == null) return;
    try {
      final permissionService = ref.read(permissionServiceProvider);
      await permissionService.reply(session.id, request.id, reply: reply);
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
    try {
      final questionService = ref.read(questionServiceProvider);
      await questionService.reply(request, answers: answers);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Question reply failed: $e')));
      }
    }
  }

  Future<void> _rejectQuestion(QuestionRequest request) async {
    try {
      final questionService = ref.read(questionServiceProvider);
      await questionService.reject(request);
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
    if (messages.isEmpty) return;
    unawaited(
      ref
          .read(sessionModeProvider.notifier)
          .hydrateFromMessages(session.id, messages),
    );
  }

  Future<void> _setSessionMode(String mode) async {
    await ref.read(sessionModeProvider.notifier).setModeForCurrentSession(mode);
  }

  Future<void> _handleModeAction(
    BuildContext context, {
    required String currentMode,
    required List<SessionModeOption> availableModes,
  }) async {
    if (availableModes.isEmpty) {
      return;
    }

    if (availableModes.length == 1) {
      return;
    }

    if (availableModes.length == 2) {
      final fallback = availableModes.first;
      var next = fallback;
      for (final item in availableModes) {
        if (item.id != currentMode) {
          next = item;
          break;
        }
      }
      await _setSessionMode(next.id);
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Session Mode',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final item in availableModes)
                ListTile(
                  dense: true,
                  title: Text(
                    item.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  subtitle:
                      item.description == null || item.description!.isEmpty
                      ? null
                      : Text(
                          item.description!,
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                  trailing: item.id == currentMode
                      ? const Icon(
                          Icons.check,
                          size: 16,
                          color: AppTheme.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(context).pop(item.id),
                ),
            ],
          ),
        );
      },
    );

    if (selected != null && selected != currentMode) {
      await _setSessionMode(selected);
    }
  }

  Future<void> _showSessionConfigSheet(
    BuildContext context,
    SessionControl control,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      builder: (context) {
        return _SessionConfigSheet(
          control: control,
          onSelectValue: (configId, valueId) async {
            await ref
                .read(sessionControlProvider.notifier)
                .setConfigOption(configId: configId, valueId: valueId);
          },
          onToggleValue: (configId, value) async {
            await ref
                .read(sessionControlProvider.notifier)
                .setConfigOption(configId: configId, boolValue: value);
          },
        );
      },
    );
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
    Map<String, dynamic>? model,
    required String mode,
  }) {
    final created = DateTime.now().millisecondsSinceEpoch;
    final info = UserMessageInfo(
      id: messageId,
      sessionID: sessionId,
      time: MessageTime(created: created, completed: created),
      agent: mode,
      model: model == null
          ? null
          : MessageModel(
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
      final statusValue = statusAsync.hasValue ? statusAsync.value : null;
      final info = statusValue?[session.id];
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

    if (messagesState.error != null && displayMessages.isEmpty) {
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

    final items = List<MessageWrapper>.from(displayMessages);
    final timelineMessages = _mergeAssistantMessagesByTurn(items);

    final listWidget = ListView.builder(
      controller: _scrollController,
      cacheExtent: 800,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: timelineMessages.length,
      itemBuilder: (context, index) {
        final msg = timelineMessages[index];
        final isLastMessage = index == timelineMessages.length - 1;
        return RepaintBoundary(
          child: KeyedSubtree(
            key: ValueKey(msg.info.id),
            child: _buildMessage(msg, isLastMessage: isLastMessage),
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

  List<MessageWrapper> _mergeAssistantMessagesByTurn(
    List<MessageWrapper> source,
  ) {
    if (source.length < 2) return source;

    final merged = <MessageWrapper>[];
    String? currentUserID;
    int? currentAssistantIndex;

    for (final message in source) {
      final info = message.info;

      if (info is UserMessageInfo) {
        merged.add(message);
        currentUserID = info.id;
        currentAssistantIndex = null;
        continue;
      }

      if (info is AssistantMessageInfo) {
        final isCommandMessage =
            info.providerID == 'local' && info.modelID == 'command';
        final canMergeIntoTurn =
            !isCommandMessage &&
            currentUserID != null &&
            info.parentID != null &&
            info.parentID == currentUserID;

        if (canMergeIntoTurn && currentAssistantIndex != null) {
          final existing = merged[currentAssistantIndex];
          merged[currentAssistantIndex] = _mergeAssistantWrappers(
            existing,
            message,
          );
          continue;
        }

        merged.add(message);
        if (canMergeIntoTurn) {
          currentAssistantIndex = merged.length - 1;
        }
        continue;
      }

      merged.add(message);
    }

    return merged;
  }

  MessageWrapper _mergeAssistantWrappers(MessageWrapper a, MessageWrapper b) {
    final aInfo = a.info;
    final bInfo = b.info;
    if (aInfo is! AssistantMessageInfo || bInfo is! AssistantMessageInfo) {
      return b;
    }

    final mergedInfo = AssistantMessageInfo(
      id: bInfo.id,
      sessionID: bInfo.sessionID,
      time: MessageTime(
        created: aInfo.time.created,
        completed: bInfo.time.completed ?? aInfo.time.completed,
      ),
      error: bInfo.error ?? aInfo.error,
      parentID: bInfo.parentID ?? aInfo.parentID,
      modelID: bInfo.modelID,
      providerID: bInfo.providerID,
      mode: bInfo.mode.isNotEmpty ? bInfo.mode : aInfo.mode,
      agent: bInfo.agent ?? aInfo.agent,
      path: bInfo.path ?? aInfo.path,
      isSummary: bInfo.isSummary ?? aInfo.isSummary,
      cost: aInfo.cost + bInfo.cost,
      tokens: MessageTokens(
        input: aInfo.tokens.input + bInfo.tokens.input,
        output: aInfo.tokens.output + bInfo.tokens.output,
        reasoning: aInfo.tokens.reasoning + bInfo.tokens.reasoning,
        cache: MessageCacheTokens(
          read: aInfo.tokens.cache.read + bInfo.tokens.cache.read,
          write: aInfo.tokens.cache.write + bInfo.tokens.cache.write,
        ),
      ),
      finish: bInfo.finish ?? aInfo.finish,
    );

    return MessageWrapper(
      info: mergedInfo,
      parts: <Part>[...a.parts, ...b.parts],
    );
  }

  bool _hasMultipleAssistantPartMessages(MessageWrapper msg) {
    if (msg.info is! AssistantMessageInfo) return false;
    final ids = msg.parts.map((part) => part.messageID).toSet();
    return ids.length > 1;
  }

  Widget _buildSidebar({required SessionErrorState errorState}) {
    final todosState = ref.watch(todosProvider);
    final diffState = ref.watch(sessionDiffProvider);

    const tabs = [Tab(text: 'TODOS'), Tab(text: 'CHANGES')];

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
                        _buildTodosTab(todosState.todos),
                        _buildChangesTab(diffState.diffs),
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

  Widget _buildTodosTab(List<Todo> todos) {
    if (todos.isEmpty) {
      return const Center(
        child: Text(
          'No todos',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: todos.length,
      itemBuilder: (context, index) {
        final todo = todos[index];
        Color statusColor;
        switch (todo.status) {
          case 'completed':
            statusColor = AppTheme.success;
            break;
          case 'in_progress':
            statusColor = AppTheme.warning;
            break;
          case 'pending':
          default:
            statusColor = AppTheme.textTertiary;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 4, right: 8),
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  todo.content,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChangesTab(List<FileDiff> diffs) {
    if (diffs.isEmpty) {
      return const Center(
        child: Text(
          'No changes',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: diffs.length,
      itemBuilder: (context, index) {
        final diff = diffs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.surfaceVariant,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file,
                    size: 14,
                    color: AppTheme.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      diff.file,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    '+${diff.additions}',
                    style: const TextStyle(
                      color: AppTheme.success,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '-${diff.deletions}',
                    style: const TextStyle(color: AppTheme.error, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
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
        providerID: model?['providerID'],
        modelID: model?['modelID'],
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
        AppSnackBar.showSuccess(context, 'Message effects reverted.');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Undo failed: $e');
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
        AppSnackBar.showSuccess(context, 'Message effects restored.');
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Redo failed: $e');
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

  void _showToolsMenu(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final project = ref.read(selectedProjectProvider);
    final sshState = ref.read(sshProvider);

    showConnectionChoiceSheet(
      context,
      onTerminal: () async {
        if (sshState.isConnected) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => const TerminalPage()));
        } else {
          final connected = await showSshConnectionDialog(
            context,
            defaultHost: settings.serverHost,
            workingDirectory: project?.worktree ?? '/',
          );
          final isConnectedNow = ref.read(sshProvider).isConnected;
          if (connected == true && context.mounted && isConnectedNow) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const TerminalPage()),
            );
          }
        }
      },
      onSftp: () async {
        if (sshState.isConnected) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  SftpPage(workingDirectory: project?.worktree ?? '/'),
            ),
          );
        } else {
          final connected = await showSshConnectionDialog(
            context,
            defaultHost: settings.serverHost,
            workingDirectory: project?.worktree ?? '/',
          );
          final isConnectedNow = ref.read(sshProvider).isConnected;
          if (connected == true && context.mounted && isConnectedNow) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) =>
                    SftpPage(workingDirectory: project?.worktree ?? '/'),
              ),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(selectedSessionProvider);
    final messagesState = ref.watch(messagesProvider);
    final mode = ref.watch(sessionModeProvider);
    final sessionControlState = ref.watch(sessionControlProvider);
    final sessionControl = sessionControlState.control;
    final activeModel = ref.watch(activeModelProvider);
    final selectedAgent = ref.watch(selectedAgentProvider);
    final selectedAgentLabel =
        selectedAgent.agentId != null &&
            selectedAgent.agentId == session?.agentID &&
            selectedAgent.agentName != null
        ? selectedAgent.agentName
        : session?.agentID;
    final statusAsync = ref.watch(sessionStatusProvider);

    final errorState = ref.watch(sessionErrorProvider);

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

    final effectiveBusy = _isBusy || isSessionBusy || _isSyncing;
    final availableModes = sessionControl?.modes ?? const <SessionModeOption>[];
    final modelOption = sessionControl?.optionByCategory('model');
    final activeModelLabel =
        modelOption?.selectedChoice?.name ??
        modelOption?.currentValue ??
        activeModel?['modelID'];
    final busyLabel = switch (mode.toLowerCase()) {
      'plan' => 'Planning...',
      'build' => 'Building...',
      _ => 'Working...',
    };

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
                      ? busyLabel
                      : 'Ready${activeModelLabel != null
                            ? " • $activeModelLabel"
                            : selectedAgentLabel != null
                            ? " • $selectedAgentLabel"
                            : ""}',
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
            onTap: () => unawaited(
              _handleModeAction(
                context,
                currentMode: mode,
                availableModes: availableModes,
              ),
            ),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            tooltip: 'More options',
            onSelected: (value) {
              switch (value) {
                case 'sidebar':
                  setState(() => _isSidebarOpen = !_isSidebarOpen);
                  break;
                case 'tools':
                  _showToolsMenu(context);
                  break;
                case 'session_config':
                  if (sessionControl != null) {
                    unawaited(_showSessionConfigSheet(context, sessionControl));
                  }
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'sidebar',
                child: Row(
                  children: [
                    Icon(
                      _isSidebarOpen
                          ? Icons.view_sidebar
                          : Icons.view_sidebar_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isSidebarOpen ? 'Hide Sidebar' : 'Show Sidebar',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'tools',
                child: Row(
                  children: [
                    Icon(
                      Icons.build_circle_outlined,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                    SizedBox(width: 12),
                    Text('Tools', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              if (sessionControl != null &&
                  sessionControl.configOptions.isNotEmpty)
                const PopupMenuItem<String>(
                  value: 'session_config',
                  child: Row(
                    children: [
                      Icon(Icons.tune, size: 18, color: AppTheme.textSecondary),
                      SizedBox(width: 12),
                      Text('Session Config', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            ],
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

  Widget _buildMessage(MessageWrapper msg, {bool isLastMessage = false}) {
    final isUser = msg.info.role == 'user';
    final session = ref.watch(selectedSessionProvider);
    final statusAsync = ref.watch(sessionStatusProvider);
    final isSessionBusy = session != null
        ? statusAsync.maybeWhen(
            data: (status) {
              final info = status[session.id];
              if (info is Map<String, dynamic>) {
                return info['type'] != 'idle';
              }
              if (info is String) {
                return info != 'idle';
              }
              return false;
            },
            orElse: () => false,
          )
        : false;
    final isSessionIdle = !isSessionBusy;
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
            child: isUser
                ? UserMessageWidget(
                    parts: msg.parts,
                    isOptimistic: isOptimistic,
                  )
                : MessagePartsWidget(
                    parts: msg.parts,
                    isUser: isUser,
                    groupOperationalByMessageID:
                        !_hasMultipleAssistantPartMessages(msg),
                    isSessionIdle: !isLastMessage || isSessionIdle,
                  ),
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
                  if ((msg.info as AssistantMessageInfo).mode.isNotEmpty)
                    Text(
                      (msg.info as AssistantMessageInfo).mode.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 9,
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

  bool _isSecret(QuestionInfo question) => question.secret ?? false;

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
            const SizedBox(height: 4),
            Text(
              'Answer all questions to continue',
              style: TextStyle(fontSize: 10, color: AppTheme.textTertiary),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(widget.request.questions.length, (i) {
                    final question = widget.request.questions[i];
                    final allowCustom = _allowsCustom(question);
                    final isAnswered =
                        _answers[i].isNotEmpty || _customAnswers[i] != null;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: i == widget.request.questions.length - 1
                            ? 0
                            : 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isAnswered
                                      ? AppTheme.success.withValues(alpha: 0.15)
                                      : AppTheme.warning.withValues(
                                          alpha: 0.15,
                                        ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.request.questions.length > 1
                                      ? 'Question ${i + 1} of ${widget.request.questions.length}'
                                      : 'Question',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: isAnswered
                                        ? AppTheme.success
                                        : AppTheme.warning,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              if (!isAnswered)
                                Text(
                                  'Required',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
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
                              obscureText: _isSecret(question),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textPrimary,
                              ),
                              decoration: InputDecoration(
                                hintText: _isSecret(question)
                                    ? 'Type secret answer'
                                    : 'Type your own answer',
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

class _SessionConfigSheet extends StatelessWidget {
  const _SessionConfigSheet({
    required this.control,
    required this.onSelectValue,
    required this.onToggleValue,
  });

  final SessionControl control;
  final Future<void> Function(String configId, String valueId) onSelectValue;
  final Future<void> Function(String configId, bool value) onToggleValue;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text(
              'Session Config',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final option in control.configOptions) ...[
              Text(
                option.name,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (option.description != null && option.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 6),
                  child: Text(
                    option.description!,
                    style: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                const SizedBox(height: 6),
              if (option.isBoolean)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: option.currentBoolValue ?? false,
                  title: Text(
                    option.currentBoolValue == true ? 'Enabled' : 'Disabled',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  onChanged: (value) async {
                    Navigator.of(context).pop();
                    await onToggleValue(option.id, value);
                  },
                )
              else
                for (final choice in option.choices)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      choice.name,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    subtitle:
                        choice.description == null ||
                            choice.description!.isEmpty
                        ? (choice.group == null
                              ? null
                              : Text(
                                  choice.group!,
                                  style: const TextStyle(
                                    color: AppTheme.textTertiary,
                                    fontSize: 10,
                                  ),
                                ))
                        : Text(
                            [
                              if (choice.group != null) choice.group!,
                              choice.description!,
                            ].join(' • '),
                            style: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                    trailing: option.currentValue == choice.value
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: AppTheme.accent,
                          )
                        : null,
                    onTap: () async {
                      Navigator.of(context).pop();
                      await onSelectValue(option.id, choice.value);
                    },
                  ),
              const Divider(color: AppTheme.border),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
